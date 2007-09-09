/*
 * iconv library implemented with Win32 API.
 *
 * When $WINICONV_LIBICONV_DLL environment variable is defined,
 * win_iconv load the dll dynamically and use it.  If iconv_open()
 * failed, falls back to internal conversion.
 *
 * Win32 API does not support strict encoding conversion for some
 * codepage.  And MLang function drop or replace invalid bytes and does
 * not return useful error status as iconv.  This implementation cannot
 * be used for encoding validation purpose.
 */

#include <windows.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>

#if 0
# define MAKE_EXE
# define MAKE_DLL
# define USE_LIBICONV_INTERFACE
# define USE_LIBICONV_DLL
#endif

#if defined(MAKE_DLL) && defined(_MSC_VER)
# define DLL_EXPORT __declspec(dllexport)
#else
# define DLL_EXPORT
#endif

#define MB_CHAR_MAX 16

#define return_error(code)  \
    do {                    \
        errno = code;       \
        return -1;          \
    } while (0)

#define STATIC_STRLEN(arr) (sizeof(arr) - 1)

typedef unsigned char uchar;
typedef unsigned short ushort;
typedef unsigned int uint;

typedef void* iconv_t;

DLL_EXPORT iconv_t iconv_open(const char *tocode, const char *fromcode);
DLL_EXPORT int iconv_close(iconv_t cd);
DLL_EXPORT size_t iconv(iconv_t cd, const char **inbuf, size_t *inbytesleft, char **outbuf, size_t *outbytesleft);

typedef struct csconv_t csconv_t;
typedef struct compat_t compat_t;
typedef struct rec_iconv_t rec_iconv_t;

typedef iconv_t (*f_iconv_open)(const char *tocode, const char *fromcode);
typedef int (*f_iconv_close)(iconv_t cd);
typedef size_t (*f_iconv)(iconv_t cd, const char **inbuf, size_t *inbytesleft, char **outbuf, size_t *outbytesleft);
typedef int* (*f_errno)(void);
typedef int (*f_mbtowc)(csconv_t *cv, const uchar *buf, int bufsize, ushort *wbuf, int *wbufsize);
typedef int (*f_wctomb)(csconv_t *cv, ushort *wbuf, int wbufsize, uchar *buf, int bufsize);
typedef int (*f_mblen)(csconv_t *cv, const uchar *buf, int bufsize);
typedef int (*f_flush)(csconv_t *cv, uchar *buf, int bufsize);

#define COMPAT_IN   1
#define COMPAT_OUT  2

/* unicode mapping for compatibility with other conversion table. */
struct compat_t {
    uint in;
    uint out;
    uint flag;
};

struct csconv_t {
    int codepage;
    f_mbtowc mbtowc;
    f_wctomb wctomb;
    f_mblen mblen;
    f_flush flush;
    DWORD mode;
    compat_t *compat;
};

struct rec_iconv_t {
    iconv_t cd;
    f_iconv_close iconv_close;
    f_iconv iconv;
    f_errno _errno;
    csconv_t from;
    csconv_t to;
};

static iconv_t *win_iconv_open(rec_iconv_t *cd, const char *tocode, const char *fromcode);
static int win_iconv_close(iconv_t cd);
static size_t win_iconv(iconv_t cd, const char **inbuf, size_t *inbytesleft, char **outbuf, size_t *outbytesleft);

static int load_mlang();
static csconv_t make_csconv(const char *name);
static int name_to_codepage(const char *name);
static uint utf16_to_ucs4(const ushort *wbuf);
static void ucs4_to_utf16(uint wc, ushort *wbuf, int *wbufsize);
static char *strrstr(const char *str, const char *token);

#if defined(USE_LIBICONV_DLL)

static int load_libiconv();
static PVOID MyImageDirectoryEntryToData(LPVOID pBase, BOOLEAN bMappedAsImage, USHORT DirectoryEntry, PULONG Size);
static int find_imported_module_by_funcname(HMODULE hModule, const char *funcname, char *dllname);

static f_iconv_open dyn_libiconv_open;
static f_iconv_close dyn_libiconv_close;
static f_iconv dyn_libiconv;
static f_errno dyn_libiconv_errno;

static HMODULE hwiniconv;
#endif

static int sbcs_mblen(csconv_t *cv, const uchar *buf, int bufsize);
static int dbcs_mblen(csconv_t *cv, const uchar *buf, int bufsize);
static int utf8_mblen(csconv_t *cv, const uchar *buf, int bufsize);
static int eucjp_mblen(csconv_t *cv, const uchar *buf, int bufsize);

static int kernel_mbtowc(csconv_t *cv, const uchar *buf, int bufsize, ushort *wbuf, int *wbufsize);
static int kernel_wctomb(csconv_t *cv, ushort *wbuf, int wbufsize, uchar *buf, int bufsize);
static int mlang_mbtowc(csconv_t *cv, const uchar *buf, int bufsize, ushort *wbuf, int *wbufsize);
static int mlang_wctomb(csconv_t *cv, ushort *wbuf, int wbufsize, uchar *buf, int bufsize);
static int utf16_mbtowc(csconv_t *cv, const uchar *buf, int bufsize, ushort *wbuf, int *wbufsize);
static int utf16_wctomb(csconv_t *cv, ushort *wbuf, int wbufsize, uchar *buf, int bufsize);
static int utf32_mbtowc(csconv_t *cv, const uchar *buf, int bufsize, ushort *wbuf, int *wbufsize);
static int utf32_wctomb(csconv_t *cv, ushort *wbuf, int wbufsize, uchar *buf, int bufsize);
static int iso2022jp_mbtowc(csconv_t *cv, const uchar *buf, int bufsize, ushort *wbuf, int *wbufsize);
static int iso2022jp_wctomb(csconv_t *cv, ushort *wbuf, int wbufsize, uchar *buf, int bufsize);
static int iso2022jp_flush(csconv_t *cv, uchar *buf, int bufsize);

