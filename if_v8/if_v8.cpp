/*
 * v8 interface to Vim
 *
 * Last Change: 2009-01-02
 * Maintainer: Yukihiro Nakadaira <yukihiro.nakadaira@gmail.com>
 *
 * Require:
 *  linux or windows.
 *  Vim executable file with some exported symbol that if_v8 requires.
 *    On linux:
 *      Compile with gcc's -rdynamic option.
 *    On windows (msvc):
 *      Use vim_export.def and add linker flag "/DEF:vim_export.def".
 *      nmake -f Make_mvc.mak linkdebug=/DEF:vim_export.def
 *
 * Compile:
 *  g++ -I/path/to/v8/include -shared -o if_v8.so if_v8.cpp \
 *      -L/path/to/v8 -lv8 -lpthread
 *
 * Usage:
 *  let if_v8 = '/path/to/if_v8.so'
 *  let err = libcall(if_v8, 'init', if_v8)
 *  let err = libcall(if_v8, 'execute', 'vim.execute("echo \"hello, v8\"")')
 *  let err = libcall(if_v8, 'execute', 'vim.eval("&tw")')
 *  let err = libcall(if_v8, 'execute', 'load("foo.js")')
 *
 *  if_v8 returns error message for initialization error.  Normal
 *  execution time error is raised in the same way as :echoerr command.
 *
 *
 * Note:
 *  g:['%v8*%'] variables are internally used.
 *
 */
#ifdef WIN32
# include <windows.h>
#else
# include <dlfcn.h>
#endif
#include <cstdio>
#include <cstring>
#include <string>
#include <map>
#include <v8.h>

#define FEAT_FLOAT 1

typedef unsigned char char_u;
typedef unsigned short short_u;
typedef unsigned int int_u;
typedef unsigned long long_u;

/* Item for a hashtable.  "hi_key" can be one of three values:
 * NULL:	   Never been used
 * HI_KEY_REMOVED: Entry was removed
 * Otherwise:	   Used item, pointer to the actual key; this usually is
 *		   inside the item, subtract an offset to locate the item.
 *		   This reduces the size of hashitem by 1/3.
 */
typedef struct hashitem_S
{
    long_u	hi_hash;	/* cached hash number of hi_key */
    char_u	*hi_key;
} hashitem_T;

/* The address of "hash_removed" is used as a magic number for hi_key to
 * indicate a removed item. */
#define HI_KEY_REMOVED p_hash_removed
#define HASHITEM_EMPTY(hi) ((hi)->hi_key == NULL || (hi)->hi_key == p_hash_removed)

/* Initial size for a hashtable.  Our items are relatively small and growing
 * is expensive, thus use 16 as a start.  Must be a power of 2. */
#define HT_INIT_SIZE 16

typedef struct hashtable_S
{
    long_u	ht_mask;	/* mask used for hash value (nr of items in
				 * array is "ht_mask" + 1) */
    long_u	ht_used;	/* number of items used */
    long_u	ht_filled;	/* number of items used + removed */
    int		ht_locked;	/* counter for hash_lock() */
    int		ht_error;	/* when set growing failed, can't add more
				   items before growing works */
    hashitem_T	*ht_array;	/* points to the array, allocated when it's
				   not "ht_smallarray" */
    hashitem_T	ht_smallarray[HT_INIT_SIZE];   /* initial array */
} hashtab_T;

typedef long_u hash_T;		/* Type for hi_hash */


#if SIZEOF_INT <= 3		/* use long if int is smaller than 32 bits */
typedef long	varnumber_T;
#else
typedef int	varnumber_T;
#endif
typedef double	float_T;

typedef struct listvar_S list_T;
typedef struct dictvar_S dict_T;

/*
 * Structure to hold an internal variable without a name.
 */
typedef struct
{
    char	v_type;	    /* see below: VAR_NUMBER, VAR_STRING, etc. */
    char	v_lock;	    /* see below: VAR_LOCKED, VAR_FIXED */
    union
    {
	varnumber_T	v_number;	/* number value */
#ifdef FEAT_FLOAT
	float_T		v_float;	/* floating number value */
#endif
	char_u		*v_string;	/* string value (can be NULL!) */
	list_T		*v_list;	/* list value (can be NULL!) */
	dict_T		*v_dict;	/* dict value (can be NULL!) */
    }		vval;
} typval_T;

