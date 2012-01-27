#! /usr/bin/perl -w

# Copy RDF Pipeline result-files from one directory to another, 
# excluding any hidden files/directories that might cause problems.
# Note that extra files in the destination directory (i.e., files
# that are not in the source directory) are not deleted.

use strict;

@ARGV == 2 or die "Usage: $0 fromDir toDir\n";
my $fromDir = shift @ARGV;
my $toDir = shift @ARGV;

-d $fromDir or die "$0: Source directory does not exist: $fromDir\n";

# Copy $fromDir to $toDir .
# $fromDir *must* have a trailing slash, so that rsync won't put it
# underneath $toDir, as explained in Kaleb Pederson's comment here:
# http://stackoverflow.com/questions/2193584/copy-folder-recursively-excluding-some-folders
$fromDir .= "/" if $fromDir !~ m|\/\Z|;
my $copyCmd = "rsync -a '--exclude=.*' '$fromDir' '$toDir'";
warn "copyCmd: $copyCmd\n";
!system($copyCmd) or die;

exit 0;

