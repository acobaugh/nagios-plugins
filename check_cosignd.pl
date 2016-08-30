#!/usr/bin/perl

use strict;
use warnings;

use Nagios::Plugin;
use IO::Socket::SSL;# qw(debug3);
use Getopt::Long;
use Time::HiRes qw( time );

my ($rsp, $txt, $sep);
my $perfdata = '';
my $cookie = '';

# defaults
my %o = (
        'H' => '',
        'P' => 6663,
        'cookiefile' => '',
	'cookiestring' => '',
	'cookiename' => 'cosign',
	'cookiedomain' => '',
	'cookiepath' => '/',
        'w' => .5,
        'c' => 1,
	't' => 10,
	'm' => 'noop'
);

sub usage() {
	print "Usage: $0 -H <host> [-P <port>] --key <file> --cert <file> --capath <dir> [-m <check|noop>] [-w <warn>] [-c <crit>] [--cookiejar <cookie jar>] [--cookiename <cookie key>] [--cookiestring <string>] [--cookiedomain <domain>] [--cookiepath <path>] [-t <timeout>] [-h]\n";
}

Getopt::Long::Configure('bundling');
GetOptions( \%o, "h", "w=f", "c=f", "H=s", "P=i", "m=s", 't=f', 'cookiejar=s', 'cookiename=s', 'cookiestring=s', 'cookiedomain=s', 'cookiepath=s', 'key=s', 'capath=s', 'cert=s') or usage();

if ($o{'h'}) {
	usage();
	exit OK;
}

# check required arguments
if (!$o{'H'} or !$o{'key'} or !$o{'capath'} or !$o{'cert'}) {
	print "UNKNOWN: Missing required options -H, --key, --capath, or --cert\n";
	usage();
	exit UNKNOWN;
}

# check arg values
if ($o{'m'} !~ /^(noop|check)$/) {
	print "UNKNOWN: -m option expects one of noop, check\n";
	usage();
	exit UNKNOWN;
}

if ($o{'m'} eq 'check') {
	if ($o{'cookiejar'} and -f $o{'cookiejar'} and $o{'cookiedomain'}) {
		use HTTP::Cookies;
		my $cookie_jar = new HTTP::Cookies;
		$cookie_jar->load($o{'cookiejar'});
		if (ref($cookie_jar) and exists $cookie_jar->{COOKIES}{ $o{'cookiedomain'} }{ $o{'cookiepath'} }{ $o{'cookiename'} }) {
			$cookie = $o{'cookiename'} . '=' 
				. $cookie_jar->{COOKIES}{ $o{'cookiedomain'} }{ $o{'cookiepath'} }{ $o{'cookiename'} }[1];
			$cookie =~ s/\/.*//;
		} else {
			printf "UNKNOWN: Could not locate cookie name=%s path=%s domain=%s in cookie jar %s\n",
				$o{'cookiename'}, $o{'cookiepath'}, $o{'cookiedomain'}, $o{'cookiejar'};
			exit UNKNOWN;
		}
	} elsif ($o{'cookiestring'}) {
		$cookie = $o{'cookiestring'};
	} else {
		print "UNKNOWN: Need either --cookiejar, --cookiename, and --cookiedomain, or --cookiestring to be set.\n";
		usage();
		exit UNKNOWN;
	}
}

my $starttime = time();
my $delta_t = -1;

# open the socket
our $sock = new IO::Socket::INET(
	PeerAddr => $o{'H'},
	PeerPort => $o{'P'},
	Proto => 'tcp',
	Timeout => $o{'t'});