/* Values for "v_type". */
#define VAR_UNKNOWN 0
#define VAR_NUMBER  1	/* "v_number" is used */
#define VAR_STRING  2	/* "v_string" is used */
#define VAR_FUNC    3	/* "v_string" is function name */
#define VAR_LIST    4	/* "v_list" is used */
#define VAR_DICT    5	/* "v_dict" is used */
#define VAR_FLOAT   6	/* "v_float" is used */

/* Values for "v_lock". */
#define VAR_LOCKED  1	/* locked with lock(), can use unlock() */
#define VAR_FIXED   2	/* locked forever */

/*
 * Structure to hold an item of a list: an internal variable without a name.
 */
typedef struct listitem_S listitem_T;

struct listitem_S
{
    listitem_T	*li_next;	/* next item in list */
    listitem_T	*li_prev;	/* previous item in list */
    typval_T	li_tv;		/* type and value of the variable */
};

/*
 * Struct used by those that are using an item in a list.
 */
typedef struct listwatch_S listwatch_T;

struct listwatch_S
{
    listitem_T		*lw_item;	/* item being watched */
    listwatch_T		*lw_next;	/* next watcher */
};

/*
 * Structure to hold info about a list.
 */
struct listvar_S
{
    listitem_T	*lv_first;	/* first item, NULL if none */
    listitem_T	*lv_last;	/* last item, NULL if none */
    int		lv_refcount;	/* reference count */
    int		lv_len;		/* number of items */
    listwatch_T	*lv_watch;	/* first watcher, NULL if none */
    int		lv_idx;		/* cached index of an item */
    listitem_T	*lv_idx_item;	/* when not NULL item at index "lv_idx" */
    int		lv_copyID;	/* ID used by deepcopy() */
    list_T	*lv_copylist;	/* copied list used by deepcopy() */
    char	lv_lock;	/* zero, VAR_LOCKED, VAR_FIXED */
    list_T	*lv_used_next;	/* next list in used lists list */
    list_T	*lv_used_prev;	/* previous list in used lists list */
};

/*
 * Structure to hold an item of a Dictionary.
 * Also used for a variable.
 * The key is copied into "di_key" to avoid an extra alloc/free for it.
 */
struct dictitem_S
{
    typval_T	di_tv;		/* type and value of the variable */
    char_u	di_flags;	/* flags (only used for variable) */
    char_u	di_key[1];	/* key (actually longer!) */
};

typedef struct dictitem_S dictitem_T;

#define DI_FLAGS_RO	1 /* "di_flags" value: read-only variable */
#define DI_FLAGS_RO_SBX 2 /* "di_flags" value: read-only in the sandbox */
#define DI_FLAGS_FIX	4 /* "di_flags" value: fixed variable, not allocated */
#define DI_FLAGS_LOCK	8 /* "di_flags" value: locked variable */

/*
 * Structure to hold info about a Dictionary.
 */
struct dictvar_S
{
    int		dv_refcount;	/* reference count */
    hashtab_T	dv_hashtab;	/* hashtab that refers to the items */
    int		dv_copyID;	/* ID used by deepcopy() */
    dict_T	*dv_copydict;	/* copied dict used by deepcopy() */
    char	dv_lock;	/* zero, VAR_LOCKED, VAR_FIXED */
    dict_T	*dv_used_next;	/* next dict in used dicts list */
    dict_T	*dv_used_prev;	/* previous dict in used dicts list */
};

/*
 * In a hashtab item "hi_key" points to "di_key" in a dictitem.
 * This avoids adding a pointer to the hashtab item.
 * DI2HIKEY() converts a dictitem pointer to a hashitem key pointer.
 * HIKEY2DI() converts a hashitem key pointer to a dictitem pointer.
 * HI2DI() converts a hashitem pointer to a dictitem pointer.
 */
