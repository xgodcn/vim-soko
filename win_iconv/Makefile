
CFLAGS=-pedantic -Wall
CFLAGS+=-DUSE_LIBICONV_DLL

all: iconv.dll libiconv.a win_iconv.exe

iconv.dll: win_iconv.c
	gcc $(CFLAGS) -shared -s -o iconv.dll win_iconv.c -DMAKE_DLL -DUSE_LIBICONV_INTERFACE

libiconv.a: win_iconv.c
	gcc $(CFLAGS) -s -c win_iconv.c
	ar rcs libiconv.a win_iconv.o

win_iconv.exe: win_iconv.c
	gcc $(CFLAGS) -s -o win_iconv.exe win_iconv.c -DMAKE_EXE

clean:
	rm win_iconv.exe win_iconv.o iconv.dll libiconv.a

