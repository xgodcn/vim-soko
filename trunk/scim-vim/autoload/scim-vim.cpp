/* 2007-02-11 */

/* API */
extern "C" {
const char *load(const char *args);
const char *unload(const char *args);
const char *init(const char *args);
const char *uninit(const char *args);
const char *get_imlist(const char *args);
const char *create_context(const char *args);
const char *delete_context(const char *args);
const char *send_key(const char *args);
}

#define Uses_SCIM_DEBUG
#define Uses_SCIM_BACKEND
#define Uses_SCIM_IMENGINE
#define Uses_SCIM_IMENGINE_MODULE
#define Uses_SCIM_CONFIG
#define Uses_SCIM_CONFIG_MODULE
#define Uses_SCIM_CONFIG_PATH
#define Uses_SCIM_TRANSACTION
#define Uses_SCIM_HOTKEY
#include <scim.h>

#include <dlfcn.h>

#include <cstdio>
#include <vector>
#include <cctype>

#include <stdexcept>
#include <string>
#include <vector>
#include <sstream>
#include <cstdlib>
#include <cctype>

namespace vp {

using namespace std;

const char EOV = '\x01';

typedef vector<unsigned char> buf_t;

class iobuf_t {
  stringstream m_strm;
  string m_str;

public:
  iobuf_t(const string& s = "")
    : m_strm(s)
  {}
  void str(const string& s) {
    m_strm.clear();
    m_strm.str(s);
  }
  const char *str() {
    m_str = m_strm.str();
    return m_str.c_str();
  }
  stringstream& strm() {
    return m_strm;
  }
  template <typename T>
  iobuf_t& operator >> (T& var) {
    stringstream tmp;
    string s;

    getline(m_strm, s, EOV);
    tmp << s;
    tmp >> var;
    if (!tmp.eof())
      throw logic_error("format error");
    return *this;
  }
  iobuf_t& operator >> (string& var) {
    getline(m_strm, var, EOV);
    return *this;
  }
  iobuf_t& operator >> (buf_t& var) {
    char tmp[3] = {0,};
    string s;

    getline(m_strm, s, EOV);
    var.clear();
    for (const char *p = s.c_str(); *p; p += 2) {
      if (!isxdigit(p[0]) || !isxdigit(p[1]))
        throw logic_error("format error");
      tmp[0] = p[0];
      tmp[1] = p[1];
      var.push_back(strtol(tmp, 0, 16));
    }
    return *this;
  }
  template <typename T>
  iobuf_t& operator << (const T& var) {
    m_strm << var << EOV;
    return *this;
  }
  iobuf_t& operator << (const buf_t& var) {
    const char hex[] = "0123456789ABCDEF";

    for (buf_t::const_iterator it = var.begin(); it != var.end(); ++it)
      m_strm << hex[*it >> 4] << hex[*it & 0xF];
    m_strm << EOV;
    return *this;
  }
};

} // namespace vp

using namespace std;
using namespace scim;

#ifdef DEBUG
const int debug = 1;
#else
const int debug = 0;
#endif

static vp::iobuf_t iobuf;
static void* dll_handle;

struct ic_t {
    IMEngineInstancePointer instance;
    IMEngineFactoryPointer factory;
};

static int instance_id;
static BackEndPointer m_backend;
static ConfigPointer m_config;
static ConfigModule* m_config_module;
static FrontEndHotkeyMatcher m_frontend_hotkey_matcher;
static IMEngineHotkeyMatcher m_imengine_hotkey_matcher;
static KeyboardLayout m_keyboard_layout = SCIM_KEYBOARD_Default;
static int m_valid_key_mask = SCIM_KEY_AllMasks;


static void attach_instance(const IMEngineInstancePointer& si);

static void slot_show_preedit_string (IMEngineInstanceBase *si);
static void slot_show_aux_string (IMEngineInstanceBase *si);
static void slot_show_lookup_table (IMEngineInstanceBase *si);

static void slot_hide_preedit_string (IMEngineInstanceBase *si);
static void slot_hide_aux_string (IMEngineInstanceBase *si);
static void slot_hide_lookup_table (IMEngineInstanceBase *si);