static dictitem_T dumdi;
#define DI2HIKEY(di) ((di)->di_key)
#define HIKEY2DI(p)  ((dictitem_T *)(p - (dumdi.di_key - (char_u *)&dumdi)))
#define HI2DI(hi)     HIKEY2DI((hi)->hi_key)

struct condstack;

// variables
static char_u *p_hash_removed;
// functions
static typval_T * (*eval_expr) (char_u *arg, char_u **nextcmd);
static char_u * (*eval_to_string) (char_u *arg, char_u **nextcmd, int convert);
static int (*do_cmdline_cmd) (char_u *cmd);
static void (*free_tv) (typval_T *varp);
static void (*clear_tv) (typval_T *varp);
static int (*emsg) (char_u *s);
static char_u * (*alloc) (unsigned size);
static void * (*vim_free) (void *x);
static char_u * (*vim_strsave) (char_u *string);
static char_u * (*vim_strnsave) (char_u *string, int len);
static void (*vim_strncpy) (char_u *to, char_u *from, size_t len);
static list_T * (*list_alloc)();
static void (*list_free) (list_T *l, int recurse);
static dict_T * (*dict_alloc)();
static int (*hash_add) (hashtab_T *ht, char_u *key);
static hashitem_T * (*hash_find) (hashtab_T *ht, char_u *key);

#define FALSE 0
#define TRUE 1

#define STRLEN(s)	    strlen((char *)(s))
#define STRCPY(d, s)	    strcpy((char *)(d), (char *)(s))
#define vim_memset(ptr, c, size)   memset((ptr), (c), (size))

/*
 * Set the value of a variable to NULL without freeing items.
 */
    static void
init_tv(
    typval_T *varp
    )
{
    if (varp != NULL)
	vim_memset(varp, 0, sizeof(typval_T));
}

/*
 * Allocate a list item.
 */
    static listitem_T *
listitem_alloc()
{
    return (listitem_T *)alloc(sizeof(listitem_T));
}

/*
 * Free a list item.  Also clears the value.  Does not notify watchers.
 */
    static void
listitem_free(
    listitem_T *item
    )
{
    clear_tv(&item->li_tv);
    vim_free(item);
}

/*
 * Append item "item" to the end of list "l".
 */
    static void
list_append(
    list_T	*l,
    listitem_T	*item
    )
{
    if (l->lv_last == NULL)
    {
	/* empty list */
	l->lv_first = item;
	l->lv_last = item;
	item->li_prev = NULL;
    }
    else
    {
	l->lv_last->li_next = item;
	item->li_prev = l->lv_last;
	l->lv_last = item;
    }
    ++l->lv_len;
    item->li_next = NULL;
}

/*
 * Allocate a Dictionary item.
 * The "key" is copied to the new item.
 * Note that the value of the item "di_tv" still needs to be initialized!
 * Returns NULL when out of memory.
 */
    static dictitem_T *
dictitem_alloc(
    char_u	*key
    )
{
    dictitem_T *di;

    di = (dictitem_T *)alloc((unsigned)(sizeof(dictitem_T) + STRLEN(key)));
    if (di != NULL)
    {
	STRCPY(di->di_key, key);
	di->di_flags = 0;
    }
    return di;
}

/*
 * Free a dict item.  Also clears the value.
 */
    static void
dictitem_free(
    dictitem_T *item
    )
{
    clear_tv(&item->di_tv);
    vim_free(item);
}

/*
 * Add item "item" to Dictionary "d".
 * Returns FAIL when out of memory and when key already existed.
 */
    static int
dict_add(
    dict_T	*d,
    dictitem_T	*item
    )
{
    return hash_add(&d->dv_hashtab, item->di_key);
}

/*
 * Free a Dictionary, including all items it contains.
 * Ignores the reference count.
 * XXX: recurse is not supported (always TRUE)
 */
#define dict_free(d, recurse) wrap_dict_free(d)
    static void
wrap_dict_free(dict_T  *d)
{
    typval_T tv;
    init_tv(&tv);
    tv.v_type = VAR_DICT;
    tv.vval.v_dict = d;
    tv.vval.v_dict->dv_refcount = 1;
    clear_tv(&tv);
}

