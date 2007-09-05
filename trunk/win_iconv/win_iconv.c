/*
 * Stateful encoding (such as iso-2022) is not supported because it is
 * difficult to handle shift sequence properly.
 *
 * MLang function drop or replace invalid bytes and does not return
 * useful error status as iconv.  It cannot be used for encoding
 * validation purpose.
 */

#include <windows.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>

#if 0
# define MAKE_EXE
# define MAKE_DLL
# define USE_LIBICONV_INTERFACE
#endif

#if defined(MAKE_DLL) && defined(_MSC_VER)
# define DLL_EXPORT __declspec(dllexport)
#else
# define DLL_EXPORT
#endif

/* libiconv interface for vim */
#if defined(USE_LIBICONV_INTERFACE)
# define iconv_open libiconv_open
# define iconv_close libiconv_close
# define iconv libiconv
#endif

#define MB_CHAR_MAX 16

#define return_error(code)  \
    do {                    \
        errno = code;       \
        return -1;          \
    } while (0)

typedef void* iconv_t;

DLL_EXPORT iconv_t iconv_open(const char *tocode, const char *fromcode);
DLL_EXPORT int iconv_close(iconv_t cd);
DLL_EXPORT size_t iconv(iconv_t cd, const char **inbuf, size_t *inbytesleft, char **outbuf, size_t *outbytesleft);
#if defined(USE_LIBICONV_INTERFACE)
DLL_EXPORT int libiconvctl (iconv_t cd, int request, void* argument) { return 0; }
#endif

static int win_iconv_close(iconv_t cd);
static size_t win_iconv(iconv_t cd, const char **inbuf, size_t *inbytesleft, char **outbuf, size_t *outbytesleft);

typedef struct csconv_t csconv_t;
typedef struct rec_iconv_t rec_iconv_t;

typedef int (*f_iconv_close)(iconv_t cd);
typedef size_t (*f_iconv)(iconv_t cd, const char **inbuf, size_t *inbytesleft, char **outbuf, size_t *outbytesleft);
typedef int (*f_mbtowc)(csconv_t *cv, const char *buf, int bufsize, wchar_t *wbuf, int *wbufsize);
typedef int (*f_wctomb)(csconv_t *cv, const wchar_t *wbuf, int wbufsize, char *buf, int bufsize);
typedef int (*f_mblen)(csconv_t *cv, const char *buf, int bufsize);
typedef int (*f_flush)(csconv_t *cv, char *buf, int bufsize);

struct csconv_t {
    int codepage;
    f_mbtowc mbtowc;
    f_wctomb wctomb;
    f_mblen mblen;
    f_flush flush;
    DWORD mode;
};

struct rec_iconv_t {
    csconv_t from;
    csconv_t to;
    f_iconv_close iconv_close;
    f_iconv iconv;
};

static int load_mlang();
static csconv_t make_csconv(const char *name);
static int name_to_codepage(const char *name);

static int sbcs_mblen(csconv_t *cv, const char *buf, int bufsize);
static int dbcs_mblen(csconv_t *cv, const char *buf, int bufsize);
static int utf8_mblen(csconv_t *cv, const char *buf, int bufsize);
static int eucjp_mblen(csconv_t *cv, const char *buf, int bufsize);

static int kernel_mbtowc(csconv_t *cv, const char *buf, int bufsize, wchar_t *wbuf, int *wbufsize);
static int kernel_wctomb(csconv_t *cv, const wchar_t *wbuf, int wbufsize, char *buf, int bufsize);
static int mlang_mbtowc(csconv_t *cv, const char *buf, int bufsize, wchar_t *wbuf, int *wbufsize);
static int mlang_wctomb(csconv_t *cv, const wchar_t *wbuf, int wbufsize, char *buf, int bufsize);
static int utf16le_mbtowc(csconv_t *cv, const char *buf, int bufsize, wchar_t *wbuf, int *wbufsize);
static int utf16le_wctomb(csconv_t *cv, const wchar_t *wbuf, int wbufsize, char *buf, int bufsize);
static int utf16be_mbtowc(csconv_t *cv, const char *buf, int bufsize, wchar_t *wbuf, int *wbufsize);
static int utf16be_wctomb(csconv_t *cv, const wchar_t *wbuf, int wbufsize, char *buf, int bufsize);

