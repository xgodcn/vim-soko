/* 2007-02-10 */

#include <uim/uim.h>
#include <uim/uim-im-switcher.h>
#include <uim/uim-scm.h>

#include <dlfcn.h>
#include <string.h>
#include <stdlib.h>

#include "vp_iobuf.c"

#ifdef DEBUG
const int debug = 1;
#else
const int debug = 0;
#endif

/* API */
const char *load(const char *args);
const char *unload(const char *args);
const char *init(const char *args);
const char *uninit(const char *args);
const char *get_imlist(const char *args);
const char *create_context(const char *args);
const char *delete_context(const char *args);
const char *send_key(const char *args);
const char *load_key_constant(const char *args);

static vp_iobuf_t *iobuf;
static void *dll_handle;

typedef struct ic_t ic_t;
struct ic_t {
    uim_context cx;
    int cand_index;
    int cand_nr;
    int cand_limit;
};

static void commit_cb(void *ptr, const char *str);
static void preedit_clear_cb(void *ptr);
static void preedit_pushback_cb(void *ptr, int attr, const char *str);
static void preedit_update_cb(void *ptr);
static void candidate_activate_cb(void *ptr, int nr, int display_limit);
static void candidate_select_cb(void *ptr, int index);
static void candidate_shift_page_cb(void *ptr, int direction);
static void candidate_deactivate_cb(void *ptr);
static void property_list_update_cb(void *ptr, const char *str);

const char *
load(const char *args)
{
    char *path;

    if (!dll_handle) {
        iobuf = vp_iobuf_new();
        if (!iobuf)
            return "vp_iobuf_new: error";
        if (!vp_iobuf_get_args(iobuf, args, "s", &path)) /* never happen */
            return vp_iobuf_return(iobuf);
        dll_handle = dlopen(path, RTLD_LAZY);
        if (!dll_handle) {
            vp_iobuf_delete(iobuf);
            return dlerror();
        }
    }
    return 0;
}

const char *
unload(const char *args)
{
    if (dll_handle) {
        dlclose(dll_handle);
        vp_iobuf_delete(iobuf);
        dll_handle = 0;
        iobuf = 0;
    }
    return 0;
}

const char *
init(const char *args)
{
    if (uim_init() != 0)
        return "uim_init() failed"; /* according to uim.c, this never happen. */
    return NULL;
}

const char *
uninit(const char *args)
{
    uim_quit();
    return NULL;
}

const char *
get_imlist(const char *args)
{
    int i, nr;
    uim_context uc;

    if (!vp_iobuf_get_args(iobuf, args, ""))
        return vp_iobuf_return(iobuf);

    uc = uim_create_context(NULL, "UTF-8", NULL, NULL, NULL, NULL);
    if (uc == NULL)
        return "uim_create_context error";

    /* [method, langs, desc, is_default] */
    nr = uim_get_nr_im(uc);
    for (i = 0; i < nr; ++i) {
        vp_iobuf_put_str(iobuf, uim_get_im_name(uc, i));
        vp_iobuf_put_str(iobuf, uim_get_im_language(uc, i));
        vp_iobuf_put_str(iobuf, uim_get_im_short_desc(uc, i));
        vp_iobuf_put_num(iobuf, (strcmp(uim_get_im_name(uc, i),
                                        uim_get_default_im_name("")) == 0));
    }

    uim_release_context(uc);

    return vp_iobuf_return(iobuf);
}

const char *
create_context(const char *args)
{
    char *method;
    char *lang;
    ic_t *ic;

    if (!vp_iobuf_get_args(iobuf, args, "ss", &method, &lang))
        return vp_iobuf_return(iobuf);

    ic = malloc(sizeof(ic_t));
    if (ic == NULL)
        return "malloc error";
    ic->cand_index = 0;
    ic->cand_nr = 0;
    ic->cand_limit = 0;
    ic->cx = uim_create_context(ic, "UTF-8", lang, method, NULL, commit_cb);
    if (ic->cx == NULL) {
        free(ic);
        return "uim_create_context error";
    }

    /* Install callback functions */
    uim_set_preedit_cb(ic->cx,
                       preedit_clear_cb,
                       preedit_pushback_cb,
                       preedit_update_cb);
    uim_set_candidate_selector_cb(ic->cx,
                                  candidate_activate_cb,
                                  candidate_select_cb,
                                  candidate_shift_page_cb,
                                  candidate_deactivate_cb);
    uim_set_prop_list_update_cb(ic->cx, property_list_update_cb);

    /*
     * Turn on Input Mode.
     * TODO: Use proper method.  "action" can be used?
     */
    uim_scm_call_with_gc_ready_stack(
            (uim_gc_gate_func_ptr)uim_scm_eval_c_string,
            (void*)
            "(if (and (symbol-bound? 'generic-on-key) generic-on-key)"
            "  (let* ((id (context-id (car context-list)))"
            "         (parsed (parse-key-str (car generic-on-key) () -1 0))"
            "         (key (list-ref parsed 2))"
            "         (mod (list-ref parsed 3)))"
            "    (key-press-handler id key mod)"
            "    (key-release-handler id key mod)"
            "  ))"
            );

    vp_iobuf_put_str(iobuf, "create_context");
    vp_iobuf_put_ptr(iobuf,  ic);

    return vp_iobuf_return(iobuf);
}

