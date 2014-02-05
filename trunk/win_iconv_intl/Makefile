
GNUFTP=http://ftp.gnu.org/pub/gnu
LIBICONV=libiconv-1.14
GETTEXT=gettext-0.18.3.1
SPECSFILE=specs100

all: libintl.zip

libintl.zip: libintl.dll
	svn export . libintl
	cp libintl.dll libintl/
	cp $(GETTEXT)/gettext-runtime/intl/COPYING.LIB libintl/
	zip -r libintl.zip libintl

msvcrt: $(SPECSFILE)
	SPECS=$$PWD/$(SPECSFILE); \
	export CFLAGS="-specs=$$SPECS"; \
	svn checkout http://win-iconv.googlecode.com/svn/trunk/ msvcrt; \
	cd msvcrt; \
	$(MAKE) "SPECS_FLAGS=-specs=$$SPECS"; \
	mkdir include; \
	cp iconv.h include; \
	mkdir lib; \
	cp libiconv.a lib;

$(LIBICONV).tar.gz:
	wget $(GNUFTP)/libiconv/$(LIBICONV).tar.gz

$(GETTEXT).tar.gz:
	wget $(GNUFTP)/gettext/$(GETTEXT).tar.gz

libiconv.dll: $(LIBICONV).tar.gz $(SPECSFILE)
	SPECS=$$PWD/$(SPECSFILE); \
	export CFLAGS="-specs=$$SPECS"; \
	tar xzvf $(LIBICONV).tar.gz; \
	cd $(LIBICONV); \
	./configure --enable-extra-encodings; \
	cp lib/Makefile lib/Makefile.orig; \
	sed "s@-version-info@-Xcompiler \"-specs=$$SPECS\" -avoid-version &@" lib/Makefile.orig > lib/Makefile; \
	$(MAKE); \
	cd ..; \
	cp $(LIBICONV)/lib/.libs/libiconv.dll ./; \
	strip libiconv.dll;

# When building gettext whole, -O2 is needed to enable inline function.
# When building libintl only, it is not needed.
# Add -static-libgcc flag to prevent libgcc_s_dw2-1.dll dependency.

libintl.dll: $(GETTEXT).tar.gz msvcrt $(SPECSFILE)
	ICONVDIR=$$PWD/msvcrt; \
	SPECS=$$PWD/$(SPECSFILE); \
	export CFLAGS="-specs=$$SPECS -O2"; \
	tar xzvf $(GETTEXT).tar.gz; \
	cd $(GETTEXT)/gettext-runtime; \
	./configure --enable-threads=win32 --with-libiconv-prefix=$$ICONVDIR; \
	cp libtool libtool.orig; \
	sed -e "s@^CC=\"gcc\"@CC=\"gcc -static-libgcc\"@" libtool.orig > libtool; \
	cd intl; \
	cp Makefile Makefile.orig; \
	sed -e "s@-version-info@-Xcompiler \"-specs=$$SPECS\" -avoid-version &@" Makefile.orig > Makefile; \
	$(MAKE); \
	cd ../../..; \
	cp $(GETTEXT)/gettext-runtime/intl/.libs/libintl.dll ./; \
	strip libintl.dll;

specs:
	gcc -dumpspecs > $@

# http://www.mingw.org/wiki/SpecsFileHOWTO

specs100:
	gcc -dumpspecs | sed \
	  -e '/^*cpp:/{n;s/^/%(msvcrt_version) /}' \
	  -e 's/-lmsvcrt/-l%(msvcrt)/g' \
	  -e 's/-lmoldname/-l%(moldname)/g' \
	  > $@
	echo "*msvcrt:" >> $@
	echo "msvcr100" >> $@
	echo "" >> $@
	echo "*msvcrt_version:" >> $@
	echo "-D__MSVCRT_VERSION__=0x1000 -include `pwd -W`/stat100.h" >> $@
	echo "" >> $@
	echo "*moldname:" >> $@
	echo "moldname100" >> $@
	echo "" >> $@

clean:
	rm -rf libintl
	rm -rf libintl.zip
	rm -rf msvcrt
	rm -rf $(LIBICONV) $(LIBICONV).tar.gz libiconv.dll
	rm -rf $(GETTEXT) $(GETTEXT).tar.gz libintl.dll
	rm -rf specs specs100

