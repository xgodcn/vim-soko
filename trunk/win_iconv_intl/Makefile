
GNUFTP=http://ftp.gnu.org/pub/gnu
LIBICONV=libiconv-1.13.1
GETTEXT=gettext-0.17

all: libintl.zip

libintl.zip: libintl.dll
	svn export . libintl
	cp libintl.dll libintl/
	cp $(GETTEXT)/gettext-runtime/intl/COPYING.LIB-2.0 libintl/
	cp $(GETTEXT)/gettext-runtime/intl/COPYING.LIB-2.1 libintl/
	zip -r libintl.zip libintl

msvcrt:
	svn checkout http://win-iconv.googlecode.com/svn/trunk/ msvcrt; \
	cd msvcrt; \
	$(MAKE);

$(LIBICONV).tar.gz:
	wget $(GNUFTP)/libiconv/$(LIBICONV).tar.gz

$(GETTEXT).tar.gz:
	wget $(GNUFTP)/gettext/$(GETTEXT).tar.gz

libiconv.dll: $(LIBICONV).tar.gz
	tar xzvf $(LIBICONV).tar.gz; \
	cd $(LIBICONV); \
	./configure --enable-extra-encodings; \
	cp lib/Makefile lib/Makefile.orig; \
	sed "s/-version-info/-avoid-version &/" lib/Makefile.orig > lib/Makefile; \
	$(MAKE); \
	cd ..; \
	cp $(LIBICONV)/lib/.libs/libiconv.dll ./; \
	strip libiconv.dll;

libintl.dll: $(GETTEXT).tar.gz msvcrt
	export C_INCLUDE_PATH=$$PWD/msvcrt LIBRARY_PATH=$$PWD/msvcrt; \
	tar xzvf $(GETTEXT).tar.gz; \
	cd $(GETTEXT)/gettext-runtime; \
	./configure; \
	cd intl; \
	cp Makefile Makefile.orig; \
	sed -e "s/-version-info/-avoid-version &/" -e "s/-liconv/-Wl,&/" Makefile.orig > Makefile; \
	$(MAKE); \
	cd ../../..; \
	cp $(GETTEXT)/gettext-runtime/intl/.libs/libintl.dll ./; \
	strip libintl.dll;

clean:
	rm -rf libintl
	rm -rf libintl.zip
	rm -rf msvcrt
	rm -rf $(LIBICONV) $(LIBICONV).tar.gz libiconv.dll
	rm -rf $(GETTEXT) $(GETTEXT).tar.gz libintl.dll

