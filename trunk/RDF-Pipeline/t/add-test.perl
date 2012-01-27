#! /usr/bin/perl -w

# Add a test case to the test suite by copying the current
# state of the Apache WWW root directory to a new test directory,
# and then run it via RDF-Pipeline/t/runtest.perl .

use strict;

@ARGV == 1 or die "Usage: $0 URL
where URL is the RDF Pipeline test URL to invoke for the new test.\n";
my $url = shift @ARGV;

my $wwwDir = $ENV{'RDF_PIPELINE_WWW_DIR'} or &EnvNotSet('RDF_PIPELINE_WWW_DIR');
my $devDir = $ENV{'RDF_PIPELINE_DEV_DIR'} or &EnvNotSet('RDF_PIPELINE_DEV_DIR');
my $moduleDir = "$devDir/RDF-Pipeline";

# Make the new test dir:
chdir("$moduleDir/t") or die "ERROR: Could not chdir('$moduleDir/t')\n";
my $maxDir = 0;
map {m/\A\d+/; $maxDir = $& if $& > $maxDir; } grep { -d $_ } <0*>;
my $dir = sprintf("%04d", $maxDir+1);
($dir =~ m/^0/) or die "ERROR: Test number exceeded 999.  The numbered test directories
  must be renamed to add another digit, and this test script 
  ( $0 ) must be 
  updated to generate another digit.\n";
mkdir($dir) or die;

# Generate an initial test-script, that can later be customized:
my $content = &ReadFile("<$moduleDir/t/helpers/test-script-template") or die;
$content =~ s/BEGIN_TEMPLATE_WARNING(.|\n)*END_TEMPLATE_WARNING\s*\n(\n?)//ms;
$content =~ s/\$URL\b/$url/g;
&WriteFile("$dir/test-script", $content);
my $chmodCmd = "chmod +x '$dir/test-script'";
# warn "chmodCmd: $chmodCmd\n";
!system($chmodCmd) or die;

# Capture the initial WWW state as the setup-files:
my $setupFiles = "$dir/setup-files";
my $setupCmd = "helpers/copy-dir.perl -s '$wwwDir' '$setupFiles'";
# warn "setupCmd: $setupCmd\n";
!system($setupCmd) or die;

print "Created test directory: $dir\n\n";

print "Running test $dir , which should fail because
expected-files have not yet been created ...\n";
my $runCmd = "./run-test.perl '$dir'";
# warn "runCmd: $runCmd\n";
system($runCmd);

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

############ WriteFile ##########
# Write a file.  Examples:
#   &WriteFile("/tmp/foo", $all)   # Same as &WriteFile(">/tmp/foo", all);
#   &WriteFile(">$f", $all)
#   &WriteFile(">>$f", $all)
sub WriteFile
{
@_ == 2 || die;
my ($f, $all) = @_;
my $ff = (($f =~ m/\A\>/) ? $f : ">$f");    # Default to ">$f"
my $nameOnly = $ff;
$nameOnly =~ s/\A\>(\>?)//;
open(my $fh, $ff) || die;
print $fh $all;
close($fh) || die;
}

############ ReadFile ##########
# Read a file and return its contents or "" if the file does not exist.
# Examples:
#   my $all = &ReadFile("<$f")
sub ReadFile
{
@_ == 1 || die;
my ($f) = @_;
open(my $fh, $f) || return "";
my $all = join("", <$fh>);
close($fh) || die;
return $all;
}


