# Must define one of XP_BEOS, XP_MAC, XP_OS2, XP_WIN or XP_UNIX.
# JS_THREADSAFE should be defined if SpiderMonkey was compiled with it.
# SpiderMonkey library may be named libjs, libmozjs or something.
# TraceMonkey can be used without any change.

CFLAGS=-I$(HOME)/tmp/js/src -I$(HOME)/tmp/js/src/Linux_All_DBG.OBJ -DXP_UNIX -DJS_THREADSAFE
LDFLAGS=-L$(HOME)/tmp/js/src/Linux_All_DBG.OBJ -ljs -lpthread -lm

# for Ubuntu libmozjs-dev package
# XXX: but if_spidermonkey does not work with libmozjs. ???
#CFLAGS=`pkg-config --cflags xulrunner-js`
#LDFLAGS=`pkg-config --libs xulrunner-js`

all: if_spidermonkey.so

if_spidermonkey.so: if_spidermonkey.cpp
	g++ $(CFLAGS) -shared -o $@ if_spidermonkey.cpp $(LDFLAGS)

clean:
	rm if_spidermonkey.so
