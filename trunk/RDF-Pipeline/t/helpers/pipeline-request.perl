#! /usr/bin/perl -w

# Run a test of an RDF Pipeline by using curl to invoke a URL, 
# saving the output and the apache access and error logs 
# to the $RDF_PIPELINE_WWW_DIR/test directory.
#
# Usage: 
#	pipeline-request.perl [GET/HEAD] URL
#
# where URL is the pipeline URL to invoke and GET or HEAD is the HTTP
# method to use.  The method defaults to GET if not specified.
#
# Example: 
#	pipeline-request.perl HEAD http://localhost/node/addone

use strict;

my $wwwDir = $ENV{'RDF_PIPELINE_WWW_DIR'} or &EnvNotSet('RDF_PIPELINE_WWW_DIR');
my $moduleDir = $ENV{'RDF_PIPELINE_MODULE_DIR'} or &EnvNotSet('RDF_PIPELINE_MODULE_DIR');
# chdir("$moduleDir/t") or die "ERROR: Could not chdir('$moduleDir/t')\n";

###### Configure these paths as needed:
my $apacheError = "/var/log/apache2/error.log";
my $apacheAccess = "/var/log/apache2/access.log";
my $stripDates = "$moduleDir/t/helpers/stripdates.perl";
my $filterLog = "$moduleDir/t/helpers/filterlog.perl";

# Get command line arguments:
my $method = 'GET';
$method = uc(shift @ARGV) if @ARGV > 1;
@ARGV == 1 or die "Usage: $0 [GET/HEAD] URL\n";
my $url = shift @ARGV;
$method eq "GET" || $method eq "HEAD" or die "Usage: $0 [GET/HEAD] URL\n";
$url =~ m/^http(s?)\:/ or die "Usage: $0 [GET/HEAD] URL\n";

-x $stripDates or die "ERROR: Not found or not executable: $stripDates\n";
-x $filterLog or die "ERROR: Not found or not executable: $filterLog\n";

-e $apacheError or die "ERROR: The apache error log must exist even if empty: $apacheError\n";
-e $apacheAccess or die "ERROR: The apache access log must exist even if empty: $apacheAccess\n";

chomp (my $apacheErrorLines = `wc -l < '$apacheError'`);
# warn "apacheError lines: $apacheErrorLines\n";
chomp (my $apacheAccessLines = `wc -l < '$apacheAccess'`);
# warn "apacheAccess lines: $apacheAccessLines\n";

-d "$wwwDir/test" || mkdir "$wwwDir/test" or die;

# Sleep is used here to ensure that apache has had time to write
# the log files.
my $curlOption = $method eq "HEAD" ? "-I" : "-i";
my $curlCmd = "curl $curlOption -s '$url' | '$stripDates' >> '$wwwDir/test/testout' ; sleep 1";
# warn "curlCmd: $curlCmd\n";
my $curlResult = system($curlCmd);
die "ERROR: curl failed: $curlCmd\n" if $curlResult;

my $errCmd = "tail -n +'$apacheErrorLines' '$apacheError' >> '$wwwDir/test/apacheError.log'";
# warn "errCmd: $errCmd\n";
my $errResult = system($errCmd);
die "ERROR: Failed to copy Apache error log: $errCmd\n" if $errResult;

my $logCmd = "tail -n +'$apacheAccessLines' '$apacheAccess' | '$filterLog' >> '$wwwDir/test/apacheAccess.log'";
# warn "logCmd: $logCmd\n";
my $logResult = system($logCmd);
die "ERROR: Failed to copy Apache access log: $logCmd\n" if $logResult;

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

