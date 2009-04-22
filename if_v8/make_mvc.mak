# to make v8.lib
#   > nmake -f make_mvc.mak v8lib
# to make gvim.exe with dll extension support
#   > nmake -f make_mvc.mak gvim
# then, make if_v8.dll
#   > nmake -f make_mvc.mak if_v8.dll

V8DIR=.\v8

CFLAGS=/I$(V8DIR)\include /DWIN32
LDFLAGS=/MD $(V8DIR)\v8.lib winmm.lib ws2_32.lib
VIMNAME=gvim.exe

all: if_v8.dll

if_v8.dll: if_v8.cpp vimext.h vim_export.lib
	cl $(CFLAGS) /LD if_v8.cpp $(LDFLAGS) vim_export.lib
	mt -manifest if_v8.dll.manifest -outputresource:if_v8.dll;2

vim_export.lib: vim_export.def
	lib /DEF:vim_export.def /OUT:vim_export.lib /NAME:$(VIMNAME)

clean:
	del *.exp *.lib *.obj *.dll *.manifest



v8:
	svn co http://v8.googlecode.com/svn/trunk v8

v8lib: v8
	cd v8 && scons mode=release msvcrt=shared env="PATH:C:\Program Files\Microsoft Visual Studio 9.0\VC\bin;C:\Program Files\Microsoft Visual Studio 9.0\Common7\IDE;C:\Program Files\Microsoft Visual Studio 9.0\Common7\Tools,INCLUDE:C:\Program Files\Microsoft Visual Studio 9.0\VC\include;C:\Program Files\Microsoft SDKs\Windows\v6.0A\Include,LIB:C:\Program Files\Microsoft Visual Studio 9.0\VC\lib;C:\Program Files\Microsoft SDKs\Windows\v6.0A\Lib"


vim7:
	svn co https://vim.svn.sourceforge.net/svnroot/vim/vim7

gvim: vim7
	copy /y vim_export.def vim7\src
	cd vim7\src && nmake -f Make_mvc.mak linkdebug=/DEF:vim_export.def GUI=yes IME=yes MBYTE=yes

