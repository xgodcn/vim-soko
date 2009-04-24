# for MinGW and MSYS

V8DIR=./v8
V8CFLAGS=-I$(V8DIR)/include -DUSING_V8_SHARED
V8LDFLAGS=-L$(V8DIR) -lv8
CFLAGS=$(V8CFLAGS) -DWIN32 -O
LDFLAGS=$(V8LDFLAGS) -s -shared -L. -lgvim
VIMNAME=gvim.exe

all: if_v8.dll

if_v8.dll: if_v8.cpp vimext.h libgvim.a
	g++ $(CFLAGS) -o $@ if_v8.cpp $(LDFLAGS)

libgvim.a: vim_export.def
	dlltool --input-def $< --dllname $(VIMNAME) --output-lib $@

clean:
	del *.a *.dll



v8:
	svn co http://v8.googlecode.com/svn/trunk v8
	# workaround for build
	cd v8 && patch -p0 < ../v8_mingw.diff

v8lib: v8
	cd v8 && scons mode=release library=shared

vim7:
	svn co https://vim.svn.sourceforge.net/svnroot/vim/vim7

gvim: vim7
	cp vim_export.def vim/src
	cd vim7/src && make -f Make_mvc.mak LFLAGS=vim_export.def GUI=yes IME=yes MBYTE=yes

