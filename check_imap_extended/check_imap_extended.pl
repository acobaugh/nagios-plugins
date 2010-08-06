#!/usr/bin/env perl

use warnings;
use strict;

use Mail::IMAPClient;
use Getopt::Long;

my $OK=0;
my $WARNING=1;
my $CRITICAL=2;
my $UNKNOWN=3;

my %o = (
	'H' => '',
	'P' => 143,
	'U' => '',
	'f' => 'INBOX',
	'S' => 0,
	'pwdfile' => '',
	'p' => '',
	'help' => 0,
	'h' => 0
);

sub usage {
	print "Usage: check_imap_extended.pl [--help] -H <hostname> -U <user> {-p <password>|--pwdfile <file>} [-P <port>] [-f <folder>] [-S]\n";
	exit 0;
}

Getopt::Long::Configure("bundling");
GetOptions(\%o,	"help", "h", "H=s", "P=i", "U=s", "f=s", "S", "pwdfile=s", "p=s") or usage;

if ($o{'help'}) {
	exec('perldoc', '-T', $0);
	exit $UNKNOWN;
}

if (!$o{'p'} and $o{'pwdfile'}) {
	open(PWDFILE, $o{'pwdfile'});
	$o{'p'} = <PWDFILE>;
	$o{'p'} =~ s/\s+//;
	close PWDFILE;
}

if ( (!$o{'H'}) or (!$o{'U'}) or (!$o{'p'}) or ($o{'h'}) ) {
	usage;
	exit $UNKNOWN;
}

my $imap = Mail::IMAPClient->new(
	Server => $o{'H'},
	User => $o{'U'},
	Password => $o{'p'},
	Ssl => $o{'S'},
	Port => $o{'P'},
);

if (defined($imap)) {
	if ($imap->IsConnected) {
		my $count = $imap->message_count($o{'f'});
		if (defined($count)) {
			if ($count gt 0) {
				printf "OK: Found %s message(s) in %s\n", $count, $o{'f'};
				exit $OK
			} else {
				printf "WARNING: Found %s message(s) in %s\n", $count, $o{'f'};
				exit $WARNING;
			}
		} else {
			printf "CRITICAL: Could not count messages or non-existant folder %s\n", $o{'f'};
			exit $CRITICAL;
		}
	} else {
		print "CRITICAL: Could not connect\n";
		print $imap->LastError, "\n";
		exit $CRITICAL;
	}
} else {
	print "CRITICAL: Could not connect\n";
	exit $CRITICAL;
}


__END__

=head1 NAME

check_imap_extended.pl - Check for a positive message count in a given folder on a given IMAP server

=head1 SYNOPSIS

check_imap_extended.pl [--help] -H <hostname> -U <user> {-p <password>|--pwdfile <file>} [-P <port>] [-f <folder>] [-S]

=head1 OPTIONS

Required:

=over

=item B<-H>

Hostname to connect to.

=item B<-U>

Username to use.

=item B<-p>
Password for user. Either -p or --pwdfile must be specified.

=back

Optional:

=over

=item B<--help>

Prints this full help message

=item B<-P>

Port. Defaults to 143.

=item B<-S>

Use SSL. Defaults to no.

=item B<--pwdfile>

File containing password for user. Either --pwdfile or -p must be specified.

=item B<-f>

Folder to check.

=back

=head1 SEE ALSO

Nagios: L<http://www.nagios.org/>

Phalenor's Nagios plugins: L<http://github.com/phalenor/nagios_plugins>

=head1 AUTHOR

Andy Cobaugh <phalenor@gmail.com>

=cut
