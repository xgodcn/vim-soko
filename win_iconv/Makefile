
all: libiconv.dll libiconv.a win_iconv.exe

libiconv.dll: win_iconv.c
	gcc -shared -s -o libiconv.dll win_iconv.c -DMAKE_DLL -DUSE_LIBICONV_INTERFACE

libiconv.a: win_iconv.c
	gcc -s -c win_iconv.c
	ar rcs libiconv.a win_iconv.o

win_iconv.exe: win_iconv.c
	gcc -s -o win_iconv.exe win_iconv.c -DMAKE_EXE

clean:
	rm win_iconv.exe win_iconv.o libiconv.dll libiconv.a
