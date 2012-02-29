#! /usr/bin/perl -w

# This can be used to filter each of the expected-files.
# It will be run with the filename as its only argument.
#
# This script should be temporarily modified as needed when changes
# are made that affect the format of the actual result files.

use strict;

# Skip the given file?
my $f = $ARGV[0];
exit(0) if $f =~ m|FILE_THAT_SHOULD_NOT_BE_FILTERED|;
# exit(0) if $f !~ m|FILE_THAT_SHOULD_BE_FILTERED|;

my $newf = $f;
$newf =~ s|\bout\Z|state|g;
$newf =~ s|Out\Z|State|g;
if ($newf ne $f) {
	rename($f, $newf) || die;
	@ARGV = ( $newf );
	$f = $newf;
	}

# The given file will be filtered by first writing to a tmp file:
my $tmp = "/tmp/filtered-$$.txt";
open(my $tmpfh, ">$tmp") || die;
while (<>) {
	# Make whatever changes are needed:
        # s/ETag\: \"(\d)/ETag\: \"LM$1/;
	s|\bout\b|state|g;
	s|Out\b|State|g;

	print $tmpfh $_;
	}
close($tmpfh) || die;
rename($tmp, $f) || die;