/*
 * Find item "key[len]" in Dictionary "d".
 * If "len" is negative use strlen(key).
 * Returns NULL when not found.
 */
    static dictitem_T *
dict_find(
    dict_T	*d,
    char_u	*key,
    int		len
    )
{
#define AKEYLEN 200
    char_u	buf[AKEYLEN];
    char_u	*akey;
    char_u	*tofree = NULL;
    hashitem_T	*hi;

    if (len < 0)
	akey = key;
    else if (len >= AKEYLEN)
    {
	tofree = akey = vim_strnsave(key, len);
	if (akey == NULL)
	    return NULL;
    }
    else
    {
	/* Avoid a malloc/free by using buf[]. */
	vim_strncpy(buf, key, len);
	akey = buf;
    }

    hi = hash_find(&d->dv_hashtab, akey);
    vim_free(tofree);
    if (HASHITEM_EMPTY(hi))
	return NULL;
    return HI2DI(hi);
}

typedef void* list_or_dict_ptr;
typedef std::map<list_or_dict_ptr, v8::Handle<v8::Value> > LookupMap;

static void *dll_handle = NULL;
static v8::Handle<v8::Context> context;

#ifdef WIN32
# define DLLEXPORT __declspec(dllexport)
#else
# define DLLEXPORT
#endif

/* API */
extern "C" {
DLLEXPORT const char *init(const char *dll_path);
DLLEXPORT const char *execute(const char *expr);
}

static const char *init_vim();
static const char *init_v8();
static v8::Handle<v8::Value> vim_execute(const v8::Arguments& args);
static bool let_global(const char *name, typval_T *tv, std::string *err);
static bool vim_to_v8(typval_T *vimobj, v8::Handle<v8::Value> *v8obj, int depth, LookupMap *lookup, std::string *err);
static LookupMap::iterator LookupMapFindV8Value(LookupMap* lookup, v8::Handle<v8::Value> v);
static bool v8_to_vim(v8::Handle<v8::Value> v8obj, typval_T *vimobj, int depth, LookupMap *lookup, std::string *err);
static v8::Handle<v8::Value> Load(const v8::Arguments& args);
static v8::Handle<v8::String> ReadFile(const char* name);
static bool ExecuteString(v8::Handle<v8::String> source, v8::Handle<v8::Value> name, std::string* err);

const char *
init(const char *dll_path)
{
  const char *err;
  if (dll_handle != NULL)
    return NULL;
#ifdef WIN32
  if ((dll_handle = (void*)LoadLibrary(dll_path)) == NULL)
    return "error: LoadLibrary()";
#else
  if ((dll_handle = dlopen(dll_path, RTLD_NOW)) == NULL)
    return dlerror();
#endif
  if ((err = init_vim()) != NULL)
    return err;
  if ((err = init_v8()) != NULL)
    return err;
  return NULL;
}

const char *
execute(const char *expr)
{
  if (eval_expr == NULL)
    return "not initialized";
  v8::HandleScope handle_scope;
  v8::Context::Scope context_scope(context);
  std::string err;
  if (!ExecuteString(v8::String::New(expr), v8::Undefined(), &err))
    emsg((char_u*)err.c_str());
  return NULL;
}

#define GETSYMBOL(name) GETSYMBOL2(name, #name)

#ifdef WIN32
#define GETSYMBOL2(var, name)                                             \
  do {                                                                    \
    void **p = (void **)&var;                                             \
    if ((*p = (void*)GetProcAddress((HMODULE)vim_handle, name)) == NULL)  \
      return "error: GetProcAddress()";                                   \
  } while (0)
#else
#define GETSYMBOL2(var, name)                     \
  do {                                            \
    void **p = (void **)&var;                     \
    if ((*p = dlsym(vim_handle, name)) == NULL)   \
      return dlerror();                           \
  } while (0)
#endif

