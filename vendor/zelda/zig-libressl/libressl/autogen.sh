#!/bin/sh
set -e

./update.sh
mkdir -p m4
autoreconf -i -f

# Patch libtool 2.4.2 to pass -fstack-protector as a linker argument
sed 's/-fuse-linker-plugin)/-fuse-linker-plugin|-fstack-protector*)/' \
  ltmain.sh > ltmain.sh.fixed
mv -f ltmain.sh.fixed ltmain.sh

# Update config scripts and fixup permissions
find . ! -perm -u=w -exec chmod u+w {} \;
cp scripts/config.* .
