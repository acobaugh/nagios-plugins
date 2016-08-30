#!/usr/bin/perl 

use strict;
use warnings;

use POSIX;
use Getopt::Long;
use File::Temp;
use Nagios::Plugin;

my $SMBCLIENT = "/usr/bin/smbclient" ;
my $KINIT='/usr/bin/kinit';

my %o = (
	'H' => '',
	'P' => '', 
	'h' => 0, 
	'k' => '/etc/krb5.keytab',
	'u' => 'nagios',
	's' => '',
	't' => 30,
	'D' => 0
);

Getopt::Long::Configure('bundling');
GetOptions(\%o,
	"H=s",
	"P=s",
	"h",
	"k=s",
	"u=s",
	"s=s",
	"D"
);

sub usage {
	print "Usage: $0 -H <host> -s <share> -u <user> -k <keytab_file> -w <warn> -c <crit> [-W <workgroup>] [-P <port>] [-h]\n";
}

# print help
if ($o{'h'}) {
	usage();
}

# Options checking
if (! ($o{'H'} and $o{'u'} and $o{'s'} and $o{'k'}) ) {
	print "UNKNOWN: Missing required command line options: -H, -u, -s, -k\n";
	exit UNKNOWN;
}

# krb5 credential cache
my $cc = File::Temp->new();


# Get keytab
if ( -r $o{'k'}) {
	if (system("KRB5CCNAME=$cc $KINIT -k -t $o{'k'} $o{'u'} 2>/dev/null") ne 0) {
		print "UNKNOWN - kinit failed\n";
		exit UNKNOWN;
	}
} else {
	printf "UNKNOWN - Unable to read %s\n", $o{'k'};
	exit UNKNOWN;
}

# Just in case of problems, let's not hang Nagios
$SIG{'ALRM'} = sub { 
	printf "No Answer from Client after %i seconds\n", $o{'t'};
	# Clear up the credentials
	exit UNKNOWN;
};

# build smbclient command string
my $cmd = sprintf("KRB5CCNAME=%s %s \/\/%s\/%s -k -c 'cd %s' 2>&1", $cc, $SMBCLIENT, $o{'H'}, $o{'s'}, $o{'P'});
if ($o{'D'}) {
	printf STDERR "DEBUG: cmd = %s\n", $cmd;
}

alarm($o{'t'});
my $result = qx/$cmd/;
alarm(0);

#Split $res into an array of lines
my @lines = split /\n/, $result;

#Get the last line into $_
$_ = $lines[$#lines];
#print "$_\n";

my ($answer, $state_text, $state, $server_output);

# set defaults to handle the scenario where we get smbclient output that we don't know about
$state = UNKNOWN;
$state_text = 'UNKNOWN';
$answer = 'Unknown output from smbclient';

foreach (@lines) {
	if ($o{'D'}) {
		printf STDERR "DEBUG: %s\n", $_;
	}

	# This just initializes to something informative
	if (/Server=\[(.+)\]/) {
		$answer = $1;
		$state_text = "OK";
		$state = OK;
	}

	# this happens if smbd is running, but without a keytab
	if ( /.*(smb_krb5_get_credentials failed for .+)/ ) {
		$answer = "$1\n";
		$state_text = "CRITICAL";
		$state = CRITICAL;
		last;
	}	
	if (/(Access denied|NT_STATUS_LOGON_FAILURE)/) {
		$answer = "Access Denied\n";
		$state_text = "CRITICAL";
		$state = CRITICAL;
		last;
	}
	if (/(Unknown host \w*|Connection.*failed)/) {
		$answer = "$1\n";
		$state_text = "CRITICAL";
		$state = CRITICAL;
		last;
	}
	if (/(You specified an invalid share name|NT_STATUS_BAD_NETWORK_NAME)/) {
		$answer = "Invalid share name \\\\$o{'H'}\\$o{'s'}\n";
		$state_text = "CRITICAL";
		$state = CRITICAL;
		last;
	}
	if ( /(.*NT_STATUS_OBJECT_NAME_NOT_FOUND.*)/ ) {
		$answer = $_;
		$state_text = "CRITICAL";
		$state = CRITICAL;
		last;
	}
}

printf "%s: \\\\%s\\%s%s : %s\n", $state_text, $o{'H'}, $o{'s'}, $o{'P'}, $answer;
exit $state;

