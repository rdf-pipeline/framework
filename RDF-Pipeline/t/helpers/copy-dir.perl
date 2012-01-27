#! /usr/bin/perl -w

# Copy RDF Pipeline result-files from one directory to another, 
# excluding hidden files/directories.
# The destination directory is first deleted.
#
# The -s ("subversion") option says to be svn-aware, which means that it if the
# destination directory contains a hidden .svn subdirectory, then
# we will do an "svn rm" to remove the destination directory
# from svn's control before copying the directory.  And after
# copying, we will do an "svn add" to add the destination directory
# back under svn control.  This allows files to be added/removed
# from the destination directory, which svn otherwise would not
# notice or would automatically restore.

use strict;

my $svnOption = 0;
if (@ARGV && $ARGV[0] eq "-s") {
	shift @ARGV;
	$svnOption = 1;
	}

@ARGV == 2 or die "Usage: $0 [-s] sourceDir destDir\n";
my $sourceDir = shift @ARGV;
my $destDir = shift @ARGV;

-d $sourceDir or die "$0: Source directory does not exist: $sourceDir\n";

my $useSvn = $svnOption && -d "$destDir/.svn";

if ($useSvn) {
	my $svnCmd = "svn rm -q --force '$destDir'";
	warn "$svnCmd\n";
	!system($svnCmd) or die "Command failed: $svnCmd";
	}
else	{
	if (-d "$destDir/.svn") {
		die "ERROR: Destination directory contains a .svn subdirectory!
If it is under subversion control, then use the -s option.
Otherwise, manually delete the destination directory first.\n" 
		}
	my $rmCmd = "rm -r '$destDir'";
	# warn "rmCmd: $rmCmd\n";
	!system($rmCmd) or die "Command failed: $rmCmd";
	}

# Copy $sourceDir to $destDir .
# $sourceDir *must* have a trailing slash, so that rsync won't put it
# underneath $destDir, as explained in Kaleb Pederson's comment here:
# http://stackoverflow.com/questions/2193584/copy-folder-recursively-excluding-some-folders
$sourceDir .= "/" if $sourceDir !~ m|\/\Z|;
my $copyCmd = "rsync -a '--exclude=.*' '$sourceDir' '$destDir'";
# warn "copyCmd: $copyCmd\n";
warn "Copying ...\n" if $useSvn;
!system($copyCmd) or die;

if ($useSvn) {
	my $svnCmd = "svn add -q '$destDir'";
	warn "$svnCmd\n";
	!system($svnCmd) or die "Command failed: $svnCmd";
	}

exit 0;

