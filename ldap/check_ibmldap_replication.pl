#!/usr/bin/perl

use warnings;
use strict;

use Nagios::Plugin;
use Net::LDAP;
use Getopt::Long;

my $pending_attr = 'ibm-replicationPendingChangeCount';
my $failed_attr = 'ibm-replicationFailedChangeCount';

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

# sanity-check -w and -c
if ($o{'c'} <= $o{'w'}) {
	print "WARNING (-w) must be less than CRITICAL (-c)\n";
	usage();
}

# build search string
my $search = sprintf("cn=%s:636,cn=%s:636,ibm-replicaGroup=%s,%s", $o{'H'}, $o{'m'}, $o{'g'}, $o{'b'});
if ($o{'v'}) {
	printf "DEBUG: search = %s\n", $search;
}

# connect
my $ldap;
if (! ($ldap = Net::LDAP->new($o{'m'})) ) {
	printf "UNKNOWN: Failed to create ldap object for %s: %s\n", $o{'m'}, $@;
	exit UNKNOWN;
}

# bind
my $mesg = $ldap->bind();
if ($mesg->code) {
	printf "UNKNOWN: Failed to bind to %s: %s\n", $o{'m'}, $mesg->error;
	exit UNKNOWN;
}

# search
$mesg = $ldap->search(
	base => $search,
	scope => 'base',
	filter => '(objectClass=ibm-replicationagreement)',
	attrs => [ $pending_attr, $failed_attr ],
	sizelimit => 1
);

# count results
if ($mesg->count ne 1) {
	printf "CRITICAL: LDAP search returned %i entries\n", $mesg->count;
	exit CRITICAL;
}

# get attr values
my @entries = $mesg->entries;
my $pending = $entries[0]->get_value($pending_attr);
my $failed = $entries[0]->get_value($failed_attr);

my $statusline = sprintf("%s = %i, %s = %i", $pending_attr, $pending, $failed_attr, $failed);

# failed changes take precedence
if ($failed > 0) {
	printf "CRITICAL: %s\n", $statusline;
	exit CRITICAL;
}

if ($pending <= $o{'w'}) {
	printf "OK: %s\n", $statusline;
	exit OK;
} elsif ($pending <= $o{'c'}) {
	printf "WARNING: %s\n", $statusline;
	exit WARNING;
} else {
	printf "CRITICAL: %s\n", $statusline;
	exit CRITICAL;
}