static int flush_dummy(csconv_t *cv, char *buf, int bufsize);

struct {
    int codepage;
    const char *name;
} codepage_alias[] = {
    {65001, "CP65001"},
    {65001, "UTF8"},
    {65001, "UTF-8"},

    /* !IsValidCodePage(1200) */
    {1200, "CP1200"},
    {1200, "UTF16LE"},
    {1200, "UTF-16LE"},

    /* !IsValidCodePage(1201) */
    {1201, "CP1201"},
    {1201, "UTF16"},
    {1201, "UTF16BE"},
    {1201, "UTF-16BE"},

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

    /*
     * what is different between 20932 and 51932
     * CP20932: A1C1 -> U+301C
     * CP51932: A1C1 -> U+FF5E
     */
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

    {0, NULL}
};

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
    if (ConvertINetString != NULL)
        return 1;
    HMODULE h = LoadLibrary("mlang.dll");
    if (!h)
        return 0;
    ConvertINetString = (CONVERTINETSTRING)GetProcAddress(h, "ConvertINetString");
    ConvertINetMultiByteToUnicode = (CONVERTINETMULTIBYTETOUNICODE)GetProcAddress(h, "ConvertINetMultiByteToUnicode");
    ConvertINetUnicodeToMultiByte = (CONVERTINETUNICODETOMULTIBYTE)GetProcAddress(h, "ConvertINetUnicodeToMultiByte");
    IsConvertINetStringAvailable = (ISCONVERTINETSTRINGAVAILABLE)GetProcAddress(h, "IsConvertINetStringAvailable");
    LcidToRfc1766 = (LCIDTORFC1766)GetProcAddress(h, "LcidToRfc1766");
    Rfc1766ToLcid = (RFC1766TOLCID)GetProcAddress(h, "Rfc1766ToLcid");
    return 1;
}

/* XXX: load libiconv.dll if possible? */
iconv_t
iconv_open(const char *tocode, const char *fromcode)
{
    rec_iconv_t cd;
    rec_iconv_t *res;

    cd.from = make_csconv(fromcode);
    cd.to = make_csconv(tocode);
    if (cd.from.codepage == -1 || cd.to.codepage == -1)
    {
        errno = EINVAL;
        return (iconv_t)(-1);
    }

    cd.iconv_close = win_iconv_close;
    cd.iconv = win_iconv;

    res = (rec_iconv_t *)malloc(sizeof(rec_iconv_t));
    *res = cd;
    return (iconv_t)res;
}

int
iconv_close(iconv_t cd)
{
    return ((rec_iconv_t *)cd)->iconv_close(cd);
}

size_t
iconv(iconv_t cd, const char **inbuf, size_t *inbytesleft, char **outbuf, size_t *outbytesleft)
{
    return ((rec_iconv_t *)cd)->iconv(cd, inbuf, inbytesleft, outbuf, outbytesleft);
}

static int
win_iconv_close(iconv_t cd)
{
    free(cd);
    return 0;
}

static size_t
win_iconv(iconv_t _cd, const char **inbuf, size_t *inbytesleft, char **outbuf, size_t *outbytesleft)
{
    rec_iconv_t *cd = (rec_iconv_t *)_cd;
    wchar_t wbuf[MB_CHAR_MAX]; /* enough room for one character */
    int insize;
    int outsize;
    int wsize;

    if (inbuf == NULL || *inbuf == NULL)
    {
        if (outbuf != NULL && *outbuf != NULL && cd->to.flush != NULL)
        {
            outsize = cd->to.flush(&cd->to, *outbuf, *outbytesleft);
            cd->to.mode = 0;
            if (outsize == -1)
                return (size_t)(-1);
        }
        else
            cd->to.mode = 0;
        return 0;
    }

    while (*inbytesleft != 0)
    {
        wsize = MB_CHAR_MAX;

        insize = cd->from.mbtowc(&cd->from, *inbuf, *inbytesleft, wbuf, &wsize);
        if (insize == -1)
            return (size_t)(-1);

        outsize = cd->to.wctomb(&cd->to, wbuf, wsize, *outbuf, *outbytesleft);
        if (outsize == -1)
            return (size_t)(-1);

        *inbuf += insize;
        *outbuf += outsize;
        *inbytesleft -= insize;
        *outbytesleft -= outsize;
    }

    return 0;
}

