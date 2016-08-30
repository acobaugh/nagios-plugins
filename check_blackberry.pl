#!/usr/bin/perl

use strict;
use warnings;
use Getopt::Long;
use Nagios::Plugin;
use Net::SNMP qw(ENDOFMIBVIEW);

#
# MIB for org 3530:
# http://www.oidview.com/mibs/3530/BLACKBERRYSERVERMIB-SMIV2.html
#
 
# This is HOST-RESOURCES-MIB::hrSWRunName
my $oid_procs = '.1.3.6.1.2.1.25.4.2.1.2';
my $oid_pending = '.1.3.6.1.4.1.3530.5.2.0';
my @procs = ( 
	'BESAlert.exe',
	'BlackberryRouter.exe',
	'BlackBerryController.exe',
	'BlackBerryDispatcher.exe',
	'BBAttachServer.exe',
	'bmds.exe',
	'BlackBerrySyncServer.exe',
);

# set option defaults
my %o = (
	'H' => '',
	'C' => 'public',
	'w' => '100',
	'c' => '1000',
	'q' => '',
	'p' => '',
	'h' => 0,
	'v' => 0
);

sub usage() {	
	print "Usage: check_blackberry.pl -H <HOSTADDRESS> [-C <community>] -q [pending|processes] [-w <warning>] [-c <critical>] [-p proc1,proc2,...] [-v] [-h|--help]\n";
	print "\t-h : This usage message\n";
	print "\t-w, -c : warning and critical thresholds for pending message count\n";
	print "\t-p : comma-separated list of processes to look for, without spaces\n";
	print "\t-v : print verbose/debug messages to STDERR\n";
}

Getopt::Long::Configure('bundling');
GetOptions(\%o, 
	'h',
	'H=s',
	'C=s',
	'w=i',
	'c=i',
	'q=s',
	'p=s',
	'v'
) or usage() && exit UNKNOWN;

# print help
if ($o{'h'}) {
	usage();
	exit UNKNOWN;
}

# check required options
if (!$o{'H'}) {
	print "UNKNOWN: Missing option -H\n";
	usage();
	exit UNKNOWN;
}
if (!$o{'q'}) {
	print "UNKNOWN: Missing option -q\n";
	usage();
	exit UNKNOWN;
}

# set @procs to value specified with -p
if ($o{'p'}) {
	@procs = split(/,/ , $o{'p'});
}

# create Net::SNMP session
my ($session, $error) = Net::SNMP->session(
	-hostname => $o{'H'},
	-community => $o{'C'},
	-version => 2,
	-timeout => 10,
	-retries => 1
);
if ($error) {
	print "CRITICAL: $error\n";
	exit CRITICAL;
}

# pending
if ($o{'q'} eq "pending") {
	my $result = $session->get_request(-varbindlist => [ $oid_pending ]);
	
	if (!defined $result) {
		printf "CRITICAL: While requesting pending OID, %s\n", $session->error();
		$session->close();
		exit CRITICAL;
	}

	my $pending = $result->{$oid_pending};
	$session->close();

	my $exit_code = UNKNOWN;
	my $exit_msg = 'UNKNOWN';

	if ($pending >= $o{'c'}) {
		print "I am here\n";
		$exit_code = CRITICAL;
		$exit_msg = 'CRITICAL';
	} elsif ($pending >= $o{'w'}) {
		$exit_code = WARNING;
		$exit_msg = 'WARNING';
	} else {
		$exit_code = OK;
		$exit_msg = 'OK';
	}
		
	printf "%s: Pending msgs = %s|pending=%s;%s;%s;%s\n", $exit_msg, $pending, $pending, $o{'w'}, $o{'c'}, 0, 0;
	exit $exit_code;
}

# process list
if ($o{'q'} eq "processes") {
	# hash to store running process names
	my %procs_running = ();
	
	# loop while there is an OID after this one
	my $next_oid = $oid_procs;
	while ( defined $session->get_next_request(-varbindlist => [ $next_oid ]) ) {
		my $oid = ($session->var_bind_names())[0];
		# if we've walked out of our base oid, or hit the end of this view, exit the loop
		if ($oid !~ /^$oid_procs/ or $session->var_bind_types()->{$oid} == ENDOFMIBVIEW) {
			last;
		}	
		# store this processe name
		$procs_running{$session->var_bind_list()->{$oid}} = 1;
		$next_oid = $oid;
	}
	$session->close();
	
	# error checking
	if ($session->error()) {
		printf "CRITICAL: While walking process list, %s\n", $session->error();
		exit CRITICAL;
	}

	# some debugging output to help fine-tune processes to check
	if ($o{'v'}) {
		printf STDERR "Running processes:\n";
		for my $proc (sort keys %procs_running) {
			printf STDERR "\t%s\n", $proc;
		}
	}

	# build array of processes that should be running, but aren't
	my @procs_missing = ();
	for my $proc (@procs) {
		if (!defined $procs_running{$proc}) {
			push @procs_missing, $proc;
		}
	}

	# there are missing processes
	if (scalar(@procs_missing) gt 0) {
		printf "CRITICAL: Proc(s) not running: ";
		for my $proc (@procs_missing) {
			printf "%s ", $proc;
		}	
		printf "\n";
		exit CRITICAL;
	} else {
		printf "OK: Requested proc(s) are running: ";
		for my $proc (@procs) {
			printf "%s ", $proc;
		}	
		printf "\n";
		exit OK;
	}
	
		
		
	
	$session->close();
}

usage();
exit UNKNOWN;
