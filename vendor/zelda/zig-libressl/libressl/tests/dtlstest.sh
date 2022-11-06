#!/bin/sh
set -e

dtlstest_bin=./dtlstest
if [ -e ./dtlstest.exe ]; then
	dtlstest_bin=./dtlstest.exe
fi

if [ -z $srcdir ]; then
	srcdir=.
fi

$dtlstest_bin $srcdir/server.pem $srcdir/server.pem $srcdir/ca.pem
