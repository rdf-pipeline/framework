#! /usr/bin/perl -w

# This script runs one or more tests in the suite of numbered tests.
# It exits with 0 status iff all tests pass.
#
# Usage:
#
#  	./run-test.perl [-q] [nnnn] ...
#
# where nnnn is the numbered test directory you wish to run, defaulting
# to the highest numbered test directory if none is specified.  
#
# Option:
#	-q	Quiet.  Less verbose output.

my $quietOption = 0;
if (@ARGV && $ARGV[0] eq "-q") {
	shift @ARGV;
	$quietOption = 1;
	}

my $wwwDir = $ENV{'RDF_PIPELINE_WWW_DIR'} or &EnvNotSet('RDF_PIPELINE_WWW_DIR');
my $devDir = $ENV{'RDF_PIPELINE_DEV_DIR'} or &EnvNotSet('RDF_PIPELINE_DEV_DIR');
my $moduleDir = "$devDir/RDF-Pipeline";
my $testsDir = "$moduleDir/t/tests";
chdir($testsDir) or die "ERROR: Could not chdir('$testsDir')\n";

my @tDirs = @ARGV;
if (!@tDirs) {
	@tDirs = sort grep { -d $_ } <0*>;
	@tDirs or die "ERROR: No numbered test directories found in $testsDir\n";
	@tDirs = ( $tDirs[@tDirs-1] );		# The last one.
	warn "Running $tDirs[0] ...\n";
	}

my $tmpDir = "/tmp/rdfp";
-e $tmpDir || mkdir($tmpDir) || die;

# Diffs file will hold diffs of *all* tests run in the loop below,
# so clear it out first:
my $tmpDiff = "$tmpDir/diffs.txt";
!system("/bin/cat /dev/null > '$tmpDiff'") || die;

my $allPassed = 1;
foreach my $tDir (@tDirs) {
  $tDir =~ s|\/$||;
  warn "=================== $tDir ===================\n" if !$quietOption;
  !system("/bin/echo '===================' '$tDir' '===================' >> '$tmpDiff'") || die;

  my $testScript = "$tDir/test-script";
  if (!-e $testScript || !-x $testScript) {
    # Fail if there's no executable test-script
    warn "Failed -- no test-script: $tDir\n";
    $allPassed = 0;
    next;
    }

  my $tmpTDir = "$tmpDir/$tDir";
  -e $tmpTDir || mkdir($tmpTDir) || die;

  -e $wwwDir || mkdir($wwwDir) || die "ERROR: Failed to mkdir $wwwDir\n";

  ### If there is a "setup-files" directory, then use it.
  my $setupFiles = "$tDir/setup-files";
  if (-d $setupFiles) {
    my $copyCmd = "$moduleDir/t/helpers/copy-dir.perl '$setupFiles' '$wwwDir'";
    # warn "copyCmd: $copyCmd\n";
    !system($copyCmd) or die "ERROR: Failed to copy setup-files: $copyCmd\n";
    }

  # Clear out old $wwwDir/test files:
  !system("$moduleDir/t/helpers/copy-dir.perl '/dev/null' '$wwwDir/test'") or die;

  # Run the test-script.
  my $testCmd = "cd '$tDir' ; ./test-script '$wwwDir'";
  # warn "Running test: $testCmd\n" if -e "$tDir/.svn";
  my $status = system($testCmd);
  warn "Failed test-script: $tDir\n" if $status;
  $allPassed = 0 if $status;
  if ($status) {
    $allPassed = 0;
    next;
    }

  # Copy actual result files to tmp dirs for filtering:
  my $actualUnfilteredDir = "$tmpTDir/actual-files";
  my $actualFilteredDir = "$tmpTDir/actual-filtered";
  !system("$moduleDir/t/helpers/copy-dir.perl '$wwwDir' '$actualUnfilteredDir'") || die;
  !system("$moduleDir/t/helpers/copy-dir.perl '$wwwDir' '$actualFilteredDir'") || die;

  # Filter all actual-files
  my $aFindCmd = "find '$actualFilteredDir' -type f -exec '$moduleDir/t/helpers/filter-actual.perl' '{}' \\;";
  # warn "aFindCmd: $aFindCmd\n";
  !system($aFindCmd) || die;

  # Fail if the result files contain the word "error" or "died":
  if (!-e "$tDir/IgnoreErrors.txt"
	&& (!system("grep -r -m 1 -i '\\berror\\b' '$actualFilteredDir'")
	    || !system("grep -r -m 1 -i '\\bdied\\b' '$actualFilteredDir'")))
        {
	warn "Failed 'error' or 'died' check: $tDir\n";
	$allPassed = 0;
	}

  # Copy expected-files to tmp dirs for filtering:
  if (!-e "$tDir/expected-files") {
    # Fail if there's no expected-files
    warn "Failed -- no expected-files: $tDir\n";
    $allPassed = 0;
    next;
    }
  my $expectedFilteredDir = "$tmpTDir/expected-filtered";
  !system("$moduleDir/t/helpers/copy-dir.perl '$tDir/expected-files' '$expectedFilteredDir'") || die;

  # Filter all expected-files
  my $eFindCmd = "find '$expectedFilteredDir' -type f -exec '$moduleDir/t/helpers/filter-expected.perl' '{}' \\;";
  # warn "eFindCmd: $eFindCmd\n";
  !system($eFindCmd) || die;

  # Compare the (filtered) expected with the (filtered) actual files:
  my $checkCmd = "$moduleDir/t/helpers/compare-results.perl '$expectedFilteredDir' '$actualFilteredDir' >> $tmpDiff";
  # warn "Running check: $checkCmd\n" if -e "$tDir/.svn";
  my $diffStatus = system($checkCmd);
  warn "Failed comparison: $tDir\n  Diffs file: $tmpDiff\n" if $diffStatus;
  $allPassed = 0 if $diffStatus;

  }

exit 0 if $allPassed;
exit 1;

