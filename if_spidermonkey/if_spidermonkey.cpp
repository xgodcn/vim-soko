/*
 * SpiderMonkey interface to Vim
 *
 * Last Change: 2008-09-15
 * Maintainer: Yukihiro Nakadaira <yukihiro.nakadaira@gmail.com>
 *
 * Require:
 *  Unix-like system.
 *  Vim compiled with -rdynamic option.
 *
 * Compile:
 *  g++ -I/path/to/spidermonkey/include -shared -o if_spidermonkey.so \
 *      -DXP_UNIX -DJS_THREADSAFE if_spidermonkey.c \
 *      -L/path/to/spidermonkey/lib -ljs -lpthread -lm
 *
 * Usage:
 *  let if_spidermonkey = '/path/to/if_spidermonkey.so'
 *  let err = libcall(if_spidermonkey, 'init', if_spidermonkey)
 *  let err = libcall(if_spidermonkey, 'execute', 'vim.execute("echo \"hello, v8\"")')
 *  let err = libcall(if_spidermonkey, 'execute', 'vim.eval("&tw")')
 *  let err = libcall(if_spidermonkey, 'execute', 'load("foo.js")')
 *
 */
#include <dlfcn.h>
#include <jsapi.h>
#include <string>
#include <sstream>
#include <map>

typedef std::map<void*, jsval> LookupMap;

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
#define HI_KEY_REMOVED vim.hash_removed
#define HASHITEM_EMPTY(hi) ((hi)->hi_key == NULL || (hi)->hi_key == vim.hash_removed)

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
	float_T		v_float;	/* floating number value */
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
 * flags for update_screen()
 * The higher the value, the higher the priority
 */
#define VALID			10  /* buffer not changed, or changes marked
				       with b_mod_* */
#define INVERTED		20  /* redisplay inverted part that changed */
#define INVERTED_ALL		25  /* redisplay whole inverted part */
#define REDRAW_TOP		30  /* display first w_upd_rows screen lines */
#define SOME_VALID		35  /* like NOT_VALID but may scroll */
#define NOT_VALID		40  /* buffer needs complete redraw */
#define CLEAR			50  /* screen messed up, clear it */

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

static struct vim {
  typval_T * (*eval_expr) (char_u *arg, char_u **nextcmd);
  int (*do_cmdline_cmd) (char_u *cmd);
  void (*free_tv) (typval_T *varp);
  char_u *hash_removed;
  void (*ui_breakcheck) ();
  int *got_int;
  void (*update_screen) (int type);
  int (*msg) (char_u *s);
  int (*emsg) (char_u *s);
} vim;

static void *dll_handle = NULL;
static JSRuntime *sm_rt;
static JSContext *sm_cx;
static JSObject  *sm_global;

/* API */
extern "C" {
const char *init(const char *dll_path);
const char *execute(const char *expr);
}

static const char *init_vim();
static const char *init_spidermonkey();

static void sm_error_reporter(JSContext *cx, const char *message, JSErrorReport *report);
static JSBool sm_branch_callback(JSContext *cx, JSScript *script);

/*
 * global class
 */

static JSBool sm_global_load(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);

static JSFunctionSpec sm_global_methods[] = {
  {"load", sm_global_load, 1},
  {0}
};

/*
 * vim class
 */
