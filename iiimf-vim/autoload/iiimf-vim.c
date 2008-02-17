/* 2007-03-12 */

#include <iiimcf.h>

#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

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

static vp_iobuf_t *iobuf;
static void *dll_handle;

typedef struct ic_t ic_t;
struct ic_t {
    IIIMCF_context cx;
};

static IIIMCF_handle iiim_handle;

#if 0
#ifdef __FreeBSD__
/* it seems that FreeBSD port of iiimf is broken. */
# define USE_LITTLE_ENDIAN_1 0
# define USE_LITTLE_ENDIAN_2 1
#else
# define USE_LITTLE_ENDIAN_1 0
# define USE_LITTLE_ENDIAN_2 0
#endif
#else
# define USE_LITTLE_ENDIAN_1 0
# define USE_LITTLE_ENDIAN_2 0
#endif

static int iiim_trigger(ic_t *ic, int flag);
#define ST_CHECK(expr) st_check((expr), #expr)
static int st_check(IIIMF_status st, const char *expr);
static const char *status_string(IIIMF_status st);
static char *utf16_to_utf8(const IIIMP_card16 *u16, int little_endian);
static char *iiim_text_to_utf8(IIIMCF_text text, int little_endian);
static void iiim_event_dispatch(ic_t *ic, const char *raw);

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
    IIIMCF_attr attr = NULL;

    if (!ST_CHECK(iiimcf_initialize(IIIMCF_ATTR_NULL)))
        return "iiimcf_initialize error";
    if (!ST_CHECK(iiimcf_create_attr(&attr)))
        return "iiimcf_create_attr error";
    if (!ST_CHECK(iiimcf_attr_put_string_value(attr,
                    IIIMCF_ATTR_CLIENT_TYPE, "Vim")))
        return "iiimcf_attr_put_string_value error";
#if 0
    if (!ST_CHECK(iiimcf_attr_put_integer_value(attr,
                IIIMCF_ATTR_DISABLE_AUTOMATIC_RESTORATION, 1)))
        return "iiimcf_attr_put_integer_value error";
#endif
    if (!ST_CHECK(iiimcf_create_handle(attr, &iiim_handle)))
        return "iiimcf_create_handle error";
    if (!ST_CHECK(iiimcf_destroy_attr(attr)))
        return "iiimcf_destroy_attr error";

    return NULL;
}

const char *
uninit(const char *args)
{
    int lib_quit;

    if (!vp_iobuf_get_args(iobuf, args, "d", &lib_quit))
        return vp_iobuf_return(iobuf);

    if (iiim_handle != NULL) {
        ST_CHECK(iiimcf_destroy_handle(iiim_handle));
        iiim_handle = NULL;
        if (lib_quit)
            ST_CHECK(iiimcf_finalize());
        vp_iobuf_clear(iobuf);
    }
    return NULL;
}

const char *
get_imlist(const char *args)
{
    char langs[256];
    int i, j, nmethods, nlangs;
    const IIIMP_card16 *u16idname, *u16hrn, *u16domain;
    IIIMCF_input_method *im_list;
    const char *langid;
    IIIMCF_language *lang_list;

    if (!vp_iobuf_get_args(iobuf, args, ""))
        return vp_iobuf_return(iobuf);

    /* [method, langs, desc, is_default] */
    if (!ST_CHECK(iiimcf_get_supported_input_methods(iiim_handle, &nmethods, &im_list)))
        return "iiimcf_get_supported_input_methods error";
    for (i = 0; i < nmethods; ++i) {
        if (!ST_CHECK(iiimcf_get_input_method_desc(im_list[i], &u16idname, &u16hrn, &u16domain)))
            return "iiimcf_get_input_method_desc error";
        if (!ST_CHECK(iiimcf_get_input_method_languages(im_list[i], &nlangs, &lang_list)))
            return "iiimcf_get_input_method_languages error";
        strcpy(langs, "");
        for (j = 0; j < nlangs; ++j) {
            if (!ST_CHECK(iiimcf_get_language_id(lang_list[j], &langid)))
                return "iiimcf_get_language_id error";
            if (j != 0)
                strcat(langs, ":");
            strcat(langs, langid);
        }
        vp_iobuf_put_str(iobuf, utf16_to_utf8(u16idname, USE_LITTLE_ENDIAN_1));
        vp_iobuf_put_str(iobuf, langs);
        /* TODO: u16hrn is not description of Input Method. */
        vp_iobuf_put_str(iobuf, utf16_to_utf8(u16hrn, USE_LITTLE_ENDIAN_1));
        /* TODO: how to detect default method */
        vp_iobuf_put_num(iobuf, 0);
    }

    return vp_iobuf_return(iobuf);
}

