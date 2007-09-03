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

typedef void* iconv_t;

DLL_EXPORT iconv_t iconv_open(const char *tocode, const char *fromcode);
DLL_EXPORT int iconv_close(iconv_t cd);
DLL_EXPORT size_t iconv(iconv_t cd, const char **inbuf, size_t *inbytesleft, char **outbuf, size_t *outbytesleft);
#if defined(USE_LIBICONV_INTERFACE)
DLL_EXPORT int libiconvctl (iconv_t cd, int request, void* argument) { return 0; }
#endif

static int kernel_iconv_close(iconv_t cd);
static size_t kernel_iconv(iconv_t cd, const char **inbuf, size_t *inbytesleft, char **outbuf, size_t *outbytesleft);
static size_t mlang_iconv(iconv_t cd, const char **inbuf, size_t *inbytesleft, char **outbuf, size_t *outbytesleft);

typedef int (* f_iconv_close)(iconv_t cd);
typedef size_t (*f_iconv)(iconv_t cd, const char **inbuf, size_t *inbytesleft, char **outbuf, size_t *outbytesleft);

struct csconv_t {
    DWORD mode;
    int codepage;
};
typedef struct csconv_t csconv_t;

struct rec_iconv_t {
    csconv_t from;
    csconv_t to;
    f_iconv_close iconv_close;
    f_iconv iconv;
};
typedef struct rec_iconv_t rec_iconv_t;

static csconv_t make_csconv(const char *name);
static int name_to_codepage(const char *name);
static int is_kernel_codepage(int codepage);
static int cp_mblen(int codepage, const char *str);
static int utf16_to_wchar(const char *buf, wchar_t *wbuf, int codepage);
static int wchar_to_utf16(const wchar_t *wbuf, char *buf, int codepage);

static int load_mlang();

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

    /* load mlang.dll if necessary. */
    if (ConvertINetString == NULL
            && (!is_kernel_codepage(cd.from.codepage)
                || !is_kernel_codepage(cd.to.codepage)))
    {
        if (!load_mlang())
        {
            errno = EINVAL;
            return (iconv_t)(-1);
        }
    }

    if (is_kernel_codepage(cd.from.codepage) && is_kernel_codepage(cd.to.codepage))
    {
        cd.iconv_close = kernel_iconv_close;
        cd.iconv = kernel_iconv;
    }
    else
    {
        cd.iconv_close = kernel_iconv_close;
        cd.iconv = mlang_iconv;
    }

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
kernel_iconv_close(iconv_t cd)
{
    free(cd);
    return 0;
}

static size_t
kernel_iconv(iconv_t _cd, const char **inbuf, size_t *inbytesleft, char **outbuf, size_t *outbytesleft)
{
    rec_iconv_t *cd = (rec_iconv_t *)_cd;
    wchar_t wbuf[16]; /* enough room for one character */
    char buf[32];
    int insize;
    int outsize;
    int wsize;
    int len;
    BOOL usedDefaultChar = 0;

    if (inbuf == NULL || *inbuf == NULL)
        return 0;

    while (*inbytesleft != 0)
    {
        len = cp_mblen(cd->from.codepage, *inbuf);
        if (len == -1)
        {
            errno = EILSEQ;
            return (size_t)(-1);
        }

        if (*inbytesleft < len)
        {
            errno = EINVAL;
            return (size_t)(-1);
        }

        if (cd->from.codepage == 1200 || cd->from.codepage == 1201)
        {
            if (!utf16_to_wchar(*inbuf, wbuf, cd->from.codepage))
            {
                errno = EILSEQ;
                return (size_t)(-1);
            }
            insize = len;
            wsize = len / 2;
        }
        else
        {
            insize = len;
            wsize = MultiByteToWideChar(cd->from.codepage, MB_ERR_INVALID_CHARS,
                    *inbuf, insize, wbuf, sizeof(wbuf));
            if (wsize == 0)
            {
                errno = EILSEQ;
                return (size_t)(-1);
            }
        }

        if (cd->to.codepage == 1200 || cd->to.codepage == 1201)
        {
            if (!wchar_to_utf16(wbuf, buf, cd->to.codepage))
            {
                errno = EILSEQ;
                return (size_t)(-1);
            }
            outsize = wsize * 2;
        }
        else
        {
            outsize = WideCharToMultiByte(cd->to.codepage, 0,
                    wbuf, wsize, buf, sizeof(buf),
                    NULL, (cd->to.codepage == 65000 || cd->to.codepage == 65001)
                            ? NULL : &usedDefaultChar);
            if (outsize == 0 || usedDefaultChar)
            {
                errno = EILSEQ;
                return (size_t)(-1);
            }
        }

        if (*outbytesleft < outsize)
        {
            errno = E2BIG;
            return (size_t)(-1);
        }

        memcpy(*outbuf, buf, outsize);
        *inbuf += insize;
        *outbuf += outsize;
        *inbytesleft -= insize;
        *outbytesleft -= outsize;
    }

    return 0;
}

