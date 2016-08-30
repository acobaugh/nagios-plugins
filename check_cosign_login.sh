#!/bin/sh

#curl_cmd='/usr/bin/curl'
curl_cmd='/usr/bin/curl'
program="check_cosign_login"
login_path="/cosign.cgi"

if [ -z "$5" ] ; then
	echo "$program UNKNOWN: Wrong arguments"
	echo "usage: $0 <hostname> <vhost> <username> <string> <password file> [<final cookie file>]"
	echo
	exit 3
fi

# arguments
host=$1
vhost=$2
username=$3
string=$4
pwdfile=$5
cookie=$6

output=`mktemp /tmp/check_cosign_login_output_XXXXX`
cookietmp=`mktemp /tmp/check_cosign_login_cookie_XXXXX`
password=`cat $pwdfile`

# get cookies
$curl_cmd -L -b $cookietmp -c $cookietmp http://${host} -H "Host: $vhost" --insecure -s -o /dev/null 2>/dev/null
if [ "$?" -ne 0 ] ; then
	echo "$program UNKNOWN: Unable to connect to http://${host}"
	rm -f $output $cookietmp
	exit 3
fi

# try to login
$curl_cmd -L -b $cookietmp -c $cookietmp https://${host}${login_path} -H "Host: $vhost" --insecure --data "login=$username&password=$password&required=" -s -o $output 2>/dev/null
if [ "$?" -ne 0 ] ; then
	echo "$program UNKNOWN: Unable to connect to https://${host}${login_path}"
	rm -f $output $cookietmp
	exit 3
fi

# look for $string in output
grep "$string" $output >/dev/null 2>&1
if [ "$?" -ne 0 ] ; then
	echo "$program CRITICAL: String not found"
	rm -f $output $cookietmp
	exit 2
fi

echo "$program OK: String found"
rm -f $output

# optional: save these cookies for use with check_http_cosign
if [ -n "$cookie" ] ; then
	mv $cookietmp $cookie
fi
rm -f $cookietmp

exit 0

