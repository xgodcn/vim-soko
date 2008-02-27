
all: plugin/uim-ctl.so plugin/uim-ctl-helper

plugin/uim-ctl.so: plugin/uim-ctl.c
	gcc -shared -o plugin/uim-ctl.so -I/usr/local/include plugin/uim-ctl.c -L/usr/local/lib -luim -lpthread

plugin/uim-ctl-helper: plugin/uim-ctl-helper.c
	gcc -o plugin/uim-ctl-helper -I/usr/local/include plugin/uim-ctl-helper.c -L/usr/local/lib -luim -lpthread

archive:
	mkdir uim-ctl
	mkdir uim-ctl/plugin
	cp Makefile README uim-ctl
	cp plugin/uim-ctl.c plugin/uim-ctl.vim plugin/uim-ctl-helper.c uim-ctl/plugin
	zip -r uim-ctl.zip uim-ctl
	rm -r uim-ctl

clean:
	rm plugin/uim-ctl.so
	rm plugin/uim-ctl-helper