const char *
delete_context(const char *args)
{
    ic_t *ic;

    if (!vp_iobuf_get_args(iobuf, args, "p", &ic))
        return vp_iobuf_return(iobuf);

    uim_release_context(ic->cx);
    free(ic);

    return NULL;
}

const char *
send_key(const char *args)
{
    ic_t *ic;
    int code;
    int mod;
    char *raw;
    int rawcommit;

    if (!vp_iobuf_get_args(iobuf, args, "pddb", &ic, &code, &mod, &raw, 0))
        return vp_iobuf_return(iobuf);

/*
 * @return 0 if IM not handle the event, otherwise the event is handled by IM so please stop key event handling.
 * uim_press_key()
 *
 * i don't understand.
 */
    rawcommit = uim_press_key(ic->cx, code, mod);
    uim_release_key(ic->cx, code, mod);
    if (rawcommit) {
        vp_iobuf_put_str(iobuf, "commit_raw");
        vp_iobuf_put_bin(iobuf, raw, strlen(raw));
    }
    return vp_iobuf_return(iobuf);
}

const char *
load_key_constant(const char *args)
{
    if (!vp_iobuf_get_args(iobuf, args, ""))
        return vp_iobuf_return(iobuf);

    vp_iobuf_put_vars(iobuf, "sd", "UKey_0", UKey_0);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_1", UKey_1);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_2", UKey_2);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_3", UKey_3);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_4", UKey_4);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_5", UKey_5);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_6", UKey_6);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_7", UKey_7);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_8", UKey_8);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_9", UKey_9);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Escape", UKey_Escape);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Tab", UKey_Tab);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Backspace", UKey_Backspace);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Delete", UKey_Delete);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Return", UKey_Return);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Left", UKey_Left);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Up", UKey_Up);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Right", UKey_Right);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Down", UKey_Down);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Prior", UKey_Prior);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Next", UKey_Next);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Home", UKey_Home);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_End", UKey_End);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Multi_key", UKey_Multi_key);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Mode_switch", UKey_Mode_switch);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Kanji", UKey_Kanji);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Muhenkan", UKey_Muhenkan);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Henkan_Mode", UKey_Henkan_Mode);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Romaji", UKey_Romaji);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Hiragana", UKey_Hiragana);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Katakana", UKey_Katakana);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Hiragana_Katakana", UKey_Hiragana_Katakana);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Zenkaku", UKey_Zenkaku);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Hankaku", UKey_Hankaku);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Zenkaku_Hankaku", UKey_Zenkaku_Hankaku);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Touroku", UKey_Touroku);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Massyo", UKey_Massyo);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Kana_Lock", UKey_Kana_Lock);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Kana_Shift", UKey_Kana_Shift);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Eisu_Shift", UKey_Eisu_Shift);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Eisu_toggle", UKey_Eisu_toggle);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_F1", UKey_F1);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_F2", UKey_F2);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_F3", UKey_F3);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_F4", UKey_F4);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_F5", UKey_F5);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_F6", UKey_F6);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_F7", UKey_F7);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_F8", UKey_F8);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_F9", UKey_F9);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_F10", UKey_F10);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_F11", UKey_F11);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_F12", UKey_F12);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_F13", UKey_F13);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_F14", UKey_F14);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_F15", UKey_F15);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_F16", UKey_F16);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_F17", UKey_F17);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_F18", UKey_F18);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_F19", UKey_F19);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_F20", UKey_F20);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_F21", UKey_F21);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_F22", UKey_F22);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_F23", UKey_F23);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_F24", UKey_F24);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_F25", UKey_F25);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_F26", UKey_F26);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_F27", UKey_F27);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_F28", UKey_F28);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_F29", UKey_F29);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_F30", UKey_F30);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_F31", UKey_F31);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_F32", UKey_F32);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_F33", UKey_F33);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_F34", UKey_F34);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_F35", UKey_F35);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Private1", UKey_Private1);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Private2", UKey_Private2);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Private3", UKey_Private3);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Private4", UKey_Private4);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Private5", UKey_Private5);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Private6", UKey_Private6);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Private7", UKey_Private7);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Private8", UKey_Private8);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Private9", UKey_Private9);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Private10", UKey_Private10);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Private11", UKey_Private11);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Private12", UKey_Private12);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Private13", UKey_Private13);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Private14", UKey_Private14);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Private15", UKey_Private15);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Private16", UKey_Private16);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Private17", UKey_Private17);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Private18", UKey_Private18);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Private19", UKey_Private19);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Private20", UKey_Private20);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Private21", UKey_Private21);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Private22", UKey_Private22);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Private23", UKey_Private23);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Private24", UKey_Private24);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Private25", UKey_Private25);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Private26", UKey_Private26);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Private27", UKey_Private27);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Private28", UKey_Private28);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Private29", UKey_Private29);
    vp_iobuf_put_vars(iobuf, "sd", "UKey_Private30", UKey_Private30);

    /* modifier */
    vp_iobuf_put_vars(iobuf, "sd", "UMod_Shift", UMod_Shift);
    vp_iobuf_put_vars(iobuf, "sd", "UMod_Control", UMod_Control);
    vp_iobuf_put_vars(iobuf, "sd", "UMod_Alt", UMod_Alt);
    vp_iobuf_put_vars(iobuf, "sd", "UMod_Meta", UMod_Meta);
    vp_iobuf_put_vars(iobuf, "sd", "UMod_Pseudo0", UMod_Pseudo0);
    vp_iobuf_put_vars(iobuf, "sd", "UMod_Pseudo1", UMod_Pseudo1);
    vp_iobuf_put_vars(iobuf, "sd", "UMod_Super", UMod_Super);
    vp_iobuf_put_vars(iobuf, "sd", "UMod_Hyper", UMod_Hyper);

    return vp_iobuf_return(iobuf);
}