static void slot_update_preedit_caret (IMEngineInstanceBase *si, int caret);
static void slot_update_preedit_string (IMEngineInstanceBase *si, const WideString &str, const AttributeList &attrs);
static void slot_update_aux_string (IMEngineInstanceBase *si, const WideString &str, const AttributeList &attrs);
static void slot_commit_string (IMEngineInstanceBase *si, const WideString &str);
static void slot_forward_key_event (IMEngineInstanceBase *si, const KeyEvent &key);
static void slot_update_lookup_table (IMEngineInstanceBase *si, const LookupTable &table);

static void slot_register_properties (IMEngineInstanceBase *si, const PropertyList &properties);
static void slot_update_property (IMEngineInstanceBase *si, const Property &property);
static void slot_beep (IMEngineInstanceBase *si);
static void slot_start_helper (IMEngineInstanceBase *si, const String &helper_uuid);
static void slot_stop_helper (IMEngineInstanceBase *si, const String &helper_uuid);
static void slot_send_helper_event (IMEngineInstanceBase *si, const String &helper_uuid, const Transaction &trans);
static bool slot_get_surrounding_text (IMEngineInstanceBase *si, WideString &text, int &cursor, int maxlen_before, int maxlen_after);
static bool slot_delete_surrounding_text (IMEngineInstanceBase *si, int offset, int len);

static void reload_config_callback (const ConfigPointer &config);
static bool filter_hotkeys(const KeyEvent &key);

const char *
load(const char *args)
{
    string path;

    iobuf.str(args);
    iobuf >> path;

    if (!dll_handle) {
        dll_handle = dlopen(path.c_str(), RTLD_LAZY);
        if (!dll_handle)
            return dlerror();
    }
    return 0;
}

const char *
unload(const char *args)
{
    if (dll_handle) {
        dlclose(dll_handle);
        dll_handle = 0;
    }
    return 0;
}

const char *
init(const char *args)
{
    std::vector<String> method_list;
    std::vector<String> config_list;
    String config_module_name;

    scim_get_imengine_module_list(method_list);
    scim_get_config_module_list(config_list);

    if (!config_list.empty()) {
        config_module_name = scim_global_config_read(SCIM_GLOBAL_CONFIG_DEFAULT_CONFIG_MODULE, String("simple"));
        if (std::find(config_list.begin(), config_list.end(), config_module_name) == config_list.end())
            config_module_name = config_list[0];
    } else {
        config_module_name = "dummy";
    }
    if (config_module_name != "dummy") {
        m_config_module = new ConfigModule(config_module_name);
        if (m_config_module != NULL && m_config_module->valid())
            m_config = m_config_module->create_config();
    }
    if (m_config.null()) {
        if (m_config_module)
            delete m_config_module;
        m_config_module = NULL;
        m_config = new DummyConfig();
        config_module_name = "dummy";
    }

    reload_config_callback(m_config);
    m_config->signal_connect_reload(slot(reload_config_callback));

    m_backend = new CommonBackEnd(m_config, method_list);
    if (m_backend.null())
        return "cannot create backend";

    return NULL;
}

const char *
uninit(const char *args)
{
    m_backend.reset();
    m_config.reset();
    return NULL;
}

const char *
get_imlist(const char *args)
{
    std::vector<IMEngineFactoryPointer> imlist;
    IMEngineFactoryPointer def_factory;

    iobuf.str("");

    /* [method, langs, desc, is_default] */
    def_factory = m_backend->get_default_factory(scim_get_current_language(),
                                                 "UTF-8");
    m_backend->get_factories_for_encoding(imlist, "UTF-8");
    for (unsigned i = 0; i < imlist.size(); ++i) {
        iobuf << utf8_wcstombs(imlist[i]->get_name())
              << imlist[i]->get_locales()
              << utf8_wcstombs(imlist[i]->get_help())
              << (imlist[i]->get_name() == def_factory->get_name());
    }

    return iobuf.str();
}

