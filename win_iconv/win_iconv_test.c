
#include "win_iconv.c"
#include <stdio.h>

const char *
tohex(const char *str, int size)
{
    static char buf[BUFSIZ];
    char *pbuf = buf;
    int i;
    buf[0] = 0;
    for (i = 0; i < size; ++i)
        pbuf += sprintf(pbuf, "%02X", str[i] & 0xFF);
    return buf;
}

const char *
errstr(int errcode)
{
    static char buf[BUFSIZ];
    switch (errcode)
    {
    case 0: return "NOERROR";
    case EINVAL: return "EINVAL";
    case EILSEQ: return "EILSEQ";
    case E2BIG: return "E2BIG";
    }
    sprintf(buf, "%d\n", errcode);
    return buf;
}

int
setdll(const char *dllpath)
{
    char buf[BUFSIZ];
    sprintf(buf, "WINICONV_LIBICONV_DLL=%s", dllpath);
    putenv(buf);
    if (dllpath != NULL && dllpath[0] != 0)
    {
        HMODULE h = LoadLibrary(dllpath);
        if (h != NULL)
        {
            FreeLibrary(h);
            return TRUE;
        }
    }
    return FALSE;
}

void
test(const char *from, const char *fromstr, int fromsize, const char *to, const char *tostr, int tosize, int errcode, int bufsize, int line)
{
    char outbuf[BUFSIZ];
    const char *pin;
    char *pout;
    size_t inbytesleft;
    size_t outbytesleft;
    iconv_t cd;
    size_t r;
    const char *dllpath;

    dllpath = getenv("WINICONV_LIBICONV_DLL");
    if (dllpath != NULL && dllpath[0] == 0)
        dllpath = NULL;

    cd = iconv_open(to, from);
    if (cd == (iconv_t)(-1))
    {
        printf("%s -> %s: NG: INVALID ENCODING NAME: line=%d\n", from, to, line);
        exit(1);
    }
    if (dllpath != NULL && ((rec_iconv_t *)cd)->iconv == win_iconv)
    {
        printf("%s: %s -> %s: NG: FAILED TO USE DLL: line=%d\n", dllpath, from, to, line);
        exit(1);
    }

    errno = 0;

    pin = fromstr;
    pout = outbuf;
    inbytesleft = fromsize;
    outbytesleft = bufsize;
    r = iconv(cd, &pin, &inbytesleft, &pout, &outbytesleft);
    if (r != (size_t)(-1))
        r = iconv(cd, NULL, NULL, &pout, &outbytesleft);
    *pout = 0;

    if (dllpath != NULL)
        printf("%s: ", dllpath);
    printf("%s(%s) -> ", from, tohex(fromstr, fromsize));
    printf("%s(%s%s%s): ", to, tohex(tostr, tosize),
            errcode == 0 ? "" : ":",
            errcode == 0 ? "" : errstr(errcode));
    if (strcmp(outbuf, tostr) == 0 && errno == errcode)
        printf("OK\n");
    else
    {
        printf("RESULT(%s:%s): ", tohex(outbuf, sizeof(outbuf) - outbytesleft),
                errstr(errno));
        printf("NG: line=%d\n", line);
        exit(1);
    }
}

#define success(from, fromstr, to, tostr) test(from, fromstr, STATIC_STRLEN(fromstr), to, tostr, STATIC_STRLEN(tostr), 0, BUFSIZ, __LINE__)
#define einval(from, fromstr, to, tostr) test(from, fromstr, STATIC_STRLEN(fromstr), to, tostr, STATIC_STRLEN(tostr), EINVAL, BUFSIZ, __LINE__)
#define eilseq(from, fromstr, to, tostr) test(from, fromstr, STATIC_STRLEN(fromstr), to, tostr, STATIC_STRLEN(tostr), EILSEQ, BUFSIZ, __LINE__)
#define e2big(from, fromstr, to, tostr, bufsize) test(from, fromstr, STATIC_STRLEN(fromstr), to, tostr, STATIC_STRLEN(tostr), E2BIG, bufsize, __LINE__)

int
main(int argc, char **argv)
{
    char *dllpath = argv[1];

    setdll("");

    /* ascii (CP20127) */
    success("ascii", "ABC", "ascii", "ABC");
    success("ascii", "\x80\xFF", "ascii", "\x00\x7F"); /* MSB is dropped.  Hmm... */

    /* unicode (CP1200 CP1201 CP12000 CP12001 CP65001) */
    success("utf-16", "\x01\x02", "utf-16be", "\x01\x02"); /* default is big endian */
    success("utf-16be", "\x01\x02", "utf-16le", "\x02\x01");
    success("utf-16le", "\x02\x01", "utf-16be", "\x01\x02");
    success("utf-16be", "\xFF\xFE", "utf-16le", "\xFE\xFF");
    success("utf-16le", "\xFE\xFF", "utf-16be", "\xFF\xFE");
    success("utf-32be", "\x00\x00\x03\x04", "utf-32le", "\x04\x03\x00\x00");
    success("utf-32le", "\x04\x03\x00\x00", "utf-32be", "\x00\x00\x03\x04");
    success("utf-32be", "\x00\x00\xFF\xFF", "utf-16be", "\xFF\xFF");
    success("utf-16be", "\xFF\xFF", "utf-32be", "\x00\x00\xFF\xFF");
    success("utf-32be", "\x00\x01\x00\x00", "utf-16be", "\xD8\x00\xDC\x00");
    success("utf-16be", "\xD8\x00\xDC\x00", "utf-32be", "\x00\x01\x00\x00");
    success("utf-32be", "\x00\x10\xFF\xFF", "utf-16be", "\xDB\xFF\xDF\xFF");
    success("utf-16be", "\xDB\xFF\xDF\xFF", "utf-32be", "\x00\x10\xFF\xFF");
    eilseq("utf-32be", "\x00\x11\x00\x00", "utf-16be", "");
    eilseq("utf-16be", "\xDB\xFF\xE0\x00", "utf-32be", "");
    success("utf-8", "\xE3\x81\x82", "utf-16be", "\x30\x42");
    einval("utf-8", "\xE3", "utf-16be", "");

    /* Japanese (CP932 CP20932 CP50220 CP50221 CP50222 CP51932) */
    success("utf-16be", "\xFF\x5E", "cp932", "\x81\x60");
    success("utf-16be", "\x30\x1C", "cp932", "\x81\x60");
    success("utf-16be", "\xFF\x5E", "cp932//nocompat", "\x81\x60");
    eilseq("utf-16be", "\x30\x1C", "cp932//nocompat", "");
    success("euc-jp", "\xA4\xA2", "utf-16be", "\x30\x42");
    einval("euc-jp", "\xA4\xA2\xA4", "utf-16be", "\x30\x42");
    eilseq("euc-jp", "\xA4\xA2\xFF\xFF", "utf-16be", "\x30\x42");
    success("cp932", "\x81\x60", "iso-2022-jp", "\x1B\x24\x42\x21\x41\x1B\x28\x42");
    eilseq("cp932", "\x81\x60", "iso-2022-jp//nocompat", "");

    /* test use of dll */
    if (setdll(dllpath))
    {
        success("ascii", "ABC", "ascii", "ABC");
        eilseq("ascii", "\x80\xFF", "ascii", "");
        setdll("");
    }

    /*
     * TODO:
     * Test for state after iconv() failed.
     * Ensure iconv() error is safe and continuable.
     */

    return 0;
}