if (!$sock) {
	$delta_t = time() - $starttime;
	printf "CRITICAL: Failed to open a socket to %s:%i : %s (%.3fs) | time=%.3fs;%.3f;%.3f;;\n", $o{'H'}, $o{'P'}, $@, $delta_t, $delta_t, $o{'w'}, $o{'c'};
	exit CRITICAL;
} else {
	($rsp, $txt) = response($sock);
	if ($rsp == 220) {
		# initiate STARTTLS
		print $sock "STARTTLS 2\r\n";
		($rsp, $txt) = response($sock);
		if ($rsp == 220) {
			# negotiate SSL/TLS connection
			if ( IO::Socket::SSL->start_SSL($sock, 
				{SSLL_verify_mode => SSL_VERIFY_PEER, 
				SSL_version => 'TLSv1_2',
				SSL_use_cert => 1, # defaults to false unless we are a server
				SSL_cert_file => $o{'cert'},
				SSL_key_file => $o{'key'},
				SSL_ca_path => $o{'capath'}
			}) ) {
				($rsp, $txt) = response($sock);
				if ($rsp == 220) {
					if ($o{'m'} eq 'noop') {
						print $sock "NOOP\r\n";
						($rsp, $txt) = response($sock);
						quit_SSL($sock);
						$delta_t = time() - $starttime;
						my ($statuscode, $statustext) = compare_time($delta_t, $o{'w'}, $o{'c'});
						if ($rsp == 250) {
							printf "%s: NOOP returned: %i %s (%.3fs) | time=%.3fs;%.3f;%.3f;;\n", $statustext, $rsp, $txt, $delta_t, $delta_t, $o{'w'}, $o{'c'};
							exit $statuscode;
						} else {
							printf "CRITICAL: NOOP unknown response: %i %s (%.3fs) | time=%.3fs;%.3f;%.3f;;\n", $rsp, $txt, $delta_t, $delta_t, $o{'w'}, $o{'c'};
							exit CRITICAL;
						}
					} elsif ($o{'m'} eq 'check') {
						print $sock "CHECK $cookie\r\n";	
						($rsp, $txt) = response($sock);
						quit_SSL($sock);
						$delta_t = time() - $starttime;
						if ($rsp == 231 or $rsp == 232 or $rsp == 534 or $rsp == 533 or $rsp == 431 or $rsp == 432) {
							my ($statuscode, $statustext) = compare_time($delta_t, $o{'w'}, $o{'c'});
							printf "%s: CHECK returned: %i %s (%.3fs) | time=%.3fs;%.3f;%.3f;;\n", $statustext, $rsp, $txt, $delta_t, $delta_t, $o{'w'}, $o{'c'};
							exit $statuscode;
						} elsif ($rsp == 430 or $rsp == 431 or $rsp == 531 or $rsp == 532) {
							printf "UNKNOWN: CHECK returned: %i %s (%.3fs) | time=%.3fs;%.3f;%.3f;;\n", $rsp, $txt, $delta_t, $delta_t, $o{'w'}, $o{'c'};
							exit UNKNOWN;
						} else {
							printf "UNKNOWN: CHECK returned unknown code: %i %s (%.3fs) | time=%.3fs;%.3f;%.3f;;\n", $rsp, $txt, $delta_t, $delta_t, $o{'w'}, $o{'c'};
							exit UNKNOWN;
						}
					}
				} else {
					quit_SSL($sock);
					$delta_t = time() - $starttime;
					printf "CRITICAL: After negotiating TLS: \"%.3f %s\" (%.3fs) | time=%.3fs;%.3f;%.3f;;\n", $rsp, $txt, $delta_t, $delta_t, $o{'w'}, $o{'c'};
					exit CRITICAL;
				}
			} else {
				quit($sock);
				$delta_t = time() - $starttime;
				printf "CRITICAL: IO::Socket::start_SSL(): %s (%.3fs) | time=%.3fs;%.3f;%.3f;;\n", $SSL_ERROR, $delta_t, $delta_t, $o{'w'}, $o{'c'};
				exit CRITICAL;
			}
		} else {
			quit($sock);
			$delta_t = time() - $starttime;
			printf "CRITICAL: When issuing STARTTLS command: \"%.3f %s\" (%.3fs) | time=%.3fs;%.3f;%.3f;;\n", $rsp, $txt, $delta_t, $delta_t, $o{'w'}, $o{'c'};
			exit CRITICAL;
		}
	} else {
		quit($sock);
		$delta_t = time() - $starttime;
		printf "CRITICAL: Initial connection: \"%.3f %s\" (%.3fs) | time=%.3fs;%.3f;%.3f;;\n", $rsp, $txt, $delta_t, $delta_t, $o{'w'}, $o{'c'};
		exit CRITICAL;
	}
}

## This is taken from Net::SMTP::TLS
# read a line from the server and parse the
# CODE SEPERATOR TEXT response format
sub response {
	my $sock = shift;
	my $line = $sock->getline();
	my @rsp = ($line =~ /(\d+)(.)([^\r]*)/);
	# reverse things so the seperator is at the end...
	# that way we don't have to get fancy with the return
	# values for calls that don't require the "more indicator"
	return ($rsp[0],$rsp[2],$rsp[1]);
}

sub quit_SSL {
	my $sock = shift;
	print $sock "QUIT\r\n";
	$sock->close(SSL_ctx_free => 1);
	return 0;
}

sub quit {
	my $sock = shift;
	print $sock "QUIT\r\n";
	$sock->shutdown(2);
	return 0;
}

sub compare_time {
	my ($delta_t, $w, $c) = @_;
	if ($delta_t >= $c) {
		return CRITICAL, "CRITICAL";
	} elsif ($delta_t >= $w) {
		return WARNING, "WARNING";
	} else {
		return OK, "OK";
	}
}


##
## TODO
##
# 1) Check expiration date of the cert specified with --cert to warn the operator when our cert is near expiration date
# 2) Perform a REGISTER as well to test full mod_cosign functionality?
# 3) Extend the help() output to be more helpfull
# 4) Add support for reading in a standalone cert, intermmediate, and root, and build a cert bundle in memory