struct {
    int codepage;
    const char *name;
} codepage_alias[] = {
    {65001, "CP65001"},
    {65001, "UTF8"},
    {65001, "UTF-8"},

    {1200, "CP1200"},
    {1200, "UTF16LE"},
    {1200, "UTF-16LE"},
    /* use little endian by default. */
    {1200, "UTF16"},
    {1200, "UTF-16"},

    {1201, "CP1201"},
    {1201, "UTF16BE"},
    {1201, "UTF-16BE"},
    {1201, "unicodeFFFE"},

    {12000, "CP12000"},
    {12000, "UTF32LE"},
    {12000, "UTF-32LE"},
    /* use little endian by default. */
    {12000, "UTF32"},
    {12000, "UTF-32"},

    {12001, "CP12001"},
    {12001, "UTF32BE"},
    {12001, "UTF-32BE"},

    /* copy from libiconv `iconv -l` */
    /* !IsValidCodePage(367) */
    {20127, "ANSI_X3.4-1968"},
    {20127, "ANSI_X3.4-1986"},
    {20127, "ASCII"},
    {20127, "CP367"},
    {20127, "IBM367"},
    {20127, "ISO-IR-6"},
    {20127, "ISO646-US"},
    {20127, "ISO_646.IRV:1991"},
    {20127, "US"},
    {20127, "US-ASCII"},
    {20127, "CSASCII"},

    /* !IsValidCodePage(819) */
    {1252, "CP819"},
    {1252, "IBM819"},
    {1252, "ISO-8859-1"},
    {1252, "ISO-IR-100"},
    {1252, "ISO8859-1"},
    {1252, "ISO_8859-1"},
    {1252, "ISO_8859-1:1987"},
    {1252, "L1"},
    {1252, "LATIN1"},
    {1252, "CSISOLATIN1"},

    {1250, "CP1250"},
    {1250, "MS-EE"},
    {1250, "WINDOWS-1250"},

    {1251, "CP1251"},
    {1251, "MS-CYRL"},
    {1251, "WINDOWS-1251"},

    {1252, "CP1252"},
    {1252, "MS-ANSI"},
    {1252, "WINDOWS-1252"},

    {1253, "CP1253"},
    {1253, "MS-GREEK"},
    {1253, "WINDOWS-1253"},

    {1254, "CP1254"},
    {1254, "MS-TURK"},
    {1254, "WINDOWS-1254"},

    {1255, "CP1255"},
    {1255, "MS-HEBR"},
    {1255, "WINDOWS-1255"},

    {1256, "CP1256"},
    {1256, "MS-ARAB"},
    {1256, "WINDOWS-1256"},

    {1257, "CP1257"},
    {1257, "WINBALTRIM"},
    {1257, "WINDOWS-1257"},

    {1258, "CP1258"},
    {1258, "WINDOWS-1258"},

    {850, "850"},
    {850, "CP850"},
    {850, "IBM850"},
    {850, "CSPC850MULTILINGUAL"},

    /* !IsValidCodePage(862) */
    {862, "862"},
    {862, "CP862"},
    {862, "IBM862"},
    {862, "CSPC862LATINHEBREW"},

    {866, "866"},
    {866, "CP866"},
    {866, "IBM866"},
    {866, "CSIBM866"},

    /* !IsValidCodePage(154) */
    {154, "CP154"},
    {154, "CYRILLIC-ASIAN"},
    {154, "PT154"},
    {154, "PTCP154"},
    {154, "CSPTCP154"},

    /* !IsValidCodePage(1133) */
    {1133, "CP1133"},
    {1133, "IBM-CP1133"},

    {874, "CP874"},
    {874, "WINDOWS-874"},

    /* !IsValidCodePage(51932) */
    {51932, "CP51932"},
    {51932, "MS51932"},
    {51932, "WINDOWS-51932"},
    {51932, "EUC-JP"},

    {932, "CP932"},
    {932, "MS932"},
    {932, "SHIFFT_JIS"},
    {932, "SHIFFT_JIS-MS"},
    {932, "SJIS"},
    {932, "SJIS-MS"},
    {932, "SJIS-OPEN"},
    {932, "SJIS-WIN"},
    {932, "WINDOWS-31J"},
    {932, "WINDOWS-932"},
    {932, "CSWINDOWS31J"},

    {50221, "CP50221"},
    {50221, "ISO-2022-JP"},
    {50221, "ISO-2022-JP-MS"},
    {50221, "MS50221"},
    {50221, "WINDOWS-50221"},

    {936, "CP936"},
    {936, "GBK"},
    {936, "MS936"},
    {936, "WINDOWS-936"},

    {950, "CP950"},
    {950, "BIG5"},

    {949, "CP949"},
    {949, "UHC"},
    {949, "EUC-KR"},

    {1361, "CP1361"},
    {1361, "JOHAB"},

    {437, "437"},
    {437, "CP437"},
    {437, "IBM437"},
    {437, "CSPC8CODEPAGE437"},

    {737, "CP737"},

    {775, "CP775"},
    {775, "IBM775"},
    {775, "CSPC775BALTIC"},

    {852, "852"},
    {852, "CP852"},
    {852, "IBM852"},
    {852, "CSPCP852"},

    /* !IsValidCodePage(853) */
    {853, "CP853"},

    {855, "855"},
    {855, "CP855"},
    {855, "IBM855"},
    {855, "CSIBM855"},

    {857, "857"},
    {857, "CP857"},
    {857, "IBM857"},
    {857, "CSIBM857"},

    /* !IsValidCodePage(858) */
    {858, "CP858"},

    {860, "860"},
    {860, "CP860"},
    {860, "IBM860"},
    {860, "CSIBM860"},

    {861, "861"},
    {861, "CP-IS"},
    {861, "CP861"},
    {861, "IBM861"},
    {861, "CSIBM861"},

    {863, "863"},
    {863, "CP863"},
    {863, "IBM863"},
    {863, "CSIBM863"},

    {864, "CP864"},
    {864, "IBM864"},
    {864, "CSIBM864"},

    {865, "865"},
    {865, "CP865"},
    {865, "IBM865"},
    {865, "CSIBM865"},

    {869, "869"},
    {869, "CP-GR"},
    {869, "CP869"},
    {869, "IBM869"},
    {869, "CSIBM869"},

    /* !IsValidCodePage(1152) */
    {1125, "CP1125"},

    /*
     * Code Page Identifiers
     * http://msdn2.microsoft.com/en-us/library/ms776446.aspx
     */
    {37, "IBM037"}, /* IBM EBCDIC US-Canada */
    {437, "IBM437"}, /* OEM United States */
    {500, "IBM500"}, /* IBM EBCDIC International */
    {708, "ASMO-708"}, /* Arabic (ASMO 708) */
    /* 709 		Arabic (ASMO-449+, BCON V4) */
    /* 710 		Arabic - Transparent Arabic */
    {720, "DOS-720"}, /* Arabic (Transparent ASMO); Arabic (DOS) */
    {737, "ibm737"}, /* OEM Greek (formerly 437G); Greek (DOS) */
    {775, "ibm775"}, /* OEM Baltic; Baltic (DOS) */
    {850, "ibm850"}, /* OEM Multilingual Latin 1; Western European (DOS) */
    {852, "ibm852"}, /* OEM Latin 2; Central European (DOS) */
    {855, "IBM855"}, /* OEM Cyrillic (primarily Russian) */
    {857, "ibm857"}, /* OEM Turkish; Turkish (DOS) */
    {858, "IBM00858"}, /* OEM Multilingual Latin 1 + Euro symbol */
    {860, "IBM860"}, /* OEM Portuguese; Portuguese (DOS) */
    {861, "ibm861"}, /* OEM Icelandic; Icelandic (DOS) */
    {862, "DOS-862"}, /* OEM Hebrew; Hebrew (DOS) */
    {863, "IBM863"}, /* OEM French Canadian; French Canadian (DOS) */
    {864, "IBM864"}, /* OEM Arabic; Arabic (864) */
    {865, "IBM865"}, /* OEM Nordic; Nordic (DOS) */
    {866, "cp866"}, /* OEM Russian; Cyrillic (DOS) */
    {869, "ibm869"}, /* OEM Modern Greek; Greek, Modern (DOS) */
    {870, "IBM870"}, /* IBM EBCDIC Multilingual/ROECE (Latin 2); IBM EBCDIC Multilingual Latin 2 */
    {874, "windows-874"}, /* ANSI/OEM Thai (same as 28605, ISO 8859-15); Thai (Windows) */
    {875, "cp875"}, /* IBM EBCDIC Greek Modern */
    {932, "shift_jis"}, /* ANSI/OEM Japanese; Japanese (Shift-JIS) */
    {936, "gb2312"}, /* ANSI/OEM Simplified Chinese (PRC, Singapore); Chinese Simplified (GB2312) */
    {949, "ks_c_5601-1987"}, /* ANSI/OEM Korean (Unified Hangul Code) */
    {950, "big5"}, /* ANSI/OEM Traditional Chinese (Taiwan; Hong Kong SAR, PRC); Chinese Traditional (Big5) */
    {1026, "IBM1026"}, /* IBM EBCDIC Turkish (Latin 5) */
    {1047, "IBM01047"}, /* IBM EBCDIC Latin 1/Open System */
    {1140, "IBM01140"}, /* IBM EBCDIC US-Canada (037 + Euro symbol); IBM EBCDIC (US-Canada-Euro) */
    {1141, "IBM01141"}, /* IBM EBCDIC Germany (20273 + Euro symbol); IBM EBCDIC (Germany-Euro) */
    {1142, "IBM01142"}, /* IBM EBCDIC Denmark-Norway (20277 + Euro symbol); IBM EBCDIC (Denmark-Norway-Euro) */
    {1143, "IBM01143"}, /* IBM EBCDIC Finland-Sweden (20278 + Euro symbol); IBM EBCDIC (Finland-Sweden-Euro) */
    {1144, "IBM01144"}, /* IBM EBCDIC Italy (20280 + Euro symbol); IBM EBCDIC (Italy-Euro) */
    {1145, "IBM01145"}, /* IBM EBCDIC Latin America-Spain (20284 + Euro symbol); IBM EBCDIC (Spain-Euro) */
    {1146, "IBM01146"}, /* IBM EBCDIC United Kingdom (20285 + Euro symbol); IBM EBCDIC (UK-Euro) */
    {1147, "IBM01147"}, /* IBM EBCDIC France (20297 + Euro symbol); IBM EBCDIC (France-Euro) */
    {1148, "IBM01148"}, /* IBM EBCDIC International (500 + Euro symbol); IBM EBCDIC (International-Euro) */
    {1149, "IBM01149"}, /* IBM EBCDIC Icelandic (20871 + Euro symbol); IBM EBCDIC (Icelandic-Euro) */
    {1250, "windows-1250"}, /* ANSI Central European; Central European (Windows) */
    {1251, "windows-1251"}, /* ANSI Cyrillic; Cyrillic (Windows) */
    {1252, "windows-1252"}, /* ANSI Latin 1; Western European (Windows) */
    {1253, "windows-1253"}, /* ANSI Greek; Greek (Windows) */
    {1254, "windows-1254"}, /* ANSI Turkish; Turkish (Windows) */
    {1255, "windows-1255"}, /* ANSI Hebrew; Hebrew (Windows) */
    {1256, "windows-1256"}, /* ANSI Arabic; Arabic (Windows) */
    {1257, "windows-1257"}, /* ANSI Baltic; Baltic (Windows) */
    {1258, "windows-1258"}, /* ANSI/OEM Vietnamese; Vietnamese (Windows) */
    {1361, "Johab"}, /* Korean (Johab) */
    {10000, "macintosh"}, /* MAC Roman; Western European (Mac) */
    {10001, "x-mac-japanese"}, /* Japanese (Mac) */
    {10002, "x-mac-chinesetrad"}, /* MAC Traditional Chinese (Big5); Chinese Traditional (Mac) */
    {10003, "x-mac-korean"}, /* Korean (Mac) */
    {10004, "x-mac-arabic"}, /* Arabic (Mac) */
    {10005, "x-mac-hebrew"}, /* Hebrew (Mac) */
    {10006, "x-mac-greek"}, /* Greek (Mac) */
    {10007, "x-mac-cyrillic"}, /* Cyrillic (Mac) */
    {10008, "x-mac-chinesesimp"}, /* MAC Simplified Chinese (GB 2312); Chinese Simplified (Mac) */
    {10010, "x-mac-romanian"}, /* Romanian (Mac) */
    {10017, "x-mac-ukrainian"}, /* Ukrainian (Mac) */
    {10021, "x-mac-thai"}, /* Thai (Mac) */
    {10029, "x-mac-ce"}, /* MAC Latin 2; Central European (Mac) */
    {10079, "x-mac-icelandic"}, /* Icelandic (Mac) */
    {10081, "x-mac-turkish"}, /* Turkish (Mac) */
    {10082, "x-mac-croatian"}, /* Croatian (Mac) */
    {20000, "x-Chinese_CNS"}, /* CNS Taiwan; Chinese Traditional (CNS) */
    {20001, "x-cp20001"}, /* TCA Taiwan */
    {20002, "x_Chinese-Eten"}, /* Eten Taiwan; Chinese Traditional (Eten) */
    {20003, "x-cp20003"}, /* IBM5550 Taiwan */
    {20004, "x-cp20004"}, /* TeleText Taiwan */
    {20005, "x-cp20005"}, /* Wang Taiwan */
    {20105, "x-IA5"}, /* IA5 (IRV International Alphabet No. 5, 7-bit); Western European (IA5) */
    {20106, "x-IA5-German"}, /* IA5 German (7-bit) */
    {20107, "x-IA5-Swedish"}, /* IA5 Swedish (7-bit) */
    {20108, "x-IA5-Norwegian"}, /* IA5 Norwegian (7-bit) */
    {20127, "us-ascii"}, /* US-ASCII (7-bit) */
    {20261, "x-cp20261"}, /* T.61 */
    {20269, "x-cp20269"}, /* ISO 6937 Non-Spacing Accent */
    {20273, "IBM273"}, /* IBM EBCDIC Germany */
    {20277, "IBM277"}, /* IBM EBCDIC Denmark-Norway */
    {20278, "IBM278"}, /* IBM EBCDIC Finland-Sweden */
    {20280, "IBM280"}, /* IBM EBCDIC Italy */
    {20284, "IBM284"}, /* IBM EBCDIC Latin America-Spain */
    {20285, "IBM285"}, /* IBM EBCDIC United Kingdom */
    {20290, "IBM290"}, /* IBM EBCDIC Japanese Katakana Extended */
    {20297, "IBM297"}, /* IBM EBCDIC France */
    {20420, "IBM420"}, /* IBM EBCDIC Arabic */
    {20423, "IBM423"}, /* IBM EBCDIC Greek */
    {20424, "IBM424"}, /* IBM EBCDIC Hebrew */
    {20833, "x-EBCDIC-KoreanExtended"}, /* IBM EBCDIC Korean Extended */
    {20838, "IBM-Thai"}, /* IBM EBCDIC Thai */
    {20866, "koi8-r"}, /* Russian (KOI8-R); Cyrillic (KOI8-R) */
    {20871, "IBM871"}, /* IBM EBCDIC Icelandic */
    {20880, "IBM880"}, /* IBM EBCDIC Cyrillic Russian */
    {20905, "IBM905"}, /* IBM EBCDIC Turkish */
    {20924, "IBM00924"}, /* IBM EBCDIC Latin 1/Open System (1047 + Euro symbol) */
    {20932, "EUC-JP"}, /* Japanese (JIS 0208-1990 and 0121-1990) */
    {20936, "x-cp20936"}, /* Simplified Chinese (GB2312); Chinese Simplified (GB2312-80) */
    {20949, "x-cp20949"}, /* Korean Wansung */
    {21025, "cp1025"}, /* IBM EBCDIC Cyrillic Serbian-Bulgarian */
    /* 21027 		(deprecated) */
    {21866, "koi8-u"}, /* Ukrainian (KOI8-U); Cyrillic (KOI8-U) */
    {28591, "iso-8859-1"}, /* ISO 8859-1 Latin 1; Western European (ISO) */
    {28592, "iso-8859-2"}, /* ISO 8859-2 Central European; Central European (ISO) */
    {28593, "iso-8859-3"}, /* ISO 8859-3 Latin 3 */
    {28594, "iso-8859-4"}, /* ISO 8859-4 Baltic */
    {28595, "iso-8859-5"}, /* ISO 8859-5 Cyrillic */
    {28596, "iso-8859-6"}, /* ISO 8859-6 Arabic */
    {28597, "iso-8859-7"}, /* ISO 8859-7 Greek */
    {28598, "iso-8859-8"}, /* ISO 8859-8 Hebrew; Hebrew (ISO-Visual) */
    {28599, "iso-8859-9"}, /* ISO 8859-9 Turkish */
    {28603, "iso-8859-13"}, /* ISO 8859-13 Estonian */
    {28605, "iso-8859-15"}, /* ISO 8859-15 Latin 9 */
    {29001, "x-Europa"}, /* Europa 3 */
    {38598, "iso-8859-8-i"}, /* ISO 8859-8 Hebrew; Hebrew (ISO-Logical) */
    {50220, "iso-2022-jp"}, /* ISO 2022 Japanese with no halfwidth Katakana; Japanese (JIS) */
    {50221, "csISO2022JP"}, /* ISO 2022 Japanese with halfwidth Katakana; Japanese (JIS-Allow 1 byte Kana) */
    {50222, "iso-2022-jp"}, /* ISO 2022 Japanese JIS X 0201-1989; Japanese (JIS-Allow 1 byte Kana - SO/SI) */
    {50225, "iso-2022-kr"}, /* ISO 2022 Korean */
    {50227, "x-cp50227"}, /* ISO 2022 Simplified Chinese; Chinese Simplified (ISO 2022) */
    /* 50229 		ISO 2022 Traditional Chinese */
    /* 50930 		EBCDIC Japanese (Katakana) Extended */
    /* 50931 		EBCDIC US-Canada and Japanese */
    /* 50933 		EBCDIC Korean Extended and Korean */
    /* 50935 		EBCDIC Simplified Chinese Extended and Simplified Chinese */
    /* 50936 		EBCDIC Simplified Chinese */
    /* 50937 		EBCDIC US-Canada and Traditional Chinese */
    /* 50939 		EBCDIC Japanese (Latin) Extended and Japanese */
    {51932, "euc-jp"}, /* EUC Japanese */
    {51936, "EUC-CN"}, /* EUC Simplified Chinese; Chinese Simplified (EUC) */
    {51949, "euc-kr"}, /* EUC Korean */
    /* 51950 		EUC Traditional Chinese */
    {52936, "hz-gb-2312"}, /* HZ-GB2312 Simplified Chinese; Chinese Simplified (HZ) */
    {54936, "GB18030"}, /* Windows XP and later: GB18030 Simplified Chinese (4 byte); Chinese Simplified (GB18030) */
    {57002, "x-iscii-de"}, /* ISCII Devanagari */
    {57003, "x-iscii-be"}, /* ISCII Bengali */
    {57004, "x-iscii-ta"}, /* ISCII Tamil */
    {57005, "x-iscii-te"}, /* ISCII Telugu */
    {57006, "x-iscii-as"}, /* ISCII Assamese */
    {57007, "x-iscii-or"}, /* ISCII Oriya */
    {57008, "x-iscii-ka"}, /* ISCII Kannada */
    {57009, "x-iscii-ma"}, /* ISCII Malayalam */
    {57010, "x-iscii-gu"}, /* ISCII Gujarati */
    {57011, "x-iscii-pa"}, /* ISCII Punjabi */

    {0, NULL}
};

