
CFLAGS=-pedantic -Wall
CFLAGS+=-DUSE_LIBICONV_DLL

TEST_LIBICONV_DLL=libiconv.dll

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
	win_iconv_test.exe $(TEST_LIBICONV_DLL)

clean:
	rm win_iconv.exe win_iconv.o iconv.dll libiconv.a win_iconv_test.exe 2>/dev/null || :

