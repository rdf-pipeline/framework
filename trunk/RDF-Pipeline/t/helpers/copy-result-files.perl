#! /usr/bin/perl -w

# Copy RDF Pipeline result-files from one directory to another, 
# excluding any hidden files/directories that might cause problems.

use strict;

@ARGV == 2 or die "Usage: $0 fromDir toDir\n";
my $fromDir = shift @ARGV;
my $toDir = shift @ARGV;

-d $fromDir or die "$0: Directory does not exist: $fromDir\n";

# Delete old $toDir:
my $rmCmd = "rm -rf '$toDir'";
# warn "rmCmd: $rmCmd\n";
!system($rmCmd) or die if -e $toDir;

# Copy $fromDir to $toDir:
my $copyCmd = "cp -rp '$fromDir' '$toDir'";
# warn "copyCmd: $copyCmd\n";
!system($copyCmd) or die;

# Delete any hidden files (such as .svn) that could cause problems.
my $findCmd = "find '$toDir' -name '.*'";
# warn "findCmd: $findCmd\n";
my @hiddenFiles = map { chomp; $_ } `$findCmd`;
foreach my $hiddenFile (@hiddenFiles) {
	next if !-e $hiddenFile; # May have already been recursively deleted
	my $qHiddenFile = quotemeta($hiddenFile);
	my $rmCmd = "rm -rf $qHiddenFile";
	# warn "rmCmd: $rmCmd\n";
	!system($rmCmd) or die;
	}

exit 0;