/*
 * SJIS SHIFTJIS table              CP932 table
 * ---- --------------------------- --------------------------------
 *   5C U+00A5 YEN SIGN             U+005C REVERSE SOLIDUS
 *   7E U+203E OVERLINE             U+007E TILDE
 * 815C U+2014 EM DASH              U+2015 HORIZONTAL BAR
 * 815F U+005C REVERSE SOLIDUS      U+FF3C FULLWIDTH REVERSE SOLIDUS
 * 8160 U+301C WAVE DASH            U+FF5E FULLWIDTH TILDE
 * 8161 U+2016 DOUBLE VERTICAL LINE U+2225 PARALLEL TO
 * 817C U+2212 MINUS SIGN           U+FF0D FULLWIDTH HYPHEN-MINUS
 * 8191 U+00A2 CENT SIGN            U+FFE0 FULLWIDTH CENT SIGN
 * 8192 U+00A3 POUND SIGN           U+FFE1 FULLWIDTH POUND SIGN
 * 81CA U+00AC NOT SIGN             U+FFE2 FULLWIDTH NOT SIGN
 *
 * EUC-JP and ISO-2022-JP should be compatible with CP932.
 */
static compat_t cp932_compat[] = {
    {0x00A5, 0x005C, COMPAT_OUT},
    {0x203E, 0x007E, COMPAT_OUT},
    {0x2014, 0x2015, COMPAT_OUT},
    {0x301C, 0xFF5E, COMPAT_OUT},
    {0x2016, 0x2225, COMPAT_OUT},
    {0x2212, 0xFF0D, COMPAT_OUT},
    {0x00A2, 0xFFE0, COMPAT_OUT},
    {0x00A3, 0xFFE1, COMPAT_OUT},
    {0x00AC, 0xFFE2, COMPAT_OUT},
    {0, 0, 0}
};

