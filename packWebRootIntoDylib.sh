#!/bin/bash

ps axw 2>&1|grep "^$PPID.*make clean$" >/dev/null 2>&1
if [ "$?" == "0" ]; then
	echo webroot.c
	exit 0
fi

if [ -r "webroot.c" ]; then
	echo webroot.c
	exit
fi

echo Building webroot ZIP data... >&2

zip -9r - iSpyServer/HTML/* 2>/dev/null | ./packWebRootIntoDylib-finalize.pl

echo webroot.c
exit 0
