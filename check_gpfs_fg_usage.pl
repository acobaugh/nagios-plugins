#!/usr/bin/perl

use warnings;
use strict;
use Nagios::Plugin qw(OK WARNING CRITICAL UNKNOWN %STATUS_TEXT);
use Getopt::Long;

sub help {
	printf STDERR "Usage: %s [-w <N>] [-c <N>] [-t <timeout>] [-e /path/to/mmdf] [-v] [-h] -d <device>\n", $0;
	exit UNKNOWN;
}

my %o = ();

$o{'w'} = 90;
$o{'c'} = 95;
$o{'e'} = '/usr/lpp/mmfs/bin/mmdf';
$o{'t'} = 30;

GetOptions(\%o,
	"h",
	"v",
	"d=s",
	"w=i",
	"c=i",
	"e=s",
	"t=i"
) or help;

# check require options
if (! defined($o{'d'}) ) {
	print STDERR "Missing -d option\n";
	help;
}

# help message
if ($o{'h'}) {
	help;
}

# sanity-check warning and critical values
if ($o{'c'} le $o{'w'}) {
	print STDERR "-c must greater than -w\n";
	help;
}

# is the specified path to mmdf executable?
if (! -e $o{'e'}) {
	printf STDERR "'%s' not executable\n";
	help;
}

my %stats = ();

sub print_fgstats {
	my (%fgstats) = @_;
	foreach my $pool ( keys %fgstats ) {
		foreach my $fg ( keys %{$fgstats{$pool}} ) {
			printf "[%s](%s)=%i%% ", $pool, $fg, $fgstats{$pool}{$fg};
		}
	}
}

# execute mmdf and capture output
my $command = "$o{'e'} $o{'d'} 2>&1";
$SIG{ALRM} = sub { 
	printf "UNKNOWN: Timeout executing '%s' after %i seconds\n", $command, $o{'t'}; 
	exit UNKNOWN; 
};
alarm $o{'t'};
if ($o{'v'}) {
	printf STDERR "Executing '%s' with alarm timeout of %i seconds\n", $command, $o{'t'};
}
my @output = `$command 2>&1`;
if ($? ne 0) {
	printf "UNKNOWN: %s returned %i\n", $command, $?;
	exit UNKNOWN;
}

if ($o{'v'}) {
	printf STDERR "Command returned %i lines\n", $#output;
}
my $currentpool = '';
foreach (@output) {
	last if ! defined;
	if ($o{'v'}) {
		printf STDERR "Parsing line: %s\n", $_;
	}
	if ( /^Disks in storage pool: (.+)\s+\(/ ) {
		$currentpool = $1;
	}

	# disk                disk size  failure holds    holds              free KB             free KB
	# name                    in KB    group metadata data        in full blocks        in fragments
	if ( /^(.+)\s+(\d+)\s+(\d+)\s+(no|yes)\s+(no|yes)\s+(\d+)\s+\(\s*(\d+)%\)\s+(\d+)\s+\(\s*(\d+)%\)\s+/i ) {
		$stats{$currentpool}{$3}{$1}{'size'} = $2;
		$stats{$currentpool}{$3}{$1}{'metadata'} = $4;
		$stats{$currentpool}{$3}{$1}{'data'} = $5;
		$stats{$currentpool}{$3}{$1}{'blocksfree'} = $6;
		$stats{$currentpool}{$3}{$1}{'fragblocksfree'} = $8;
	}
}

my %fgtotals = ();

my %fgcrit = ();
my %fgwarn = ();
my %fgok = ();

# loop through pools
foreach my $pool ( keys %stats ) {
	if ($o{'v'}) {
		print "Pool: $pool\n";
	}

	# loop through failure groups
	foreach my $fg ( keys %{$stats{$pool}} ) {
		if ($o{'v'}) {
			print "\t$fg:\n";
		}
		# loop through disks
		foreach my $disk ( keys %{$stats{$pool}{$fg}} ) {
			if ($o{'v'}) {
				print "\t\t$disk\n";
			}
			# initialize this failure group total
			if ( ! defined($fgtotals{$pool}{$fg}{'size'}) ) {
				$fgtotals{$pool}{$fg}{'size'} = 0;
				$fgtotals{$pool}{$fg}{'free'} = 0;
			}
		
			# add up size and free space
			$fgtotals{$pool}{$fg}{'size'} += $stats{$pool}{$fg}{$disk}{'size'};
			$fgtotals{$pool}{$fg}{'free'} += $stats{$pool}{$fg}{$disk}{'blocksfree'};	

		}
	}
}

# loop through failure group totals
foreach my $pool ( keys %fgtotals ) {
	foreach my $fg ( keys %{$fgtotals{$pool}} ) {
			# calculate percent free space
			my $pcntused = ($fgtotals{$pool}{$fg}{'size'} - $fgtotals{$pool}{$fg}{'free'}) / $fgtotals{$pool}{$fg}{'size'} * 100;

			# drop those failure groups into the critical, warn, and ok buckets
			if ( $pcntused ge $o{'c'} ) {
				$fgcrit{$pool}{$fg} = $pcntused;
			} elsif ( $pcntused ge $o{'w'} ) {
				$fgwarn{$pool}{$fg} = $pcntused;
			} else {
				$fgok{$pool}{$fg} = $pcntused;
			}
	}
}


if ( scalar keys %fgcrit ) {
	print "CRITICAL: Used blocks: ";
	print_fgstats(%fgcrit);
	print "\n";
	exit CRITICAL;
}

if ( scalar keys %fgwarn ) {
	print "WARNING: Used blocks: ";
	print_fgstats(%fgwarn);
	print "\n";
	exit WARNING;
}

if ( scalar keys %fgok ) {
	print "OK: Used blocks: ";
	print_fgstats(%fgok);
	print "\n";
	exit OK;
}

# if we've fallen this far, then obviously we didn't get any usable output
printf "UNKNOWN: %s returned 0, but we could not parse the output\n", $command;
exit UNKNOWN;

