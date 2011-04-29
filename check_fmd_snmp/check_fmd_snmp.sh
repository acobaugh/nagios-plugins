#!/bin/bash

if [ -z "$1" ]; then
	echo "Usage: $0 HOSTADDRESS [COMMUNITY]"
	exit 3
fi

if [ -z "$2" ]; then
	community='public'
else
	community=$2
fi

snmp_args="-v2c -t5 -c $community $1"
tmpfile=/var/tmp/check_cmd.tmp
snmpwalk=/opt/csw/bin/snmpwalk
snmpget=/opt/csw/bin/snmpget

resource_count=".1.3.6.1.4.1.42.2.195.1.4.0"
oid_resource_table=".1.3.6.1.4.1.42.2.195.1.5.1.4"
fm_mib=".1.3.6.1.4.1.42.2.195.1.2.1"

event_count=0

rm $tmpfile >/dev/null 2>&1

count=$($snmpget -OQ $snmp_args $resource_count 2>/dev/null | cut -f2- -d '=' | grep -v "No Such Object")
if [ -z "$count" ]; then
	echo "FMD MIB Not Loaded or host not running snmp"
	exit 3
fi

for event in $($snmpwalk -Oq $snmp_args $oid_resource_table 2>/dev/null | cut -f2 -d ' ')
do
	if [ "$event" != "No" ]; then
		let event_count=$event_count+1
		echo UUID: $event >> $tmpfile 
		fault_class=$($snmpget -OQ $snmp_args $fm_mib.4.$event.1 2>/dev/null | cut -f2- -d '=')
		echo Class: $fault_class >> $tmpfile
#		echo Certainty: $($snmpget -OQ $snmp_args $fm_mib.5.$event.1 2>/dev/null | cut -f2- -d '=') >> $tmpfile
#		echo ASRU: $($snmpget -OQ $snmp_args $fm_mib.6.$event.1 2>/dev/null | cut -f2- -d '=') >> $tmpfile
		echo FRU: $($snmpget -OQ $snmp_args $fm_mib.7.$event.1 2>/dev/null | cut -f2- -d '=') >> $tmpfile
#		echo Resource: $($snmpget -OQ $snmp_args $fm_mib.8.$event.1 2>/dev/null | cut -f2- -d '=') >> $tmpfile
#		echo Status: $($snmpget -OQ $snmp_args $fm_mib.9.$event.1 2>/dev/null | cut -f2- -d '=') >> $tmpfile
#		echo Location: $($snmpget -OQ $snmp_args $fm_mib.10.$event.1 2>/dev/null | cut -f2- -d '=') >> $tmpfile
		echo >> $tmpfile
	elif [ "$event" = "No" ]; then
		echo "FMD OK - 0 Fault Events"
		rm $tmpfile >/dev/null 2>&1
		exit 0
	fi
done

if [ "$event" = "" ]; then
	echo "FMD UNKOWN - Could not contact host over snmp"
	rm $tmpfile >/dev/null 2>&1
	exit 3
fi

if [ $event_count -gt 0 ]; then
	if [ $event_count -eq 1 ]; then
		echo "FMD CRITICAL: Fault class $fault_class"
	else
		echo "FMD CRITICAL: Multiple faults"
	fi
	cat $tmpfile
	rm $tmpfile >/dev/null 2>&1
	exit 2
fi

