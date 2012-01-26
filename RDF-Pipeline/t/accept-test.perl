#! /usr/bin/perl -w

# Accept the current result-files as correct, by copying them
# to expected-files (after deleting the current expected files).
# If the -svn option is specified, then also try to add the
# test into subversion.

use strict;

# my $wwwDir = $ENV{'RDF_PIPELINE_WWW_DIR'} or &EnvNotSet('RDF_PIPELINE_WWW_DIR');
my $devDir = $ENV{'RDF_PIPELINE_DEV_DIR'} or &EnvNotSet('RDF_PIPELINE_DEV_DIR');
my $moduleDir = "$devDir/RDF-Pipeline";
chdir("$moduleDir/t") or die "ERROR: Could not chdir('$moduleDir/t')\n";

my $svn = 0;	# -svn option
if (@ARGV && $ARGV[0] eq "-svn") {
	shift @ARGV;
	$svn = 1;
	}

my @testDirs = @ARGV;
if (!@testDirs) {
	my $maxDir = 0;
	@testDirs = grep { -d $_ } <0*>;
	@testDirs or die "ERROR: No test directories found in '$moduleDir/t'\n";
	@testDirs = ( $testDirs[@testDirs-1] );		# default to last one
	}

foreach my $dir (@testDirs) {
	# Copy the result-files to expected-files
	my $copyCmd = "helpers/copy-result-files.perl '$dir/result-files' '$dir/expected-files'";
	# warn "copyCmd: $copyCmd\n";
	!system($copyCmd) or die;
	# Add the test to svn?
	next if !$svn;
	warn "Attempting to add $dir to subversion ...\n";
	my $svnCmd = "cd '$devDir' ; svn add 'RDF-Pipeline/t/$dir'";
	warn "$svnCmd\n";
	!system($svnCmd) or die;
	}

exit 0;

########## EnvNotSet #########
sub EnvNotSet
{
@_ == 1 or die;
my ($var) = @_;
die "ERROR: Environment variable '$var' not set!  Please set it
by editing set_env.sh and then (in bourne shell) issuing the 
command '. set_env.sh'\n";
}