static const char *
init_vim()
{
  void *vim_handle;
#ifdef WIN32
  if ((vim_handle = (void*)GetModuleHandle(NULL)) == NULL)
    return "error: GetModuleHandle()";
#else
  if ((vim_handle = dlopen(NULL, RTLD_NOW)) == NULL)
    return dlerror();
#endif
  // variables
  GETSYMBOL2(p_hash_removed, "hash_removed");
  // functions
  GETSYMBOL(eval_expr);
  GETSYMBOL(eval_to_string);
  GETSYMBOL(do_cmdline_cmd);
  GETSYMBOL(free_tv);
  GETSYMBOL(clear_tv);
  GETSYMBOL(emsg);
  GETSYMBOL(alloc);
  GETSYMBOL(vim_free);
  GETSYMBOL(vim_strsave);
  GETSYMBOL(vim_strnsave);
  GETSYMBOL(vim_strncpy);
  GETSYMBOL(list_alloc);
  GETSYMBOL(list_free);
  GETSYMBOL(dict_alloc);
  GETSYMBOL(hash_add);
  GETSYMBOL(hash_find);
  return NULL;
}

static const char *
init_v8()
{
  v8::HandleScope handle_scope;
  v8::Handle<v8::ObjectTemplate> internal = v8::ObjectTemplate::New();
  internal->Set(v8::String::New("load"), v8::FunctionTemplate::New(Load));
  internal->Set(v8::String::New("vim_execute"), v8::FunctionTemplate::New(vim_execute));
  v8::Handle<v8::ObjectTemplate> global = v8::ObjectTemplate::New();
  global->Set(v8::String::New("%internal%"), internal);
  context = v8::Context::New(NULL, global);
  return NULL;
}

static v8::Handle<v8::Value>
vim_execute(const v8::Arguments& args)
{
  v8::HandleScope handle_scope;

  if (args.Length() <= 1 || !args[0]->IsString())
    return v8::ThrowException(v8::String::New("usage: vim_execute(string cmd [, ...])"));

  v8::Handle<v8::Array> v8_args = v8::Array::New(args.Length());
  for (int i = 0; i < args.Length(); ++i )
    v8_args->Set(v8::Integer::New(i), args[i]);

  // :let g:['%v8_args%'] = args
  {
    LookupMap lookup;
    std::string err;
    typval_T vimobj;
    if (!v8_to_vim(v8_args, &vimobj, 1, &lookup, &err)) {
      return v8::ThrowException(v8::String::New(err.c_str()));
    }

    if (!let_global("%v8_args%", &vimobj, &err)) {
      clear_tv(&vimobj);
      return v8::ThrowException(v8::String::New(err.c_str()));
    }

    // don't clear vimobj.  see let_global.
    // clear_tv(&vimobj);
  }

  // execute
  {
    char exprbuf[] = "try | execute g:['%v8_args%'][0] | let g:['%v8_exception%'] = '' | catch | let g:['%v8_exception%'] = v:exception | endtry";
    if (!do_cmdline_cmd((char_u*)exprbuf)) {
      return v8::ThrowException(v8::String::New("vim_call(): error do_cmdline_cmd()"));
    }
  }

  // catch
  {
    char exprbuf[] = "g:['%v8_exception%']";
    char_u *e = eval_to_string((char_u*)exprbuf, NULL, 0);
    if (e == NULL) {
      return v8::ThrowException(v8::String::New("vim_call(): cannot get exception"));
    }

    if (e[0] != '\0') {
      std::string s((char*)e);
      vim_free(e);
      return v8::ThrowException(v8::String::New(s.c_str()));
    }

    vim_free(e);
  }

  // return g:['%v8_result']
  v8::Handle<v8::Value> v8_result;
  {
    char exprbuf[] = "g:['%v8_result%']";
    typval_T *tv = eval_expr((char_u*)exprbuf, NULL);
    if (tv == NULL) {
      return v8::ThrowException(v8::String::New("vim_call(): cannot get result"));
    }

    LookupMap lookup;
    std::string err;
    if (!vim_to_v8(tv, &v8_result, 1, &lookup, &err)) {
      free_tv(tv);
      return v8::ThrowException(v8::String::New(err.c_str()));
    }

    free_tv(tv);
  }

  return v8_result;
}

