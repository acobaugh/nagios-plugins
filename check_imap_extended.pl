#!/usr/bin/perl

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
	'ssl' => 0,
	'pwdfile' => '',
	'pwd' => ''
);

Getopt::Long::Configure ("bundling");
GetOptions(\%o,	"H=s", "P=i", "U=s", "f=s", "ssl", "pwdfile=s", "pwd=s");

my $imap = Mail::IMAPClient->new(
	Server => $o{'H'},
	User => $o{'U'},
	Password => $o{'pwd'},
	Ssl => $o{'ssl'},
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
}

