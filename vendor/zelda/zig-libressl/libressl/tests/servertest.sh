#!/bin/sh
set -e

servertest_bin=./servertest
if [ -e ./servertest.exe ]; then
	servertest_bin=./servertest.exe
fi

if [ -z $srcdir ]; then
	srcdir=.
fi

$servertest_bin $srcdir/server.pem $srcdir/server.pem $srcdir/ca.pem
