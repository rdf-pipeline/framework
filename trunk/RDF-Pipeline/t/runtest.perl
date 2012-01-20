#! /usr/bin/perl -w

# Run a test by using curl to invoke a URL, saving the output and
# the apache access and error logs to the WWW directory, so that
# it will be easy to regression test by using diff -r to compare 
# the directory against known good directory contents.
#
# This script is expected to be run from the RDF-Pipeline directory,
# i.e., the directory above the t directory, and will typically
# be run from make.

use strict;

# Configure these paths as needed:
my $basePath = "/home/dbooth/rdf-pipeline/trunk/www";
my $apacheError = "/var/log/apache2/error.log";
my $apacheAccess = "/var/log/apache2/access.log";
my $stripDates = "t/stripdates.perl";
my $filterLog = "t/filterlog.perl";

# Get command line arguments:
my $method = 'get';
$method = lc(shift @ARGV) if @ARGV > 1;
@ARGV == 1 or die "Usage: $0 [get/head] URL\n";
my $url = shift @ARGV;
$method eq "get" || $method eq "head" or die "Usage: $0 [get/head] URL\n";
$url =~ m/^http(s?)\:/ or die "Usage: $0 [get/head] URL\n";

-x $stripDates or die "ERROR: Helper program not found or not executable: $stripDates\n  Did you run this script from the wrong directory?\n  It must be run from the RDF-Pipeline directory, as if by make.\n";
-x $filterLog or die "ERROR: Helper program not found or not executable: $filterLog\n  Did you run this script from the wrong directory?\n  It must be run from the RDF-Pipeline directory, as if by make.\n";

-e $apacheError or die "ERROR: The apache error log must exist even if empty: $apacheError\n";
-e $apacheAccess or die "ERROR: The apache access log must exist even if empty: $apacheAccess\n";

chomp (my $apacheErrorLines = `wc -l < '$apacheError'`);
# warn "apacheError lines: $apacheErrorLines\n";
chomp (my $apacheAccessLines = `wc -l < '$apacheAccess'`);
# warn "apacheAccess lines: $apacheAccessLines\n";

my $curlCmd = "curl -i '$url' | '$stripDates' > '$basePath/test/testout' ; sleep 1";
warn "curlCmd: $curlCmd\n";
system($curlCmd);

my $errCmd = "tail -n +'$apacheErrorLines' '$apacheError' > '$basePath/test/apacheError.log'";
# warn "errCmd: $errCmd\n";
system($errCmd);

my $logCmd = "tail -n +'$apacheAccessLines' '$apacheAccess' | '$filterLog' > '$basePath/test/apacheAccess.log'";
# warn "logCmd: $logCmd\n";
system($logCmd);

