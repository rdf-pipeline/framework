#! /usr/bin/perl -w

# This test script is normally run from "make test", and runs
# all tests in the numbered subdirectories.
# 
# Normally "make test" would be run by "make install" *before* 
# a module is installed by "make install".  However, since this 
# module is only testable through Apache, it needs to be installed 
# before it can be tested.  (Is there another way this should be handled?)

#########################
# Set up for using Test::More.

my $wwwDir;
my $moduleDir;
my $nTests;
my @testDirs;
BEGIN {
  $wwwDir = $ENV{'RDF_PIPELINE_WWW_DIR'} or &EnvNotSet('RDF_PIPELINE_WWW_DIR');
  $moduleDir = $ENV{'RDF_PIPELINE_MODULE_DIR'} or &EnvNotSet('RDF_PIPELINE_MODULE_DIR');
  chdir("$moduleDir/t") or die "ERROR: Could not chdir('$moduleDir/t')\n";
  -e $wwwDir or die "ERROR: No WWW root: $wwwDir\n";
  -d $wwwDir or die "ERROR: WWW root is not a directory: $wwwDir\n";
  @testDirs = sort grep { -d $_ } <0*>;
  $nTests = scalar(@testDirs);
  $nTests or die "ERROR: No numbered test directories found in $moduleDir/t\n";

  ########## EnvNotSet #########
  sub EnvNotSet
    {
    @_ == 1 or die;
    my ($var) = @_;
    die "ERROR: Environment variable '$var' not set!  Please set it
    by editing set_env.sh and then (in bourne shell) issuing the 
    command '. set_env.sh'\n";
    }

  }

use Test::More tests => $nTests;
### The RDF::Pipeline module will be loaded into Apache -- not loaded here.
# BEGIN { use_ok('RDF::Pipeline') };

#########################
# This section is where our tests are run.

foreach my $testDir (@testDirs) {
    my $runCmd = "./run-test.perl '$testDir'";
    # warn "runCmd: $runCmd\n";
    is(system($runCmd), 0, $runCmd);
    }

exit 0;

