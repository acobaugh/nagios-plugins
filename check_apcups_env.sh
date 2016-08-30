#!/bin/bash

progname="UPS Env"

oid_temp_probe_1=".1.3.6.1.4.1.318.1.1.10.2.3.2.1.4.1"

host=$1
p=$2
w=$3
c=$4

if [ "$p" = "tprobe1" ]; then
	oid=$oid_temp_probe_1
else
	echo "$progname UNKOWN - env param not specified"
	exit 3
fi

if [ -z "$w" ] || [ -z "$c" ]; then
	echo "$progname UNKOWN - warning and critical values not specified"
	exit 3
fi

if [ -z "$5" ]; then
	community='public'
else
	community=$5
fi

snmp_args="-v1 -t5 -c $community $host"
snmpwalk=/opt/csw/bin/snmpwalk
snmpget=/opt/csw/bin/snmpget

value=$($snmpget -OQ $snmp_args $oid 2>/dev/null | cut -f2 -d '=')

if [ -z "$value" ]; then
	echo "$progname UNKOWN - snmp did not return the output expected"
	exit 3
fi

if [ $value -ge $c ]; then
	echo "$progname CRITICAL - $p = $value"
	exit 2
fi

if [ $value -ge $w ]; then
	echo "$progname WARNING - $p = $value"
	exit 1
fi

echo "$progname OK - $p = $value"
exit 0
