#!/usr/bin/perl -w
# This is based on check_ssl_certificate written by David Alden <alden@math.ohio-state.edu>

use strict;
use warnings;
use Time::Local;
use Getopt::Long;
use Nagios::Plugin;

$ENV{PATH}="/usr/sbin:/usr/bin:/bin";

my $openssl = "/usr/bin/openssl";

my $help;
my $host;
my $port = 443;
my $critical = 7;
my $warning = 30;
my $additional = '';
my $timeout = 10;

#
my %months = ('Jan' => 0, 'Feb' => 1, 'Mar' => 2, 'Apr' => 3, 'May' => 4,
	      'Jun' => 5, 'Jul' => 6, 'Aug' => 7, 'Sep' => 8, 'Oct' => 9,
	      'Nov' => 10, 'Dec' => 11);

#
Getopt::Long::Configure('bundling');
if (GetOptions(
	"a=s" => \$additional,
	"c:s" => \$critical,
	"h"   => \$help,
	"H:s" => \$host,
	"o=s" => \$openssl,
	"p=i" => \$port,
	"w:s" => \$warning,
	"t:i" => \$timeout
	) == 0) {

  print_usage();
  exit UNKNOWN;
}

if ( $help || ! ($host && $port) ) {
  print_usage();
  exit OK;
}

if (! -x $openssl) {
	printf "UNKNOWN: $openssl doesn't exist or isn't executable\n";
	exit UNKNOWN;
}

if (!open(OPENSSL, "timeout $timeout $openssl s_client -connect $host:$port $additional < /dev/null 2>&1 | $openssl x509 -enddate -subject -noout 2>&1|")) {
	printf "UNKNOWN: unable to open $openssl: $!";
	exit UNKNOWN;
}

my ($date, $cn) = '';
while (<OPENSSL>) {
	if ($_ =~ /unable to load certificate/) {
		print "UNKNOWN: unable to load certificate for [$host]:$port\n";
		exit UNKNOWN;
	}
	if ($_ =~ /^notAfter=(.*)/) {
		$date = $1;
		chomp($date);
	}
	if ($_ =~ /CN=(.*)/) {
		$cn = $1;
		chomp($cn);
	} 	
}
close(OPENSSL);

# save this string for later
my $datestring = $date;

# split $date into individual components
$date =~ s/ +/ /g;
my ($month, $day, $hour, $min, $sec, $year, $tz) = split(/[\s+|:]/, $date);

# calculate days left
my $daysLeft = int((timegm($sec, $min, $hour, $day, $months{$month}, $year - 1900) - time()) / 86400);

if ($daysLeft < 0) {
	print "CRITICAL - CN:$cn [$host]:$port expired " . abs($daysLeft) . " day(s) ago. Expires at $datestring\n";
} elsif ($daysLeft <= $critical) {
	print "CRITICAL - only $daysLeft day(s) left for CN:$cn [$host]:$port. Expires at $datestring\n";
	exit CRITICAL;
} elsif ($daysLeft <= $warning) {
	print "WARNING - only $daysLeft day(s) left for CN:$cn [$host]:$port. Expires at $datestring\n";
	exit WARNING;
} else {
	print "OK: $daysLeft day(s) left for CN:$cn [$host]:$port. Expires at $datestring\n";
}

sub print_usage {
	print "Usage: $0 -H <host> [-p <port>] [-c <low>:<high>] [-w <low>:<high>] [-t <timeout>]\n";
	print "
-a <add>   add the text to the openssl line, used for checking the smtp ssl
           certificate with starttls (\"-a '-starttls smtp'\")
-c <num>   exit with CRITICAL status if number of days left is less than <num>
-h         show this help script
-H <host>  check the certificate on the indicated host
-o <path>  path to openssl binary
-p <port>  check the certificate on the specified port
-t <num>   timeout for the openssl command
-w <num>   exit with WARNING status if number of days left is less than <num>
";

}
