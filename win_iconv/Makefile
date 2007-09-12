
# comma separated list (e.g. "iconv.dll,libiconv.dll")
DEFAULT_LIBICONV_DLL ?= \"\"

CFLAGS += -pedantic -Wall
CFLAGS += -DUSE_LIBICONV_DLL
CFLAGS += -DDEFAULT_LIBICONV_DLL=$(DEFAULT_LIBICONV_DLL)

all: iconv.dll libiconv.a win_iconv.exe

iconv.dll: win_iconv.c
	gcc $(CFLAGS) -shared -s -o iconv.dll win_iconv.c -DMAKE_DLL -DUSE_LIBICONV_INTERFACE

libiconv.a: win_iconv.c
	gcc $(CFLAGS) -s -c win_iconv.c
	ar rcs libiconv.a win_iconv.o

win_iconv.exe: win_iconv.c
	gcc $(CFLAGS) -s -o win_iconv.exe win_iconv.c -DMAKE_EXE

test:
	gcc $(CFLAGS) -s -o win_iconv_test.exe win_iconv_test.c
	win_iconv_test.exe

clean:
	rm win_iconv.exe win_iconv.o iconv.dll libiconv.a win_iconv_test.exe 2>/dev/null || :

