#!/bin/sh

MIN_VERSION=8.0
ARCH=arm64
SDK=$(ls -1d /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iP* | tail -n1)
echo $SDK

# remove object files to build nice n clean
echo '[+] Removing old object files ...'
find . -name "*.o" -exec rm {} \;

# compile the Objective-C stuff
echo '[+] Compiling Objective-C files ...'
clang -c Vendor/CocoaAsyncSocket/*.m Vendor/CocoaLumberjack/*.m Vendor/CocoaLumberjack/Extensions/*.m Core/*.m Core/Categories/*.m Core/Mime/*.m Core/Responses/*.m Extensions/WebDAV/*.m -arch $ARCH -isysroot $SDK -Wno-arc-bridge-casts-disallowed-in-nonarc -Wno-trigraphs -fobjc-arc -I Vendor/CocoaLumberjack/Extensions -I Vendor/CocoaAsyncSocket -I Extensions/WebDAV -I Core/Responses -I Core -I Core/Mime/ -I Core/Categories -I Vendor/CocoaLumberjack  -I /usr/include/libxml2 -miphoneos-version-min=$MIN_VERSION -ObjC -I "$SDK/usr/include/libxml2"

# See Makefile.* in the parent directory.
echo '[+] Creating CocoaHTTPServer.a archive'
ar -r CocoaHTTPServer.a *.o >/dev/null 2>&1

if [ -d ../../libs ]; then
    echo '[+] Copying CocoaHTTPServer.a into libs/'
    cp CocoaHTTPServer.a ../../libs/
fi

# See Makefile.* in the parent directory.
echo '[+] The CocoaHTTPServer libraries were copied into into libs/ directory. My work is done.'
