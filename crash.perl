#! /usr/bin/perl -w

use strict;
my $url = shift || 'http://localhost/addone';

my $errorLogFile = "/var/log/apache2/error.log";

die "You need to truncate the log first: 
  truncate -s 0 $errorLogFile\n"
 if `grep Segmentation $errorLogFile`;

chdir "/tmp";
my $i = 0;
while (1) {
	$i++;
	warn "Try $i ...\n";
	# `wget -O /tmp/wgetout.txt '$url' > /dev/null 2>&1 `;
	`curl '$url' > /tmp/wgetout.txt`;
	die "Empty response!\n" if (!-s "/tmp/wgetout.txt");
	die "Seg fault!\n" if `grep Segmentation $errorLogFile`;
	sleep 10 if $i==4;
	}

