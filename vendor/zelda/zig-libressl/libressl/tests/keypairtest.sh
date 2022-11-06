#!/bin/sh
set -e
TEST=./keypairtest
if [ -e ./keypairtest.exe ]; then
	TEST=./keypairtest.exe
fi

if [ -z $srcdir ]; then
	srcdir=.
fi

$TEST $srcdir/ca.pem $srcdir/server.pem $srcdir/server.pem
