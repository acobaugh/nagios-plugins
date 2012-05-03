#!/usr/bin/perl

use warnings;
use strict;

use Nagios::Plugin;
use Net::LDAP;
use Getopt::Long;

my $pending_attr = 'ibm-replicationpendingchangecount';

sub usage {
	print "Usage: $0 -H <LDAP SLAVE> -m <LDAP MASTER> -b <BASE> [-g <REPLICATION GROUP>] [-w <WARNING COUNT>] [-c <CRITICAL COUNT>] [-h] [-v]\n";
	print "-h : print this usage message\n";
	print "-v : verbose\n";
	exit UNKNOWN;
}

my %o = (
	'H' => '',
	'm' => '',
	'b' => '',
	'g' => 'default',
	'w' => '10',
	'c' => '100',
	'h' => 0,
	'v' => 0
);

Getopt::Long::Configure("bundling");
GetOptions(\%o, "b=s", "m=s", "H=s", "g=s", "w=i", "c=i", "h", "v");


# print help
if ($o{'h'}) {
	usage();
}

# check for required command line options
if (!$o{'b'} or !$o{'H'} or !$o{'m'}) {
	print "Missing one or more required command line options: -b, -m, -H\n";
	usage();
}

if ($o{'c'} lt $o{'w'} or $o{'c'} eq $o{'w'}) {
	print "WARNING (-w) must be less than CRITICAL (-c)\n";
	usage();
}

my $search = sprintf("cn=%s:636,cn=%s:636,ibm-replicaGroup=%s,%s", $o{'H'}, $o{'m'}, $o{'g'}, $o{'b'});
if ($o{'v'}) {
	printf "DEBUG: search = %s\n", $search;
}

my $ldap;
if (! ($ldap = Net::LDAP->new($o{'m'})) ) {
	printf "UNKNOWN: Failed to create ldap object for %s: %s\n", $o{'m'}, $@;
	exit UNKNOWN;
}

my $mesg = $ldap->bind();
if ($mesg->code) {
	printf "UNKNOWN: Failed to bind to %s: %s\n", $o{'m'}, $mesg->error;
	exit UNKNOWN;
}

$mesg = $ldap->search(
	base => $search,
	scope => 'base',
	filter => '(objectClass=ibm-replicationagreement)',
	attrs => [ $pending_attr ],
	sizelimit => 1
);

if ($mesg->count ne 1) {
	printf "CRITICAL: LDAP search returned %i entries\n", $mesg->count;
	exit CRITICAL;
}

my @entries = $mesg->entries;
my $pending = $entries[0]->get_value($pending_attr);


if ($pending le $o{'w'}) {
	printf "OK: %s = %i\n", $pending_attr, $pending;
	exit OK;
} elsif ($pending le $o{'c'}) {
	printf "WARNING: %s = %i\n", $pending_attr, $pending;
	exit WARNING;
} else {
	printf "CRITICAL: %s = %i\n", $pending_attr, $pending;
	exit CRITICAL;
}

