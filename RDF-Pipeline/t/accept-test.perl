#! /usr/bin/perl -w

# Accept the current $wwwDir files as correct, by copying them
# to expected-files (after deleting the current expected files).
# If the -s option is specified, then also try to add the
# test into subversion.

use strict;

# my $wwwDir = $ENV{'RDF_PIPELINE_WWW_DIR'} or &EnvNotSet('RDF_PIPELINE_WWW_DIR');
my $devDir = $ENV{'RDF_PIPELINE_DEV_DIR'} or &EnvNotSet('RDF_PIPELINE_DEV_DIR');
my $moduleDir = "$devDir/RDF-Pipeline";
my $testsDir = "$moduleDir/t/tests";
chdir($testsDir) or die "ERROR: Could not chdir('$testsDir')\n";

my $svn = 0;	# -s option
if (@ARGV && $ARGV[0] eq "-s") {
	shift @ARGV;
	$svn = 1;
	}

my @testDirs = @ARGV;
if (!@testDirs) {
	my $maxDir = 0;
	@testDirs = grep { -d $_ } <0*>;
	@testDirs or die "ERROR: No test directories found in '$testsDir'\n";
	@testDirs = ( $testDirs[@testDirs-1] );		# default to last one
	warn "Accepting test $testDirs[0] ...\n";
	}

foreach my $dir (@testDirs) {
	# Copy the $wwwDir files to expected-files
	my $copyCmd = "$moduleDir/t/helpers/copy-dir.perl -s '$wwwDir' '$dir/expected-files'";
	# warn "copyCmd: $copyCmd\n";
	!system($copyCmd) or die;
	# Add the test to svn?
	if (!$svn) {
		warn "Remember to add $dir to subversion, or use: accept-test.perl -s '$dir'\n"
			if !-e "$dir/.svn";
		next;
		}
	if (-e "$dir/.svn") {
		warn "Already in subversion: $dir\n";
		next;
		}
	warn "Attempting to add $dir to subversion ...\n";
	my $svnCmd = "cd '$devDir' ; svn -q add 'RDF-Pipeline/t/tests/$dir'";
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

