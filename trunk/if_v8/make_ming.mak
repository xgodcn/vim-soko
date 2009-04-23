# for MinGW and MSYS

V8DIR=./v8

CFLAGS=-I$(V8DIR)/include -DWIN32
LDFLAGS=-L$(V8DIR) -lv8 -lwinmm -lws2_32
VIMNAME=gvim.exe

all: if_v8.dll

if_v8.dll: if_v8.cpp vimext.h libgvim.a
	g++ $(CFLAGS) -shared -o $@ -O -s if_v8.cpp $(LDFLAGS) -L. -lgvim

libgvim.a: vim_export.def
	dlltool --input-def vim_export.def --dllname $(VIMNAME) --output-lib libgvim.a

clean:
	del *.a *.dll



v8:
	svn co http://v8.googlecode.com/svn/trunk v8
	# workaround for build
	cd v8 && patch -p0 < ../v8_mingw.diff

v8lib: v8
	cd v8 && scons mode=release

vim7:
	svn co https://vim.svn.sourceforge.net/svnroot/vim/vim7

gvim: vim7
	cp vim_export.def vim/src
	cd vim7/src && make -f Make_mvc.mak LFLAGS=vim_export.def GUI=yes IME=yes MBYTE=yes

