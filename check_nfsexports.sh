#!/bin/bash
SHOWMOUNT="/usr/sbin/showmount"

# Nagios return codes
STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3
STATE_DEPENDENT=4

if [ ! -x "${SHOWMOUNT}" ]
then
	echo "UNKNOWN: $SHOWMOUNT not found or is not executable by the nagios user"
	exit $STATE_UNKNOWN
fi

print_usage() {
	echo "Usage: `basename $0` -H <hostname> [export list]"
	echo ""
	echo "Notes:"
	echo "-H: Hostname - Can be a hostname or IP address"
	echo ""
	exit $STATE_UNKOWN
}


if [ "$1" = '-h' ] || [ "$1" != "-H" ]; then
	print_usage
else 
	shift
	HOSTNAME=$1
	shift
fi

# Check arguments for validity
if [ -z ${HOSTNAME} ]
then
	echo "You must specify a hostname (or localhost to test the local system)"
	print_usage
	exit $STATE_UNKNOWN
fi

# Run basic showmount and find our status
SHOWMOUNT_OUTPUT=`${SHOWMOUNT} -e ${HOSTNAME} 2>&1 | sed -e s/\*//g`

if [ $? -ne 0 ]
then
	echo Showmount -e failed
	exitstatus=${STATE_CRITICAL}
fi

missing=""
let missing_count=0
let total_count=0
while [ -n "$1" ]; do
	let total_count=$total_count+1
	if [ -z "`echo $SHOWMOUNT_OUTPUT | grep -i $1`" ]; then
		missing="$missing $1"
		let missing_count=$missing_count+1
	fi
	shift
done

if [ $missing_count -ne 0 ]; then
	if [ $missing_count -eq $total_count ]; then
		echo "All $total_count exports missing!"
		exit ${STATE_CRITICAL}
	else
		echo "$missing_count exports missing out of $total_count"
		echo "Missing exports: $missing"
		exit ${STATE_WARNING}
	fi
fi
	
echo $SHOWMOUNT_OUTPUT
exit ${STATE_OK}
