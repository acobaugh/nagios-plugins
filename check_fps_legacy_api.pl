#!/usr/bin/perl

use strict;
use warnings;

use Nagios::Plugin;
use LWP::UserAgent;
use Crypt::SSLeay;
use HTTP::Cookies;
use Getopt::Long;
use Time::HiRes qw( time );
use XML::Simple;
use Data::Dumper;

$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;

my $PROGNAME = $0;

my %o = (
	'H' => '',
	'V' => '',
	'P' => 443,
	'u' => '',
	'p' => '',
	'pwdfile' => '',
	'w' => 5,
	'c' => 10,
	'C' => '/fps-web/api/get_all_data.cgi'
);

sub usage() {
    print "Usage: $PROGNAME -H <host> [-V <vhost>] [-P <port>] -u <username> [-p <password>|--pwdfile <file>] [-w <warn>] [-c <crit>] [-S <string>] [-C /path/to/api] [-h] [-d]\n";
}
	
Getopt::Long::Configure('bundling');
GetOptions( \%o, "h", "w=i", "c=i", "H=s", "V=s", "P=i", "u=s", "p=s", "pwdfile=s", 'C=s', 'd') or usage();

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
if (! ($o{'H'} && $o{'u'} && $o{'p'}) ) {
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

my $leftsquare = '';
my $rightsquare = '';

if ($o{'H'} =~ /:/) {
	$leftsquare = '[';
	$rightsquare = ']';
}
# form the uri
my $uri = 'https://' . $leftsquare . $o{'H'} . $rightsquare . ':' . $o{'P'} . '/' . $o{'C'};

# set up the agent
my $ua = new LWP::UserAgent;

# set up the request
my $req = new HTTP::Request;
$req->method('GET');
$req->uri($uri);
$req->header('Content-Type' => "application/x-www-form-urlencoded");
$req->header('Host' => $o{'V'});

# if that worked, try to log in
$req->method('POST');
$req->content('userid=' . $o{'u'} . '&password=' . $o{'p'});
my $res = $ua->request($req);

$delta_t = time() - $starttime;
$perfdata = "Time = $delta_t | time=${delta_t}s";

my $content = $res->content;
my $code = $res->code;

if ($o{'d'}) {
	print STDERR "== DEBUG ==\n";
	print STDERR $content;
	print STDERR "== DEBUG ==\n";
}

# check that we got something back
if ((length $content) > 0) {
	# cosign redirects us if login was successful, so look for code 302
	if ($code == 200) {
		my $xml;
		eval { $xml = XMLin($content) };
		if ($@) {
			print "CRITICAL: Error parsing XML: $@ $perfdata\n";
		}
		if (exists $xml->{'status'}) {
			if ($xml->{'status'} eq 'SUCCESS') {
				if ( $delta_t <= $o{'w'} ) {
					print "OK: " . $o{'C'} . " login successful. $perfdata\n";
					exit OK;
				}
				if ( $delta_t < $o{'c'} ) {
					print "WARNING: " . $o{'C'} . " login successful. $perfdata\n";
					exit WARNING;
				}
				if ( $delta_t >= $o{'c'} ) {
					print "CRITICAL: " . $o{'C'} . " login successful $perfdata\n";
					exit CRITICAL;
				}
			} else {
				print "CRITICAL: " . $o{'C'} . " status is '" . $xml->{'status'} . "'. ";
				foreach ($xml->{'errorMessages'}) {
					print $_->{'message'} . ' - ';
				}
				print "$perfdata\n";
				exit CRITICAL;
			}
		} else {
			print "CRITICAL: " . $o{'C'} . " status element not found in XML output. $perfdata\n";
			exit CRITICAL;
		}
	} else {
		print "CRITICAL: HTTP Status $code during login for $uri . $perfdata\n";
		exit CRITICAL;
	}
} else {
	print "CRITICAL: No content returned after login for $uri, code = $code. $perfdata\n";
	exit CRITICAL;
}