static compat_t cp5022x_compat[] = {
    {0x00A5, 0x005C, COMPAT_OUT},
    {0x203E, 0x007E, COMPAT_OUT},
    {0x2014, 0x2015, COMPAT_OUT},
    {0xFF5E, 0x301C, COMPAT_OUT|COMPAT_IN},
    {0x2225, 0x2016, COMPAT_OUT|COMPAT_IN},
    {0xFF0D, 0x2212, COMPAT_OUT|COMPAT_IN},
    {0xFFE0, 0x00A2, COMPAT_OUT|COMPAT_IN},
    {0xFFE1, 0x00A3, COMPAT_OUT|COMPAT_IN},
    {0xFFE2, 0x00AC, COMPAT_OUT|COMPAT_IN},
    {0, 0, 0}
};

static compat_t *cp51932_compat = cp932_compat;
static compat_t *cp20932_compat = cp5022x_compat;

typedef HRESULT (WINAPI *CONVERTINETSTRING)(
    LPDWORD lpdwMode,
    DWORD dwSrcEncoding,
    DWORD dwDstEncoding,
    LPCSTR lpSrcStr,
    LPINT lpnSrcSize,
    LPBYTE lpDstStr,
    LPINT lpnDstSize
);
typedef HRESULT (WINAPI *CONVERTINETMULTIBYTETOUNICODE)(
    LPDWORD lpdwMode,
    DWORD dwSrcEncoding,
    LPCSTR lpSrcStr,
    LPINT lpnMultiCharCount,
    LPWSTR lpDstStr,
    LPINT lpnWideCharCount
);
typedef HRESULT (WINAPI *CONVERTINETUNICODETOMULTIBYTE)(
    LPDWORD lpdwMode,
    DWORD dwEncoding,
    LPCWSTR lpSrcStr,
    LPINT lpnWideCharCount,
    LPSTR lpDstStr,
    LPINT lpnMultiCharCount
);
typedef HRESULT (WINAPI *ISCONVERTINETSTRINGAVAILABLE)(
    DWORD dwSrcEncoding,
    DWORD dwDstEncoding
);
typedef HRESULT (WINAPI *LCIDTORFC1766)(
    LCID Locale,
    LPTSTR pszRfc1766,
    int nChar
);
typedef HRESULT (WINAPI *RFC1766TOLCID)(
    LCID *pLocale,
    LPTSTR pszRfc1766
);
static CONVERTINETSTRING ConvertINetString;
static CONVERTINETMULTIBYTETOUNICODE ConvertINetMultiByteToUnicode;
static CONVERTINETUNICODETOMULTIBYTE ConvertINetUnicodeToMultiByte;
static ISCONVERTINETSTRINGAVAILABLE IsConvertINetStringAvailable;
static LCIDTORFC1766 LcidToRfc1766;
static RFC1766TOLCID Rfc1766ToLcid;

static int
load_mlang()
{
    HMODULE h;
    if (ConvertINetString != NULL)
        return TRUE;
    h = LoadLibrary("mlang.dll");
    if (!h)
        return FALSE;
    ConvertINetString = (CONVERTINETSTRING)GetProcAddress(h, "ConvertINetString");
    ConvertINetMultiByteToUnicode = (CONVERTINETMULTIBYTETOUNICODE)GetProcAddress(h, "ConvertINetMultiByteToUnicode");
    ConvertINetUnicodeToMultiByte = (CONVERTINETUNICODETOMULTIBYTE)GetProcAddress(h, "ConvertINetUnicodeToMultiByte");
    IsConvertINetStringAvailable = (ISCONVERTINETSTRINGAVAILABLE)GetProcAddress(h, "IsConvertINetStringAvailable");
    LcidToRfc1766 = (LCIDTORFC1766)GetProcAddress(h, "LcidToRfc1766");
    Rfc1766ToLcid = (RFC1766TOLCID)GetProcAddress(h, "Rfc1766ToLcid");
    return TRUE;
}

iconv_t
iconv_open(const char *tocode, const char *fromcode)
{
    rec_iconv_t *cd;

    cd = (rec_iconv_t *)malloc(sizeof(rec_iconv_t));
    if (cd == NULL)
    {
        errno = ENOMEM;
        return (iconv_t)(-1);
    }

#if defined(USE_LIBICONV_DLL)
# if 1
    /*
     * TODO:
     * Which the order of priority is useful?
     *   1. libiconv.dll -> internal
     *   2. internal -> libiconv.dll
     * Also should we use default typical names to load libiconv.dll
     * when $WINICONV_LIBICONV_DLL is not defined.
     * Disable default typical names for now.
     */
    if (getenv("WINICONV_LIBICONV_DLL") == NULL
            || getenv("WINICONV_LIBICONV_DLL")[0] == 0)
        putenv("WINICONV_LIBICONV_DLL=DISABLED");
# endif

    if (load_libiconv())
    {
        cd->cd = dyn_libiconv_open(tocode, fromcode);
        if (cd->cd != (iconv_t)(-1))
        {
            cd->iconv_close = dyn_libiconv_close;
            cd->iconv = dyn_libiconv;
            cd->_errno = dyn_libiconv_errno;
            return (iconv_t)cd;
        }
        /* fallback */
    }
#endif

    cd->cd = win_iconv_open(cd, tocode, fromcode);
    if (cd->cd == (iconv_t)(-1))
    {
        free(cd);
        errno = EINVAL;
        return (iconv_t)(-1);
    }

    return (iconv_t)cd;
}

int
iconv_close(iconv_t _cd)
{
    rec_iconv_t *cd = (rec_iconv_t *)_cd;
    int r = cd->iconv_close(cd->cd);
    int e = *(cd->_errno());
    free(cd);
    errno = e;
    return r;
}

size_t
iconv(iconv_t _cd, const char **inbuf, size_t *inbytesleft, char **outbuf, size_t *outbytesleft)
{
    rec_iconv_t *cd = (rec_iconv_t *)_cd;
    size_t r = cd->iconv(cd->cd, inbuf, inbytesleft, outbuf, outbytesleft);
    errno = *(cd->_errno());
    return r;
}

/* libiconv interface for vim */
#if defined(USE_LIBICONV_INTERFACE)
DLL_EXPORT iconv_t
libiconv_open(const char *tocode, const char *fromcode)
{
    return iconv_open(tocode, fromcode);
}

DLL_EXPORT int
libiconv_close(iconv_t cd)
{
    return iconv_close(cd);
}

DLL_EXPORT size_t
libiconv(iconv_t cd, const char **inbuf, size_t *inbytesleft, char **outbuf, size_t *outbytesleft)
{
    return iconv(cd, inbuf, inbytesleft, outbuf, outbytesleft);
}

DLL_EXPORT int
libiconvctl (iconv_t cd, int request, void* argument)
{
    /* not supported */
    return 0;
}
#endif

