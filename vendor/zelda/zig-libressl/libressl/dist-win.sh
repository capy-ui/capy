#!/bin/bash
set -e
#set -x

export PATH=/cygdrive/c/Program\ Files\ \(x86\)/Microsoft\ Visual\ Studio\ 12.0/VC/bin:$PATH
VERSION=`cat VERSION`
DIST=libressl-$VERSION-windows

rm -fr $DIST
mkdir -p $DIST
autoreconf -i

for ARCH in X86 X64; do

	if [ $ARCH = X86 ]; then
		HOST=i686-w64-mingw32
		ARCHDIR=x86
	else
		HOST=x86_64-w64-mingw32
		ARCHDIR=x64
	fi

	echo Building for $HOST

	CC=$HOST-gcc ./configure --host=$HOST --with-openssldir=c:/libressl/ssl
	make clean
	PATH=$PATH:/usr/$HOST/sys-root/mingw/bin \
	   make -j 4 check
	make -j 4 install DESTDIR=`pwd`/stage-$ARCHDIR

	mkdir -p $DIST/$ARCHDIR
	if [ ! -e $DIST/include ]; then
		cp -r stage-$ARCHDIR/usr/local/include $DIST
	fi

	cp stage-$ARCHDIR/usr/local/bin/* $DIST/$ARCHDIR

	for i in libcrypto libssl libtls; do
		DLL=$(basename `ls -1 $DIST/$ARCHDIR/$i*.dll`|cut -d. -f1)
		echo EXPORTS > $DLL.def
		dumpbin /exports $DIST/$ARCHDIR/$DLL.dll | \
		    awk '{print $4}' | awk 'NF' |tail -n +9 >> $DLL.def
		lib /MACHINE:$ARCH /def:$DLL.def /out:$DIST/$ARCHDIR/$DLL.lib
		cv2pdb $DIST/$ARCHDIR/$DLL.dll
	done
done

zip -r $DIST.zip $DIST
