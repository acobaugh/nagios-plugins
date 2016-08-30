#!/usr/bin/perl

use warnings;
use strict;

use HTTP::Request::Common;
use LWP::UserAgent;
use JSON;
use Nagios::Plugin;
use Getopt::Long;
use Data::Dumper;

my $PROGNAME = "check_json_arbitrary";

my %o = (
	'H' => '',
	'U' => '/',
	'P' => 443,
	'S' => 0,
	'w' => '',
	'c' => '',
	'p' => '',
	't' => 10,
	'v' => 0
);

sub usage() {
	print "Usage: $PROGNAME -H <host> [-P <port>] [-S] [-U <uri>] -w <warning statement> -c <critical statement> [-p <perf vars>] [-t <timeout>] [-h] [-v]\n";
	print "\t-H <host> : hostname or IP\n";
	print "\t-S : Use SSL \n";
	printf "\t-P <port> : Port (%s)\n", $o{'P'};
	printf "\t-U <uri> : URI path (%s)\n", $o{'U'};
	print "\t-w <statement> : Arbitrary statement to eval. When true, this is a warning.\n";
	print "\t-c <statement> : Arbitrary statement to eval. When true, this is a critical.\n";
	printf "\t-t <timeout> : http request timeout in seconds. (%s)\n", $o{'t'};
	print "\t-p <perfvars> : Comma-separated list of variables to include in perfdata\n";
	print "\t-v : verbose output\n";
	print "\n";
}

Getopt::Long::Configure('bundling');
GetOptions( \%o, "h", "H=s", "S", "P=i", "U=s", "w=s", "c=s", "t=i", "p=s", "v" ) or usage();

if ($o{'h'}) {
   usage();
   exit OK;
}

# check for required options
if (! ($o{'H'} && $o{'w'} && $o{'c'} ) ) {
	print "Missing required options\n\n";
	usage();
	exit UNKNOWN;
}

my $starttime = time();
my $delta_t = -1;

# handle IPv6 addresses
my $leftsquare = '';
my $rightsquare = '';
if ($o{'H'} =~ /:/) {
	$leftsquare = '[';
	$rightsquare = ']';
}

# select the http scheme to use
my $scheme = 'http';
if ($o{'S'}) {
	$scheme = 'https';
}

# form the uri
my $url = $scheme . '://' . $leftsquare . $o{'H'} . $rightsquare . ':' . $o{'P'} . $o{'U'};

## GET URL
my $ua = LWP::UserAgent->new;

$ua->agent('nagios/1.0');
$ua->default_header('Accept' => 'application/json');
$ua->protocols_allowed( [ 'http', 'https'] );
$ua->parse_head(0);
$ua->timeout($o{'t'});

printf "Connecting to $url\n" if ($o{'v'});
my $resp = $ua->get($url);
$delta_t = time() - $starttime;
printf "get() returned %s\n", $resp->status_line if ($o{'v'});
if (! $resp->is_success) {
	printf "UNKNOWN: Connection failed: %s\n", $resp->status_line;
	exit UNKNOWN;
}

## Parse JSON
my $json;
eval {
	$json = decode_json($resp->content);
	1;
} or do {
	printf "UNKNOWN: Error in decode_json(): %s\n", $_;
	exit UNKNOWN;
};

print Dumper($json) if ($o{'v'});

# build perfdata string
# wrap this loop in a block so we can suppress warnings for just this code
my @perfdata_arr = ( );
{
	no warnings;
	foreach my $var (split(',', $o{'p'})) {
		my $value = eval 'no warnings ; $json->' . $var;
		if (defined $value) {
			$var =~ s/\"|{|}//g;
			$var =~ s/->/__/g;
			$var =~ s/\s+//g;
			push @perfdata_arr, $var . '=' . $value;
		}
	}
}
my $perfdata = join(', ', "time=" . $delta_t . "s", @perfdata_arr);

# initialize
my $test_result = 0;
my $test;

# check the critical expression first
$test = '$test_result = 1 if (' . $o{'c'} . ')';
print "Critical test expression: $test\n" if ($o{'v'});;
eval "local \$SIG{__WARN__} = sub { die \$_[0] }; $test";
if ($@) {
	printf "UNKNOWN: eval failed on %s : %s\n", $test, $@;
	exit UNKNOWN;
}
if ($test_result) {
	printf "CRITICAL: %s returned true, %s | %s\n", $o{'c'}, $perfdata, $perfdata;
	exit CRITICAL;
}

$test_result = 0;
# warning expression test
$test = '$test_result = 1 if (' . $o{'w'} . ')';
print "Warning test expression: $test\n" if ($o{'v'});;
eval "local \$SIG{__WARN__} = sub { die \$_[0] }; $test";
if ($@) {
	printf "UNKNOWN: eval failed on %s : %s\n", $test, $@;
	exit UNKNOWN;
}
if ($test_result) {
	printf "WARNING: %s returned true, %s | %s\n", $o{'w'}, $perfdata, $perfdata;
	exit WARNING;
}


printf "OK: All warning and critical conditions are false, %s | %s\n", $perfdata, $perfdata;
exit OK;
