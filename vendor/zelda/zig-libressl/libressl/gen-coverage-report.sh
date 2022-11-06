#!/bin/sh

VERSION=$(cat VERSION)
DESTDIR=libressl-coverage-$VERSION

echo "This will generate a code coverage report under $DESTDIR"
echo

if [ "x$(which lcov)" = "x" ]; then
	echo "'lcov' is required but not found!"
	exit 1
fi

if [ "x$(which genhtml)" = "x" ]; then
	echo "'genhtml' is required but not found!"
	exit 1
fi

find -name '*.gcda' -o -name '*.gcno' -delete
rm -fr $DESTDIR

echo "Configuring to build with code coverage support"
./configure CFLAGS='-O0 -fprofile-arcs -ftest-coverage'

echo "Running all code paths"
make clean
make check

echo "Generating report"
mkdir -p $DESTDIR
find tests -name '*.gcda' -o -name '*.gcno' -delete
lcov --capture --output-file $DESTDIR/coverage.tmp \
	--rc lcov_branch_coverage=1 \
	--directory crypto \
	--directory ssl \
	--directory tls \
    --test-name "LibreSSL $VERSION"
genhtml --prefix . --output-directory $DESTDIR \
	--branch-coverage --function-coverage \
	--rc lcov_branch_coverage=1 \
    --title "LibreSSL $VERSION" --legend --show-detail $DESTDIR/coverage.tmp

echo "Code coverage report is available under $DESTDIR"