const char *
create_context(const char *args)
{
    char *method;
    char *lang;
    IIIMCF_attr attr = NULL;
    IIIMCF_input_method iiim_im = NULL;
    IIIMCF_language iiim_lang = NULL;
    ic_t *ic;

    if (!vp_iobuf_get_args(iobuf, args, "ss", &method, &lang))
        return vp_iobuf_return(iobuf);

    ic = malloc(sizeof(ic_t));
    if (!ic)
        return "malloc error";

    {
        int i, j, nmethods, nlangs;
        const IIIMP_card16 *u16idname, *u16hrn, *u16domain;
        IIIMCF_input_method *im_list;
        const char *langid;
        IIIMCF_language *lang_list;

        if (!ST_CHECK(iiimcf_get_supported_input_methods(iiim_handle, &nmethods, &im_list)))
            return "iiimcf_get_supported_input_methods error";
        for (i = 0; i < nmethods; ++i) {
            if (!ST_CHECK(iiimcf_get_input_method_desc(im_list[i], &u16idname, &u16hrn, &u16domain)))
                return "iiimcf_get_input_method_desc error";
            if (strcmp(utf16_to_utf8(u16idname, USE_LITTLE_ENDIAN_1), method) == 0) {
                iiim_im = im_list[i];
                break;
            }
        }
        if (iiim_im == NULL)
            return "cannot select input method";
        if (!ST_CHECK(iiimcf_get_input_method_languages(iiim_im, &nlangs, &lang_list)))
            return "iiimcf_get_input_method_languages error";
        for (j = 0; j < nlangs; ++j) {
            if (!ST_CHECK(iiimcf_get_language_id(lang_list[j], &langid)))
                return "iiimcf_get_language_id error";
            if (strcmp(langid, lang) == 0) {
                iiim_lang = lang_list[j];
                break;
            }
        }
        if (iiim_lang == NULL)
            return "language is not supported";
    }
    if (!ST_CHECK(iiimcf_create_attr(&attr)))
        return "iiimcf_create_attr error";
    if (!ST_CHECK(iiimcf_attr_put_ptr_value(attr, IIIMCF_ATTR_INPUT_LANGUAGE, iiim_lang)))
        return "iiimcf_attr_put_ptr_value error";
    if (!ST_CHECK(iiimcf_attr_put_ptr_value(attr, IIIMCF_ATTR_INPUT_METHOD, iiim_im)))
        return "iiimcf_attr_put_ptr_value error";
    if (!ST_CHECK(iiimcf_create_context(iiim_handle, attr, &(ic->cx))))
        return "iiimcf_create_context error";
    if (!ST_CHECK(iiimcf_destroy_attr(attr)))
        return "iiimcf_destroy_attr error";

    vp_iobuf_put_str(iobuf, "create_context");
    vp_iobuf_put_ptr(iobuf, ic);

    iiim_trigger(ic, 1);
    iiim_event_dispatch(ic, "");

    return vp_iobuf_return(iobuf);
}

const char *
delete_context(const char *args)
{
    ic_t *ic;

    if (!vp_iobuf_get_args(iobuf, args, "p", &ic))
        return vp_iobuf_return(iobuf);

    ST_CHECK(iiimcf_destroy_context(ic->cx));
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
    IIIMCF_event ev;
    IIIMCF_keyevent kev;

    if (!vp_iobuf_get_args(iobuf, args, "pddb", &ic, &code, &mod, &raw, 0))
        return vp_iobuf_return(iobuf);

    kev.keycode = code;
    kev.modifier = mod;
    if (strlen(raw) == 1) /* normal char */
        kev.keychar = raw[0]; /* TODO: convert to ucs4? */
    else
        kev.keychar = 0;
    kev.time_stamp = time(NULL);

    ST_CHECK(iiimcf_create_keyevent(&kev, &ev));
    ST_CHECK(iiimcf_forward_event(ic->cx, ev));
    iiim_event_dispatch(ic, raw);

    return vp_iobuf_return(iobuf);
}

