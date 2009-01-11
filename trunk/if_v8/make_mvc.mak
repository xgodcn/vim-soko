
V8DIR=..\..\v8

CFLAGS=/I$(V8DIR)\include /DWIN32
LDFLAGS=$(V8DIR)\v8.lib

all: if_v8.dll

if_v8.dll: if_v8.cpp
	cl $(CFLAGS) /LD if_v8.cpp $(LDFLAGS)
	rem mt -manifest if_v8.dll.manifest -outputresource:if_v8.dll;2

clean:
	del *.exp *.lib *.obj *.dll