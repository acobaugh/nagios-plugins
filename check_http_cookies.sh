#!/bin/sh

#curl_cmd='/usr/bin/curl'
curl_cmd='/usr/bin/curl'
program="check_http_cookies"

if [ -z "$3" ] ; then
	echo "$program UNKNOWN: Wrong arguments"
	echo "usage: $0 <hostname> <vhost> <path> [<string>]"
	echo
	exit 3
fi

# arguments
host=$1
vhost=$2
path=$3
string=$4

output=`mktemp /tmp/check_http_cookies_output_XXXXX`

cookietmp=`mktemp /tmp/check_http_cookies_XXXXX`

# try to login
$curl_cmd -L -b $cookietmp -c $cookietmp ${host}${path} -H "Host: $vhost" --insecure -o $output -s 2>/dev/null
if [ "$?" -ne 0 ] ; then
	echo "$program UNKNOWN: Unable to connect to ${host}${path}"
	rm -f $output $cookietmp
	exit 3
fi

# look for $string in output
if [ -n "$string" ] ; then
	grep "$string" $output >/dev/null 2>&1
	if [ "$?" -ne 0 ] ; then
		echo "$program CRITICAL: String not found"
		rm -f $output $cookietmp
		exit 2
	else
		echo "$program OK: String found: $string"
	fi
else
	echo "$program OK: curl returned 0"
fi

# cleanup
rm -f $output $cookietmp
exit 0