static csconv_t
make_csconv(const char *name)
{
    CPINFOEX cpinfoex;
    csconv_t cv;

    cv.mode = 0;
    cv.codepage = name_to_codepage(name);
    if (cv.codepage == 1200)
    {
        cv.mbtowc = utf16le_mbtowc;
        cv.wctomb = utf16le_wctomb;
        cv.mblen = NULL;
        cv.flush = NULL;
    }
    else if (cv.codepage == 1201)
    {
        cv.mbtowc = utf16be_mbtowc;
        cv.wctomb = utf16be_wctomb;
        cv.mblen = NULL;
        cv.flush = NULL;
    }
    else if (cv.codepage == 65001)
    {
        cv.mbtowc = kernel_mbtowc;
        cv.wctomb = kernel_wctomb;
        cv.mblen = utf8_mblen;
        cv.flush = NULL;
    }
    else if (cv.codepage == 51932 && load_mlang())
    {
        cv.mbtowc = mlang_mbtowc;
        cv.wctomb = mlang_wctomb;
        cv.mblen = eucjp_mblen;
        cv.flush = NULL;
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
        cv.flush = NULL;
    }
    else
    {
        /* not supported */
        cv.codepage = -1;
    }
    return cv;
}

static int
name_to_codepage(const char *name)
{
    int i;

    if ((name[0] == 'c' || name[0] == 'C') && (name[1] == 'p' || name[1] == 'P'))
        return atoi(name + 2);
    else if ('0' <= name[0] && name[0] <= '9')
        return atoi(name);

    for (i = 0; codepage_alias[i].name != NULL; ++i)
        if (lstrcmpi(name, codepage_alias[i].name) == 0)
            return codepage_alias[i].codepage;
    return -1;
}

static int
sbcs_mblen(csconv_t *cv, const char *buf, int bufsize)
{
    return 1;
}

static int
dbcs_mblen(csconv_t *cv, const char *buf, int bufsize)
{
    int len = IsDBCSLeadByteEx(cv->codepage, buf[0]) ? 2 : 1;
    if (bufsize < len)
        return_error(EINVAL);
    return len;
}