static bool
let_global(const char *name, typval_T *tv, std::string *err)
{
  char expr[] = "g:";
  typval_T *g = eval_expr((char_u*)expr, NULL);
  if (g == NULL) {
    *err = "let_global(): error eval_expre()";
    return false;
  }

  dict_T *dict = g->vval.v_dict;
  dictitem_T *di = dict_find(dict, (char_u*)name, -1);
  if (di == NULL) {
    di = dictitem_alloc((char_u*)name);
    if (di == NULL) {
      free_tv(g);
      *err = "let_global(): error dictitem_alloc()";
      return false;
    }
    if (!dict_add(dict, di)) {
      dictitem_free(di);
      free_tv(g);
      *err = "let_global(): error dict_add()()";
      return false;
    }
  } else {
    clear_tv(&di->di_tv);
  }

  // don't use copy_tv() because it cannot implement as static function.
  // copy_tv(tv, &di->di_tv);
  di->di_tv = *tv;

  free_tv(g);

  return true;
}

static bool
vim_to_v8(typval_T *vimobj, v8::Handle<v8::Value> *v8obj, int depth, LookupMap *lookup, std::string *err)
{
  if (vimobj == NULL || depth > 100) {
    *v8obj = v8::Undefined();
    return true;
  }

  if (vimobj->v_type == VAR_NUMBER) {
    *v8obj = v8::Integer::New(vimobj->vval.v_number);
    return true;
  }

#ifdef FEAT_FLOAT
  if (vimobj->v_type == VAR_FLOAT) {
    *v8obj = v8::Number::New(vimobj->vval.v_float);
    return true;
  }
#endif

  if (vimobj->v_type == VAR_STRING) {
    if (vimobj->vval.v_string == NULL)
      *v8obj = v8::String::New("");
    else
      *v8obj = v8::String::New((char *)vimobj->vval.v_string);
    return true;
  }

  if (vimobj->v_type == VAR_LIST) {
    list_T *list = vimobj->vval.v_list;
    if (list == NULL) {
      *v8obj = v8::Array::New(0);
      return true;
    }
    LookupMap::iterator it = lookup->find(list);
    if (it != lookup->end()) {
      *v8obj = it->second;
      return true;
    }
    v8::Handle<v8::Array> o = v8::Array::New(0);
    v8::Handle<v8::Value> v;
    int i = 0;
    lookup->insert(LookupMap::value_type(list, o));
    for (listitem_T *curr = list->lv_first; curr != NULL; curr = curr->li_next) {
      if (!vim_to_v8(&curr->li_tv, &v, depth + 1, lookup, err))
        return false;
      o->Set(v8::Integer::New(i++), v);
    }
    *v8obj = o;
    return true;
  }

  if (vimobj->v_type == VAR_DICT) {
    dict_T *dict = vimobj->vval.v_dict;
    if (dict == NULL) {
      *v8obj = v8::Object::New();
      return true;
    }
    LookupMap::iterator it = lookup->find(dict);
    if (it != lookup->end()) {
      *v8obj = it->second;
      return true;
    }
    v8::Handle<v8::Object> o = v8::Object::New();
    v8::Handle<v8::Value> v;
    hashtab_T *ht = &dict->dv_hashtab;
    long_u todo = ht->ht_used;
    hashitem_T *hi;
    dictitem_T *di;
    lookup->insert(LookupMap::value_type(dict, o));
    for (hi = ht->ht_array; todo > 0; ++hi) {
      if (!HASHITEM_EMPTY(hi)) {
        --todo;
        di = HI2DI(hi);
        if (!vim_to_v8(&di->di_tv, &v, depth + 1, lookup, err))
          return false;
        o->Set(v8::String::New((char *)hi->hi_key), v);
      }
    }
    *v8obj = o;
    return true;
  }

  // TODO:
  if (vimobj->v_type == VAR_FUNC) {
    *v8obj = v8::String::New("[function]");
    return true;
  }

  if (vimobj->v_type == VAR_UNKNOWN) {
    *v8obj = v8::Undefined();
    return true;
  }

  *err = "vim_to_v8(): internal error: unknown type";
  return false;
}

