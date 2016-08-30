#!/usr/bin/perl

use strict;
use warnings;
use Net::STOMP::Client;
use Getopt::Long qw(:config bundling);
use Nagios::Plugin qw(OK WARNING CRITICAL UNKNOWN %STATUS_TEXT);

sub check_activemq($);

my %STATUSCODE = (
	'OK' => 0,
	'WARNING' => 1,
	'CRITICAL' => 2,
	'UNKNOWN' => 3
);

# defaults
my $opt_port = 61612;
my $opt_ssl = 0;
my $opt_timeout = 10;
my $opt_warning = 3;
my @opt_failover = ();

GetOptions(
	"H|host=s" => \(my $opt_host),
	"F|failover=s" => \@opt_failover,
	"u|user=s" => \(my $opt_user),
	"p|password=s" => \(my $opt_password),
	"f|pwdfile=s" => \(my $opt_pwdfile),
	"q|queue=s" => \(my $opt_queue),
	"P|port=i" => \$opt_port,
	"S|ssl" => \$opt_ssl,
	"t|timeout=i" => \$opt_timeout,
	"h|help" => \(my $opt_help),
	"D|debug" => \(my $opt_debug),
	"w|warning=i" => \$opt_warning
);

sub usage() {
	print "Usage: $0 -H|--host <hostname> -u|--user <user> (-p|--password <password> | -f|--pwdfile </path/to/pwdfile>) -q|--queue <queue name> \n";
	print "[-P|--port <port number>] [-S|--ssl] [-t|--timeout <timeout seconds>] [-w|--warning] [-h|--help] [-D|--debug]\n\n";
}

if ($opt_help) {
	usage();
	exit 1;
}

# read in password from file
if (defined $opt_pwdfile and -f $opt_pwdfile) {
	if ( open(PWDFILE, $opt_pwdfile) ) {
		$opt_password = <PWDFILE>;
		$opt_password =~ s/\s+//g;
		close PWDFILE;
	} else {
		print "UNKNOWN: Failed to read password file $opt_pwdfile\n";
		exit $STATUSCODE{"UNKNOWN"};
	}
}

# check required options
if (! (
	(defined $opt_host)
	and (defined $opt_user)
	and (defined $opt_password)
	and (defined $opt_queue)
)) {
	print "argc = $#ARGV\n";
	print "Missing required command line option(s)\n";
	usage();
	exit $STATUSCODE{'UNKNOWN'};
}

# accept comma-separate values for -F
@opt_failover = split(/,/,join(',',@opt_failover));

# this will store the results keyed by host as such:
# %results = (
#     'IP' => {
#         'string' => 'output string',
#         'code' => 'nagios exit code',
#         'delta_t' = 'time it took'
#     }
# )

# these things need to be global
my $stomp;
my $starttime;
my %results = ();

# check host specified by -H
check_activemq($opt_host);
if ($results{"$opt_host"}{'code'} == $STATUSCODE{'OK'}) {
	# This host is good
	printf "OK: This node is handling connections. %s | time=%s\n", 
		$results{"$opt_host"}{'string'}, 
		$results{"$opt_host"}{'delta'};
	exit $results{"$opt_host"}{'code'};
} else {
	# otherwise, check the other hosts in the failover group
	foreach my $host (@opt_failover) {
		check_activemq($host);
		if ($results{"$host"}{'code'} == $STATUSCODE{'OK'}) {
			printf "OK: %s is handling connections. This node reports: %s: %s | time=%s\n", 
				$host,  
				$STATUS_TEXT{$results{"$opt_host"}{'code'}},
				$results{"$opt_host"}{'string'}, 
				$results{"$opt_host"}{'delta'};
			exit $results{"$host"}{'code'};
		}
	}

	# at this point, no other node is OK, report our status
	printf "%s: No node in the failover group is handling connections. This node reports: %s | time=%s\n",
		$STATUS_TEXT{$results{"$opt_host"}{'code'}},
		$results{"$opt_host"}{'string'}, 
		$results{"$opt_host"}{'delta'};
	exit $results{"$opt_host"}{'code'};
}

printf "UNKNOWN\n";
exit UNKNOWN;


