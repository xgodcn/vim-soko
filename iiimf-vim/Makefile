
CC=cc
CFLAGS+=-W -Wall -Wno-unused -ansi -pedantic -I/usr/local/include/iiim -fPIC
LDFLAGS+=-shared -L/usr/local/lib -liiimcf

all: autoload/iiimf-vim.so

autoload/iiimf-vim.so: autoload/iiimf-vim.c autoload/vp_iobuf.c
	$(CC) -o autoload/iiimf-vim.so $(CFLAGS) autoload/iiimf-vim.c $(LDFLAGS)

