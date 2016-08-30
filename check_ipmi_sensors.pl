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
	'UNKNOWN' => 3
);
my $options = "";
my @_ignore = ();
GetOptions(
	"H|host=s" => \(my $host),
	"u|user=s" => \(my $user),
	"h|help" => \(my $help),
	"P|pwfile=s" => \(my $pwfile),
	"i|ignore=s" => \@_ignore,
	"v|verbose" => \(my $verbose),
	"o|options=s" => \$options
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
		print "$PROGRAM UNKNOWN\n";
		print "Missing command line options\n";
		usage();
		exit $STATUSCODE{'UNKNOWN'};
}

# remove leading and trailing whitespace
sub trim ($) {
	my ($v) = @_;
	$v =~ s/^ +//;
	$v =~ s/ +$//;
	return $v;
}

# ipmitool will sit and wait for a password if this file does not exist or is empty
if (! -s $pwfile ) {
	print "$PROGRAM UNKNOWN\n";
	print "Password file $pwfile is empty, unreadable, or does not exist.\n";
	exit $STATUSCODE{'UNKNOWN'};
}

# open ipmitool
if (! open IPMI, "$IPMITOOL $options -H $host -U $user -f $pwfile $SDR 2>&1 |") {
	print "$PROGRAM UNKNOWN\n";
	print "$!\n";
	exit $STATUSCODE{'UNKNOWN'};
}

# this is used to generate unique names
my %seen;
my $perfdata = "";
# parse ipmitool output
my (%sensors_ok, %sensors_critical, %sensors_warning);
while (my $line = <IPMI>) {
	chomp $line;
	print "$line\n" if ( $verbose );
	unless ($line =~ m/^(.*) \| (.*) \| (\w+)$/)
	{
		print "$PROGRAM UNKNOWN\n";
		print "Unexpected ipmitool output: $line\n";
		exit $STATUSCODE{'UNKNOWN'};
	}
	my $name  = trim $1;
	my $value = trim $2;
	my $state = trim $3;

	# skip not readable entries
	next if $state eq "ns";

	# generate unique name for this sensor if we've already seen it before
	if (! defined $seen{$name}) {	
		# store next number to append
		$seen{$name} = 2;
	} else {
		$name = $name . $seen{$name};
		$seen{$name}++;
	}

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
	my $perf_name = $name;
	$perf_name =~ s/\ /_/g;
	if ($value =~ /(\d*\.?\d+?)/) {
		$perfdata .= "$perf_name=$1;;;; ";
	}
}

if (!close IPMI) {
	print "$PROGRAM UNKNOWN\n";
	print "$! $?\n";
	exit $STATUSCODE{'UNKNOWN'};
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
printf "%s: (C:%d W:%d O:%d) %s|%s\n", 
	$status, 
	scalar keys %sensors_critical, 
	scalar keys %sensors_warning, 
	scalar keys %sensors_ok, 
	$message, $perfdata;
exit $STATUSCODE{$status};

sub usage {
	print "Usage: $0 [-H|--Host <ipaddr>] [-u|--user <username>] [-P|--pwfile <password file>]\n";
	print "[-i|--ignore <sensor> ...] [-h|--help]\n\n";
}

