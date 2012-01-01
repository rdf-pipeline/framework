#! /usr/bin/perl -w

use strict;
my $url = shift || 'http://localhost/addone';

my $errorLogFile = "/var/log/apache2/error.log";

chdir "/tmp";
# my $n = 200;
# foreach (my $i=1; $i<=20; $i++) {
my $i = 0;
while (1) {
	$i++;
	warn "Try $i ...\n";
	`wget -O /dev/null '$url' > /dev/null 2>&1 `;
	# sleep 1;
	# my $lastLines = join(" ", map {chomp; $_} `tail -1 $errorLogFile`);
	my $lastLines = join(" ", map {chomp; $_} `grep Segmentation $errorLogFile`);
	last if $lastLines =~ m/Segmentation/;
	}
warn "Seg faulted after $i tries.\n";

