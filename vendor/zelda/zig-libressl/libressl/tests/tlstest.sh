#!/bin/sh
set -e

tlstest_bin=./tlstest
if [ -e ./tlstest.exe ]; then
	tlstest_bin=./tlstest.exe
fi

if [ -z $srcdir ]; then
	srcdir=.
fi

$tlstest_bin $srcdir/ca.pem $srcdir/server.pem $srcdir/server.pem
