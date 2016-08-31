#!/usr/bin/perl

##
## check_http_cosign.pl
##
# This is a slightly modified version of check_http_cookies.pl. It reads in an
# existing LWP-style cookie jar and attempts to access the URL specified by-u,
# and if it gets redirected to the URI specified by --cosign-redirect-uri, it
# submits the subsequent login form using the username/password provided by -U
# and -p/--pwdfile. The Cosign login form should then redirect us to the page
# we originally requested.

use strict;
use warnings;

use Nagios::Plugin;
use WWW::Mechanize;
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
	'max-redirect' => 7,
	'U' => '',
	'p' => '',
	'cosign-redirect-uri' => ''
);

sub usage() {
    print "Usage: $PROGNAME -H <host> [-V <vhost>] [-P <port>] [-S] [-w <warn>] [-c <crit>] -C <LWP-style cookie file> [-s <string>] [-u <uri>] [-h] [-d] [--capath </path/to/CA>] [--max-redirect <n>] -U <username> {-p <password>|--pwdfile <password file>} --cosign-redirect-uri <uri>\n";
}
	
Getopt::Long::Configure('bundling');
GetOptions( \%o, "h", "w=i", "c=i", "H=s", "V=s", "P=i", "S", 'C=s', 's=s', 'u=s', 'd', 'capath=s', 'max-redirect=i', 'U=s', 'p=s', 'pwdfile=s', 'cosign-redirect-uri=s') or usage();

if ($o{'h'}) {
   usage();
   exit OK;
}

# read password in from file if specified, and put it in $o{'p'}
if (!$o{'p'} and $o{'pwdfile'}) {
	if (-r $o{'pwdfile'}) {
		open(PWDFILE, $o{'pwdfile'});
		$o{'p'} = <PWDFILE>;
		$o{'p'} =~ s/\s+//;
		close PWDFILE;
	} else {
		print "UNKNOWN: could not read pwdfile: " . $o{'pwdfile'} . "\n";
		exit UNKNOWN;
	}
}

# check for required options
if (! ($o{'H'} && $o{'C'}) && $o{'U'} && $o{'p'} && $o{'cosign-redirect-uri'} ) {
	print "Missing required options: -H, -C, -U, -p/--pwdfile, --cosign-redirect-uri\n\n";
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
my $mech = WWW::Mechanize->new(
	max_redirect => $o{'max-redirect'},
	cookie_jar => $cookies
);

if ($o{'S'} and $o{'capath'}) {
	$mech->ssl_opts( SSL_ca_path => $o{'capath'} );
}

if ($o{'d'}) {
	$mech->show_progress(1);
}

# this gets the initial cookies
my $res = $mech->get($uri, 'Host' => $o{'V'});

# did we get redirect to the login page? if so, login and continue
my $gotlogin = 0;
if ($res->request->uri =~ /$o{'cosign-redirect-uri'}/) {
	$gotlogin = 1;
	if ($o{'d'}) {
		printf STDERR "Got login page, will try to login: %s\n", $res->request->uri;
	}
	$res = $mech->submit_form(
		form_number => 1,
		fields => {
			login => $o{'U'},
			password => $o{'p'}
		}
	);
}

# FIXME: this is not an exact measurement in that delta_t includes the time to login if necessary
$delta_t = time() - $starttime;
my $metric = 'time';
if ($gotlogin) {
	$metric = 'login_time';
}
$perfdata = sprintf("(%s = %.2fs) | %s=%.2fs;%d;%d;0;",
	$metric, $delta_t, $metric, $delta_t, $o{'w'}, $o{'c'});

my $whereami = $mech->uri();
# check if we were redirected somewhere else
if ($mech->uri() ne $uri) {
	if ($gotlogin) {
		$whereami = sprintf("%s -login-> %s", $uri, $mech->uri);
	} else {
		$whereami = sprintf("%s -> %s", $uri, $mech->uri);
	}
}
	
my $content = $res->content;
if ($o{'d'}) {
	print STDERR "== DEBUG-content ==\n";
	print STDERR $content;
	print STDERR "== DEBUG-cookies ==\n";
	print $mech->cookie_jar->as_string;
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