static JSObject *sm_vim_init(JSContext *cx, JSObject *obj);
static JSBool sm_vim_eval(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
static JSBool sm_vim_execute(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);

static JSFunctionSpec sm_vim_methods[] = {
  {"eval", sm_vim_eval, 1},
  {"execute", sm_vim_execute, 1},
  {0}
};


static jsval vim_to_spidermonkey(JSContext *cx, typval_T *tv, int depth, LookupMap *lookup_map);
static void execute_file(const char *name);
static void execute_string(const char *expr);

const char *
init(const char *dll_path)
{
  const char *err;
  if (dll_handle != NULL)
    return NULL;
  if ((dll_handle = dlopen(dll_path, RTLD_NOW)) == NULL)
    return dlerror();
  if ((err = init_vim()) != NULL)
    return err;
  if ((err = init_spidermonkey()) != NULL)
    return err;
  return NULL;
}

const char *
execute(const char *expr)
{
  if (vim.eval_expr == NULL)
    return "not initialized";
  execute_string(expr);
  return NULL;
}

#define GETSYMBOL(name)                           \
  do {                                            \
    void **p = (void **)&vim.name;                \
    if ((*p = dlsym(vim_handle, #name)) == NULL)  \
      return dlerror();                           \
  } while (0)

static const char *
init_vim()
{
  void *vim_handle;
  if ((vim_handle = dlopen(NULL, RTLD_NOW)) == NULL)
    return dlerror();
  GETSYMBOL(eval_expr);
  GETSYMBOL(do_cmdline_cmd);
  GETSYMBOL(free_tv);
  GETSYMBOL(hash_removed);
  GETSYMBOL(ui_breakcheck);
  GETSYMBOL(got_int);
  GETSYMBOL(update_screen);
  GETSYMBOL(msg);
  GETSYMBOL(emsg);
  return NULL;
}

static const char *
init_spidermonkey()
{
  // set up global JS variables, including global and custom objects
  JSRuntime *rt;
  JSContext *cx;
  JSObject  *global;

  // initialize the JS run time, and return result in rt
  // if rt does not have a value, end the program here
  if ((rt = JS_NewRuntime(8L * 1024L * 1024L)) == NULL)
    return "JS_NewRuntime() error";

  // create a context and associate it with the JS run time
  // if cx does not have a value, end the program here
  if ((cx = JS_NewContext(rt, 8192)) == NULL)
    return "JS_NewContext() error";

  JS_SetErrorReporter(cx, sm_error_reporter);
  JS_SetBranchCallback(cx, sm_branch_callback);

  // create the global object here
  if ((global = JS_NewObject(cx, NULL, NULL, NULL)) == NULL)
    return "JS_NewObject() error";

  // initialize the built-in JS objects and the global object
  if (!JS_InitStandardClasses(cx, global))
    return "JS_InitStandardClasses() error";

  if (!JS_DefineFunctions(cx, global, sm_global_methods))
    return "JS_DefineFunctions() error";

  if (!sm_vim_init(cx, global))
    return "sm_vim_init() error";

  sm_rt = rt;
  sm_cx = cx;
  sm_global = global;

  // Before exiting the application, free the JS run time
  //JS_DestroyContext(cx);
  //JS_DestroyRuntime(rt);
  //JS_ShutDown();

  return NULL;
}

static void
sm_error_reporter(JSContext *cx, const char *message, JSErrorReport *report)
{
  std::ostringstream s;
  if (report != NULL) {
    if (JSREPORT_IS_WARNING(report->flags))
      s << "warning: ";
    if (report->filename)
      s << report->filename << ": ";
    if (report->lineno)
      s << "line " << report->lineno << ": ";
    if (report->linebuf)
      s << "col " << (report->tokenptr - report->linebuf + 1) << ": ";
  }
  s << message;
  if (report != NULL) {
    if (report->linebuf)
      s << ": " << report->linebuf;
  }
  vim.emsg((char_u *)s.str().c_str());
}

static JSBool
sm_branch_callback(JSContext *cx, JSScript *script)
{
  vim.ui_breakcheck();
  if (*vim.got_int)
    return JS_FALSE;
  return JS_TRUE;
}

static JSBool
sm_global_load(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
  char *str;
  if (!JS_ConvertArguments(cx, argc, argv, "s", &str))
    return JS_FALSE;
  execute_file(str);
  return JS_TRUE;
}

static JSObject *
sm_vim_init(JSContext *cx, JSObject *obj)
{
  JSObject *o;
  jsval v;
  if ((o = JS_NewObject(cx, NULL, NULL, NULL)) == NULL)
    return NULL;
  if (!JS_DefineFunctions(cx, o, sm_vim_methods))
    return NULL;
  v = OBJECT_TO_JSVAL(o);
  if (!JS_SetProperty(cx, obj, "vim", &v))
    return NULL;
  return o;
}

static JSBool
sm_vim_eval(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
  char *str;
  if (!JS_ConvertArguments(cx, argc, argv, "s", &str))
    return JS_FALSE;
  typval_T *tv = vim.eval_expr((char_u *)str, NULL);
  LookupMap lookup_map;
  *rval = vim_to_spidermonkey(cx, tv, 1, &lookup_map);
  lookup_map.clear();
  return JS_TRUE;
}

static JSBool
sm_vim_execute(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
  char *str;
  if (!JS_ConvertArguments(cx, argc, argv, "s", &str))
    return JS_FALSE;
  vim.do_cmdline_cmd((char_u *)str);
  vim.update_screen(VALID);
  return JS_TRUE;
}


static jsval
vim_to_spidermonkey(JSContext *cx, typval_T *tv, int depth, LookupMap *lookup_map)
{
  if (tv == NULL || depth > 100)
    return JSVAL_VOID;
  LookupMap::iterator it = lookup_map->find(tv);
  if (it != lookup_map->end())
    return it->second;
  switch (tv->v_type) {
  case VAR_NUMBER:
    return INT_TO_JSVAL(tv->vval.v_number);
  case VAR_FLOAT:
    return DOUBLE_TO_JSVAL(JS_NewDouble(cx, tv->vval.v_float));
  case VAR_STRING:
    return STRING_TO_JSVAL(JS_NewStringCopyZ(cx, (char *)tv->vval.v_string));
  case VAR_FUNC:
    return STRING_TO_JSVAL(JS_NewStringCopyZ(cx, "[function]"));
  case VAR_LIST:
    {
      list_T *list = tv->vval.v_list;
      if (list == NULL)
        return JSVAL_VOID;
      int i = 0;
      JSObject *res = JS_NewArrayObject(cx, 0, NULL);
      for (listitem_T *curr = list->lv_first; curr != NULL; curr = curr->li_next) {
        jsval v = vim_to_spidermonkey(cx, &curr->li_tv, depth + 1, lookup_map);
        JS_SetElement(cx, res, INT_TO_JSVAL(i++), &v);
      }
      lookup_map->insert(LookupMap::value_type(tv, OBJECT_TO_JSVAL(res)));
      return OBJECT_TO_JSVAL(res);
    }
  case VAR_DICT:
    {
      hashtab_T *ht = &tv->vval.v_dict->dv_hashtab;
      long_u todo = ht->ht_used;
      hashitem_T *hi;
      dictitem_T *di;
      JSObject *res = JS_NewObject(cx, NULL, NULL, NULL);
      for (hi = ht->ht_array; todo > 0; ++hi) {
        if (!HASHITEM_EMPTY(hi)) {
          --todo;
          di = HI2DI(hi);
          jsval v = vim_to_spidermonkey(cx, &di->di_tv, depth + 1, lookup_map);
          JS_SetProperty(cx, res, (char *)hi->hi_key, &v);
        }
      }
      lookup_map->insert(LookupMap::value_type(tv, OBJECT_TO_JSVAL(res)));
      return OBJECT_TO_JSVAL(res);
    }
  case VAR_UNKNOWN:
  default:
    return JSVAL_VOID;
  }
}

static void
execute_file(const char *name)
{
  JS_ClearPendingException(sm_cx);
  JSScript *script = JS_CompileFile(sm_cx, sm_global, name);
  if (script == NULL) {
    JS_ReportError(sm_cx, "compile error");
    return;
  }
  jsval result;
  JSBool ok = JS_ExecuteScript(sm_cx, sm_global, script, &result);
  JS_DestroyScript(sm_cx, script);
  if (ok == JS_FALSE)
    JS_ReportError(sm_cx, "execute error");
}

static void
execute_string(const char *expr)
{
  JS_ClearPendingException(sm_cx);
  JSScript *script = JS_CompileScript(sm_cx, sm_global, expr, strlen(expr), NULL, 0);
  if (script == NULL) {
    JS_ReportError(sm_cx, "compile error");
    return;
  }
  jsval result;
  JSBool ok = JS_ExecuteScript(sm_cx, sm_global, script, &result);
  JS_DestroyScript(sm_cx, script);
  if (ok == JS_FALSE)
    JS_ReportError(sm_cx, "execute error");
}
