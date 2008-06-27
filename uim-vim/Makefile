
CC=cc
CFLAGS+=-W -Wall -Wno-unused -ansi -pedantic -I/usr/local/include -fPIC
LDFLAGS+=-shared -L/usr/local/lib -luim

all: autoload/uim-vim.so

autoload/uim-vim.so: autoload/uim-vim.c autoload/vp_iobuf.c
	$(CC) -o autoload/uim-vim.so $(CFLAGS) autoload/uim-vim.c $(LDFLAGS)

clean:
	rm autoload/uim-vim.so
