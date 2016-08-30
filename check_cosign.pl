#!/usr/bin/perl

use strict;
use warnings;

use Nagios::Plugin;
use Net::SSLGlue::LWP;
use LWP::UserAgent;
use HTTP::Cookies;
use Getopt::Long;
use Time::HiRes qw( time );

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
	'C' => ''
);

sub usage() {
    print "Usage: $PROGNAME -H <host> [-V <vhost>] [-P <port>] -u <username> [-p <password>|--pwdfile <file>] [-w <warn>] [-c <crit>] [-C <cookie file>] [-S <string>] [-h] [-d]\n";
}
	
Getopt::Long::Configure('bundling');
GetOptions( \%o, "h", "w=i", "c=i", "H=s", "V=s", "P=i", "u=s", "p=s", "pwdfile=s", 'C=s', 'S=s', 'd') or usage();

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
# form the uri
my $uri = 'https://' . $leftsquare . $o{'H'} . $rightsquare . ':' . $o{'P'} . '/';

# set up the agent
my $ua = new LWP::UserAgent;
$ua->agent('Mozilla/5.0');
$ua->cookie_jar( HTTP::Cookies->new(ignore_discard => 1) );

# set up the request
my $req = new HTTP::Request;
$req->method('GET');
$req->uri($uri);
$req->header('Content-Type' => "application/x-www-form-urlencoded");
$req->header('Host' => $o{'V'});

# this gets the initial cookies
my $res = $ua->request($req);

# if that worked, try to log in
if ($res->is_success) {
	$req->method('POST');
   	$req->content('login=' . $o{'u'} . '&password=' . $o{'p'});
   	$res = $ua->request($req);
	
	$delta_t = time() - $starttime;
	$perfdata = sprintf("Time = %.2fs | time=%.2fs;%d;%d;0;", $delta_t, $delta_t, $o{'w'}, $o{'c'});
	
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
		if ($code == 302) {
				# if we're looking for a string	
				my $foundstring = '';
				if ($o{'S'}) {	
					if ($content =~ m/$o{'S'}/) {
						$foundstring = "Found string: '" . $o{'S'} . "'.";
					} else {
						print "CRITICAL: Cosign login successful, did NOT find string '" . $o{'S'} . "' $perfdata\n";
						exit CRITICAL;
					}
				}
				
				# if we want to save these cookies for use elsewhere
				if ($o{'C'}) {
					$ua->cookie_jar->save($o{'C'});
					chmod 0600, $o{'C'}; # just to make sure, the umask above should take care of this already
				}

				# compare $delta_t to critical and warning times
				if ( $delta_t <= $o{'w'} ) {
					print "OK: Cosign login successful. $foundstring $perfdata\n";
					exit OK;
				}
			
				if ( $delta_t < $o{'c'} ) {
					print "WARNING: Cosign login successful. $foundstring $perfdata\n";
					exit WARNING;
				}
			
				if ( $delta_t >= $o{'c'} ) {
					print "CRITICAL: Cosign login successful $foundstring $perfdata\n";
					exit CRITICAL;
				}

		} elsif ($content =~ m/login_error/) {
				print "CRITICAL: Failed to authenticate as $o{'u'}. $perfdata\n";
				exit CRITICAL;
		} else {
			print "CRITICAL: Unexpected HTTP return code during login for $uri, code = $code. $perfdata\n";
			exit CRITICAL;
		}
	} else {
		print "CRITICAL: No content returned after login for $uri, code = $code. $perfdata\n";
		exit CRITICAL;
	}
} else {
    	print "CRITICAL: No response from $uri during initial cookie request\n";
	exit CRITICAL;
}
