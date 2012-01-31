#! /usr/bin/perl -w

# Recursively compare expected-files with result-files (excluding 
# "lm", "ont" and hidden subdirectories/files), exiting with 0 iff 
# they are the same. 
#
# Option:
#	-q	Quiet: only set return status, instead of showing diffs.

use strict;

my $quiet = "";
$quiet = shift @ARGV if @ARGV && $ARGV[0] eq "-q";
my $expectedFiles = shift @ARGV || die;
my $resultFiles = shift @ARGV || die;

-d $expectedFiles or exit 1;
-d $resultFiles or exit 1;
my $cmd = "diff -r -b $quiet -x lm -x ont -x '.*' '$expectedFiles' '$resultFiles'";
if (system($cmd)) {
	my $compare = $0;
	$compare =~ s|\A.*\/||;
	warn "To view the differences, use:
  $compare $expectedFiles $resultFiles\n" if $quiet;
	exit 1;
	}
exit 0;