static LookupMap::iterator
LookupMapFindV8Value(LookupMap* lookup, v8::Handle<v8::Value> v)
{
  LookupMap::iterator it;
  for (it = lookup->begin(); it != lookup->end(); ++it) {
    if (it->second->StrictEquals(v))
      return it;
  }
  return it;
}

static bool
v8_to_vim(v8::Handle<v8::Value> v8obj, typval_T *vimobj, int depth, LookupMap *lookup, std::string *err)
{
  vimobj->v_lock = 0;

  if (depth > 100) {
    vimobj->v_type = VAR_NUMBER;
    vimobj->vval.v_number = 0;
    return true;
  }

  if (v8obj->IsUndefined()) {
    vimobj->v_type = VAR_NUMBER;
    vimobj->vval.v_number = 0;
    return true;
  }

  if (v8obj->IsNull()) {
    vimobj->v_type = VAR_NUMBER;
    vimobj->vval.v_number = 0;
    return true;
  }

  if (v8obj->IsBoolean()) {
    vimobj->v_type = VAR_NUMBER;
    vimobj->vval.v_number = v8obj->IsTrue() ? 1 : 0;
    return true;
  }

  if (v8obj->IsInt32()) {
    vimobj->v_type = VAR_NUMBER;
    vimobj->vval.v_number = v8obj->Int32Value();
    return true;
  }

#ifdef FEAT_FLOAT
  if (v8obj->IsNumber()) {
    vimobj->v_type = VAR_FLOAT;
    vimobj->vval.v_float = v8obj->NumberValue();
    return true;
  }
#endif

  if (v8obj->IsString()) {
    v8::String::Utf8Value str(v8obj);
    vimobj->v_type = VAR_STRING;
    vimobj->vval.v_string = vim_strsave((char_u*)*str);
    return true;
  }

  if (v8obj->IsDate()) {
    v8::String::Utf8Value str(v8obj);
    vimobj->v_type = VAR_STRING;
    vimobj->vval.v_string = vim_strsave((char_u*)*str);
    return true;
  }

  if (v8obj->IsArray()
      // also convert array like object, such as arguments, to array?
      //|| (v8obj->IsObject() && v8::Handle<v8::Object>::Cast(v8obj)->Has(v8::String::New("length")))
      ) {
    LookupMap::iterator it = LookupMapFindV8Value(lookup, v8obj);
    if (it != lookup->end()) {
      vimobj->v_type = VAR_LIST;
      vimobj->vval.v_list = (list_T *)it->first;
      ++vimobj->vval.v_list->lv_refcount;
      return true;
    }
    list_T *list = list_alloc();
    if (list == NULL) {
      *err = "v8_to_vim(): list_alloc(): out of memoty";
      return false;
    }
    v8::Handle<v8::Object> o = v8::Handle<v8::Object>::Cast(v8obj);
    uint32_t len;
    if (o->IsArray()) {
      v8::Handle<v8::Array> o = v8::Handle<v8::Array>::Cast(v8obj);
      len = o->Length();
    } else {
      len = o->Get(v8::String::New("length"))->Int32Value();
    }
    lookup->insert(LookupMap::value_type(list, v8obj));
    for (uint32_t i = 0; i < len; ++i) {
      v8::Handle<v8::Value> v = o->Get(v8::Integer::New(i));
      listitem_T *li = listitem_alloc();
      if (li == NULL) {
        list_free(list, TRUE);
        *err = "v8_to_vim(): listitem_alloc(): out of memoty";
        return false;
      }
      init_tv(&li->li_tv);
      if (!v8_to_vim(v, &li->li_tv, depth + 1, lookup, err)) {
        listitem_free(li);
        list_free(list, TRUE);
        return false;
      }
      list_append(list, li);
    }
    vimobj->v_type = VAR_LIST;
    vimobj->vval.v_list = list;
    ++vimobj->vval.v_list->lv_refcount;
    return true;
  }

  if (v8obj->IsObject()) {
    LookupMap::iterator it = LookupMapFindV8Value(lookup, v8obj);
    if (it != lookup->end()) {
      vimobj->v_type = VAR_DICT;
      vimobj->vval.v_dict = (dict_T *)it->first;
      ++vimobj->vval.v_dict->dv_refcount;
      return true;
    }
    dict_T *dict = dict_alloc();
    if (dict == NULL) {
      *err = "v8_to_vim(): dict_alloc(): out of memory";
      return false;
    }
    v8::Handle<v8::Object> o = v8::Handle<v8::Object>::Cast(v8obj);
    v8::Handle<v8::Array> keys = o->GetPropertyNames();
    uint32_t len = keys->Length();
    lookup->insert(LookupMap::value_type(dict, v8obj));
    for (uint32_t i = 0; i < len; ++i) {
      v8::Handle<v8::Value> key = keys->Get(v8::Integer::New(i));
      v8::Handle<v8::Value> v = o->Get(key);
      v8::String::Utf8Value keystr(key);
      dictitem_T *di = dictitem_alloc((char_u*)*keystr);
      if (di == NULL) {
        dict_free(dict, TRUE);
        *err = "v8_to_vim(): dictitem_alloc(): out of memory";
        return false;
      }
      init_tv(&di->di_tv);
      if (!v8_to_vim(v, &di->di_tv, depth + 1, lookup, err)) {
        dictitem_free(di);
        dict_free(dict, TRUE);
        return false;
      }
      if (!dict_add(dict, di)) {
        dictitem_free(di);
        dict_free(dict, TRUE);
        *err = "v8_to_vim(): error dict_add()";
        return false;
      }
    }
    vimobj->v_type = VAR_DICT;
    vimobj->vval.v_dict = dict;
    ++vimobj->vval.v_dict->dv_refcount;
    return true;
  }

  if (v8obj->IsFunction()) {
    vimobj->v_type = VAR_STRING;
    vimobj->vval.v_string = vim_strsave((char_u*)"[function]");
    return true;
  }

  if (v8obj->IsExternal()) {
    vimobj->v_type = VAR_STRING;
    vimobj->vval.v_string = vim_strsave((char_u*)"[external]");
    return true;
  }

  *err = "v8_to_vim(): internal error: unknown type";
  return true;
}

