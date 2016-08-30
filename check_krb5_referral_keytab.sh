#!/bin/bash

KINIT=/usr/bin/kinit
KVNO=/usr/bin/kvno

kdc=$1
keytab=$2
princ=$3
realm=$4
rprinc=$5

if [ $# -lt 5 ] ; then
	echo "Usage: $0 <kdc> <keytab> <user[@realm]> <realm> <referred princ>"
	exit 3
fi

if [ ! -r $keytab ] ; then
	echo "UNKNOWN: $keytab is unreadable"
	exit 3
fi

conf=`mktemp /tmp/check_krb5_keytab_referral.conf.XXXXX`
cc=`mktemp /tmp/check_krb5_keytab_referral.cc.XXXXX`

cat << EOF > $conf
[libdefaults]
default_realm = $realm
dns_lookup_realm = false
dns_lookup_kdc = true 
allow_weak_crypto = true

[realms]
$realm = {
kdc = $kdc
}

EOF

kinitoutput=$(KRB5CCNAME=$cc KRB5_CONFIG=$conf $KINIT -k -t $keytab $princ 2>&1)
code=$?

if [ $code -ne 0 ] ; then
	echo "UNKNOWN: Could not obtain initial krbtgt: $kinitoutput"
	rm -f $cc $conf
	exit 3
else
	kvnooutput=$(KRB5CCNAME=$cc KRB5_CONFIG=$conf $KVNO $rprinc@$realm 2>&1)
	code=$?
	rm -f $cc $conf
	if [ $code -ne 0 ] ; then
		echo "CRITICAL: Could not obtain referral for ($rprinc@$realm) from kdc ($kdc)"
		echo $kvnooutput
		exit 2
	else
		echo "OK: Got referral for ($rprinc@$realm) from kdc ($kdc)"
		echo $kvnooutput
		exit 0
	fi
fi
