#!/usr/bin/perl -w

use strict;
use Nagios::Plugin;
use Getopt::Long;
use Net::Jabber;

my (	
	$opt_help,
	$opt_port,
	$opt_host,
	$opt_verbose,
	$opt_uname,
	$opt_pass,
	$opt_tls,
	$opt_pwdfile,
	$opt_tstuser,
	$opt_timeout
) = ( 0 );
  
my $PROGNAME = $0;
$opt_timeout = 15;

Getopt::Long::Configure('bundling');
GetOptions(
	"h"   => \$opt_help,        "help"              => \$opt_help,
	"tls"   => \$opt_tls,
	"p=i" => \$opt_port,
	"H=s" => \$opt_host,
	"v+"  => \$opt_verbose,     "verbose+"          => \$opt_verbose,
	"u=s"   => \$opt_uname,
	"t=i" => \$opt_timeout,
	"P=s"   => \$opt_pass,
	"U=s" => \$opt_tstuser,
	"pwdfile=s" => \$opt_pwdfile
);

sub print_usage () {
        print "Usage: \n";
        print " $PROGNAME -H <host> -p <port> -u <username> [-U <user to send test message to>] [-P <password> | --pwdfile <file>]  [--tls] [-t <timeout>]\n";
        print " $PROGNAME [-h | --help]\n";
        print " $PROGNAME [-V | --version]\n";
}

# print usage
if ($opt_help) { print_usage(); exit OK; }

if (!$opt_pass and $opt_pwdfile) {
	open(PWDFILE, $opt_pwdfile);
	$opt_pass = <PWDFILE>;
	$opt_pass =~ s/\s+//;
	close PWDFILE;
}

# check for required options
if (!$opt_host || !$opt_port || !$opt_uname || !$opt_pass) { print_usage(); exit UNKNOWN; }

# build default test username value
if (! defined $opt_tstuser || ! $opt_tstuser) {
	$opt_tstuser = $opt_uname . '@' . $opt_host;
}

my $debug = 0;
$debug = '2' if defined $opt_verbose;

my $starttime = time;

my $client = new Net::Jabber::Client(debuglevel => $debug, file => 'stdout');
my $status = $client->Connect(
	hostname => $opt_host,
	port => $opt_port,
	tls => $opt_tls,
	timeout => $opt_timeout
);

# are we connected?
if (! defined $status or $status ne 1) {
	printf "CRITICAL: Connect(): %s\n", $!;
	exit CRITICAL;
}

$client->SetCallBacks(message => \&messageCB);

# try to auth
my @resp_array = $client->AuthSend(
	username => $opt_uname,
	password => $opt_pass,
	resource => 'Nagios',
);
if ($resp_array[0] ne "ok") {
	printf "CRITICAL: AuthSend(): %s (%s)\n", $resp_array[0], $resp_array[1];
	$client->Disconnect();
	exit CRITICAL;
}

# this will store the output
our $output = "XMPP login successful";

# announce our presence to the world
$client->PresenceSend();

my $body = "Current UNIX time is " . time;
$client->MessageSend( 
	to => $opt_tstuser,
	subject => 'nagios test',
	body => $body
);

# normally we Process() in a loop, but we only want to wait around for one message
$status = $client->Process($opt_timeout);
$client->Disconnect();

my $delta_t = time - $starttime;
$output = $output . ', Duration: ' . $delta_t . 's';
my $perfdata = '| time=' . $delta_t . "s\n";

if (! defined $status) {
	print "CRITICAL: $output, Process() returned undef" . $perfdata;
	exit CRITICAL;
} elsif ($status eq 0) {
	print "WARNING: $output, no testmessage recieved after $opt_timeout seconds" . $perfdata;
	exit WARNING;
} elsif ($status eq 1) {
	print "OK: $output" . $perfdata;
	exit OK;
}

sub messageCB() {
	my $sid = shift;
	my $message = shift;
	
	$output = $output . ", Test msg: From=" . $message->GetFrom() . " Body=\"" . $message->GetBody() . "\"";
}