static iconv_t *
win_iconv_open(rec_iconv_t *cd, const char *tocode, const char *fromcode)
{
    cd->from = make_csconv(fromcode);
    cd->to = make_csconv(tocode);
    if (cd->from.codepage == -1 || cd->to.codepage == -1)
        return (iconv_t)(-1);
    cd->iconv_close = win_iconv_close;
    cd->iconv = win_iconv;
    cd->_errno = _errno;
    return (iconv_t)cd;
}

static int
win_iconv_close(iconv_t cd)
{
    return 0;
}

static size_t
win_iconv(iconv_t _cd, const char **inbuf, size_t *inbytesleft, char **outbuf, size_t *outbytesleft)
{
    rec_iconv_t *cd = (rec_iconv_t *)_cd;
    ushort wbuf[MB_CHAR_MAX]; /* enough room for one character */
    int insize;
    int outsize;
    int wsize;
    DWORD mode;
    uint wc;
    compat_t *cp;
    int i;

    if (inbuf == NULL || *inbuf == NULL)
    {
        if (outbuf != NULL && *outbuf != NULL && cd->to.flush != NULL)
        {
            outsize = cd->to.flush(&cd->to, (uchar *)*outbuf, *outbytesleft);
            if (outsize == -1)
                return (size_t)(-1);
            *outbuf += outsize;
            *outbytesleft -= outsize;
        }
        cd->from.mode = 0;
        cd->to.mode = 0;
        return 0;
    }

    while (*inbytesleft != 0)
    {
        mode = cd->from.mode;
        wsize = MB_CHAR_MAX;

        insize = cd->from.mbtowc(&cd->from, (const uchar *)*inbuf, *inbytesleft, wbuf, &wsize);
        if (insize == -1)
            return (size_t)(-1);

        if (wsize == 0)
        {
            *inbuf += insize;
            *inbytesleft -= insize;
            continue;
        }

        if (cd->from.compat != NULL)
        {
            wc = utf16_to_ucs4(wbuf);
            cp = cd->from.compat;
            for (i = 0; cp[i].in != 0; ++i)
            {
                if ((cp[i].flag & COMPAT_IN) && cp[i].out == wc)
                {
                    ucs4_to_utf16(cp[i].in, wbuf, &wsize);
                    break;
                }
            }
        }

        if (cd->to.compat != NULL)
        {
            wc = utf16_to_ucs4(wbuf);
            cp = cd->to.compat;
            for (i = 0; cp[i].in != 0; ++i)
            {
                if ((cp[i].flag & COMPAT_OUT) && cp[i].in == wc)
                {
                    ucs4_to_utf16(cp[i].out, wbuf, &wsize);
                    break;
                }
            }
        }

        outsize = cd->to.wctomb(&cd->to, wbuf, wsize, (uchar *)*outbuf, *outbytesleft);
        if (outsize == -1)
        {
            /* Restore the mode.  Is this safe for MLang function? */
            cd->from.mode = mode;
            return (size_t)(-1);
        }

        *inbuf += insize;
        *outbuf += outsize;
        *inbytesleft -= insize;
        *outbytesleft -= outsize;
    }

    return 0;
}

static csconv_t
make_csconv(const char *_name)
{
    CPINFOEX cpinfoex;
    csconv_t cv;
    int use_compat = TRUE;
    char name[512];
    char *p;

    strncpy(name, _name, sizeof(name));
    name[sizeof(name) - 1] = 0;

    /* check for option "enc_name//opt1//opt2" */
    while ((p = strrstr(name, "//")) != NULL)
    {
        if (_stricmp(p + 2, "nocompat") == 0)
            use_compat = FALSE;
        *p = 0;
    }

    cv.mode = 0;
    cv.mblen = NULL;
    cv.flush = NULL;
    cv.compat = NULL;
    cv.codepage = name_to_codepage(name);
    if (cv.codepage == 1200 || cv.codepage == 1201)
    {
        cv.mbtowc = utf16_mbtowc;
        cv.wctomb = utf16_wctomb;
    }
    else if (cv.codepage == 12000 || cv.codepage == 12001)
    {
        cv.mbtowc = utf32_mbtowc;
        cv.wctomb = utf32_wctomb;
    }
    else if (cv.codepage == 65001)
    {
        cv.mbtowc = kernel_mbtowc;
        cv.wctomb = kernel_wctomb;
        cv.mblen = utf8_mblen;
    }
    else if (cv.codepage == 50220 || cv.codepage == 50221 || cv.codepage == 50222)
    {
        cv.mbtowc = iso2022jp_mbtowc;
        cv.wctomb = iso2022jp_wctomb;
        cv.flush = iso2022jp_flush;
    }
    else if (cv.codepage == 51932 && load_mlang())
    {
        cv.mbtowc = mlang_mbtowc;
        cv.wctomb = mlang_wctomb;
        cv.mblen = eucjp_mblen;
    }
    else if (IsValidCodePage(cv.codepage)
            && GetCPInfoEx(cv.codepage, 0, &cpinfoex) != 0
            && (cpinfoex.MaxCharSize == 1 || cpinfoex.MaxCharSize == 2))
    {
        cv.mbtowc = kernel_mbtowc;
        cv.wctomb = kernel_wctomb;
        if (cpinfoex.MaxCharSize == 1)
            cv.mblen = sbcs_mblen;
        else
            cv.mblen = dbcs_mblen;
    }
    else
    {
        /* not supported */
        cv.codepage = -1;
    }
    if (use_compat)
    {
        switch (cv.codepage)
        {
        case 932: cv.compat = cp932_compat; break;
        case 20932: cv.compat = cp20932_compat; break;
        case 51932: cv.compat = cp51932_compat; break;
        case 50220: case 50221: case 50222: cv.compat = cp5022x_compat; break;
        }
    }
    return cv;
}

static int
name_to_codepage(const char *name)
{
    int i;

    if (_strnicmp(name, "cp", 2) == 0)
        return atoi(name + 2); /* CP123 */
    else if ('0' <= name[0] && name[0] <= '9')
        return atoi(name);     /* 123 */
    else if (_strnicmp(name, "xx", 2) == 0)
        return atoi(name + 2); /* XX123 for debug */

    for (i = 0; codepage_alias[i].name != NULL; ++i)
        if (_stricmp(name, codepage_alias[i].name) == 0)
            return codepage_alias[i].codepage;
    return -1;
}

static uint
utf16_to_ucs4(const ushort *wbuf)
{
    uint wc = wbuf[0];
    if (0xD800 <= wbuf[0] && wbuf[0] <= 0xDBFF)
        wc = ((wbuf[0] & 0x03C0) << 16) | ((wbuf[0] & 0x003F) << 10) | (wbuf[1] & 0x03FF);
    return wc;
}

static void
ucs4_to_utf16(uint wc, ushort *wbuf, int *wbufsize)
{
    if (0xFFFF < wc)
    {
        wbuf[0] = 0xD800 | ((wc & 0x1F0000) - 1) | (wc & 0x00FC00);
        wbuf[1] = 0xDC00 | (wc & 0x0003FF);
        *wbufsize = 2;
    }
    else
    {
        wbuf[0] = wc;
        *wbufsize = 1;
    }
}

static char *
strrstr(const char *str, const char *token)
{
    int len = strlen(token);
    const char *p = str + strlen(str);

    while (str <= --p)
        if (p[0] == token[0] && strncmp(p, token, len) == 0)
            return (char *)p;
    return NULL;
}

#if defined(USE_LIBICONV_DLL)
static int
load_libiconv()
{
    HMODULE hlibiconv = NULL;
    HMODULE hmsvcrt = NULL;
    int i;
    const char *env;
    char msvcrt_dll[_MAX_PATH];
    char *libiconv_names[] = {
        "iconv.dll", "libiconv.dll", "iconv-2.dll", "libiconv-2.dll",
        NULL};

    if (dyn_libiconv_open != NULL)
        return TRUE;

    /* Use $WINICONV_LIBICONV_DLL if defined. */
    env = getenv("WINICONV_LIBICONV_DLL");
    if (env != NULL && env[0] != 0)
    {
        hlibiconv = LoadLibrary(env);
        if (hwiniconv != NULL && hlibiconv == hwiniconv)
        {
            FreeLibrary(hlibiconv);
            hlibiconv = NULL;
        }
    }
    else
    {
        for (i = 0; libiconv_names[i] != NULL; ++i)
        {
            hlibiconv = LoadLibrary(libiconv_names[i]);
            if (hwiniconv != NULL && hlibiconv == hwiniconv)
            {
                FreeLibrary(hlibiconv);
                hlibiconv = NULL;
            }
            else if (hlibiconv != NULL)
                break;
        }
    }

    if (hlibiconv != NULL
            && find_imported_module_by_funcname(hlibiconv, "_errno", msvcrt_dll)
            && (hmsvcrt = LoadLibrary(msvcrt_dll)) != NULL)
    {
        dyn_libiconv_open = (f_iconv_open)GetProcAddress(hlibiconv, "libiconv_open");
        dyn_libiconv_close = (f_iconv_close)GetProcAddress(hlibiconv, "libiconv_close");
        dyn_libiconv = (f_iconv)GetProcAddress(hlibiconv, "libiconv");
        dyn_libiconv_errno = (f_errno)GetProcAddress(hmsvcrt, "_errno");
        if (dyn_libiconv_open != NULL && dyn_libiconv_close != NULL
                && dyn_libiconv != NULL && dyn_libiconv_errno != NULL)
            return TRUE;
    }

    if (hlibiconv != NULL)
        FreeLibrary(hlibiconv);
    if (hmsvcrt != NULL)
        FreeLibrary(hmsvcrt);
    dyn_libiconv_open = NULL;
    dyn_libiconv_close = NULL;
    dyn_libiconv = NULL;
    dyn_libiconv_errno = NULL;
    return FALSE;
}

