#! /usr/bin/perl -w

# Recursively compare expected-files with result-files (excluding 
# "lm", "ont" and hidden subdirectories/files), exiting with 0 iff 
# they are the same. 

use strict;

my $expectedFiles = shift @ARGV || die;
my $resultFiles = shift @ARGV || die;

-d $expectedFiles or exit 1;
-d $resultFiles or exit 1;
exit 1 if system("diff -rq -x lm -x ont -x '.*' '$expectedFiles' '$resultFiles'");
exit 0;

