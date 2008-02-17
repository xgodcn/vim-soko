
all: plugin/uim-ctl.so

plugin/uim-ctl.so: plugin/uim-ctl.c
	gcc -shared -o plugin/uim-ctl.so plugin/uim-ctl.c -luim

archive:
	mkdir uim-ctl
	mkdir uim-ctl/plugin
	cp Makefile README uim-ctl
	cp plugin/uim-ctl.c plugin/uim-ctl.vim uim-ctl/plugin
	zip -r uim-ctl.zip uim-ctl
	rm -r uim-ctl

clean:
	rm plugin/uim-ctl.so

