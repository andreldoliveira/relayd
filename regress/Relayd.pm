#	$OpenBSD: Relayd.pm,v 1.12 2014/08/18 22:58:19 bluhm Exp $

# Copyright (c) 2010-2014 Alexander Bluhm <bluhm@openbsd.org>
#
# Permission to use, copy, modify, and distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

use strict;
use warnings;

package Relayd;
use parent 'Proc';
use Carp;
use File::Basename;

sub new {
	my $class = shift;
	my %args = @_;
	$args{logfile} ||= "relayd.log";
	$args{up} ||= $args{dryrun} || "relay_launch: ";
	$args{down} ||= $args{dryrun} ? "relayd.conf:" : "parent terminating";
	$args{func} = sub { Carp::confess "$class func may not be called" };
	$args{conffile} ||= "relayd.conf";
	$args{forward}
	    or croak "$class forward not given";
	my $self = Proc::new($class, %args);
	ref($self->{protocol}) eq 'ARRAY'
	    or $self->{protocol} = [ split("\n", $self->{protocol} || "") ];
	ref($self->{relay}) eq 'ARRAY'
	    or $self->{relay} = [ split("\n", $self->{relay} || "") ];
	$self->{listenaddr}
	    or croak "$class listen addr not given";
	$self->{listenport}
	    or croak "$class listen port not given";
	$self->{connectaddr}
	    or croak "$class connect addr not given";
	$self->{connectport}
	    or croak "$class connect port not given";

	my $test = basename($self->{testfile} || "");
	# ssl does not allow a too long session id, so truncate it
	substr($test, 25, length($test) - 25, "") if length($test) > 25;
	open(my $fh, '>', $self->{conffile})
	    or die ref($self), " conf file $self->{conffile} create failed: $!";
	print $fh "log all\n";
	print $fh "table <table-$test> { $self->{connectaddr} }\n"
	    if defined($self->{table});

	# substitute variables in config file
	my $curdir = dirname($0) || ".";
	my $connectport = $self->{connectport};
	my $connectaddr = $self->{connectaddr};
	my $listenaddr = $self->{listenaddr};
	my $listenport = $self->{listenport};

	my @protocol = @{$self->{protocol}};
	my $proto = shift @protocol;
	$proto = defined($proto) ? "$proto " : "";
	unshift @protocol,
	    $self->{forward} eq "splice" ? "tcp splice" :
	    $self->{forward} eq "copy"   ? "tcp no splice" :
	    die ref($self), " invalid forward $self->{forward}"
	    unless grep { /splice/ } @protocol;
	print $fh "${proto}protocol proto-$test {";
	# substitute variables in config file
	foreach (@protocol) {
		s/(\$[a-z]+)/$1/eeg;
	}
	print $fh  map { "\n\t$_" } @protocol;
	print $fh  "\n}\n";

	my @relay = @{$self->{relay}};
	print $fh  "relay relay-$test {";
	print $fh  "\n\tprotocol proto-$test"
	    unless grep { /^protocol / } @relay;
	my $ssl = $self->{listenssl} ? " ssl" : "";
	print $fh  "\n\tlisten on $self->{listenaddr} ".
	    "port $self->{listenport}$ssl" unless grep { /^listen / } @relay;
	my $withssl = $self->{forwardssl} ? " with ssl" : "";
	print $fh  "\n\tforward$withssl to $self->{connectaddr} ".
	    "port $self->{connectport}" unless grep { /^forward / } @relay;
	# substitute variables in config file
	foreach (@relay) {
		s/(\$[a-z]+)/$1/eeg;
	}
	print $fh  map { "\n\t$_" } @relay;
	print $fh  "\n}\n";

	return $self;
}

sub child {
	my $self = shift;
	my @sudo = $ENV{SUDO} ? $ENV{SUDO} : ();
	my @ktrace = $ENV{KTRACE} ? ($ENV{KTRACE}, "-i") : ();
	my $relayd = $ENV{RELAYD} ? $ENV{RELAYD} : "relayd";
	my @cmd = (@sudo, @ktrace, $relayd, "-dvv", "-f", $self->{conffile});
	print STDERR "execute: @cmd\n";
	exec @cmd;
	die ref($self), " exec '@cmd' failed: $!";
}

1;