static int
iiim_trigger(ic_t *ic, int flag)
{
    IIIMCF_event ev;
    ST_CHECK(iiimcf_create_trigger_notify_event(flag, &ev));
    ST_CHECK(iiimcf_forward_event(ic->cx, ev));
    return 0;
}

static int
st_check(IIIMF_status st, const char *expr)
{
    if (debug) fprintf(stderr, "%s: %s\n", expr, status_string(st));
    return (st == IIIMF_STATUS_SUCCESS);
}

static const char *
status_string(IIIMF_status st)
{
#define CASE_RETURN(st) case st: return #st;
    switch (st) {
    CASE_RETURN(IIIMF_STATUS_FAIL)
    CASE_RETURN(IIIMF_STATUS_SUCCESS)

    CASE_RETURN(IIIMF_STATUS_MALLOC)
    CASE_RETURN(IIIMF_STATUS_ARGUMENT)
    CASE_RETURN(IIIMF_STATUS_PROTOCOL_VERSION)

    CASE_RETURN(IIIMF_STATUS_CONFIG)
    CASE_RETURN(IIIMF_STATUS_ROLE)

    CASE_RETURN(IIIMF_STATUS_OPCODE)

    CASE_RETURN(IIIMF_STATUS_SEQUENCE_REQUEST)
    CASE_RETURN(IIIMF_STATUS_SEQUENCE_REPLY)
    CASE_RETURN(IIIMF_STATUS_SEQUENCE_ROLE)
    CASE_RETURN(IIIMF_STATUS_SEQUENCE_STATE)
    CASE_RETURN(IIIMF_STATUS_SEQUENCE_NEST)

    CASE_RETURN(IIIMF_STATUS_IM_INVALID)
    CASE_RETURN(IIIMF_STATUS_IC_INVALID)

    CASE_RETURN(IIIMF_STATUS_STREAM)
    CASE_RETURN(IIIMF_STATUS_STREAM_SEND)
    CASE_RETURN(IIIMF_STATUS_STREAM_RECEIVE)
    CASE_RETURN(IIIMF_STATUS_PACKET)
    CASE_RETURN(IIIMF_STATUS_INVALID_ID)
    CASE_RETURN(IIIMF_STATUS_TIMEOUT)
    CASE_RETURN(IIIMF_STATUS_CONNECTION_CLOSED)

    CASE_RETURN(IIIMF_STATUS_IIIMCF_START)
    CASE_RETURN(IIIMF_STATUS_NO_ATTR_VALUE)
    CASE_RETURN(IIIMF_STATUS_NO_TEXT_PROPERTY)
    CASE_RETURN(IIIMF_STATUS_NO_EVENT)
    CASE_RETURN(IIIMF_STATUS_NO_PREEDIT)
    CASE_RETURN(IIIMF_STATUS_NO_LOOKUP_CHOICE)
    CASE_RETURN(IIIMF_STATUS_NO_STATUS_TEXT)
    CASE_RETURN(IIIMF_STATUS_NO_COMMITTED_TEXT)
    CASE_RETURN(IIIMF_STATUS_CLIENT_RESET_BY_PEER)
    CASE_RETURN(IIIMF_STATUS_INVALID_EVENT_TYPE)
    CASE_RETURN(IIIMF_STATUS_EVENT_NOT_FORWARDED)
    CASE_RETURN(IIIMF_STATUS_COMPONENT_DUPLICATED_NAME)
    CASE_RETURN(IIIMF_STATUS_COMPONENT_FAIL)
    CASE_RETURN(IIIMF_STATUS_NO_COMPONENT)
    CASE_RETURN(IIIMF_STATUS_STATIC_EVENT_FLOW)
    CASE_RETURN(IIIMF_STATUS_FAIL_TO_EVENT_DISPATCH)
    CASE_RETURN(IIIMF_STATUS_NO_AUX)
    CASE_RETURN(IIIMF_STATUS_NOT_TRIGGER_KEY)
    CASE_RETURN(IIIMF_STATUS_COMPONENT_INDIFFERENT)
    default: return NULL;
    }
#undef CASE_RETURN
}

