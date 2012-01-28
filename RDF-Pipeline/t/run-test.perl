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
	warn "Running $testDirs[0] ...\n";
	}

my $allPassed = 1;
foreach my $testDir (@testDirs) {
  my $testScript = "$testDir/test-script";
  if (!-e $testScript || !-x $testScript) {
    # Fail if there's no exectutable test-script
    $allPassed = 0;
    next;
    }

  ### If there is a "setup-files" directory, then use it.
  my $setupFiles = "$testDir/setup-files";
  my $needToRestoreWwwRoot = 0;
  my $savedWwwDir = "$wwwDir-SAVE";

  if (-d $setupFiles) {
    if (-e $wwwDir && !$clobber) {
      die "ERROR: savedWwwDir already exists: $savedWwwDir\n"
		if -e $savedWwwDir;
      $needToRestoreWwwRoot = 1;
      my $saveCmd = "copy-dir.perl -s '$wwwDir' '$savedWwwDir'";
      warn "saveCmd: $saveCmd\n";
      !system($saveCmd) or die "ERROR: Failed to save wwwDir: $saveCmd\n";
      }
    my $copyCmd = "copy-dir.perl -s '$setupFiles' '$wwwDir'";
    warn "copyCmd: $copyCmd\n";
    !system($copyCmd) or die "ERROR: Failed to copy setup-files: $copyCmd\n";
    }

  # Run the test-script.
  my $testCmd = "$testDir/test-script '$testDir' '$wwwDir'";
  warn "testCmd: $testCmd\n";
  my $status = system($testCmd);
  warn "Failed: $testCmd\n" if $status;
  $allPassed = 0 if $status;

  # Restore $wwwDir if necessary.
  if ($needToRestoreWwwRoot) {
    my $restoreCmd = "copy-dir.perl -s '$savedWwwDir' '$wwwDir'";
    warn "restoreCmd: $restoreCmd\n";
    !system($restoreCmd) or die "ERROR: Failed to restore wwwDir: $restoreCmd\n";
    }
  }

exit 0 if $allPassed;
exit 1;

