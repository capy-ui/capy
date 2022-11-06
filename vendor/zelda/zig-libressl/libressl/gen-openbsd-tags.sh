#!/bin/sh
set -e

for tag in `git tag`; do
	branch=master
	if [[ $tag = v2.0* ]]; then
		branch=OPENBSD_5_6
	elif [[ $tag = v2.1* ]]; then
		branch=OPENBSD_5_7
	elif [[ $tag = v2.2* ]]; then
		branch=OPENBSD_5_8
	elif [[ $tag = v2.3* ]]; then
		branch=OPENBSD_5_9
	fi
	# adjust for 9 hour timezone delta between trees
	release_ts=$((`git show -s --format=%ct $tag|tail -n1` + 32400))
	commit=`git -C openbsd rev-list -n 1 --before=$release_ts $branch`
	git -C openbsd tag -f libressl-$tag $commit
	echo Tagged $tag as $commit in openbsd
done
