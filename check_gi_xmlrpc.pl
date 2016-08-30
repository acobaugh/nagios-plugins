#!/usr/bin/perl

use strict;
use warnings;

use Nagios::Plugin;
use Getopt::Long;
use Time::HiRes qw( time );
use RPC::XML;
use RPC::XML::Client;

my $PROGNAME = $0;

my %o = (
	'H' => '',
	'V' => '',
	'P' => 443,
	'U' => '/rpc2',
	'r' => '',
	'a' => '',
	'u' => '',
	'p' => '',
	'pwdfile' => '',
	'w' => '5',
	'c' => '10'
);

sub usage() {
	print "Usage: $PROGNAME -H <host> [-S] [-P <port>] [-U /uri] -r <RPC> -a <application> -u <username> [-p <password>] [--pwdfile <pwdfile>] [-w <warn>] [-c <crit>] [-h]\n";
	print "\t-H <host> : hostname or IP\n";
	print "\t-S : Use SSL\n";
	printf "\t-P <port> : Port (%s)\n", $o{'P'};
	printf "\t-U <uri> : URI path (%s)\n", $o{'U'};
	printf "\t-r <rpc> : RPC program (%s)\n", $o{'r'};
	printf "\t-a <application> : Application name (%s)\n", $o{'a'};
	printf "\t-u <username> : Username (%s)\n", $o{'u'};
	printf "\t-p <password> : Plaintext password (%s)\n", $o{'p'};
	printf "\t--pwdfile <pwdfile> : Path to password file, takes precedence over -p (%s)\n", $o{'p'};
	printf "\t-w <warn> : Warning time in seconds (%s)\n", $o{'w'};
	printf "\t-c <crit> : Critical time in seconds (%s)\n", $o{'c'};
	print "\n";
}
	
Getopt::Long::Configure('bundling');
GetOptions( \%o, "h", "w=i", "c=i", "H=s", "P=i", "U=s", "r=s", "u=s", "a=s", "p=s", "pwdfile=s", "S" ) or usage();

if ($o{'h'}) {
   usage();
   exit OK;
}

# read password in from file if specified, and put it in $o{'p'}
if (!$o{'p'} and $o{'pwdfile'}) {
	open(PWDFILE, $o{'pwdfile'});
	$o{'p'} = <PWDFILE>;
	$o{'p'} =~ s/\s+//;
	close PWDFILE;
}

# check for required options
if (! ($o{'H'} && $o{'u'} && $o{'p'} && $o{'r'} && $o{'a'}) ) {
	print "Missing required options\n\n";
	usage();
	exit UNKNOWN;
}

# check sanity of -w and -c
if ($o{'c'} <= $o{'w'}) {
	print "-c must be greater than -w\n\n";
	usage();
	exit UNKNOWN;
}

# substitute H for V if V isn't specified
if (!$o{'V'}) {
	$o{'V'} = $o{'H'};
}

my $starttime = time();
my $delta_t = -1;
my $perfdata = '';

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
my $uri = $scheme . '://' . $leftsquare . $o{'H'} . $rightsquare . ':' . $o{'P'} . $o{'U'};

my $client = RPC::XML::Client->new($uri);
# call Rpc with arguments Application, Username, and Password
my $resp = $client->send_request($o{'r'}, ($o{'a'}, $o{'u'}, $o{'p'}));
$delta_t = time() - $starttime;
$perfdata = sprintf("ResponseTime = %.3fs | response_time=%.3fs", $delta_t, $delta_t);

# check for a low level error
if (! ref $resp) {
	printf "UNKNOWN: %s (uri=%s) %s\n", $resp, $uri, $perfdata;
	exit UNKNOWN;
}

# check for fault
if ($resp->is_fault) {
	printf "CRITICAL: XMLRPC fault: %s->%s (uri=%s) %s\n", $resp->code, $resp->string, $uri, $perfdata;
	exit CRITICAL;
}

# otherwise, we should have gotten back some data
my $status = sprintf("%s returned %s (uri=%s)", $o{'r'}, $resp->value, $uri);

if ( $delta_t <= $o{'w'} ) {
	printf "OK: %s %s\n", $status, $perfdata;
	exit OK;
}
if ( $delta_t < $o{'c'} ) {
	print "WARNING: %s %s\n", $status, $perfdata;
	exit WARNING;
}
if ( $delta_t >= $o{'c'} ) {
	print "CRITICAL: %s %s\n", $status, $perfdata;
	exit CRITICAL;
}
