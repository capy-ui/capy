#!/bin/sh
set -e
TEST=./aeadtest
if [ -e ./aeadtest.exe ]; then
	TEST=./aeadtest.exe
fi
$TEST aead $srcdir/aeadtests.txt
$TEST aes-128-gcm $srcdir/aes_128_gcm_tests.txt
$TEST aes-192-gcm $srcdir/aes_192_gcm_tests.txt
$TEST aes-256-gcm $srcdir/aes_256_gcm_tests.txt
$TEST chacha20-poly1305 $srcdir/chacha20_poly1305_tests.txt
$TEST xchacha20-poly1305 $srcdir/xchacha20_poly1305_tests.txt

