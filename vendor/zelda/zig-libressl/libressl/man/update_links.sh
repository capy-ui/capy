#!/bin/sh

# Run this periodically to ensure that the manpage links are up to date
(
    cd /usr/src/usr.bin/mandoc/
    make obj
    make cleandir
    make depend
    make
    cd /usr/src/regress/usr.bin/mandoc/db/mlinks/
    make obj
    make cleandir
    make
)

makewhatis -a .

# We have to filter out some links that fail on case-insensitive filesystems
# Running makewhatis with the right arguments should work on mandoc systems.
echo "# This is an auto-generated file by $0" > links
/usr/src/regress/usr.bin/mandoc/db/mlinks/obj/mlinks mandoc.db | \
    grep -v OCSP_crlID_new | \
    grep -v bn_print | \
    sort >> links