/*
 * Reference:
 * http://forums.belution.com/ja/vc/000/234/78s.shtml
 * http://nienie.com/~masapico/api_ImageDirectoryEntryToData.html
 */
static PVOID
MyImageDirectoryEntryToData(LPVOID pBase, BOOLEAN bMappedAsImage, USHORT DirectoryEntry, PULONG Size)
{
    PIMAGE_IMPORT_DESCRIPTOR pImportDescriptor;
    PIMAGE_DOS_HEADER pDosHdr;
    PIMAGE_NT_HEADERS pNTHdr;

    pDosHdr = (PIMAGE_DOS_HEADER)pBase;
    pNTHdr = (PIMAGE_NT_HEADERS)((LPBYTE)pBase + pDosHdr->e_lfanew);
    pImportDescriptor = (PIMAGE_IMPORT_DESCRIPTOR)((LPBYTE)pBase + pNTHdr->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT].VirtualAddress);
    /* TODO: *Size = ? */
    return pImportDescriptor;
}

static int
find_imported_module_by_funcname(HMODULE hModule, const char *funcname, char *dllname)
{
    DWORD BaseAddress;
    ULONG Size;
    PIMAGE_IMPORT_DESCRIPTOR pImportDescriptor;
    PIMAGE_THUNK_DATA pThunkData;
    PIMAGE_IMPORT_BY_NAME pImportByName;

    BaseAddress = (DWORD)hModule;
    pImportDescriptor = MyImageDirectoryEntryToData(
            (LPVOID)BaseAddress,
            TRUE,
            IMAGE_DIRECTORY_ENTRY_IMPORT,
            &Size);
    for ( ; pImportDescriptor->OriginalFirstThunk != 0; ++pImportDescriptor)
    {
        pThunkData = (PIMAGE_THUNK_DATA)
            (BaseAddress + pImportDescriptor->OriginalFirstThunk);
        for ( ; pThunkData->u1.Ordinal != 0; ++pThunkData)
        {
            if (!IMAGE_SNAP_BY_ORDINAL(pThunkData->u1.Ordinal))
            {
                pImportByName = (PIMAGE_IMPORT_BY_NAME)
                    (BaseAddress + (DWORD)pThunkData->u1.AddressOfData);
                if (strcmp((char *)pImportByName->Name, funcname) == 0)
                {
                    strcpy(dllname, (char *)(BaseAddress + pImportDescriptor->Name));
                    return TRUE;
                }
            }
        }
    }
    return FALSE;
}
#endif

static int
sbcs_mblen(csconv_t *cv, const uchar *buf, int bufsize)
{
    return 1;
}

static int
dbcs_mblen(csconv_t *cv, const uchar *buf, int bufsize)
{
    int len = IsDBCSLeadByteEx(cv->codepage, buf[0]) ? 2 : 1;
    if (bufsize < len)
        return_error(EINVAL);
    return len;
}

static int
utf8_mblen(csconv_t *cv, const uchar *buf, int bufsize)
{
    int len = 0;

    if (buf[0] < 0x80) len = 1;
    else if ((buf[0] & 0xE0) == 0xC0) len = 2;
    else if ((buf[0] & 0xF0) == 0xE0) len = 3;
    else if ((buf[0] & 0xF8) == 0xF0) len = 4;
    else if ((buf[0] & 0xFC) == 0xF8) len = 5;
    else if ((buf[0] & 0xFE) == 0xFC) len = 6;

    if (len == 0)
        return_error(EILSEQ);
    else if (bufsize < len)
        return_error(EINVAL);
    return len;
}

static int
eucjp_mblen(csconv_t *cv, const uchar *buf, int bufsize)
{
    if (buf[0] < 0x80) /* ASCII */
        return 1;
    else if (buf[0] == 0x8E) /* JIS X 0201 */
    {
        if (bufsize < 2)
            return_error(EINVAL);
        else if (!(0xA1 <= buf[1] && buf[1] <= 0xDF))
            return_error(EILSEQ);
        return 2;
    }
    else if (buf[0] == 0x8F) /* JIS X 0212 */
    {
        if (bufsize < 3)
            return_error(EINVAL);
        else if (!(0xA1 <= buf[1] && buf[1] <= 0xFE)
                || !(0xA1 <= buf[2] && buf[2] <= 0xFE))
            return_error(EILSEQ);
        return 3;
    }
    else /* JIS X 0208 */
    {
        if (bufsize < 2)
            return_error(EINVAL);
        else if (!(0xA1 <= buf[0] && buf[0] <= 0xFE)
                || !(0xA1 <= buf[1] && buf[1] <= 0xFE))
            return_error(EILSEQ);
        return 2;
    }
}

static int
kernel_mbtowc(csconv_t *cv, const uchar *buf, int bufsize, ushort *wbuf, int *wbufsize)
{
    int len;

    len = cv->mblen(cv, buf, bufsize);
    if (len == -1)
        return -1;
    *wbufsize = MultiByteToWideChar(cv->codepage, MB_ERR_INVALID_CHARS,
            (const char *)buf, len, (wchar_t *)wbuf, *wbufsize);
    if (*wbufsize == 0)
        return_error(EILSEQ);
    return len;
}

static int
kernel_wctomb(csconv_t *cv, ushort *wbuf, int wbufsize, uchar *buf, int bufsize)
{
    BOOL usedDefaultChar = 0;
    int len;

    len = WideCharToMultiByte(cv->codepage, 0,
            (const wchar_t *)wbuf, wbufsize, (char *)buf, bufsize, NULL,
            (cv->codepage == 65000 || cv->codepage == 65001) ? NULL : &usedDefaultChar);
    if (len == 0)
    {
        if (GetLastError() == ERROR_INSUFFICIENT_BUFFER)
            return_error(E2BIG);
        return_error(EILSEQ);
    }
    else if (usedDefaultChar)
        return_error(EILSEQ);
    return len;
}

static int
mlang_mbtowc(csconv_t *cv, const uchar *buf, int bufsize, ushort *wbuf, int *wbufsize)
{
    int len;
    int insize;
    HRESULT hr;

    len = cv->mblen(cv, buf, bufsize);
    if (len == -1)
        return -1;
    insize = len;
    hr = ConvertINetMultiByteToUnicode(&cv->mode, cv->codepage,
            (const char *)buf, &insize, (wchar_t *)wbuf, wbufsize);
    if (hr != S_OK || insize != len)
        return_error(EILSEQ);
    return len;
}

static int
mlang_wctomb(csconv_t *cv, ushort *wbuf, int wbufsize, uchar *buf, int bufsize)
{
    char tmpbuf[MB_CHAR_MAX]; /* enough room for one character */
    int tmpsize = MB_CHAR_MAX;
    int insize = wbufsize;
    HRESULT hr;

    hr = ConvertINetUnicodeToMultiByte(&cv->mode, cv->codepage,
            (const wchar_t *)wbuf, &wbufsize, tmpbuf, &tmpsize);
    if (hr != S_OK || insize != wbufsize)
        return_error(EILSEQ);
    else if (bufsize < tmpsize)
        return_error(E2BIG);
    memcpy(buf, tmpbuf, tmpsize);
    return tmpsize;
}

