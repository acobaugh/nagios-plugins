#!/usr/bin/perl

use strict;
use warnings;

use Getopt::Long qw(:config bundling);
use File::Temp;

my $PYNFS='/usr/local/nagios/etc/checks.d/pynfs/nfs4.0/testserver.py';
my $KINIT='/usr/kerberos/bin/kinit';

my $DEFAULT_TESTS = 'access';

my %STATUSCODE = (
	'OK' => 0,
	'WARNING' => 1,
	'CRITICAL' => 2,
	'UNKNOWN' => 3
);

GetOptions(
	"H|host=s" => \(my $host),
	"p|path=s" => \(my $path),
	"u|user=s" => \(my $user),
	"h|help" => \(my $help),
	"k|keytab=s" => \(my $keytab),
	"t|tests=s" => \(my $tests),
	"i|ignore=s" => \(my @_ignore)
);

if ($help) {
	usage();
	exit 1;
}

# check for required options
if (! (
	(defined $host) 
	and (defined $path) 
	and (defined $user) 
	and (defined $keytab)
)) {
	print STDERR "Missing command line option(s)\n";
	usage();
	exit $STATUSCODE{'UNKNOWN'};
}

# %ignore hash for fast lookup
my %ignore;
foreach (@_ignore) {
	$ignore{$_} = 1;
}

# krb5 credential cache
my $cc = File::Temp->new();


# Get keytab in $cc
if (system("KRB5CCNAME=$cc $KINIT -k -t $keytab $user 2>/dev/null") ne 0) {
	print "UNKNOWN - kinit failed\n";
	exit $STATUSCODE{'UNKNOWN'};
}

my %tests_pass = ();
my %tests_fail = ();
my $command_results = "";
my @command_output;

# build string of tests based on passed options, or fall
# back to $DEFAULT_TESTS

if (defined $tests) {
	$tests =~ s/,/ /g;
} else {
	$tests = $DEFAULT_TESTS;
}

# testserver.py writes stuff to a temporary file
my $outfile = File::Temp->new();

# define command to run	
my $command = "KRB5CCNAME=$cc $PYNFS --security=krb5i $host:$path --outfile=$outfile --maketree $tests";


# run command
if (!open(OUTPUT, "$command 2>&1|")) {
	print "UNKNOWN - pynfs script failed to execute\n";
	print "Command was $command\n";
	exit $STATUSCODE{'UNKNOWN'};
} else {
	while (<OUTPUT>) {
		# store all command output for later use
		push @command_output, $_;

		# skip things we don't care about
		next if /^Starting Call Back.*/;
		next if /^\*+/;

		# make output easier to parse by removing excess whitespace
		s/\s+/ /g;

		# store testserver.py result lines for later use
		if ( $_ =~ /^Command line|^Of those/ ) {
			$command_results = "$command_results$_ ";
		}

		# This is a test result
		if ( $_ =~ /(.+)\s\S+\s:\s(PASS|WARNING|FAILURE)/ ) {
			# skip if we want to ignore this test
			next if defined $ignore{$1}; 

			# store PASS or FAILURE results in separate hashes
			if ($2 eq "PASS") {
				$tests_pass{$1} = $2;
			} elsif ($2 eq "FAILURE") {
				$tests_fail{$1} = $2;
			}
		}
	}
}

my $num_fail = scalar keys %tests_fail;
my $num_pass = scalar keys %tests_pass;

# We didn't see any test results, return UNKNOWN
if ($num_fail == 0 && $num_pass == 0) {
	print "UNKNOWN: No test results\n";
	print "Command was: $command\n";
	foreach (@command_output) {
		print "$_";
	}
	exit $STATUSCODE{'UNKNOWN'};
}

# No FAILURE
if ($num_fail == 0) {
	print "OK: ";
	# print tests that passed
	print "P($num_pass): ";
	foreach my $test (sort keys %tests_pass) {
		print "$test ";
	}
	print "\n$command_results\n";
	exit $STATUSCODE{'OK'};
} 

# no PASS. Assume this is a critical condition
if ($num_fail > 0 or $num_pass == 0) {
	print "CRITICAL: ";
	print "P($num_pass), F($num_fail): ";
	foreach my $test (sort keys %tests_fail) {
		print "$test ";
	}
	print "\n$command_results\n";
	exit $STATUSCODE{'CRITICAL'};
}

print "command = $command\n";
sub usage {
	print STDERR "Usage: $0 -H|--hostname <ipaddr|hostname> -u|--user <username> -p|--path <test path> -k|--keytab <keytab> [-t|--tests <list of tests>]\n";
}