const char *
create_context(const char *args)
{
    String method;
    String lang;
    std::vector<IMEngineFactoryPointer> imlist;
    ic_t *ic;

    iobuf.str(args);
    iobuf >> method >> lang;
    iobuf.str("");

    ic = new ic_t;

    m_backend->get_factories_for_encoding(imlist, "UTF-8");
    for (unsigned i = 0; i < imlist.size(); ++i) {
        /* TODO: check imlist[i]->validate_locale(lang + ".UTF-8")? */
        if (utf8_wcstombs(imlist[i]->get_name()) == method) {
            ic->factory = imlist[i];
            break;
        }
    }

    if (ic->factory.null())
        return "cannot select factory";

    ic->instance = ic->factory->create_instance("UTF-8", instance_id++);
    attach_instance(ic->instance);
    ic->instance->focus_in();

    iobuf << "create_context" << (void*&)ic;

    return iobuf.str();
}

const char *
delete_context(const char *args)
{
    ic_t *ic;

    iobuf.str(args);
    iobuf >> (void*&)ic;
    iobuf.str("");

    ic->instance.reset();
    ic->factory.reset();
    delete ic;

    return NULL;
}

const char *
send_key(const char *args)
{
    ic_t *ic;
    int code;
    int mod;
    vp::buf_t raw;
    bool processed;
    KeyEvent keyevent;

    iobuf.str(args);
    iobuf >> (void*&)ic >> code >> mod >> raw;
    iobuf.str("");

    keyevent.mask = mod & m_valid_key_mask;
    keyevent.layout = m_keyboard_layout;
    keyevent.code = code;

    if (filter_hotkeys(keyevent)) {
        iobuf << "commit_raw" << raw;
        return iobuf.str();
    }

    // key down
    processed = ic->instance->process_key_event(keyevent);
    // key up. need for Anthy's prediction
    keyevent.mask |= SCIM_KEY_ReleaseMask;
    (void)ic->instance->process_key_event(keyevent);

    if (!processed) {
        iobuf << "commit_raw" << raw;
        return iobuf.str();
    }

    return iobuf.str();
}

static void
attach_instance(const IMEngineInstancePointer& si)
{
    si->signal_connect_show_preedit_string (
        slot (slot_show_preedit_string));
    si->signal_connect_show_aux_string (
        slot (slot_show_aux_string));
    si->signal_connect_show_lookup_table (
        slot (slot_show_lookup_table));

    si->signal_connect_hide_preedit_string (
        slot (slot_hide_preedit_string));
    si->signal_connect_hide_aux_string (
        slot (slot_hide_aux_string));
    si->signal_connect_hide_lookup_table (
        slot (slot_hide_lookup_table));

    si->signal_connect_update_preedit_caret (
        slot (slot_update_preedit_caret));
    si->signal_connect_update_preedit_string (
        slot (slot_update_preedit_string));
    si->signal_connect_update_aux_string (
        slot (slot_update_aux_string));
    si->signal_connect_update_lookup_table (
        slot (slot_update_lookup_table));

    si->signal_connect_commit_string (
        slot (slot_commit_string));

    si->signal_connect_forward_key_event (
        slot (slot_forward_key_event));

    si->signal_connect_register_properties (
        slot (slot_register_properties));

    si->signal_connect_update_property (
        slot (slot_update_property));

    si->signal_connect_beep (
        slot (slot_beep));

    si->signal_connect_start_helper (
        slot (slot_start_helper));

    si->signal_connect_stop_helper (
        slot (slot_stop_helper));

    si->signal_connect_send_helper_event (
        slot (slot_send_helper_event));

    si->signal_connect_get_surrounding_text (
        slot (slot_get_surrounding_text));

    si->signal_connect_delete_surrounding_text (
        slot (slot_delete_surrounding_text));
}

static void
slot_show_preedit_string (IMEngineInstanceBase *si)
{
    if (debug) fprintf(stderr, "slot_show_preedit_string\n");
    iobuf << "show_preedit";
}

static void
slot_show_aux_string (IMEngineInstanceBase *si)
{
    if (debug) fprintf(stderr, "slot_show_aux_string\n");
}

static void
slot_show_lookup_table (IMEngineInstanceBase *si)
{
    if (debug) fprintf(stderr, "slot_show_lookup_table\n");
    iobuf << "show_candidate";
}

static void
slot_hide_preedit_string (IMEngineInstanceBase *si)
{
    if (debug) fprintf(stderr, "slot_hide_preedit_string\n");
    iobuf << "hide_preedit";
}

