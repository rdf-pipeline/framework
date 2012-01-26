#! /usr/bin/perl -w

# This script runs one or more tests in the suite of numbered tests.
# It exits with 0 status iff all tests pass.
#
# Usage:
#
#  	./run-test.perl [-c] [nnnn] ...
#
# where nnnn is the numbered test directory you wish to run, defaulting
# to the highest numbered test directory if none is specified.  
#
# Options:
#	-c	Clobber the existing $RDF_PIPELINE_WWW_DIR files and leave
#		them in whatever state the test leaves them in, instead
#		restoring them from a saved copy after the test.  This
#		is useful when you plan to add another test after this
#		one, and you want the initial state of the next test to
#		be the final state of this test.

my $wwwDir = $ENV{'RDF_PIPELINE_WWW_DIR'} or &EnvNotSet('RDF_PIPELINE_WWW_DIR');
my $devDir = $ENV{'RDF_PIPELINE_DEV_DIR'} or &EnvNotSet('RDF_PIPELINE_DEV_DIR');
my $moduleDir = "$devDir/RDF-Pipeline";
chdir("$moduleDir/t") or die "ERROR: Could not chdir('$moduleDir/t')\n";

my $clobber = 0;
if (@ARGV && $ARGV[0] eq "-c") {
	shift @ARGV;
	$clobber = 1;
	}

my @testDirs = @ARGV;
if (!@testDirs) {
	@testDirs = sort grep { -d $_ } <0*>;
	@testDirs or die "ERROR: No numbered test directories found in $moduleDir/t\n";
	@testDirs = ( $testDirs[@testDirs-1] );		# The last one.
	}

my $allPassed = 1;
foreach my $testDir (@testDirs) {
  my $testScript = "$testDir/test-script";
  if (!-e $testScript) {
    # Fail if no test script:
    $allPassed = 0;
    next;
    }
  if (!-x $testScript) {
    # Fail if non-executable test script:
    $allPassed = 0;
    next;
    }

  ### If there is a "setup-files" directory, then use it.
  my $setupFiles = "$testDir/setup-files";
  my $needToRestoreWwwRoot = 0;
  my $savedWwwDir = "$wwwDir-SAVE";
  if (-d $setupFiles) {
    if ($clobber) {
      my $rmCmd = "rm -rf '$wwwDir'";
      # warn "rmCmd: $rmCmd\n";
      !system($rmCmd) or die if -e $wwwDir;
      }
    else {
      $needToRestoreWwwRoot = 1;
      &SaveWwwRoot($savedWwwDir);
      }
    my $copyCmd = "cp -rp '$setupFiles' '$wwwDir'";
    # warn "copyCmd: $copyCmd\n";
    system($copyCmd) == 0 or die "ERROR: Unable to copy setup-files: $copyCmd\n";
    }

  # Run the test-script.
  my $testCmd = "$testDir/test-script '$testDir' '$wwwDir'";
  # warn "testCmd: $testCmd\n";
  my $status = system($testCmd);
  warn "Failed: $testCmd\n" if $status;
  $allPassed = 0 if $status;

  # Restore $wwwDir if necessary.
  if ($needToRestoreWwwRoot) {
    &RestoreWwwRoot($savedWwwDir);
    }
  }

exit 0 if $allPassed;
exit 1;

############# SaveWwwRoot ##############
sub SaveWwwRoot
{
@_ == 1 || die;
my ($savedWwwDir) = @_;
die "ERROR: Previously saved directory for Apache WWW root already 
  exists: $savedWwwDir
  This probably means that a previous test died and you should:
  (a) delete the existing Apache WWW root by issuing the command: 

    rm -rf '$wwwDir'
 
  and then (b) restore the saved version by issuing the command:

    mv '$savedWwwDir' '$wwwDir'\n\n" if -d $savedWwwDir;

die "ERROR: File exists but is not a directory: $savedWwwDir\n" 
	if -e $savedWwwDir;
# TODO: Use File::Copy instead of "rename", to make this portable:
rename($wwwDir, $savedWwwDir) or die "ERROR: Unable to save '$wwwDir' to '$savedWwwDir'\n";
}

############# RestoreWwwRoot ##############
sub RestoreWwwRoot
{
@_ == 1 || die;
my ($savedWwwDir) = @_;
# Delete existing $wwwDir if the test-script left one there:
-d $savedWwwDir or die;
if (-e $wwwDir) {
	my $rmCmd = "rm -rf '$wwwDir'";
	!system($rmCmd) or die;
	}
# TODO: Use File::Copy instead of "rename", to make this portable:
rename($savedWwwDir, $wwwDir) or die "ERROR: Unable to restore '$wwwDir' from '$savedWwwDir'\n";
}

########## EnvNotSet #########
sub EnvNotSet
{
@_ == 1 or die;
my ($var) = @_;
die "ERROR: Environment variable '$var' not set!  Please set it
by editing set_env.sh and then (in bourne shell) issuing the
command '. set_env.sh'\n";
}