static int
utf8_mblen(csconv_t *cv, const char *_buf, int bufsize)
{
    unsigned char *buf = (unsigned char *)_buf;
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
eucjp_mblen(csconv_t *cv, const char *_buf, int bufsize)
{
    unsigned char *buf = (unsigned char *)_buf;

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
kernel_mbtowc(csconv_t *cv, const char *buf, int bufsize, wchar_t *wbuf, int *wbufsize)
{
    int len;

    len = cv->mblen(cv, buf, bufsize);
    if (len == -1)
        return -1;
    *wbufsize = MultiByteToWideChar(cv->codepage, MB_ERR_INVALID_CHARS,
            buf, len, wbuf, *wbufsize);
    if (*wbufsize == 0)
        return_error(EILSEQ);
    return len;
}

static int
kernel_wctomb(csconv_t *cv, const wchar_t *wbuf, int wbufsize, char *buf, int bufsize)
{
    BOOL usedDefaultChar = 0;
    int len;

    len = WideCharToMultiByte(cv->codepage, 0,
            wbuf, wbufsize, buf, bufsize, NULL,
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
mlang_mbtowc(csconv_t *cv, const char *buf, int bufsize, wchar_t *wbuf, int *wbufsize)
{
    int len;
    int insize;
    HRESULT hr;

    len = cv->mblen(cv, buf, bufsize);
    if (len == -1)
        return -1;
    insize = len;
    hr = ConvertINetMultiByteToUnicode(&cv->mode, cv->codepage,
            buf, &insize, wbuf, wbufsize);
    if (hr != S_OK || insize != len)
        return_error(EILSEQ);
    return len;
}

static int
mlang_wctomb(csconv_t *cv, const wchar_t *wbuf, int wbufsize, char *buf, int bufsize)
{
    char tmpbuf[MB_CHAR_MAX]; /* enough room for one character */;
    int tmpsize = MB_CHAR_MAX;
    int insize = wbufsize;
    HRESULT hr;

    hr = ConvertINetUnicodeToMultiByte(&cv->mode, cv->codepage,
            wbuf, &wbufsize, tmpbuf, &tmpsize);
    if (hr != S_OK || insize != wbufsize)
        return_error(EILSEQ);
    else if (bufsize < tmpsize)
        return_error(E2BIG);
    memcpy(buf, tmpbuf, tmpsize);
    return tmpsize;
}

static int
utf16le_mbtowc(csconv_t *cv, const char *_buf, int bufsize, wchar_t *wbuf, int *wbufsize)
{
    unsigned char *buf = (unsigned char *)_buf;

    if (bufsize < 2)
        return_error(EINVAL);
    wbuf[0] = (buf[1] << 8) | buf[0];
    if (0xDC00 <= wbuf[0] && wbuf[0] <= 0xDFFF)
        return_error(EILSEQ);
    if (0xD800 <= wbuf[0] && wbuf[0] <= 0xDBFF)
    {
        if (bufsize < 4)
            return_error(EINVAL);
        wbuf[1] = (buf[3] << 8) | buf[2];
        if (!(0xDC00 <= wbuf[1] && wbuf[1] <= 0xDFFF))
            return_error(EILSEQ);
        *wbufsize = 2;
        return 4;
    }
    *wbufsize = 1;
    return 2;
}

static int
utf16le_wctomb(csconv_t *cv, const wchar_t *wbuf, int wbufsize, char *buf, int bufsize)
{
    if (bufsize < 2)
        return_error(E2BIG);
    buf[0] = (wbuf[0] & 0x00FF);
    buf[1] = (wbuf[0] & 0xFF00) >> 8;
    if (0xD800 <= wbuf[0] && wbuf[0] <= 0xDBFF)
    {
        if (bufsize < 4)
            return_error(E2BIG);
        buf[2] = (wbuf[1] & 0x00FF);
        buf[3] = (wbuf[1] & 0xFF00) >> 8;
        return 4;
    }
    return 2;
}

static int
utf16be_mbtowc(csconv_t *cv, const char *_buf, int bufsize, wchar_t *wbuf, int *wbufsize)
{
    unsigned char *buf = (unsigned char *)_buf;

    if (bufsize < 2)
        return_error(EINVAL);
    wbuf[0] = (buf[0] << 8) | buf[1];
    if (0xDC00 <= wbuf[0] && wbuf[0] <= 0xDFFF)
        return_error(EILSEQ);
    if (0xD800 <= wbuf[0] && wbuf[0] <= 0xDBFF)
    {
        if (bufsize < 4)
            return_error(EINVAL);
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
utf16be_wctomb(csconv_t *cv, const wchar_t *wbuf, int wbufsize, char *buf, int bufsize)
{
    if (bufsize < 2)
        return_error(E2BIG);
    buf[0] = (wbuf[0] & 0xFF00) >> 8;
    buf[1] = (wbuf[0] & 0x00FF);
    if (0xD800 <= wbuf[0] && wbuf[0] <= 0xDBFF)
    {
        if (bufsize < 4)
            return_error(E2BIG);
        buf[2] = (wbuf[1] & 0xFF00) >> 8;
        buf[3] = (wbuf[1] & 0x00FF);
        return 4;
    }
    return 2;
}

static int
flush_dummy(csconv_t *cv, char *buf, int bufsize)
{
    return 0;
}

#if defined(MAKE_EXE)
#include <stdio.h>
#include <fcntl.h>
#include <io.h>
int
main(int argc, char **argv)
{
    char *fromcode;
    char *tocode;
    int i;
    char inbuf[8192];
    char outbuf[8192];
    const char *inp;
    char *outp;
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
        inp = inbuf;
        outp = outbuf;
        outbytesleft = sizeof(outbuf);
        r = iconv(cd, &inp, &inbytesleft, &outp, &outbytesleft);
        if (r != (size_t)(-1) || errno == E2BIG || errno == EINVAL)
        {
            fwrite(outbuf, 1, sizeof(outbuf) - outbytesleft, stdout);
            memmove(inbuf, inp, sizeof(inbuf) - inbytesleft);
            rest = inbytesleft;
        }
        else
        {
            fwrite(outbuf, 1, sizeof(outbuf) - outbytesleft, stdout);
            perror("conversion error");
            return 1;
        }
    }

    iconv_close(cd);

    return 0;
}
#endif

