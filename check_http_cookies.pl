#!/usr/bin/perl

use strict;
use warnings;

use Nagios::Plugin;
use LWP::UserAgent;
use HTTP::Cookies;
use Getopt::Long;
use Time::HiRes qw( time );

my $PROGNAME = $0;

my %o = (
	'H' => '',
	'V' => '',
	'P' => '',
	'S' => 1,
	'u' => '/',
	'w' => 5,
	'c' => 10,
	'C' => '',
	's' => '',
	'd' => 0,
	'capath' => '',
	'max-redirect' => 7
);

sub usage() {
    print "Usage: $PROGNAME -H <host> [-V <vhost>] [-P <port>] [-S] [-w <warn>] [-c <crit>] -C <LWP-style cookie file> [-s <string>] [-u <uri>] [-h] [-d] [--capath </path/to/CA>] [--max-redirect <n>]\n";
}
	
Getopt::Long::Configure('bundling');
GetOptions( \%o, "h", "w=i", "c=i", "H=s", "V=s", "P=i", "S", 'C=s', 's=s', 'u=s', 'd', 'capath=s', 'max-redirect=i') or usage();

if ($o{'h'}) {
   usage();
   exit OK;
}

# check for required options
if (! ($o{'H'} && $o{'C'}) ) {
	print "Missing required options: -H, -C\n\n";
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

# ensure any files created by us are only readable by us
umask 0600;

my $starttime = time();
my $delta_t = -1;
my $perfdata = '';

my $leftsquare = '';
my $rightsquare = '';

if ($o{'H'} =~ /:/) {
	$leftsquare = '[';
	$rightsquare = ']';
}

# form the port number
my $port = '';
if ($o{'P'}) {
	$port = ':' . $o{'P'};
}
	
# form the uri
my $https = '';
if ($o{'S'}) {
	$https = 's';
}
my $uri = sprintf('http%s://%s%s%s%s%s', $https, $leftsquare, $o{'H'}, $rightsquare, $port, $o{'u'});

# load cookies
my $cookies = HTTP::Cookies->new;
$cookies->load($o{'C'});
# set up the agent
my $ua = LWP::UserAgent->new(
	max_redirect => $o{'max-redirect'},
	cookie_jar => $cookies
);

if ($o{'S'} and $o{'capath'}) {
	$ua->ssl_opts( SSL_ca_path => $o{'capath'} );
}

# set up the request
my $req = new HTTP::Request;
$req->method('GET');
$req->uri($uri);
$req->header('Host' => $o{'V'});

if ($o{'d'}) {
	$ua->show_progress(1);
}

# this gets the initial cookies
my $res = $ua->request($req);

$delta_t = time() - $starttime;
$perfdata = sprintf("(Time = %.2fs) | time=%.2fs;%d;%d;0;", $delta_t, $delta_t, $o{'w'}, $o{'c'});

my $whereami = $req->url;
# if we were redirected, previous will be set, and include that in the output
if ($res->previous) {
	$whereami = sprintf("%s -> %s", $req->url, $res->request->uri);
}
	
my $content = $res->content;

if ($o{'d'}) {
	$ua->show_progress(1);
	print STDERR "== DEBUG-content ==\n";
	print STDERR $content;
	print STDERR "== DEBUG-cookies ==\n";
	print $ua->cookie_jar->as_string;
	print STDERR "== /DEBUG ==\n";
}

	
# if that worked, try to log in
if ($res->is_success) {
	# check that we got something back
	if ((length $content) > 0) {
		my $foundstring = '';
		my $statustext = 'UNKNOWN';
		my $statuscode = UNKNOWN;
		if ($o{'s'}) {	
			if ($content =~ m/$o{'s'}/) {
				($statustext, $statuscode) = compare_time();
				$foundstring = sprintf("Found string: '%s' ", $o{'s'});
				$statustext = 'OK';
			} else {
				$statustext = 'CRITICAL';
				$statuscode = CRITICAL;	
				$foundstring = sprintf("did NOT find string '%s' ", $o{'s'});
			}
		} else {
			($statustext, $statuscode) = compare_time();
		}

		printf "%s: %s%s (%s) %s\n", $statustext, $foundstring, $res->status_line, $whereami, $perfdata;
		exit $statuscode;
		
	} else {
		printf "CRITICAL: No content from (%s): %s %s\n", $whereami, $res->status_line, $perfdata;
		exit CRITICAL;
	}
} else {
	printf "CRITICAL: %s (%s) %s\n", $res->status_line, $whereami, $perfdata;
	exit CRITICAL;
}

sub compare_time {
	# compare $delta_t to critical and warning times
	if ( $delta_t < $o{'w'} ) {
		return 'OK', OK
	}
	if ( $delta_t >= $o{'w'} and $delta_t < $o{'c'} ) {
		return 'WARNING', WARNING;	
	}
	if ( $delta_t >= $o{'c'} ) {
		return 'CRITICAL', CRITICAL;	
	}
}
