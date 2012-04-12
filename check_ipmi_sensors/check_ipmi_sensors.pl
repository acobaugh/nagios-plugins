#!/usr/bin/perl 

use strict;
use warnings;

use Getopt::Long qw(:config bundling);

my $PROGRAM = "IPMI Sensors";

# Path to ipmitool
my $IPMITOOL = "/usr/bin/ipmitool";

# sdr command
my $SDR = "sdr list full";

# nagios exit codes
my %STATUSCODE = (
	'OK' => 0,
	'WARNING' => 1,
	'CRITICAL' => 2,
	'UNKOWN' => 3
);

my @_ignore = ();
GetOptions(
	"H|host=s" => \(my $host),
	"u|user=s" => \(my $user),
	"h|help" => \(my $help),
	"P|pwfile=s" => \(my $pwfile),
	"i|ignore=s" => \@_ignore,
	"v|verbose" => \(my $verbose)
);

# build an ignore hash for faster lookup
my %ignore;
foreach (@_ignore) {
	$ignore{$_} = 1;
}

if ($help) {
	usage();
	exit 1;
}

# perform checking on command line options
if ( !( (defined $host) && (defined $user) && (defined $pwfile) ) ) {
		print "$PROGRAM UNKOWN\n";
		print "Missing command line options\n";
		usage();
		exit $STATUSCODE{'UNKOWN'};
}

# remove leading and trailing whitespace
sub trim ($) {
	my ($v) = @_;
	$v =~ s/^ +//;
	$v =~ s/ +$//;
	return $v;
}


# open ipmitool
if (! open IPMI, "$IPMITOOL -H $host -U $user -f $pwfile $SDR |") {
	print "$PROGRAM UNKOWN\n";
	print "$!\n";
	exit $STATUSCODE{'UNKOWN'};
}

# parse ipmitool output
my (%sensors_ok, %sensors_critical, %sensors_warning);
while (my $line = <IPMI>) {
	chomp $line;
	print "$line\n" if ( $verbose );
	unless ($line =~ m/^(.*) \| (.*) \| (\w+)$/)
	{
		print "$PROGRAM UNKOWN\n";
		print "Bad format in ipmitool output: $line\n";
		exit $STATUSCODE{'UNKOWN'};
	}
	my $name  = trim $1;
	my $value = trim $2;
	my $state = trim $3;

	# skip not readable entries
	next if $state eq "ns";
		
	# skip values we should ignore
	if (defined $ignore{$name}) {
		print "skipping $name\n" if $verbose;
		next;
	}

	$value =~ s/ degrees //;
	$value =~ s/degrees C//;
	$value =~ s/RPM//;
	$value = trim $value;

	if ($state eq "ok") {
		$sensors_ok{$name} = $value;
	}
	if ($state eq "nc") {
		$sensors_warning{$name} = $value;
	}
	if ($state eq "cr" or $state eq "nr") {
		$sensors_critical{$name} = $value;
	}
}

if (!close IPMI) {
	print "$PROGRAM UNKOWN\n";
	print "$! $?\n";
	exit $STATUSCODE{'UNKOWN'};
}

# set initial status
my $status = 'OK';

# sensors that are ok 
my $message_ok = '';
if (keys %sensors_ok) {
	$message_ok .= 'O:';
	foreach my $name (sort keys %sensors_ok) {
		$message_ok = $message_ok.$name."=".$sensors_ok{$name} . ' ';
	}
}

# sensors that warning
my $message_warn = '';
if (keys %sensors_warning) {
	$message_warn .= 'W:';
	$status = 'WARNING';
	foreach my $name (sort keys %sensors_warning) {
		$message_warn = $message_warn . $name . "=" . $sensors_warning{$name} . ' ';
	}
}

# sensors that are critical
my $message_crit = '';
if (keys %sensors_critical) {
	$message_crit .= 'C:';
	$status = 'CRITICAL';
	foreach my $name (sort keys %sensors_critical) {
		$message_crit = $message_crit . $name . "=" . $sensors_critical{$name} . ' ';
	}
}

# if we have any sensors that are warn (nc) or critical (cr), we only print those
# so clear out $message_ok
if ($message_warn ne '' or $message_crit ne '') {
	$message_ok = '';
}

my $message = $message_crit . $message_warn . $message_ok;

# print out $status, critical, warning, and ok sensor count, then the sensor name/value
printf "%s: (C:%d W:%d O:%d) %s\n", 
	$status, scalar keys %sensors_critical, scalar keys %sensors_warning, scalar keys %sensors_ok, $message;
exit $STATUSCODE{$status};

sub usage {
	print "Usage: $0 [-H|--Host <ipaddr>] [-u|--user <username>] [-P|--pwfile <password file>]\n";
	print "[-i|--ignore <sensor> ...] [-h|--help]\n\n";
}

