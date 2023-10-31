DYLIB_NAME=iSpy.dylib
DYLIB_NAME32=iSpy32.dylib
DYLIB_NAME64=iSpy64.dylib

ISPY_SRC=iSpy.mm iSpy.custom.mm iSpy.class.mm iSpy.instance.mm iSpy.msgSend.watchlist.mm iSpy.msgSend.mm 3rd-party/typestring.mm iSpy.logwriter.mm iSpy.SSLPinning.mm iSpyServer/RPCHandler.mm iSpyServer/iSpyServer.mm iSpyServer/iSpyHTTPServer.mm iSpyServer/iSpyHTTPConnection.mm iSpyServer/iSpyWebSocket.mm iSpyServer/shellWebSocket.mm iSpyServer/iSpyStaticFileResponse.mm iSpyServer/iSpyHTTPServer.mm iSpyServer/iSpyStaticFileResponse.mm iSpy.blacklist.mm iSpy.FloatingButtonWindow.mm iSpy.HoverButton.mm
FISHHOOK_SRC=3rd-party/fishhook/fishhook.c
MINIZIP_SRC=3rd-party/SSZipArchive/minizip/ioapi.c 3rd-party/SSZipArchive/minizip/mztools.c 3rd-party/SSZipArchive/minizip/unzip.c 3rd-party/SSZipArchive/minizip/zip.c
SSZIPARCHIVE_SRC=3rd-party/SSZipArchive/SSZipArchive.m
#WEBROOT_SRC=$(shell ./packWebRootIntoDylib.sh)
WEBROOT_SRC=webroot.c
OBJS=$(addsuffix .o,$(basename $(FISHHOOK_SRC))) \
	$(addsuffix .o,$(basename $(MINIZIP_SRC))) \
	$(addsuffix .o,$(basename $(SSZIPARCHIVE_SRC))) \
	$(addsuffix .o,$(basename $(WEBROOT_SRC))) \
	$(addsuffix .o,$(basename $(ISPY_SRC)))

SDK=iphoneos
SDK_PATH=$(shell xcrun --sdk $(SDK) --show-sdk-path)

CC=$(shell xcrun --sdk $(SDK) --find clang)
CXX=$(shell xcrun --sdk $(SDK) --find clang++)
LD=$(CXX)
#INCLUDES=-I $(SDK_PATH)/usr/include -I 3rd-party/SSZipArchive -I 3rd-party/SSZipArchive/minizip -I /usr/local/Cellar/openssl/1.0.2n/include/
INCLUDES=-I $(SDK_PATH)/usr/include -I 3rd-party/SSZipArchive -I 3rd-party/SSZipArchive/minizip -I /usr/local/opt/openssl/include/
#ARCHS=-arch armv7
ARCHS=-arch arm64

IOS_FLAGS=-isysroot $(SDK_PATH) -miphoneos-version-min=8.0
CFLAGS=$(IOS_FLAGS) -g $(ARCHS) $(INCLUDES) -Wdeprecated-declarations
CXXFLAGS=$(IOS_FLAGS) -g $(ARCHS) $(INCLUDES) -stdlib=libc++ -std=c++11 -Wdeprecated-declarations

FRAMEWORKS=-framework Foundation -framework JavaScriptCore -framework UIKit -framework Security -framework CFNetwork -framework CoreGraphics -F . -F 3rd-party
LIBS=-lobjc -L$(SDK_PATH)/usr/lib $(SDK_PATH)/usr/lib/libc++.tbd libs/CocoaHTTPServer.a -lsqlite3 -lxml2 -lz
LDFLAGS=$(IOS_FLAGS) $(ARCHS) $(FRAMEWORKS) $(LIBS) -shared -current_version 1.0 -compatibility_version 1.0 -all_load -ObjC
MAKE=/usr/bin/make


all: $(DYLIB_NAME)

$(DYLIB_NAME): $(OBJS)
	$(LD) $(LDFLAGS) $^ -o $@

%.o: %.mm $(DEPS)
	$(CXX) -c $(CXXFLAGS) $< -o $@

%.o: %.c $(DEPS)
	$(CC) -c $(CFLAGS) $< -o $@

webroot.o: webroot.c

deb:
	ldid -S $(DYLIB_NAME)
	cp $(DYLIB_NAME) layout/Library/MobileSubstrate/DynamicLibraries/
	cp iSpy.plist layout/Library/MobileSubstrate/DynamicLibraries/
	dpkg-deb -Zgzip -b layout/ iSpy.deb

clean:
	rm -f __x 2>&1 > /dev/null
	#rm -f webroot.* 2>&1 > /dev/null
	rm -f $(OBJS) 2>&1 > /dev/null
	rm -f $(DYLIB_NAME) 2>&1 > /dev/null
	rm -f $(DYLIB_NAME32) 2>&1 > /dev/null
	rm -f $(DYLIB_NAME64) 2>&1 > /dev/null
	