static int
utf16_mbtowc(csconv_t *cv, const uchar *buf, int bufsize, ushort *wbuf, int *wbufsize)
{
    if (bufsize < 2)
        return_error(EINVAL);
    if (cv->codepage == 1200) /* little endian */
        wbuf[0] = (buf[1] << 8) | buf[0];
    else if (cv->codepage == 1201) /* big endian */
        wbuf[0] = (buf[0] << 8) | buf[1];
    if (0xDC00 <= wbuf[0] && wbuf[0] <= 0xDFFF)
        return_error(EILSEQ);
    if (0xD800 <= wbuf[0] && wbuf[0] <= 0xDBFF)
    {
        if (bufsize < 4)
            return_error(EINVAL);
        if (cv->codepage == 1200) /* little endian */
            wbuf[1] = (buf[3] << 8) | buf[2];
        else if (cv->codepage == 1201) /* big endian */
            wbuf[1] = (buf[2] << 8) | buf[3];
        if (!(0xDC00 <= wbuf[1] && wbuf[1] <= 0xDFFF))
            return_error(EILSEQ);
        *wbufsize = 2;
        return 4;
    }
    *wbufsize = 1;
    return 2;
}

static int
utf16_wctomb(csconv_t *cv, ushort *wbuf, int wbufsize, uchar *buf, int bufsize)
{
    if (bufsize < 2)
        return_error(E2BIG);
    if (cv->codepage == 1200) /* little endian */
    {
        buf[0] = (wbuf[0] & 0x00FF);
        buf[1] = (wbuf[0] & 0xFF00) >> 8;
    }
    else if (cv->codepage == 1201) /* big endian */
    {
        buf[0] = (wbuf[0] & 0xFF00) >> 8;
        buf[1] = (wbuf[0] & 0x00FF);
    }
    if (0xD800 <= wbuf[0] && wbuf[0] <= 0xDBFF)
    {
        if (bufsize < 4)
            return_error(E2BIG);
        if (cv->codepage == 1200) /* little endian */
        {
            buf[2] = (wbuf[1] & 0x00FF);
            buf[3] = (wbuf[1] & 0xFF00) >> 8;
        }
        else if (cv->codepage == 1201) /* big endian */
        {
            buf[2] = (wbuf[1] & 0xFF00) >> 8;
            buf[3] = (wbuf[1] & 0x00FF);
        }
        return 4;
    }
    return 2;
}

static int
utf32_mbtowc(csconv_t *cv, const uchar *buf, int bufsize, ushort *wbuf, int *wbufsize)
{
    uint wc;

    if (bufsize < 4)
        return_error(EINVAL);
    if (cv->codepage == 12000) /* little endian */
        wc = (buf[3] << 24) | (buf[2] << 16) | (buf[1] << 8) | buf[0];
    else if (cv->codepage == 12001) /* big endian */
        wc = (buf[0] << 24) | (buf[1] << 16) | (buf[2] << 8) | buf[3];
    if ((0xD800 <= wc && wc <= 0xDFFF) || 0x10FFFF < wc)
        return_error(EILSEQ);
    ucs4_to_utf16(wc, wbuf, wbufsize);
    return 4;
}

static int
utf32_wctomb(csconv_t *cv, ushort *wbuf, int wbufsize, uchar *buf, int bufsize)
{
    uint wc;

    if (bufsize < 4)
        return_error(E2BIG);
    wc = utf16_to_ucs4(wbuf);
    if (cv->codepage == 12000) /* little endian */
    {
        buf[0] = wc & 0x000000FF;
        buf[1] = (wc & 0x0000FF00) >> 8;
        buf[2] = (wc & 0x00FF0000) >> 16;
        buf[3] = (wc & 0xFF000000) >> 24;
    }
    else if (cv->codepage == 12001) /* big endian */
    {
        buf[0] = (wc & 0xFF000000) >> 24;
        buf[1] = (wc & 0x00FF0000) >> 16;
        buf[2] = (wc & 0x0000FF00) >> 8;
        buf[3] = wc & 0x000000FF;
    }
    return 4;
}

/*
 * 50220: ISO 2022 Japanese with no halfwidth Katakana; Japanese (JIS)
 * 50221: ISO 2022 Japanese with halfwidth Katakana; Japanese (JIS-Allow
 *        1 byte Kana)
 * 50222: ISO 2022 Japanese JIS X 0201-1989; Japanese (JIS-Allow 1 byte
 *        Kana - SO/SI)
 */
static const char iso2022jp_escape_ascii[] = "\x1B\x28\x42";
static const char iso2022jp_escape_jisx0201_roman[] = "\x1B\x28\x4A";
static const char iso2022jp_escape_jisx0201_kana[] = "\x1B\x28\x49";
static const char iso2022jp_escape_jisx0208_1978[] = "\x1B\x24\x40";
static const char iso2022jp_escape_jisx0208_1983[] = "\x1B\x24\x42";

/* shift out (to kana) */
static const char iso2022jp_SO[] = "\x0E";
/* shift in (to ascii) */
static const char iso2022jp_SI[] = "\x0F";

#define ISO2022JP_MODE_ASCII            0
#define ISO2022JP_MODE_JISX0201_ROMAN   1
#define ISO2022JP_MODE_JISX0201_KANA    2
#define ISO2022JP_MODE_JISX0208         3

static int
iso2022jp_mbtowc(csconv_t *cv, const uchar *buf, int bufsize, ushort *wbuf, int *wbufsize)
{
    char tmp[MB_CHAR_MAX];
    int len;
    int esc_len;

    if (buf[0] == 0x1B)
    {
        if (bufsize < 3) /* escape sequence is 3 or 4 bytes */
            return_error(EINVAL);
        if (strncmp((char *)buf, iso2022jp_escape_ascii,
                    STATIC_STRLEN(iso2022jp_escape_ascii)) == 0)
        {
            cv->mode = ISO2022JP_MODE_ASCII;
            esc_len = STATIC_STRLEN(iso2022jp_escape_ascii);
        }
        else if (strncmp((char *)buf, iso2022jp_escape_jisx0201_roman,
                    STATIC_STRLEN(iso2022jp_escape_jisx0201_roman)) == 0)
        {
            cv->mode = ISO2022JP_MODE_JISX0201_ROMAN;
            esc_len = STATIC_STRLEN(iso2022jp_escape_jisx0201_roman);
        }
        else if (strncmp((char *)buf, iso2022jp_escape_jisx0201_kana,
                    STATIC_STRLEN(iso2022jp_escape_jisx0201_kana)) == 0)
        {
            cv->mode = ISO2022JP_MODE_JISX0201_KANA;
            esc_len = STATIC_STRLEN(iso2022jp_escape_jisx0201_kana);
        }
        else if (strncmp((char *)buf, iso2022jp_escape_jisx0208_1978,
                    STATIC_STRLEN(iso2022jp_escape_jisx0208_1978)) == 0)
        {
            cv->mode = ISO2022JP_MODE_JISX0208;
            esc_len = STATIC_STRLEN(iso2022jp_escape_jisx0208_1978);
        }
        else if (strncmp((char *)buf, iso2022jp_escape_jisx0208_1983,
                    STATIC_STRLEN(iso2022jp_escape_jisx0208_1983)) == 0)
        {
            cv->mode = ISO2022JP_MODE_JISX0208;
            esc_len = STATIC_STRLEN(iso2022jp_escape_jisx0208_1983);
        }
        else
        {
            /* not supported escape sequence */
            return_error(EILSEQ);
        }
        *wbufsize = 0;
        return esc_len;
    }
    else if (buf[0] == iso2022jp_SO[0])
    {
        cv->mode = ISO2022JP_MODE_JISX0201_KANA;
        *wbufsize = 0;
        return 1;
    }
    else if (buf[0] == iso2022jp_SI[0])
    {
        cv->mode = ISO2022JP_MODE_ASCII;
        *wbufsize = 0;
        return 1;
    }

    if (0x80 <= buf[0])
        return_error(EILSEQ);

    if (cv->mode == ISO2022JP_MODE_ASCII)
    {
        len = 1;
        esc_len = STATIC_STRLEN(iso2022jp_escape_ascii);
        memcpy(tmp, iso2022jp_escape_ascii, esc_len);
        memcpy(tmp + esc_len, buf, len);
    }
    else if (cv->mode == ISO2022JP_MODE_JISX0201_ROMAN)
    {
        len = 1;
        esc_len = STATIC_STRLEN(iso2022jp_escape_jisx0201_roman);
        memcpy(tmp, iso2022jp_escape_jisx0201_roman, esc_len);
        memcpy(tmp + esc_len, buf, len);
    }
    else if (cv->mode == ISO2022JP_MODE_JISX0201_KANA)
    {
        len = 1;
        esc_len = STATIC_STRLEN(iso2022jp_escape_jisx0201_kana);
        memcpy(tmp, iso2022jp_escape_jisx0201_kana, esc_len);
        memcpy(tmp + esc_len, buf, len);
    }
    else if (cv->mode == ISO2022JP_MODE_JISX0208)
    {
        len = 2;
        if (bufsize < len)
            return_error(EINVAL);
        else if (0x80 <= buf[1])
            return_error(EILSEQ);
        esc_len = STATIC_STRLEN(iso2022jp_escape_jisx0208_1983);
        memcpy(tmp, iso2022jp_escape_jisx0208_1983, esc_len);
        memcpy(tmp + esc_len, buf, len);
    }
    /* MB_ERR_INVALID_CHARS cannot be used for CP50220, CP50221 and
     * CP50222 */
    *wbufsize = MultiByteToWideChar(cv->codepage, 0,
            tmp, len + esc_len, (wchar_t *)wbuf, *wbufsize);
    if (*wbufsize == 0)
        return_error(EILSEQ);

    /* Check for conversion error.  Assuming defaultChar is 0x3F. */
    /* ascii should be converted from ascii */
    if (wbuf[0] == buf[0] && cv->mode != ISO2022JP_MODE_ASCII)
        return_error(EILSEQ);

    return len;
}

