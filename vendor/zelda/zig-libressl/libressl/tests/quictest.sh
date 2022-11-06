#!/bin/sh
set -e

quictest_bin=./quictest
if [ -e ./quictest.exe ]; then
	quictest_bin=./quictest.exe
fi

if [ -z $srcdir ]; then
	srcdir=.
fi

$quictest_bin $srcdir/server.pem $srcdir/server.pem $srcdir/ca.pem
