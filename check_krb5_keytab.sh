#!/bin/bash

KINIT=/usr/bin/kinit

kdc=$1
keytab=$2
princ=$3
realm=$4

if [ $# -lt 4 ] ; then
	echo "Usage: $0 <kdc> <keytab> <user[@realm]> <realm>"
	exit 3
fi

if [ ! -r $keytab ] ; then
	echo "UNKNOWN: $keytab is unreadable"
	exit 3
fi

conf=`mktemp /tmp/check_krb5_keytab.conf.XXXXX`
cc=`mktemp /tmp/check_krb5_keytab.cc.XXXXX`
time_output=$(mktemp /tmp/$(basename $0)_XXXXX)

cat << EOF > $conf
[libdefaults]
default_realm = $realm
dns_lookup_realm = false
dns_lookup_kdc = false
allow_weak_crypto = true

[realms]
$realm = {
kdc = $kdc
}

EOF

output=$(KRB5CCNAME=$cc KRB5_CONFIG=$conf /usr/bin/time -f '%e' -o $time_output $KINIT -k -t $keytab $princ 2>&1)
code=$?

perfdata="| time=$(cat $time_output)s"

rm -f $time_output
rm -f $cc $conf

if [ $code -ne 0 ] ; then
	echo "CRITICAL: $output $perfdata"
	exit 1
else
	echo "OK: kinit ($princ) in realm ($realm) against kdc ($kdc) SUCCESS $perfdata"
	exit 0
fi


