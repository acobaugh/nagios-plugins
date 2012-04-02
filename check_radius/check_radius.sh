#!/bin/bash

if [ $#ARGV -ne 5 ] ; then
	echo "Usage: $0 <server> <key file> <Calling-Station-ID> <Username> <expected output>"
	exit 3
fi

output=`echo "Calling-Station-Id = $3, User-Name = $4, Service-Type = Call-check" | /usr/bin/radclient -S $2 ${1} auth 2>&1`
exitstatus=$?


if [ $exitstatus -ne 0 ] ; then
	echo "CRITICAL: $output"
	exit 1
fi

expected=`echo $output | grep "$5"`
if [ -z "$expected" ] ; then
	echo "WARNING: Expected output not found: $output"
	exit 2
fi

echo "OK: $output"
exit 0