static char *
utf16_to_utf8(const IIIMP_card16 *u16, int little_endian)
{
    static char buf[8196];
    int c;
    char *p = buf;

    while ((c = *u16++)) {
        /* WORKAROUND: remove BOM */
        if (c == 0xFEFF)
            continue;
        if (little_endian)
            c = ((c & 0xFF00) >> 8) | ((c & 0xFF) << 8);
        if (0xD800 <= c && c <= 0xDBFF) {
            int c2 = *u16++;
            if (little_endian)
                c2 = ((c2 & 0xFF00) >> 8) | ((c2 & 0xFF) << 8);
            c = (((c & 0x3FF) << 10) | (c2 & 0x3FF)) + 0x10000;
        }

        if (c <= 0x7F) {
            *p++ = c;
        } else if (0x80 <= c && c <= 0x7FF) {
            *p++ = (c >> 6) | 0xC0;
            *p++ = (c & 0x3F) | 0x80;
        } else if (0x0800 <= c && c <= 0xFFFF) {
            *p++ = (c >> 12) | 0xE0;
            *p++ = ((c >> 6) & 0x3F) | 0x80;
            *p++ = (c & 0x3F) | 0x80;
        } else if (0x010000 <= c && c <= 0x10FFFF) {
            *p++ = (c >> 18) | 0xF0;
            *p++ = ((c >> 12) & 0x3F) | 0x80;
            *p++ = ((c >> 6) & 0x3F) | 0x80;
            *p++ = (c & 0x3F) | 0x80;
        }
    }
    *p = 0;
    return buf;
}

static char *
iiim_text_to_utf8(IIIMCF_text text, int little_endian)
{
    const IIIMP_card16 *u16;
    if (ST_CHECK(iiimcf_get_text_utf16string(text, &u16)))
        return utf16_to_utf8(u16, little_endian);
    return NULL;
}