// The callback that is invoked by v8 whenever the JavaScript 'load'
// function is called.  Loads, compiles and executes its argument
// JavaScript file.
v8::Handle<v8::Value> Load(const v8::Arguments& args) {
  for (int i = 0; i < args.Length(); i++) {
    v8::HandleScope handle_scope;
    v8::String::Utf8Value file(args[i]);
    v8::Handle<v8::String> source = ReadFile(*file);
    if (source.IsEmpty()) {
      return v8::ThrowException(v8::String::New("Error loading file"));
    }
    std::string err;
    if (!ExecuteString(source, v8::String::New(*file), &err)) {
      return v8::ThrowException(v8::String::New(err.c_str()));
    }
  }
  return v8::Undefined();
}

// Reads a file into a v8 string.
v8::Handle<v8::String> ReadFile(const char* name) {
  FILE* file = fopen(name, "rb");
  if (file == NULL) return v8::Handle<v8::String>();

  fseek(file, 0, SEEK_END);
  int size = ftell(file);
  rewind(file);

  char* chars = new char[size + 1];
  chars[size] = '\0';
  for (int i = 0; i < size;) {
    int read = fread(&chars[i], 1, size - i, file);
    i += read;
  }
  fclose(file);
  v8::Handle<v8::String> result = v8::String::New(chars, size);
  delete[] chars;
  return result;
}

bool ExecuteString(v8::Handle<v8::String> source,
                   v8::Handle<v8::Value> name,
                   std::string* err) {
  v8::HandleScope handle_scope;
  v8::TryCatch try_catch;
  v8::Handle<v8::Script> script = v8::Script::Compile(source, name);
  if (script.IsEmpty()) {
    if (err != NULL) {
      v8::String::Utf8Value error(try_catch.Exception());
      *err = *error;
    }
    return false;
  }
  v8::Handle<v8::Value> result = script->Run();
  if (result.IsEmpty()) {
    if (err != NULL) {
      v8::String::Utf8Value error(try_catch.Exception());
      *err = *error;
    }
    return false;
  }
  return true;
}
