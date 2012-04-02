#!/bin/bash

fs=$1

count=`/usr/sbin/vos listvol $fs 2>/dev/null | grep -v '^$' | grep -v Total | grep -v On-line | wc -l 2>/dev/null`

if [ $count -ne 0 ]; then
	echo "$fs : $count volume(s) NOT On-line"
	exit 2
else
	echo "$fs : All volumes On-line"
fi
