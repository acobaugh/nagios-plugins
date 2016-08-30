#!/usr/bin/perl

use strict;
use warnings;

use DBI;
use Nagios::Plugin;
use Getopt::Long;

sub usage() {
	print "Usage: $0 -H|--hostname <hostname> -u|--username <username> (-p|--password <password> | -P|--pwdfile </path/to/pwdfile>)\n";
	print "\t[-m|--mode connection-time|query] : Mode to use. Default: connect\n";
	print "\t[-f|--freetdsconf </path/to/freetds.conf>] : FreeTDS config file. Default: /etc/freetds.conf\n";
	print "\t[-Q|--query <SQL query to execute> : When in query mode, specifies the query to run. Default: select 1\n";
	print "\t[-c|--critical <seconds> : Execution time threshold in seconds for critical. Default: 10\n";
	print "\t[-w|--warning <seconds> : Execution time threshold in seconds for warning. Default: 5\n";
}

sub remove_newlines($) {
	my $text = shift;
	$text =~ s/\n//g;
	$text =~ s/\r//g;
	return $text;
}

# defaults and variable declarations
my $hostname = '';
my $freetdsconf = '/etc/freetds.conf';
my $mode = 'connection-time';
my $warning = 5;
my $critical = 10;
my $username = '';
my $password = '';
my $pwdfile = '';
my $query = 'select 1';
my $help = 0;

Getopt::Long::Configure('bundling');
if (! GetOptions(
	"h|help" => \$help,
	"H|hostname=s" => \$hostname,
	"f|freetdsconf=s" => \$freetdsconf,
	"m|mode=s" => \$mode,
	"w|warning=i" => \$warning,
	"c|critical=i" => \$critical,
	"u|username=s" => \$username,
	"p|password=s" => \$password,
	"P|pwdfile=s" => \$pwdfile,
	"Q|query=s" => \$query ) || $help) {
	
	usage();
	exit UNKNOWN;
}

# sanity-check warning/critical time
if ($warning >= $critical) {
	print "UNKNOWN: warning value must be less than critical value.\n";
	exit UNKNOWN;
}

# read in password from file
if (defined $pwdfile and -r $pwdfile) {
	if ( open(PWDFILE, $pwdfile) ) {
		$password = <PWDFILE>;
		$password =~ s/\s+//g;
	} else {
		print "UNKNOWN: Failed to read password from file $pwdfile\n";
		exit UNKNOWN;
	}
}

# check we have hostname/username/password
if (! ($hostname || $username || $password) ) {
	print "UNKNOWN: Missing necessary command-line options.\n";
	usage();
	exit UNKNOWN;
}

# set FREETDSCONF env variable
if (-r $freetdsconf) {
	$ENV{FREETDSCONF} = $freetdsconf;
} else {
	print "UNKNOWN: Could not read freetds config file: $freetdsconf\n";
	exit UNKNOWN;
}

my $starttime = time;
my $delta_t = 0;

my $dbh = DBI->connect("DBI:Sybase:encryptPassword=1:server=$hostname", $username, $password, {PrintError => 0, RaiseError => 0, PrintWarn => 0});
if (!$dbh) {
	$delta_t = time - $starttime;
	printf "CRITICAL: Could not connect: %s. Time = %s | time=%s\n", remove_newlines(DBI::errstr), $delta_t, $delta_t;
	exit CRITICAL;
}

# connection-time
if ($mode eq "connection-time") {
	$dbh->disconnect;
	$delta_t = time - $starttime;
	if ($delta_t lt $warning) {
		printf "OK: Connected. Time = %s | time=%s\n", $delta_t, $delta_t;
		exit OK;
	} elsif ($warning <= $delta_t and $delta_t < $critical) {
		printf "WARNING: Connected. Time = %s | time=%s\n", $delta_t, $delta_t;
		exit WARNING;
	} else {
		printf "CRITICAL: Connected. Time = %s | time=%s\n", $delta_t, $delta_t;
		exit CRITICAL;
	}
}

# query
if ($mode eq "query") {
	my $sth = $dbh->prepare($query);
	if (! $sth->execute) {
		$delta_t = time - $starttime;
		printf "CRITICAL: Could not execute query '%s'. Error: %s. Time = %s | time=%s\n", $query, remove_newlines(DBI::errstr), $delta_t, $delta_t;
		$dbh->disconnect;
		exit CRITICAL;
	} else {
		$sth->finish;
		$dbh->disconnect;	
		$delta_t = time - $starttime;
		if ($delta_t lt $warning) {
			printf "OK: Query executed sucessfully. Time = %s | time=%s\n", $delta_t, $delta_t;
			exit OK;
		} elsif ($warning <= $delta_t and $delta_t < $critical) {
			printf "WARNING: Query executed sucessfully. Time = %s | time=%s\n", $delta_t, $delta_t;
			exit WARNING;
		} else {
			printf "CRITICAL: Query executed sucessfully. Time = %s | time=%s\n", $delta_t, $delta_t;
			exit CRITICAL;
		}
	}
}

# if we got this far, the mode is wrong
print "UNKNOWN: Invalid mode specified: $mode\n";
usage();
exit UNKNOWN;