static size_t
mlang_iconv(iconv_t _cd, const char **inbuf, size_t *inbytesleft, char **outbuf, size_t *outbytesleft)
{
    rec_iconv_t *cd = (rec_iconv_t *)_cd;
    wchar_t wbuf[16]; /* enough room for one character */
    char buf[32];
    int insize;
    int outsize;
    int wsize;
    int len;
    HRESULT hr;

    if (inbuf == NULL || *inbuf == NULL)
        return 0;

    while (*inbytesleft != 0)
    {
        len = cp_mblen(cd->from.codepage, *inbuf);
        if (len == -1)
        {
            errno = EILSEQ;
            return (size_t)(-1);
        }

        if (*inbytesleft < len)
        {
            errno = EINVAL;
            return (size_t)(-1);
        }

        /* Few codepage combination cannot be converted directly (e.g.
         * CP51932 <-> UTF-8).  Convert via Unicode for it. */
#if 0
        insize = len;
        outsize = *outbytesleft;
        hr = ConvertINetString(&cd->from.mode, cd->from.codepage, cd->to.codepage,
                *inbuf, &insize, buf, &outsize);
        if (hr != S_OK || insize != len)
        {
            errno = EILSEQ;
            return (size_t)(-1);
        }
#else
        insize = len;
        wsize = sizeof(wbuf);
        hr = ConvertINetMultiByteToUnicode(&cd->from.mode, cd->from.codepage,
                *inbuf, &insize, wbuf, &wsize);
        if (hr != S_OK || insize != len)
        {
            errno = EILSEQ;
            return (size_t)(-1);
        }

        len = wsize;
        outsize = sizeof(buf);
        hr = ConvertINetUnicodeToMultiByte(&cd->to.mode, cd->to.codepage,
                wbuf, &wsize, buf, &outsize);
        if (hr != S_OK || wsize != len)
        {
            errno = EILSEQ;
            return (size_t)(-1);
        }
#endif

        if (*outbytesleft < outsize)
        {
            errno = E2BIG;
            return (size_t)(-1);
        }

        memcpy(*outbuf, buf, outsize);
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
    csconv_t cv;
    cv.mode = 0;
    cv.codepage = name_to_codepage(name);
    return cv;
}

static int
name_to_codepage(const char *name)
{
    if ((name[0] == 'c' || name[0] == 'C') && (name[1] == 'p' || name[1] == 'P'))
    {
        int codepage = atoi(name + 2);
        if (IsValidCodePage(codepage))
            return codepage;
    }

    if (lstrcmpi(name, "CP65001") == 0) return 65001;
    if (lstrcmpi(name, "UTF8") == 0) return 65001;
    if (lstrcmpi(name, "UTF-8") == 0) return 65001;

    /* !IsValidCodePage(1200) */
    if (lstrcmpi(name, "CP1200") == 0) return 1200;
    if (lstrcmpi(name, "UTF16LE") == 0) return 1200;
    if (lstrcmpi(name, "UTF-16LE") == 0) return 1200;

    /* !IsValidCodePage(1201) */
    if (lstrcmpi(name, "CP1201") == 0) return 1201;
    if (lstrcmpi(name, "UTF16") == 0) return 1201;
    if (lstrcmpi(name, "UTF16BE") == 0) return 1201;
    if (lstrcmpi(name, "UTF-16BE") == 0) return 1201;

    /* copy from libiconv `iconv -l` */
    /* !IsValidCodePage(367) */
    if (lstrcmpi(name, "ANSI_X3.4-1968") == 0) return 20127;
    if (lstrcmpi(name, "ANSI_X3.4-1986") == 0) return 20127;
    if (lstrcmpi(name, "ASCII") == 0) return 20127;
    if (lstrcmpi(name, "CP367") == 0) return 20127;
    if (lstrcmpi(name, "IBM367") == 0) return 20127;
    if (lstrcmpi(name, "ISO-IR-6") == 0) return 20127;
    if (lstrcmpi(name, "ISO646-US") == 0) return 20127;
    if (lstrcmpi(name, "ISO_646.IRV:1991") == 0) return 20127;
    if (lstrcmpi(name, "US") == 0) return 20127;
    if (lstrcmpi(name, "US-ASCII") == 0) return 20127;
    if (lstrcmpi(name, "CSASCII") == 0) return 20127;

    /* !IsValidCodePage(819) */
    if (lstrcmpi(name, "CP819") == 0) return 1252;
    if (lstrcmpi(name, "IBM819") == 0) return 1252;
    if (lstrcmpi(name, "ISO-8859-1") == 0) return 1252;
    if (lstrcmpi(name, "ISO-IR-100") == 0) return 1252;
    if (lstrcmpi(name, "ISO8859-1") == 0) return 1252;
    if (lstrcmpi(name, "ISO_8859-1") == 0) return 1252;
    if (lstrcmpi(name, "ISO_8859-1:1987") == 0) return 1252;
    if (lstrcmpi(name, "L1") == 0) return 1252;
    if (lstrcmpi(name, "LATIN1") == 0) return 1252;
    if (lstrcmpi(name, "CSISOLATIN1") == 0) return 1252;

    if (lstrcmpi(name, "CP1250") == 0) return 1250;
    if (lstrcmpi(name, "MS-EE") == 0) return 1250;
    if (lstrcmpi(name, "WINDOWS-1250") == 0) return 1250;

    if (lstrcmpi(name, "CP1251") == 0) return 1251;
    if (lstrcmpi(name, "MS-CYRL") == 0) return 1251;
    if (lstrcmpi(name, "WINDOWS-1251") == 0) return 1251;

    if (lstrcmpi(name, "CP1252") == 0) return 1252;
    if (lstrcmpi(name, "MS-ANSI") == 0) return 1252;
    if (lstrcmpi(name, "WINDOWS-1252") == 0) return 1252;

    if (lstrcmpi(name, "CP1253") == 0) return 1253;
    if (lstrcmpi(name, "MS-GREEK") == 0) return 1253;
    if (lstrcmpi(name, "WINDOWS-1253") == 0) return 1253;

    if (lstrcmpi(name, "CP1254") == 0) return 1254;
    if (lstrcmpi(name, "MS-TURK") == 0) return 1254;
    if (lstrcmpi(name, "WINDOWS-1254") == 0) return 1254;

    if (lstrcmpi(name, "CP1255") == 0) return 1255;
    if (lstrcmpi(name, "MS-HEBR") == 0) return 1255;
    if (lstrcmpi(name, "WINDOWS-1255") == 0) return 1255;

    if (lstrcmpi(name, "CP1256") == 0) return 1256;
    if (lstrcmpi(name, "MS-ARAB") == 0) return 1256;
    if (lstrcmpi(name, "WINDOWS-1256") == 0) return 1256;

    if (lstrcmpi(name, "CP1257") == 0) return 1257;
    if (lstrcmpi(name, "WINBALTRIM") == 0) return 1257;
    if (lstrcmpi(name, "WINDOWS-1257") == 0) return 1257;

    if (lstrcmpi(name, "CP1258") == 0) return 1258;
    if (lstrcmpi(name, "WINDOWS-1258") == 0) return 1258;

    if (lstrcmpi(name, "850") == 0) return 850;
    if (lstrcmpi(name, "CP850") == 0) return 850;
    if (lstrcmpi(name, "IBM850") == 0) return 850;
    if (lstrcmpi(name, "CSPC850MULTILINGUAL") == 0) return 850;

    /* !IsValidCodePage(862) */
    if (lstrcmpi(name, "862") == 0) return 862;
    if (lstrcmpi(name, "CP862") == 0) return 862;
    if (lstrcmpi(name, "IBM862") == 0) return 862;
    if (lstrcmpi(name, "CSPC862LATINHEBREW") == 0) return 862;

    if (lstrcmpi(name, "866") == 0) return 866;
    if (lstrcmpi(name, "CP866") == 0) return 866;
    if (lstrcmpi(name, "IBM866") == 0) return 866;
    if (lstrcmpi(name, "CSIBM866") == 0) return 866;

    /* !IsValidCodePage(154) */
    if (lstrcmpi(name, "CP154") == 0) return 154;
    if (lstrcmpi(name, "CYRILLIC-ASIAN") == 0) return 154;
    if (lstrcmpi(name, "PT154") == 0) return 154;
    if (lstrcmpi(name, "PTCP154") == 0) return 154;
    if (lstrcmpi(name, "CSPTCP154") == 0) return 154;

    /* !IsValidCodePage(1133) */
    if (lstrcmpi(name, "CP1133") == 0) return 1133;
    if (lstrcmpi(name, "IBM-CP1133") == 0) return 1133;

    if (lstrcmpi(name, "CP874") == 0) return 874;
    if (lstrcmpi(name, "WINDOWS-874") == 0) return 874;

    /* what is different 20932 and 51932 */
    /* !IsValidCodePage(51932) */
    if (lstrcmpi(name, "CP51932") == 0) return 51932;
    if (lstrcmpi(name, "MS51932") == 0) return 51932;
    if (lstrcmpi(name, "WINDOWS-51932") == 0) return 51932;

    /* 20932 can be converted with MultiByteToWideChar() */
    /* if (lstrcmpi(name, "EUC-JP") == 0) return 51932; */
    if (lstrcmpi(name, "EUC-JP") == 0) return 20932;

    if (lstrcmpi(name, "CP932") == 0) return 932;
    if (lstrcmpi(name, "MS932") == 0) return 932;
    if (lstrcmpi(name, "SHIFFT_JIS") == 0) return 932;
    if (lstrcmpi(name, "SHIFFT_JIS-MS") == 0) return 932;
    if (lstrcmpi(name, "SJIS") == 0) return 932;
    if (lstrcmpi(name, "SJIS-MS") == 0) return 932;
    if (lstrcmpi(name, "SJIS-OPEN") == 0) return 932;
    if (lstrcmpi(name, "SJIS-WIN") == 0) return 932;
    if (lstrcmpi(name, "WINDOWS-31J") == 0) return 932;
    if (lstrcmpi(name, "WINDOWS-932") == 0) return 932;
    if (lstrcmpi(name, "CSWINDOWS31J") == 0) return 932;

    if (lstrcmpi(name, "CP50221") == 0) return 50221;
    if (lstrcmpi(name, "ISO-2022-JP") == 0) return 50221;
    if (lstrcmpi(name, "ISO-2022-JP-MS") == 0) return 50221;
    if (lstrcmpi(name, "MS50221") == 0) return 50221;
    if (lstrcmpi(name, "WINDOWS-50221") == 0) return 50221;

    if (lstrcmpi(name, "CP936") == 0) return 936;
    if (lstrcmpi(name, "GBK") == 0) return 936;
    if (lstrcmpi(name, "MS936") == 0) return 936;
    if (lstrcmpi(name, "WINDOWS-936") == 0) return 936;

    if (lstrcmpi(name, "CP950") == 0) return 950;
    if (lstrcmpi(name, "BIG5") == 0) return 950;

    if (lstrcmpi(name, "CP949") == 0) return 949;
    if (lstrcmpi(name, "UHC") == 0) return 949;
    if (lstrcmpi(name, "EUC-KR") == 0) return 949;

    if (lstrcmpi(name, "CP1361") == 0) return 1361;
    if (lstrcmpi(name, "JOHAB") == 0) return 1361;

    if (lstrcmpi(name, "437") == 0) return 437;
    if (lstrcmpi(name, "CP437") == 0) return 437;
    if (lstrcmpi(name, "IBM437") == 0) return 437;
    if (lstrcmpi(name, "CSPC8CODEPAGE437") == 0) return 437;

    if (lstrcmpi(name, "CP737") == 0) return 737;

    if (lstrcmpi(name, "CP775") == 0) return 775;
    if (lstrcmpi(name, "IBM775") == 0) return 775;
    if (lstrcmpi(name, "CSPC775BALTIC") == 0) return 775;

    if (lstrcmpi(name, "852") == 0) return 852;
    if (lstrcmpi(name, "CP852") == 0) return 852;
    if (lstrcmpi(name, "IBM852") == 0) return 852;
    if (lstrcmpi(name, "CSPCP852") == 0) return 852;

    /* !IsValidCodePage(853) */
    if (lstrcmpi(name, "CP853") == 0) return 853;

    if (lstrcmpi(name, "855") == 0) return 855;
    if (lstrcmpi(name, "CP855") == 0) return 855;
    if (lstrcmpi(name, "IBM855") == 0) return 855;
    if (lstrcmpi(name, "CSIBM855") == 0) return 855;

    if (lstrcmpi(name, "857") == 0) return 857;
    if (lstrcmpi(name, "CP857") == 0) return 857;
    if (lstrcmpi(name, "IBM857") == 0) return 857;
    if (lstrcmpi(name, "CSIBM857") == 0) return 857;

    /* !IsValidCodePage(858) */
    if (lstrcmpi(name, "CP858") == 0) return 858;

    if (lstrcmpi(name, "860") == 0) return 860;
    if (lstrcmpi(name, "CP860") == 0) return 860;
    if (lstrcmpi(name, "IBM860") == 0) return 860;
    if (lstrcmpi(name, "CSIBM860") == 0) return 860;

    if (lstrcmpi(name, "861") == 0) return 861;
    if (lstrcmpi(name, "CP-IS") == 0) return 861;
    if (lstrcmpi(name, "CP861") == 0) return 861;
    if (lstrcmpi(name, "IBM861") == 0) return 861;
    if (lstrcmpi(name, "CSIBM861") == 0) return 861;

    if (lstrcmpi(name, "863") == 0) return 863;
    if (lstrcmpi(name, "CP863") == 0) return 863;
    if (lstrcmpi(name, "IBM863") == 0) return 863;
    if (lstrcmpi(name, "CSIBM863") == 0) return 863;

    if (lstrcmpi(name, "CP864") == 0) return 864;
    if (lstrcmpi(name, "IBM864") == 0) return 864;
    if (lstrcmpi(name, "CSIBM864") == 0) return 864;

    if (lstrcmpi(name, "865") == 0) return 865;
    if (lstrcmpi(name, "CP865") == 0) return 865;
    if (lstrcmpi(name, "IBM865") == 0) return 865;
    if (lstrcmpi(name, "CSIBM865") == 0) return 865;

    if (lstrcmpi(name, "869") == 0) return 869;
    if (lstrcmpi(name, "CP-GR") == 0) return 869;
    if (lstrcmpi(name, "CP869") == 0) return 869;
    if (lstrcmpi(name, "IBM869") == 0) return 869;
    if (lstrcmpi(name, "CSIBM869") == 0) return 869;

    /* !IsValidCodePage(1152) */
    if (lstrcmpi(name, "CP1125") == 0) return 1125;

    return -1;
}

static int
is_kernel_codepage(int codepage)
{
    return ((IsValidCodePage(codepage) || codepage == 1200 || codepage == 1201));
}

static int
cp_mblen(int codepage, const char *str)
{
    CPINFOEX cpinfoex;

    if (codepage == 51932)
        codepage = 20932; /* use 20932 for GetCPInfoEx() */

    if (codepage == 1200)
    {
        /* UTF-16LE */
        int wc = ((str[1] & 0xFF) << 8) | (str[0] & 0xFF);
        if (0xD800 <= wc && wc <= 0xDBFF)
            return 4;
        return 2;
    }
    else if (codepage == 1201)
    {
        /* UTF-16BE */
        int wc = ((str[0] & 0xFF) << 8) | (str[1] & 0xFF);
        if (0xD800 <= wc && wc <= 0xDBFF)
            return 4;
        return 2;
    }
    else if (codepage == 65001)
    {
        /* UTF-8 */
        if ((str[0] & 0xFF) < 0x80) return 1;
        if ((str[0] & 0xE0) == 0xC0) return 2;
        if ((str[0] & 0xF0) == 0xE0) return 3;
        if ((str[0] & 0xF8) == 0xF0) return 4;
        if ((str[0] & 0xFC) == 0xF8) return 5;
        if ((str[0] & 0xFE) == 0xFC) return 6;
    }
    else if (GetCPInfoEx(codepage, 0, &cpinfoex) != 0)
    {
        if (cpinfoex.MaxCharSize == 1)
            return 1;
        else if (cpinfoex.MaxCharSize == 2)
        {
            if (IsDBCSLeadByteEx(codepage, str[0]))
                return 2;
            else
                return 1;
        }
    }

    return -1;
}

static int
utf16_to_wchar(const char *buf, wchar_t *wbuf, int codepage)
{
    wbuf[0] = ((buf[0] & 0xFF) << 8) | (buf[1] & 0xFF);
    if (codepage == 1200)
        wbuf[0] = ((wbuf[0] & 0xFF00) >> 8) | ((wbuf[0] & 0x00FF) << 8);
    if (0xD800 <= wbuf[0] && wbuf[0] <= 0xDBFF)
    {
        wbuf[1] = ((buf[2] & 0xFF) << 8) | (buf[3] & 0xFF);
        if (codepage == 1200)
            wbuf[1] = ((wbuf[1] & 0xFF00) >> 8) | ((wbuf[1] & 0x00FF) << 8);
        if (wbuf[1] < 0xDC00 || 0xDFFF < wbuf[1])
            return 0;
    }
    return 1;
}

static int
wchar_to_utf16(const wchar_t *wbuf, char *buf, int codepage)
{
    if (codepage == 1200)
    {
        buf[0] = (wbuf[0] & 0x00FF);
        buf[1] = (wbuf[0] & 0xFF00) >> 8;
        if (0xD800 <= wbuf[0] && wbuf[0] <= 0xDBFF)
        {
            buf[2] = (wbuf[1] & 0x00FF);
            buf[3] = (wbuf[2] & 0xFF00) >> 8;
        }
    }
    else if (codepage == 1201)
    {
        buf[0] = (wbuf[0] & 0xFF00) >> 8;
        buf[1] = (wbuf[0] & 0x00FF);
        if (0xD800 <= wbuf[0] && wbuf[0] <= 0xDBFF)
        {
            buf[2] = (wbuf[1] & 0xFF00) >> 8;
            buf[3] = (wbuf[2] & 0x00FF);
        }
    }
    return 1;
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