static int
iso2022jp_wctomb(csconv_t *cv, ushort *wbuf, int wbufsize, uchar *buf, int bufsize)
{
    char tmp[MB_CHAR_MAX];
    int len;
    int esc_len;
    int mode = cv->mode;

    /* defaultChar cannot be used for CP50220, CP50221 and CP50222 */
    len = WideCharToMultiByte(cv->codepage, 0,
            (const wchar_t *)wbuf, wbufsize, tmp, sizeof(tmp), NULL, NULL);
    if (len == 0)
        return_error(EILSEQ);

    /* Check for conversion error.  Assuming defaultChar is 0x3F. */
    /* ascii should be converted from ascii */
    if (len == 1 && wbuf[0] >= 0x80)
        return_error(EILSEQ);

    if (len == 1)
    {
        mode = ISO2022JP_MODE_ASCII;
        esc_len = 0;
    }
    else if (strncmp(tmp, iso2022jp_escape_jisx0201_roman,
                STATIC_STRLEN(iso2022jp_escape_jisx0201_roman)) == 0)
    {
        mode = ISO2022JP_MODE_JISX0201_ROMAN;
        esc_len = STATIC_STRLEN(iso2022jp_escape_jisx0201_roman);
    }
    else if (strncmp(tmp, iso2022jp_escape_jisx0201_kana,
                STATIC_STRLEN(iso2022jp_escape_jisx0201_kana)) == 0)
    {
        mode = ISO2022JP_MODE_JISX0201_KANA;
        esc_len = STATIC_STRLEN(iso2022jp_escape_jisx0201_kana);
    }
    else if (strncmp(tmp, iso2022jp_escape_jisx0208_1978,
                STATIC_STRLEN(iso2022jp_escape_jisx0208_1978)) == 0)
    {
        mode = ISO2022JP_MODE_JISX0208;
        esc_len = STATIC_STRLEN(iso2022jp_escape_jisx0208_1978);
    }
    else if (strncmp(tmp, iso2022jp_escape_jisx0208_1983,
                STATIC_STRLEN(iso2022jp_escape_jisx0208_1983)) == 0)
    {
        mode = ISO2022JP_MODE_JISX0208;
        esc_len = STATIC_STRLEN(iso2022jp_escape_jisx0208_1983);
    }
    else
    {
        /* not supported escape sequence */
        return_error(EILSEQ);
    }

    if (tmp[esc_len] == iso2022jp_SO[0])
    {
        mode = ISO2022JP_MODE_JISX0201_KANA;
        esc_len += 1;
    }

    len -= esc_len;

    if (cv->mode != mode && mode == ISO2022JP_MODE_ASCII)
    {
        /* insert escape sequence */
        if (cv->codepage == 50222 && cv->mode == ISO2022JP_MODE_JISX0201_KANA)
        {
            /* use SI */
            esc_len = 1;
            memmove(tmp + esc_len, tmp, len);
            memcpy(tmp, iso2022jp_SI, esc_len);
        }
        else
        {
            esc_len = STATIC_STRLEN(iso2022jp_escape_ascii);
            memmove(tmp + esc_len, tmp, len);
            memcpy(tmp, iso2022jp_escape_ascii, esc_len);
        }
    }
    else if (cv->codepage == 50222 && cv->mode != mode && cv->mode == ISO2022JP_MODE_JISX0201_KANA)
    {
        /* insert SI before changing to other mode */
        memmove(tmp + 1, tmp, len);
        memcpy(tmp, iso2022jp_SI, 1);
        esc_len += 1;
    }
    else if (cv->mode == mode && mode != ISO2022JP_MODE_ASCII)
    {
        /* remove escape sequence */
        memmove(tmp, tmp + esc_len, len);
        esc_len = 0;
    }

    if (bufsize < len + esc_len)
        return_error(E2BIG);
    memcpy(buf, tmp, len + esc_len);
    cv->mode = mode;
    return len + esc_len;
}

static int
iso2022jp_flush(csconv_t *cv, uchar *buf, int bufsize)
{
    int esc_len;

    if (cv->mode != ISO2022JP_MODE_ASCII)
    {
        esc_len = STATIC_STRLEN(iso2022jp_escape_ascii);
        if (bufsize < esc_len)
            return_error(E2BIG);
        memcpy(buf, iso2022jp_escape_ascii, esc_len);
        return esc_len;
    }
    return 0;
}

#if defined(MAKE_DLL) && defined(USE_LIBICONV_DLL)
BOOL WINAPI
DllMain(HINSTANCE hinstDLL, DWORD fdwReason, LPVOID lpReserved)
{
    switch( fdwReason )
    {
    case DLL_PROCESS_ATTACH:
        hwiniconv = (HMODULE)hinstDLL;
        break;
    case DLL_THREAD_ATTACH:
    case DLL_THREAD_DETACH:
    case DLL_PROCESS_DETACH:
        break;
    }
    return TRUE;
}
#endif

#if defined(MAKE_EXE)
#include <stdio.h>
#include <fcntl.h>
#include <io.h>
int
main(int argc, char **argv)
{
    char *fromcode = NULL;
    char *tocode = NULL;
    int i;
    char inbuf[BUFSIZ];
    char outbuf[BUFSIZ];
    const char *pin;
    char *pout;
    size_t inbytesleft;
    size_t outbytesleft;
    size_t rest = 0;
    iconv_t cd;
    size_t r;
    FILE *in = stdin;

    _setmode(_fileno(stdin), _O_BINARY);
    _setmode(_fileno(stdout), _O_BINARY);

    for (i = 1; i < argc; ++i)
    {
        if (strcmp(argv[i], "-l") == 0)
        {
            for (i = 0; codepage_alias[i].name != NULL; ++i)
                printf("%s\n", codepage_alias[i].name);
            return 0;
        }

        if (strcmp(argv[i], "-f") == 0)
            fromcode = argv[++i];
        else if (strcmp(argv[i], "-t") == 0)
            tocode = argv[++i];
        else
        {
            in = fopen(argv[i], "rb");
            if (in == NULL)
            {
                fprintf(stderr, "cannot open %s\n", argv[i]);
                return 1;
            }
            break;
        }
    }

    if (fromcode == NULL || tocode == NULL)
    {
        printf("usage: %s -f from-enc -t to-enc [file]\n", argv[0]);
        return 0;
    }

    cd = iconv_open(tocode, fromcode);
    if (cd == (iconv_t)(-1))
    {
        perror("iconv_open error");
        return 1;
    }

    while ((inbytesleft = fread(inbuf + rest, 1, sizeof(inbuf) - rest, in)) != 0
            || rest != 0)
    {
        inbytesleft += rest;
        pin = inbuf;
        pout = outbuf;
        outbytesleft = sizeof(outbuf);
        r = iconv(cd, &pin, &inbytesleft, &pout, &outbytesleft);
        fwrite(outbuf, 1, sizeof(outbuf) - outbytesleft, stdout);
        if (r == (size_t)(-1) && errno != EINVAL && errno != E2BIG)
        {
            perror("conversion error");
            return 1;
        }
        memmove(inbuf, pin, inbytesleft);
        rest = inbytesleft;
    }
    pout = outbuf;
    outbytesleft = sizeof(outbuf);
    r = iconv(cd, NULL, NULL, &pout, &outbytesleft);
    fwrite(outbuf, 1, sizeof(outbuf) - outbytesleft, stdout);
    if (r == (size_t)(-1))
    {
        perror("conversion error");
        return 1;
    }

    iconv_close(cd);

    return 0;
}
#endif