static void
slot_hide_aux_string (IMEngineInstanceBase *si)
{
    if (debug) fprintf(stderr, "slot_hide_aux_string\n");
}

static void
slot_hide_lookup_table (IMEngineInstanceBase *si)
{
    if (debug) fprintf(stderr, "slot_hide_lookup_table\n");
    iobuf << "hide_candidate";
}

static void
slot_update_preedit_caret (IMEngineInstanceBase *si, int caret)
{
    if (debug) fprintf(stderr, "slot_update_preedit_caret\n");
}

static void
slot_update_preedit_string (IMEngineInstanceBase *si, const WideString &str, const AttributeList &attrs)
{
    if (debug) fprintf(stderr, "slot_update_preedit_string: '%s' %d\n", utf8_wcstombs(str).c_str(), attrs.size());

    iobuf << "update_preedit";
    // "preedit", str, attrlen, [type, val, start, end, ...]
    iobuf << "preedit"
          << utf8_wcstombs(str)
          << attrs.size();
    for (unsigned i = 0; i < attrs.size(); ++i) {
        iobuf << attrs[i].get_type()
              << attrs[i].get_value()
              << attrs[i].get_start()
              << attrs[i].get_end();
    }
}

static void
slot_update_aux_string (IMEngineInstanceBase *si, const WideString &str, const AttributeList &attrs)
{
    if (debug) fprintf(stderr, "slot_update_aux_string\n");
}

static void
slot_commit_string (IMEngineInstanceBase *si, const WideString &str)
{
    if (debug) fprintf(stderr, "slot_commit_string: %s\n", utf8_wcstombs(str).c_str());
    // "commit", commit string
    iobuf << "commit" << utf8_wcstombs(str);
}

static void
slot_forward_key_event (IMEngineInstanceBase *si, const KeyEvent &key)
{
    if (debug) fprintf(stderr, "slot_forward_key_event\n");
}

static void
slot_update_lookup_table (IMEngineInstanceBase *si, const LookupTable &table)
{
    if (debug) fprintf(stderr, "slot_update_lookup_table\n");
    iobuf << "update_candidate";
    // "candidate", candlen, [str, ...]
    iobuf << "candidate"
          << table.number_of_candidates();
    for (uint32 i = 0; i < table.number_of_candidates(); ++i)
        iobuf << utf8_wcstombs(table.get_candidate(i));
    // "page", pagelen, [label, str, attrlen, [type, val, start, end], ...]
    iobuf << "page"
          << table.get_current_page_size();
    for (int i = 0; i < table.get_current_page_size(); ++i) {
        AttributeList attrs = table.get_attributes_in_current_page(i);
        iobuf << utf8_wcstombs(table.get_candidate_label(i))
              << utf8_wcstombs(table.get_candidate_in_current_page(i))
              << attrs.size();
        for (unsigned j = 0; j < attrs.size(); ++j) {
            iobuf << attrs[j].get_type()
                  << attrs[j].get_value()
                  << attrs[j].get_start()
                  << attrs[j].get_end();
        }
    }
    // candidate_current, candidate_page_first, candidate_page_last
    iobuf << table.get_cursor_pos()
          << table.get_current_page_start()
          << table.get_current_page_start() + table.get_current_page_size() - 1;
}

static void
slot_register_properties (IMEngineInstanceBase *si, const PropertyList &properties)
{
    if (debug) fprintf(stderr, "slot_register_properties\n");
    for (unsigned i = 0; i < properties.size(); ++i) {
        iobuf << "register_property"
              << properties[i].get_key()
              << properties[i].get_label()
              << properties[i].get_icon()
              << properties[i].get_tip()
              << properties[i].visible()
              << properties[i].active();
    }
}

static void
slot_update_property (IMEngineInstanceBase *si, const Property &property)
{
    if (debug) fprintf(stderr, "slot_update_property\n");
    iobuf << "property"
          << property.get_key()
          << property.get_label()
          << property.get_icon()
          << property.get_tip()
          << property.visible()
          << property.active();
}

static void
slot_beep (IMEngineInstanceBase *si)
{
    if (debug) fprintf(stderr, "slot_beep\n");
}

