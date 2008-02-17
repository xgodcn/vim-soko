
CXX=g++
CFLAGS+=-W -Wall -Wno-unused -ansi -pedantic -I/usr/local/include/scim-1.0 -fPIC
CFLAGS+=-D__STDC_ISO_10646__
LDFLAGS+=-shared -L/usr/local/lib -lscim-1.0

all: autoload/scim-vim.so

autoload/scim-vim.so: autoload/scim-vim.cpp autoload/vp_iobuf.c
	$(CXX) -o autoload/scim-vim.so $(CFLAGS) autoload/scim-vim.cpp $(LDFLAGS)

