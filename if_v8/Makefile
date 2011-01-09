V8DIR=./v8
V8CFLAGS=-I$(V8DIR)/include
V8LDFLAGS=-L$(V8DIR) -lv8 -lpthread
CFLAGS=$(V8CFLAGS) -W -Wall -Werror -Wno-unused-parameter -fPIC
LDFLAGS=$(V8LDFLAGS) -shared

# To build static libv8.so for if_v8.so. (ubuntu 10.10 64bit)
# $ cd v8 && CCFLAGS=-fPIC scons arch=x64 mode=release

all: if_v8.so

if_v8.so: if_v8.cpp vimext.h
	g++ $(CFLAGS) -o $@ if_v8.cpp $(LDFLAGS)

clean:
	rm if_v8.so

build-v8:
	test -d v8 || svn co http://v8.googlecode.com/svn/trunk v8
	cd v8 && scons mode=release

build-vim:
	test -d vim || hg clone https://vim.googlecode.com/hg/ vim
	cd vim && LDFLAGS=-rdynamic ./configure && make