static void
slot_start_helper (IMEngineInstanceBase *si, const String &helper_uuid)
{
    if (debug) fprintf(stderr, "slot_start_helper\n");
}

static void
slot_stop_helper (IMEngineInstanceBase *si, const String &helper_uuid)
{
    if (debug) fprintf(stderr, "slot_stop_helper\n");
}

static void
slot_send_helper_event (IMEngineInstanceBase *si, const String &helper_uuid, const Transaction &trans)
{
    if (debug) {
        TransactionReader reader(trans);
        int cmd;
        if (reader.get_command(cmd))
            fprintf(stderr, "slot_send_helper_event: uuid=%s cmd=%d\n", helper_uuid.c_str(), cmd);
        else
            fprintf(stderr, "slot_send_helper_event: uuid=%s cmd=None\n", helper_uuid.c_str());
    }
}

static bool
slot_get_surrounding_text (IMEngineInstanceBase *si, WideString &text, int &cursor, int maxlen_before, int maxlen_after)
{
    if (debug) fprintf(stderr, "slot_get_surrounding_text\n");
    return false;
}

static bool
slot_delete_surrounding_text (IMEngineInstanceBase *si, int offset, int len)
{
    if (debug) fprintf(stderr, "slot_delete_surrounding_text\n");
    return false;
}

static void
reload_config_callback (const ConfigPointer &config)
{
    if (debug) fprintf(stderr, "reload_config_callback\n");
    m_frontend_hotkey_matcher.load_hotkeys(config);
    m_imengine_hotkey_matcher.load_hotkeys(config);

    KeyEvent key;

    scim_string_to_key(key, config->read(String(SCIM_CONFIG_HOTKEYS_FRONTEND_VALID_KEY_MASK), String("Shift+Control+Alt+Lock")));

    m_valid_key_mask = (key.mask > 0) ? (key.mask) : 0xFFFF;
    m_valid_key_mask |= SCIM_KEY_ReleaseMask;

    scim_global_config_flush();

    m_keyboard_layout = scim_get_default_keyboard_layout();
}

static bool
filter_hotkeys(const KeyEvent &key)
{

    m_frontend_hotkey_matcher.push_key_event(key);
    m_imengine_hotkey_matcher.push_key_event(key);

    FrontEndHotkeyAction hotkey_action = m_frontend_hotkey_matcher.get_match_result();

    if (hotkey_action == SCIM_FRONTEND_HOTKEY_TRIGGER) {
        if (debug) fprintf(stderr, "filter_hotkeys: SCIM_FRONTEND_HOTKEY_TRIGGER\n");
        return true;
    } else if (hotkey_action == SCIM_FRONTEND_HOTKEY_ON) {
        if (debug) fprintf(stderr, "filter_hotkeys: SCIM_FRONTEND_HOTKEY_ON\n");
        return true;
    } else if (hotkey_action == SCIM_FRONTEND_HOTKEY_OFF) {
        if (debug) fprintf(stderr, "filter_hotkeys: SCIM_FRONTEND_HOTKEY_OFF\n");
        return true;
    } else if (hotkey_action == SCIM_FRONTEND_HOTKEY_NEXT_FACTORY) {
        if (debug) fprintf(stderr, "filter_hotkeys: SCIM_FRONTEND_HOTKEY_NEXT_FACTORY\n");
        return true;
    } else if (hotkey_action == SCIM_FRONTEND_HOTKEY_PREVIOUS_FACTORY) {
        if (debug) fprintf(stderr, "filter_hotkeys: SCIM_FRONTEND_HOTKEY_PREVIOUS_FACTORY\n");
        return true;
    } else if (hotkey_action == SCIM_FRONTEND_HOTKEY_SHOW_FACTORY_MENU) {
        if (debug) fprintf(stderr, "filter_hotkeys: SCIM_FRONTEND_HOTKEY_SHOW_FACTORY_MENU\n");
        return true;
    } else if (m_imengine_hotkey_matcher.is_matched()) {
        if (debug) fprintf(stderr, "filter_hotkeys: is_matched()\n");
        return true;
    } else {
        if (debug) fprintf(stderr, "filter_hotkeys: else %d\n", hotkey_action);
    }
    return false;
}

