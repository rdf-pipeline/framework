#! /usr/bin/perl -w

# Recursively compare expected-files with result-files (excluding 
# "lm", "ont" and hidden subdirectories/files), exiting with 0 iff 
# they are the same. 

use strict;

my $expectedFiles = shift @ARGV || die;
my $resultFiles = shift @ARGV || die;

-d $expectedFiles or exit 1;
-d $resultFiles or exit 1;
my $cmd = "diff -r -q -x lm -x ont -x '.*' '$expectedFiles' '$resultFiles'";
if (system($cmd)) {
	my $noisyCmd = $cmd;
	$noisyCmd =~ s/ \-q / /;
	warn "To view the differences, use:
  $noisyCmd\n";
	exit 1;
	}
exit 0;

