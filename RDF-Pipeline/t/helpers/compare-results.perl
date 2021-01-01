#! /usr/bin/perl -w

# Recursively compare the contents of the given two directories (excluding 
# "lm", "ont" and hidden subdirectories/files), exiting with 0 iff 
# they are the same.  
#
# Option:
#	-q	Quiet: only set return status, instead of showing diffs.
#	-d	Run diff after failed cmp.

use strict;

# Enable files created in /var/www to have the right group permissions:
umask 002;

my $debug = 0;
my $quiet = "";
my $showDiff = 0;
$quiet = shift @ARGV if @ARGV && $ARGV[0] eq "-q";
$showDiff = shift @ARGV if @ARGV && $ARGV[0] eq "-d";
my $expectedFiles = shift @ARGV || die;
my $resultFiles = shift @ARGV || die;

# -d $expectedFiles or exit 1;
# -d $resultFiles or exit 1;

use File::DirCompare;
use File::Basename;

my $result = 0; 
if (-d $expectedFiles && -d $resultFiles) {
	# Two directories.  Global $result will be set as a side effect
	# if there is any difference.
	File::DirCompare->compare($expectedFiles, $resultFiles, \&Difference, {
		cmp             => \&CompareFiles,
		exclude         => \&Exclude,
		});
	}
else	{
	# Plain or mixed files
	$result = &CompareFiles($expectedFiles, $resultFiles);
	}
exit $result;

################ Exclude ################
# Must return true if the given file should be excluded from comparison.
sub Exclude
{
  my ($f) = @_;
  # my $cmd = "diff -b -w $quiet -x lm -x ont -x '.*' '$expectedFiles' '$resultFiles'";
  return 1 if $f eq "lm";
  return 1 if $f eq "ont";
  return 1 if $f =~ m/^\./;
  return 0;
}

################ Difference ################
# Called on file pairs that differ.
sub Difference
{
  my ($a, $b) = @_;
  if (! $b) {
    printf "Only in %s: %s\n", dirname($a), basename($a) if !$quiet;
  } elsif (! $a) {
    printf "Only in %s: %s\n", dirname($b), basename($b) if !$quiet;
  } else {
    # print "Files $a and $b differ\n" if !$quiet;
  }
$result = 1;
}


################ CompareFiles #################
# The two files are known to exist, but one may be a directory.
sub CompareFiles
{
@_ == 2 || die;
my ($expectedFiles, $resultFiles) = @_;
# my $cmd = "diff -b -w $quiet -x lm -x ont -x '.*' '$expectedFiles' '$resultFiles'";
# my $cmd = "diff -b -w $quiet '$expectedFiles' '$resultFiles'";
# warn "cmd: $cmd\n";
###### TODO: Change this to use the saved Content-type associated with
###### the files, as described in issue-53:
###### http://code.google.com/p/rdf-pipeline/issues/detail?id=53
###### Or maybe implement smarter RDF sniffing?
if (-f $expectedFiles && -f $resultFiles) {
    # First try a standard diff of the two files:
    `cmp '$expectedFiles' '$resultFiles'`;
    return 0 if !$?;  # return success if standard diff worked

    # If the diff failed, then sniff to see if this might be a pair of turtle files
    my $tmpFile = &CommentHttpHeaders($resultFiles); # comment out any headers
    my $isTurtle = (&IsTurtle($expectedFiles) && &IsTurtle($tmpFile));
    if ($isTurtle) {
        my $cmd = "rdfdiff";
        $cmd .= " -b" if $quiet;
        $cmd .= " -f turtle -t turtle '$expectedFiles' '$tmpFile'";
        print "$cmd\n" if $debug;

        my $output = `$cmd`;
        if ( !$? ) { 
            unlink $tmpFile;
            return 0;  # return success if passed
        }

        # turtle comparison failed
        warn "rdfdiff $expectedFiles $tmpFile failed.\n";
        print "$cmd\n";
        print $output;
        return 1;

    } else { 
        # Not a turtle file and standard diff failed - return a failed status
        print "cmp '$expectedFiles' '$resultFiles' failed!\n";
	if ($showDiff) {
		my $cmd = "diff '$expectedFiles' '$resultFiles'";
		print "$cmd\n";
		my $result = `$cmd`;
		print "$result\n";
	}
        return 1;
    }
} # Got 2 files

return 0;
}


################## IsTurtle #####################
# Sniff to see if the given file looks like Turtle RDF.
sub IsTurtle
{
my $f = shift or die;
return 0 if !-f $f;
open(my $fh, "<$f") or die "$0: ERROR: File not found: $f\n";
my @lines = ();
my $maxLines = 100;
for (my $i=0; $i<$maxLines; $i++) {
	my $line = <$fh>;
	last if !defined($line);
	push(@lines, $line);
	}
close($fh);
# Check for SPARQL keyword.
my @sparqlKeyword = qw(select construct describe ask
	load clear drop create add move copy insert delete);
my $sparqlPattern = join("|", @sparqlKeyword);
my $isSparql = grep {m/^\s*($sparqlPattern)\s/i} @lines;
return 0 if $isSparql;
# If it isn't SPARQL, and PREFIX or BASE appears first (after comments),
# then assume it is Turtle.
my $isTurtle = 0;
foreach my $line ( @lines ) {
	next if $line =~ m/^\s*(\#.*)?$/;
	if ($line =~ m/^\s*(\@?)(prefix|base)\s/i) {
		$isTurtle = 1;
		last;
		}
	else	{
		last;
		}
	}
return $isTurtle;
}

sub MakeTmpFileName {
    my $f = shift or die;
    return "/tmp/".basename($f).".out";
}

################## CommentHttpHeaders #####################
# Inserts a # character in front of any http header line in the specified file
# This is done so we can do an rdfdiff without getting parse errors due to the headers 
sub CommentHttpHeaders {

    # Get the file to update
    my $f = shift or die;
    return 0 if !-f $f;

    open(my $fh, "<$f") or die "$0: ERROR: File not found: $f\n";

    # Create a clean tmp file target to hold updated version with the comments
    my $tmpFileName = &MakeTmpFileName($f);
    unlink $tmpFileName if ( -e $tmpFileName ); 
    open( my $tmpFh, '>', $tmpFileName) or die "Could not open file '$tmpFileName' $!";

    while(my $line = <$fh>) {
        if ($line =~ /^HTTP\// || 
            $line =~ /^Date: / || 
            $line =~ /^Server: Apache/ || 
            $line =~ /^Last-Modified: / || 
            $line =~ /^ETag: / || 
            $line =~ /^Content-Length: / || 
            $line =~ /^Content-Location: / || 
            $line =~ /^Content-Type: / || 
            $line =~ /^Vary: Accept-Encoding/ ||
            $line =~ /^------/) {
            print $tmpFh '# '.$line;
        } else {
            print $tmpFh $line;
        }
    }

    close($tmpFh);
    close($fh);

    return $tmpFileName
}