sub check_activemq($) {
	my ($host) = @_;

	# set some defaults
	$results{"$host"}{'string'} = "UNKNOWN";
	$results{"$host"}{'code'} = $STATUSCODE{"UNKNOWN"};
	$results{"$host"}{'delta'} = 0;

	# determine $uri
	my $ssl = '';
	if ($opt_ssl) {
		$ssl = '+ssl';
	}
	my $uri = "stomp$ssl://$host:$opt_port";

	eval {
		$stomp = Net::STOMP::Client->new( uri => $uri );
	};

	# TCP connection failure
	if (!$stomp) {
		$results{"$host"}{'string'} = "Could not connect to $uri\n"
			. "new(): $@";
		$results{"$host"}{'code'} = $STATUSCODE{"CRITICAL"};
		return;
	}

	# Establish session
	eval {
		$stomp->connect(
			login => $opt_user,
			passcode => $opt_password,
			timeout => $opt_timeout
		);
	};

	# authentication or other session creation failure
	if (!$stomp->session()) {
		$results{"$host"}{'string'} = "Could not establish session as $opt_user to $uri\n"
			. "connect(): $@";
		$results{"$host"}{'code'} = $STATUSCODE{"CRITICAL"};
		return;
	}

	# $starttime is used as a test message and for timing
	my $starttime = time;

	# Send test message containing $time timestamp.
	eval {
		$stomp->send( 
			destination => $opt_queue,
			body => "$starttime",
			subject => "nagios"
		);
	};
	
	if ($@) {
		$results{"$host"}{'string'} = "Could not send to queue '$opt_queue'\n"
			. "send(): $@";
		$results{"$host"}{'code'} = $STATUSCODE{"CRITICAL"};
		return;
	}

	# Subscribe to messages from the $queue.

	eval {
		$stomp->subscribe(
			destination => $opt_queue,
			ack => 'client',
			id => 'testnagios',
			'activemq.prefetchSize' => 1
		);
	};

	if ($@) {
		$results{"$host"}{'string'} = "Could not subscribe to queue '$opt_queue'\n"
			. "subscribe(): $@";
		$results{"$host"}{'code'} = $STATUSCODE{"CRITICAL"};
	}	

	#$stomp->message_callback(\&cb);

	eval {
		$stomp->wait_for_frames( timeout => $opt_timeout, callback => sub { 
			my ($self, $frame) = @_;

			my $delta = time - $starttime;
			$results{"$host"}{'delta'} = $delta;
			my $framebody = $frame->body();
			
			if ($frame) {
				eval {
					$stomp->ack(frame => $frame);
				};
				if ($@) {
					$results{"$host"}{'string'} = "Could not ack message"
						. "ack(): $@";
					$results{"$host"}{'code'} =$STATUSCODE{"CRITICAL"};
					return 1;
				}

				if ($frame->command() eq "MESSAGE") {

					# all of the OK/WARNING/CRITICAL logic is below
					if ($framebody eq $starttime) {
						if ($delta lt $opt_warning) {
							$results{"$host"}{'string'} = "Message received in $delta seconds with body $framebody\n";
							$results{"$host"}{'code'} = $STATUSCODE{"OK"};
							return 1;
						} else {
							print "Message received in $delta seconds with body $framebody\n";
							exit $STATUSCODE{"WARNING"};
						}
					} else {
						$results{"$host"}{'string'} = "Incorrect message body after $delta seconds; got $framebody, should be $starttime. Returning 0 back to wait_for_frames() to grab the next one.\n";
						return 0; # tell wait_for_frames() to wait for more frames
					}
				} else {
					$results{"$host"}{'string'} = "%s frame received with body $framebody after $delta seconds.\n", $frame->command();
					$results{"$host"}{'code'} = $STATUSCODE{"UNKNOWN"};
					return 1;
				}
			}
			return 0;
		} ); # END wait_for_frames()
	};

	if ($@) {
		$results{"$host"}{'string'} = "Could not receive frames from queue '$opt_queue'\n"
			. "wait_for_frames(): $@";
		$results{"$host"}{'code'} = $STATUSCODE{"CRITICAL"};
	}	

	eval {
		$stomp->disconnect;
	}
} # sub check_activemq()
