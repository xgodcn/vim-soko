
V8DIR=./v8

CFLAGS=-I$(V8DIR)/include -W -Wall -Werror -Wno-unused-parameter -fPIC
LDFLAGS=-L$(V8DIR) -lv8 -lpthread

all: if_v8.so

if_v8.so: if_v8.cpp vimext.h
	g++ $(CFLAGS) -shared -o if_v8.so if_v8.cpp $(LDFLAGS)

clean:
	rm if_v8.so



v8:
	svn co http://v8.googlecode.com/svn/trunk v8

v8lib: v8
	cd v8 && scons