static void
commit_cb(void *ptr, const char *str)
{
    if (debug) fprintf(stderr, "commit_cb: str=\"%s\"\n", str);
    vp_iobuf_put_str(iobuf, "commit");
    vp_iobuf_put_str(iobuf, str);
}

static void
preedit_clear_cb(void *ptr)
{
    if (debug) fprintf(stderr, "preedit_clear_cb:\n");
    vp_iobuf_put_str(iobuf, "preedit_clear");
}

static void
preedit_pushback_cb(void *ptr, int attr, const char *str)
{
    if (debug) fprintf(stderr, "preedit_pushback: attr=%d str=\"%s\"\n", attr, str);
    vp_iobuf_put_str(iobuf, "preedit_pushback");
    vp_iobuf_put_str(iobuf, str);
    vp_iobuf_put_num(iobuf, attr);
}

static void
preedit_update_cb(void *ptr)
{
    if (debug) fprintf(stderr, "preedit_update:\n");
}

static void
candidate_activate_cb(void *ptr, int nr, int display_limit)
{
    ic_t *ic = (ic_t *)ptr;
    int i;
    uim_candidate cand;

    ic->cand_nr = nr;
    ic->cand_limit = display_limit;

    if (debug) fprintf(stderr, "candidate_activate: nr=%d display_limit=%d\n", nr, display_limit);

    vp_iobuf_put_str(iobuf, "candidate_activate");
    /* "candidate", pagesize, candlen, [label, str, annotation], ... */
    vp_iobuf_put_str(iobuf, "candidate");
    vp_iobuf_put_num(iobuf, display_limit);
    vp_iobuf_put_num(iobuf, nr);
    for (i = 0; i < nr; ++i) {
        cand = uim_get_candidate(ic->cx, i, 0);
        vp_iobuf_put_str(iobuf, uim_candidate_get_heading_label(cand));
        vp_iobuf_put_str(iobuf, uim_candidate_get_cand_str(cand));
        vp_iobuf_put_str(iobuf, uim_candidate_get_annotation_str(cand));
        uim_candidate_free(cand);
    }
}

static void
candidate_select_cb(void *ptr, int index)
{
    ic_t *ic = (ic_t *)ptr;

    ic->cand_index = index;

    if (debug) fprintf(stderr, "candidate_select: index=%d\n", index);
    vp_iobuf_put_str(iobuf, "candidate_select");
    vp_iobuf_put_num(iobuf, index);
}

static void
candidate_shift_page_cb(void *ptr, int direction)
{
    ic_t *ic = (ic_t *)ptr;

    if (debug) fprintf(stderr, "candidate_shift_page: direction=%d\n", direction);

    if (direction < 0) {
        /* to left */
        ic->cand_index -= ic->cand_limit;
        if (ic->cand_index < 0)
            ic->cand_index += ic->cand_nr;
    } else {
        /* to right */
        if (ic->cand_index / ic->cand_limit == (ic->cand_nr - 1) / ic->cand_limit)
            /* cursor is on last page. go to first page. */
            ic->cand_index = ic->cand_index % ic->cand_limit;
        else
            ic->cand_index += ic->cand_limit;
    }
    if (ic->cand_index >= ic->cand_nr)
        ic->cand_index = ic->cand_nr - 1;
    uim_set_candidate_index(ic->cx, ic->cand_index);

    /* XXX */
    candidate_activate_cb(ptr, ic->cand_nr, ic->cand_limit);
    candidate_select_cb(ptr, ic->cand_index);
}

static void
candidate_deactivate_cb(void *ptr)
{
    if (debug) fprintf(stderr, "candidate_deactivate:\n");
    vp_iobuf_put_str(iobuf, "candidate_deactivate");
}

static void
property_list_update_cb(void *ptr, const char *str)
{
    ic_t *ic = (ic_t *)ptr;

    if (debug) fprintf(stderr, "property_list_update:\n%s\n", str);
    vp_iobuf_put_str(iobuf, "property_list_update");
    vp_iobuf_put_str(iobuf, str);
    vp_iobuf_put_str(iobuf, uim_get_current_im_name(ic->cx));
}

