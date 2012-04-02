#!/bin/sh

#curl_cmd='/usr/bin/curl'
curl_cmd='/usr/bin/curl'
program="check_http_cosign"

if [ -z "$4" ] ; then
	echo "$program UNKNOWN: Wrong arguments"
	echo "usage: $0 <hostname> <vhost> <path> <cookie file> [<string>]"
	echo
	exit 3
fi

# arguments
host=$1
vhost=$2
path=$3
cookie=$4
string=$5

output=`mktemp /tmp/check_http_cosign_output_XXXXX`

# copy the cosign cookie store to our own file so we can store additional cookies
cookietmp=`mktemp /tmp/check_http_cosign_cookies_XXXXX`
cp $cookie $cookietmp

# try to login
$curl_cmd -L -b $cookietmp -c $cookietmp https://${host}${path} -H "Host: $vhost" --insecure -s -o $output -s 2>/dev/null
if [ "$?" -ne 0 ] ; then
	echo "$program UNKNOWN: Unable to connect to https://${host}${path}"
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
		echo "$program OK: String found"
	fi
else
	echo "$program OK: curl returned 0"
fi

# cleanup
rm -f $output $cookietmp
exit 0

