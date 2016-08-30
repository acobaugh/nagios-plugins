#!/usr/bin/perl

#
# Inspiration for this was taken from:
#     http://en.community.dell.com/techcenter/b/techcenter/archive/2014/01/15/dell-integration-with-nagios-core-and-nagios-xi
#

use strict;
use warnings;

use Nagios::Plugin qw(OK UNKNOWN CRITICAL WARNING %STATUS_TEXT);
use Getopt::Long;
use Net::SNMP;

# Taken from iDRAC MIB
my $globalSystemStatusOID = "1.3.6.1.4.1.674.10892.5.2.1.0";
my $systemLCDStatusOID = "1.3.6.1.4.1.674.10892.5.2.2.0";
my $globalStorageStatusOID = "1.3.6.1.4.1.674.10892.5.2.3.0";
my $systemPowerStateOID = "1.3.6.1.4.1.674.10892.5.2.4.0";
my $systemServiceTagOID = "1.3.6.1.4.1.674.10892.5.1.3.2.0";
my $systemModelNameOID = "1.3.6.1.4.1.674.10892.5.1.3.12.0";
my %StatusToString = (
	1 => "Other",
	2 => "Unknown",
	3 => "Ok",
	4 => "Non-critical",
	5 => "Critical",
	6 => "NonRecoverable",
	'noSuchObject' => "noSuchObject",
	'noSuchInstance' => 'noSuchInstance',
	'unknown' => "unknown"
);

# business logic. translate Status to nagios status code
my %StatusToNagios = (
	1 => UNKNOWN,
	2 => UNKNOWN,
	3 => OK,
	4 => WARNING,
	5 => CRITICAL,
	6 => CRITICAL,
	'noSuchObject' => UNKNOWN,
	'noSuchInstance' => UNKNOWN,
	'unknown' => UNKNOWN
);

sub usage() {
	print "Usage: $0 -H|--hostname <hostname> (-c|--community <communityString> | -C|--communityfile </path/to/community/file>) [-t|--timeout n] [-r|--retries n]\n";
}

# get options
my ($help, $hostname, $community, $communityfile);
my $timeout = 5;
my $retries = 2;
Getopt::Long::Configure('bundling');
if (! GetOptions(
	"h|help" => \$help,
	"H|hostname=s" => \$hostname,
	"c|community=s" => \$community,
	"C|communityfile=s" => \$communityfile,
	"t|timeout=i" => \$timeout,
	"r|retries=i" => \$retries)
	) {	
	usage();
	exit UNKNOWN;
}

# read in community string from file, if requested
if (defined $communityfile) {
	if ( open(FILE, $communityfile) ) {
		$community = <FILE>;
		$community =~ s/\s+//g;
		close(FILE);
	} else {
		print "UNKNOWN: Failed to open() community string from file: $communityfile\n";
	}
}

# check for required options
if (! defined $hostname or ! defined $community ) {
	print "UNKNOWN: Missing required command-line options.\n";
	usage();
	exit UNKNOWN;
}

# establish session
my ($session, $error) = Net::SNMP->session(Hostname => $hostname, Community => $community, Version => "snmpv2c", Timeout => $timeout, Retries => $retries);
if (!defined $session) {
	printf "UNKNOWN: Could not create SNMP session with %s. Error: %s\n", $hostname, $error;
	exit UNKNOWN;
}

# get value for a given OID, or exit UNKNOWN on error
sub get_oid_value($) {
	my ($oid) = @_;
	my $response = $session->get_request($oid);
	if (!$response) {
		printf STDERR "Error requesting OID %s: %s\n", $oid, $session->error();
		return "unknown";
	} else {
		return $response->{$oid};
	}
}

my $serviceTag = get_oid_value($systemServiceTagOID);
my $modelName = get_oid_value($systemModelNameOID);
my $globalSystemStatus = get_oid_value($globalSystemStatusOID);	
my $systemLCDStatus = get_oid_value($systemLCDStatusOID);	
my $globalStorageStatus = get_oid_value($globalStorageStatusOID);

printf "%s: globalSystemStatus=%s. systemLCDStatus=%s, globalStorageStatus=%s. S/T: %s, Model: %s\n", 
	$STATUS_TEXT{$StatusToNagios{$globalSystemStatus}}, 
	$StatusToString{$globalSystemStatus}, 
	$StatusToString{$systemLCDStatus}, 
	$StatusToString{$globalStorageStatus},
	$serviceTag,
	$modelName;

exit $StatusToNagios{$globalSystemStatus};
