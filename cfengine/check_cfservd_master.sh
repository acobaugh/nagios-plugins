#!/bin/bash

# need this or cfrun complains, and probably can't find ~/.cfagent
#export HOME=/usr/nagios

if [ -z "$1" ]; then
	echo "Usage: $0 HOSTADDRESS"
	exit 3
fi

cfrun="/usr/sbin/cfrun"

tmpfile=`/bin/mktemp /tmp/check_cfservd_master_hosts.XXXXX`

echo $1 > $tmpfile

$cfrun -f $tmpfile -T > $tmpfile.out

output=`grep check_cfservd $tmpfile.out`


if [ "$output" = "check_cfservd" ] ; then
	echo "cfservd appears to be running"
	cat $tmpfile.out
	rm -f $tmpfile $tmpfile.out
	exit 0
else
	echo "cfservd not running or not configured correctly"
	cat $tmpfile.out
	rm -f $tmpfile $tmpfile.out
	exit 2
fi