static void
iiim_event_dispatch(ic_t *ic, const char *raw)
{
    IIIMCF_event ev;
    IIIMCF_event_type et;

    while (ST_CHECK(iiimcf_get_next_event(ic->cx, &ev))) {
        if (!ST_CHECK(iiimcf_get_event_type(ev, &et)))
            continue;

        if (debug) fprintf(stderr, "event: 0x%08X\n", et);

        switch (et) {
        case IIIMCF_EVENT_TYPE_TRIGGER_NOTIFY:
            {
                int flag;
                ST_CHECK(iiimcf_get_trigger_notify_flag(ev, &flag));
                if (debug) fprintf(stderr, "TRIGGER_NOTIFY: %d\n", flag);
            }
            break;
        case IIIMCF_EVENT_TYPE_UI_PREEDIT_START:
            if (debug) fprintf(stderr, "PREEDIT_START\n");
            break;
        case IIIMCF_EVENT_TYPE_UI_PREEDIT_CHANGE:
            if (debug) fprintf(stderr, "PREEDIT_CHANGE\n");

            {
                IIIMF_status st;
                IIIMCF_text text;
                const char *str;
                int pos;

                if (ST_CHECK(st = iiimcf_get_preedit_text(ic->cx, &text, &pos))) {
                    str = iiim_text_to_utf8(text, USE_LITTLE_ENDIAN_2);
                    if (debug) fprintf(stderr, "Preedit(%d):%s\n", pos, str);
                    vp_iobuf_put_str(iobuf, "preedit_pushback");
                    vp_iobuf_put_str(iobuf, str);
                    vp_iobuf_put_num(iobuf, pos);
                } else if (st == IIIMF_STATUS_NO_PREEDIT) {
                    if (debug) fprintf(stderr, "Preedit is disabled\n");
                    vp_iobuf_put_str(iobuf, "preedit_clear");
                }
            }
            break;
        case IIIMCF_EVENT_TYPE_UI_PREEDIT_DONE:
            if (debug) fprintf(stderr, "PREEDIT_DONE\n");
            vp_iobuf_put_str(iobuf, "preedit_clear");
            break;
        case IIIMCF_EVENT_TYPE_UI_LOOKUP_CHOICE_START:
            if (debug) fprintf(stderr, "LOOKUP_CHOICE_START\n");
            break;
        case IIIMCF_EVENT_TYPE_UI_LOOKUP_CHOICE_CHANGE:
            if (debug) fprintf(stderr, "LOOKUP_CHOICE_CHANGE\n");

            {
                IIIMCF_lookup_choice luc;
                IIIMCF_text title, text, label;
                int nr, first, last, current, flag;
                int i;
                const char *str;

                vp_iobuf_put_str(iobuf, "candidate_activate");
                if (ST_CHECK(iiimcf_get_lookup_choice(ic->cx, &luc))) {
                    ST_CHECK(iiimcf_get_lookup_choice_title(luc, &title));
                    str = iiim_text_to_utf8(title, USE_LITTLE_ENDIAN_1);
                    if (debug) fprintf(stderr, "title: %s\n", str);
                    ST_CHECK(iiimcf_get_lookup_choice_size(luc,
                                                &nr, &first, &last, &current));
                    /* "candidate", first, last, current, candlen, [label, str], ... */
                    vp_iobuf_put_str(iobuf, "candidate");
                    vp_iobuf_put_num(iobuf, first);
                    vp_iobuf_put_num(iobuf, last);
                    vp_iobuf_put_num(iobuf, current);
                    vp_iobuf_put_num(iobuf, nr);
                    for (i = 0; i < nr; ++i) {
                        ST_CHECK(iiimcf_get_lookup_choice_item(luc, i,
                                    &text, &label, &flag));
                        str = iiim_text_to_utf8(label, USE_LITTLE_ENDIAN_2);
                        vp_iobuf_put_str(iobuf, str);
                        str = iiim_text_to_utf8(text, USE_LITTLE_ENDIAN_2);
                        vp_iobuf_put_str(iobuf, str);
                    }
                }
            }
            break;
        case IIIMCF_EVENT_TYPE_UI_LOOKUP_CHOICE_DONE:
            if (debug) fprintf(stderr, "LOOKUP_CHOICE_DONE\n");
            vp_iobuf_put_str(iobuf, "candidate_deactivate");
            break;
        case IIIMCF_EVENT_TYPE_UI_STATUS_START:
            if (debug) fprintf(stderr, "STARUT_START\n");
            break;
        case IIIMCF_EVENT_TYPE_UI_STATUS_CHANGE:
            if (debug) fprintf(stderr, "STARUT_CHANGE\n");

            {
                IIIMF_status st;
                IIIMCF_text text;
                const char *str;

                if (!ST_CHECK(st = iiimcf_get_status_text(ic->cx, &text))
                        || st == IIIMF_STATUS_NO_STATUS_TEXT)
                    str = "";
                else
                    str = iiim_text_to_utf8(text, USE_LITTLE_ENDIAN_2);
                if (debug) fprintf(stderr, "status: %s\n", str);
                vp_iobuf_put_str(iobuf, "status");
                vp_iobuf_put_str(iobuf, str);
            }
            break;
        case IIIMCF_EVENT_TYPE_UI_STATUS_DONE:
            if (debug) fprintf(stderr, "STARUT_DONE\n");
            break;
        case IIIMCF_EVENT_TYPE_UI_COMMIT:
            {
                IIIMCF_text text;
                const char *str;

                if (ST_CHECK(iiimcf_get_committed_text(ic->cx, &text))) {
                    str = iiim_text_to_utf8(text, USE_LITTLE_ENDIAN_2);
                    if (debug) fprintf(stderr, "commit: %s\n", str);
                    vp_iobuf_put_str(iobuf, "commit");
                    vp_iobuf_put_str(iobuf, str);
                }
            }
            break;
        case IIIMCF_EVENT_TYPE_KEYEVENT:
            {
                IIIMCF_keyevent kev;
                const char *str;

                if (ST_CHECK(iiimcf_get_keyevent_value(ev, &kev))) {
                    str = raw;
                    if (debug) {
                        const unsigned char *p = (unsigned char *)str;
                        fprintf(stderr, "key commit:");
                        while (*p)
                            fprintf(stderr, " %02X", *p++);
                        fprintf(stderr, "\n");
                    }
                    vp_iobuf_put_str(iobuf, "commit_raw");
                    vp_iobuf_put_bin(iobuf, raw, strlen(raw));
                }
            }
            break;
        default:
            break;
        }
        ST_CHECK(iiimcf_dispatch_event(ic->cx, ev));
        ST_CHECK(iiimcf_ignore_event(ev));
    }
}

