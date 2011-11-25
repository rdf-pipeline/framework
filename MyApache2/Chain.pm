#! /usr/bin/perl -w 

# Command line test:
#  MyApache2/Chain.pm --test --debug http://localhost/hello

# TODO:
# 1. Put nodes and caches in separate directories: 
#	/node  		-- for nodes
#	/cache 		-- for cache files maintained directly by nodes
#	/hidden		-- for hidden cache files (framework generated)

#file:MyApache2/Chain.pm
#----------------------
# Apache2 uses multiple threads and a pool of PerlInterpreters.
# Code below that is outside of any function will be executed once
# for each PerlInterpreter instance when it starts.  Since existing
# PerlInterpreter instances will be used first, a new instance will 
# only be started when all existing instances are busy.  Also, in
# spite of being threaded, variables are separate between 
# instances -- mod_perl does this somehow -- so one instance will not see
# changes made to another instance's variables unless something
# special is done to make them shared.  (Maybe threads::shared?
# Or Apache::Session::File?)  This means that HTTP response headers
# cannot be cached in memory (without doing something special),
# because they won't be visible across instances.

package MyApache2::Chain;

# See http://perl.apache.org/docs/2.0/user/intro/start_fast.html
use strict;
use warnings;
use Apache2::RequestRec (); # for $r->content_type
use Apache2::SubRequest (); # for $r->internal_redirect
use Apache2::RequestIO ();
# use Apache2::Const -compile => qw(OK SERVER_ERROR NOT_FOUND);
use Apache2::Const -compile => qw(:common REDIRECT HTTP_NO_CONTENT DIR_MAGIC_TYPE HTTP_NOT_MODIFIED);
use Apache2::Response ();
use APR::Finfo ();
use APR::Const -compile => qw(FINFO_NORM);

use HTTP::Date;
use APR::Table ();
use LWP::UserAgent;
use HTTP::Status;
use Apache2::URI ();
use URI::Escape;

my $configFile = "/home/dbooth/rdf-pipeline/trunk/pipeline.n3";
my $ontFile = "/home/dbooth/rdf-pipeline/trunk/ont.n3";
my $internalsFile = "/home/dbooth/rdf-pipeline/trunk/internals.n3";
my $prefix = "http://purl.org/pipeline/ont#";	# Pipeline ont prefix
$ENV{DOCUMENT_ROOT} ||= "/home/dbooth/rdf-pipeline/trunk/www";	# Set if not set
### TODO: Set $baseUri automatically
$ENV{SERVER_NAME} ||= "localhost";
my $baseUri = "http://$ENV{SERVER_NAME}/";
my $PCACHE = "PCACHE"; # Used in forming env vars

my $logFile = "/tmp/rdf-pipeline-log.txt";
# unlink $logFile || die;

### Package variables:
my %config = ();		# Maps: "?s ?p" --> "v1 v2 ... vn"
my %configValues = ();		# Maps: "?s ?p" --> {v1 => 1, v2 => 1, ...}
my %cachedResponse = ();	# Previous HTTP response to GET or HEAD.
				# Key: "$thisUri $supplierUri"
my $configLastModified = 0;
my $ontLastModified = 0;
my $internalsLastModified = 0;

&PrintLog("="x30 . " START8 " . "="x30 . "\n");
&PrintLog(`date`);

if (1)
{
  use Apache::Session::File;

  my %session;
  my $sessionIdFile = "/tmp/rdf-pipeline-sessionID";
  my $sessionId = &ReadFile($sessionIdFile);
  $sessionId = undef if !$sessionId;
  my $isNewSessionId = !$sessionId;
  #make a fresh session for a first-time visitor
 tie %session, 'Apache::Session::File', $sessionId, {
    Directory => '/tmp/rdf-pipeline-sessions',
    LockDirectory   => '/tmp/rdf-pipeline-locks',
 };
$sessionId ||= $session{_session_id};

&WriteFile($sessionIdFile, $sessionId) if $isNewSessionId;
&PrintLog("sessionId: $sessionId\n");

  #...time passes...

$session{date} ||= `date`;
my $testShared = $session{date};
&PrintLog("testShared: $testShared\n");
}

use Getopt::Long;
my $debug = 1;
my $test;
&GetOptions("test" => \$test,
	"debug" => \$debug,
	);
&PrintLog("ARGV: @ARGV\n") if $test || $debug;

my $testUri = shift @ARGV || "http://localhost/chain";
if ($test)
	{
	my $code = &handler("foo");
	&PrintLog("\nReturn code: $code\n");
	exit 0;
	}

#######################################################################
###################### Functions start here ###########################
#######################################################################

########## IsLocalFileNode ############
# Returns relative part of $uri if $uri is a local FileNode; otherwise 0.
sub IsLocalFileNode
{
my $uri = shift;
my $rel = $uri;
my $baseUriPattern = quotemeta($baseUri);
return $rel if ( $configValues{"$uri a"}->{FileNode} &&  $rel =~ s/\A$baseUriPattern//);
return 0;
}

########## PrintLog ############
sub PrintLog
{
open(my $fh, ">>$logFile") || die;
print $fh @_;
close($fh);
return 1;
}

##################### handler #######################
# handler will be called by apache2 to handle any request that has
# been specified in /etc/apache2/sites-enabled/000-default .
sub handler 
{
&PrintLog("-"x20 . "handler" . "-"x20 . "\n");
my $ret = &RealHandler(@_);
&PrintLog("Handler returning: $ret\n");
return $ret;
}

##################### RealHandler #######################
sub RealHandler 
{
my $r = shift;
# $debug = ($r && $r->uri =~ m/c\Z/);
# $r->content_type('text/plain') if $debug && !$test;
if (0 && $debug) {
	&PrintLog("Environment variables:\n");
	foreach my $k (sort keys %ENV) {
		&PrintLog("$k = " . $ENV{$k} . "\n");
		}
	&PrintLog("\n");
	}
&PrintLog("RealHandler called: " . `date`);

# Reload config file?
my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
	      $atime,$mtime,$ctime,$blksize,$blocks)
		  = stat($configFile);
# Avoid unused var warning:
($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
	      $atime,$mtime,$ctime,$blksize,$blocks)
	= ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
	      $atime,$mtime,$ctime,$blksize,$blocks);
my $cmtime = $mtime;
($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
	      $atime,$mtime,$ctime,$blksize,$blocks)
		  = stat($ontFile);
my $omtime = $mtime;
($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
	      $atime,$mtime,$ctime,$blksize,$blocks)
		  = stat($internalsFile);
my $imtime = $mtime;
if ($configLastModified != $cmtime
		|| $ontLastModified != $omtime) {
	# Reload config file.
	&PrintLog("Reloading config file: $configFile\n") if $debug;
	$configLastModified = $cmtime;
	$ontLastModified = $omtime;
	$internalsLastModified = $imtime;
	%config = &CheatLoadN3($ontFile, $configFile);
	%configValues = map { 
		my $hr; 
		map { $hr->{$_}=1; } split(/\s+/, ($config{$_}||"")); 
		($_, $hr)
		} keys %config;
	&PrintLog("configValues:\n") if $debug;
	foreach my $sp (sort keys %configValues) {
		my $hr = $configValues{$sp};
		foreach my $v (sort keys %{$hr}) {
			&PrintLog("  $sp $v\n") if $debug;
			}
		}

	# &PrintLog("Got here!\n"); 
	# return Apache2::Const::OK;
	%config || return Apache2::Const::SERVER_ERROR;
	}
if (0 && $debug) {
	&PrintLog("Config file $configFile:\n");
	foreach my $k (sort keys %config) {
		&PrintLog("  $k = " . $config{$k} . "\n");
		}
	&PrintLog("\n");
	&PrintLog("-" x 60 . "\n") if $debug;
	}
my $thisUri = $testUri;
# construct_url omits the query params though
$thisUri = $r->construct_url() if !$test; 
&PrintLog("thisUri: $thisUri\n") if $debug;
my @types = split(/\s+/, ($config{"$thisUri a"}||"") );
&PrintLog("ERROR: $thisUri is not a Node.  types: @types\n") if $debug && !(grep {$_ && $_ eq "Node"} @types);
my $subtype = (grep {$_ && $_ ne "Node"} @types)[0] || "";
&PrintLog("subtype: $subtype\n") if $debug;
# return Apache2::Const::DECLINED if !$subtype;
return Apache2::Const::NOT_FOUND if !$subtype;

if ($subtype eq "FileNode") { 
	&PrintLog("Dispatching to HandleFileNode\n") if $debug;
	return &HandleFileNode($r, $thisUri);
	}
elsif ($subtype eq "JenaNode") { 
	# Not yet implemented
	&PrintLog("Unimplemented: $subtype\n") if $debug;
	return Apache2::Const::SERVER_ERROR;
	}
elsif ($subtype eq "MysqlNode") { 
	# Not yet implemented
	&PrintLog("Unimplemented: $subtype\n") if $debug;
	return Apache2::Const::SERVER_ERROR;
	}
else { 
	&PrintLog("Unknown Node subtype: $subtype\n") if $debug;
	return Apache2::Const::SERVER_ERROR; 
	}
}


############## HandleFileNode ###############
# Uses global %config.
sub HandleFileNode
{
my $r = shift;
my $thisUri = shift || die;
my $cache = $config{"$thisUri cache"} || "";
my $inputs = $config{"$thisUri inputs"} || "";
my $parameters = $config{"$thisUri parameters"} || "";
my $dependsOn = $config{"$thisUri dependsOn"} || "";
my $updater = $config{"$thisUri updater"} || "";
my @inputs = ($inputs ? split(/\s+/, $inputs) : ());
my @parameters = ($parameters ? split(/\s+/, $parameters) : ());
my @dependsOn = ($dependsOn ? split(/\s+/, $dependsOn) : ());

# Make absolute $cache and $updater:
$cache = "/$cache" if $cache && $cache !~ m|\A\/|;
$updater = "$ENV{DOCUMENT_ROOT}/$updater" if $updater && $updater !~ m|\A\/|;

&PrintLog("Initial cache: $cache\n") if $debug;
my $useStdout = !$cache;
&PrintLog("useStdout: $useStdout\n") if $debug;
if ($useStdout) {
	# Make a cache filename to use.
	my $t = "$thisUri";
	my $pBaseUri = quotemeta($baseUri);
	$t =~ s/\A$pBaseUri//;		# Strip baseUri
	$t =~ s|\A\/+||;		# Strip leading /
	#### Quick and dirty POC hack, which for production should
	#### use proper escaping and put the file somewhere else:
	$t =~ s/[^a-zA-Z0-9\.\-\_]/_/g;	# Change bad chars to _
	$cache = "/$t-stdout";
	}
&PrintLog("cache after useStdout block: $cache\n") if $debug;
my $cacheFullPath = $ENV{DOCUMENT_ROOT} . $cache;
&PrintLog("cacheFullPath: $cacheFullPath\n") if $debug;

&PrintLog("inputs: $inputs\n") if $debug;
my $atInputs = join(" ", @inputs);
&PrintLog("\@inputs: $atInputs\n") if $debug;
&PrintLog("parameters: $parameters\n") if $debug;
my $atParameters = join(" ", @parameters);
&PrintLog("\@parameters: $atParameters\n") if $debug;
&PrintLog("dependsOn: $dependsOn\n") if $debug;
my $atDependsOn = join(" ", @dependsOn);
&PrintLog("\@dependsOn: $atDependsOn\n") if $debug;
&PrintLog("updater: $updater\n") if $debug;

# Test of getting query params (and it works):
my $args = $r->args() || "";
&PrintLog("Query string: $args\n") if $debug;
my %args = &ParseQueryString($args);
foreach my $k (keys %args) {
	my $v = $args{$k};
	&PrintLog("	$k = $v\n") if $debug;
	}

if ((!-e $cacheFullPath) || &AnyChanged($thisUri, @dependsOn))
	{
	# Run updater if there is one:
	if ($updater) {
		if (!-x $updater) {
			&PrintLog("ERROR: updater is not executable by web server\n") if $debug;
			# &PrintLog("Perhaps you need to setuid:  chmod a+s $updater\n";
			}
		# The FileNode updater args will be local filenames for all
		# inputs and parameters.
		my @inputFilenames = &LocalFilenames($thisUri, @inputs);
		my @parameterFilenames = &LocalFilenames($thisUri, @parameters);
		&PrintLog("inputFilenames: @inputFilenames\n");
		&PrintLog("parameterFilenames: @parameterFilenames\n");
		my $tmp = "/tmp/updater-err$$";
		# my $cmd = "/home/dbooth/rdf-pipeline/trunk/setuid-wrapper $updater $thisUri $cacheFullPath $inputs $parameters > $tmp 2>&1";
		# my $cmd = "$updater $thisUri $cacheFullPath $inputs $parameters > $tmp 2>&1";
		# $cmd = "$updater $thisUri $inputs $parameters > $cacheFullPath 2> $tmp"
			# if $useStdout;
		# TODO: Check for unsafe chars before invoking $cmd
		my $cmd = "( export $PCACHE\_THIS_URI=\"$thisUri\" ; $updater $cacheFullPath @inputFilenames @parameterFilenames > $tmp 2>&1 )";
		$cmd = "( export $PCACHE\_THIS_URI=\"$thisUri\" ; $updater @inputFilenames @parameterFilenames > $cacheFullPath 2> $tmp )"
			if $useStdout;
		&PrintLog("cmd: $cmd\n") if $debug;
		my $result = (system($cmd) >> 8);
		my $saveError = $?;
		&PrintLog("Updater returned " . ($result ? "error code:" : "success:") . " $result.\n");
		if (-s $tmp) {
			&PrintLog("Updater stderr" . ($useStdout ? "" : " and stdout") . ":\n[[\n") if $debug;
			# system("cat $tmp >> $logFile") if $debug;
			&PrintLog(&ReadFile("<$tmp")) if $debug;
			&PrintLog("]]\n") if $debug;
			}
		unlink $tmp;
		if ($result) {
			&PrintLog("UPDATER ERROR: $saveError\n") if $debug;
			return Apache2::Const::SERVER_ERROR;
			}
		}
	elsif (@inputs || @parameters) {
		&PrintLog("ERROR: inputs or parameters without an updater.\n") if $debug;
		return Apache2::Const::SERVER_ERROR;
		}
	}
else	{

	&PrintLog("HandleFileNode: No dependsOn changed -- updater not run.\n") if $debug;
	}

# Manually set the headers, so that the Content-Type can be
# set properly.  
my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
		      $atime,$mtime,$ctime,$blksize,$blocks)
			  = stat($cacheFullPath);
# Avoid unused var warning:
($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
		      $atime,$mtime,$ctime,$blksize,$blocks) =
($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
		      $atime,$mtime,$ctime,$blksize,$blocks);
&PrintLog("HandleFileNode: size: $size\n") if $debug;
my $lm = time2str($mtime);
&PrintLog("HandleFileNode: Last-Modified: $lm\n") if $debug;

&PrintLog("HandleFileNode: Trying sendfile...\n") if $debug;
# We must set headers explicitly here.
# This works for returning 304:
# $r->status(Apache2::Const::HTTP_NOT_MODIFIED);
$r->content_type('text/plain');
# This works also: $r->content_type('application/rdf+xml');
$r->set_content_length($size);
$r->set_last_modified($mtime);
my $cacheUri = $r->construct_url($cache); 
$r->headers_out->set('Content-Location' => $cacheUri); 
# TODO: Set proper ETag, perhaps using Time::HiRes mtime.
# "W/" prefix on ETag means that it is weak.
# $r->headers_out->set('ETag' => 'W/"640e9-a-4b269027adb7d;4b142a708a8ad"'); 
$r->headers_out->set('ETag' => 'W/"fake-etag"'); 
# Did not work: $r->sendfile($cache);
# sendfile seems to want a full file system path:
$r->sendfile($cacheFullPath);
my $m = $r->method;
my $ho = $r->header_only;
&PrintLog("HandleFileNode: method: $m header_only: $ho\n") if $debug;

# These work:
# $r->internal_redirect("/fchain.txt") if !$debug;
# $r->internal_redirect("http://localhost/fchain.txt");
# Apache2::Const::OK indicates that this handler ran successfully.
# It is not the HTTP response code being returned.  See:
# http://perl.apache.org/docs/2.0/user/handlers/intro.html#C_RUN_FIRST_
return Apache2::Const::OK;
}

################### ParseQueryString #################
# Returns a hash of key/value pairs, with the values unescaped.
# If the same key appears more than once in the query string,
# the last value given wins.
sub ParseQueryString
{
my $args = shift || "";
my %args = map { 
	my ($k,$v) = split(/\=/, $_); 
	$v = "" if !defined($v); 
	$k ? ($k, uri_unescape($v)) : ()
	} split(/\&/, $args);
return %args;
}

################### LocalFilenames #####################
# For each given input or parameter URI $uri, return a filename 
# that is local to $thisUri and contains the current cached
# content of $uri.
sub LocalFilenames
{
my $thisUri = shift;
my @ipUris = @_;	# Input or parameter URIs
&PrintLog("Localfilenames($thisUri, @ipUris) called\n");
my @filenames = ();
foreach my $uri (@_) {
	my $f = &IsLocalFileNode($uri);
	if ($f) {
		# Local FileNode.  Optimize by returning its existing
		# cache filename.
		&PrintLog("Localfilenames: FileNode local to this host: $uri\n");
		# Local to this host.  Optimize by using the cacheFile
		# already created for $uri.
		##### TODO: Finish this properly:
		push(@filenames, $ENV{DOCUMENT_ROOT} . "/$f-stdout");
		}
	else	{
		&PrintLog("LocalFilenames: Not yet implemented\n");
		die;
		my $res = &CachingRequest("GET", @_) || return undef;
		return $res->decoded_content();
		}
	}
return @filenames;
}

################### CachingGet #####################
sub CachingGet
{
my $res = &CachingRequest("GET", @_) || return undef;
return $res->decoded_content();
}

################### CachingRequest #####################
# Issue HTTP "HEAD" or "GET" request from $thisUri to $supplierUri,
# caching the response in global %cachedResponse.
# The %cachedResponse is used both to make the request conditional
# and to return the previously cached content if 304 Not Modified is returned.
# TODO: Change to use files to cache the content, so that the filenames
# can be passed directly to updaters as arguments.
sub CachingRequest
{
my $method = shift @_;
my $thisUri = shift @_;
my $relativeUri = shift @_;	# Possibly relative supplier URI
my $supplierUri = $relativeUri;	# Absolute supplier URI
$supplierUri = $baseUri . $relativeUri if $relativeUri !~ m/\A[a-z]+\:/;
my $ncr = scalar(keys %cachedResponse);
&PrintLog("CachingRequest: Called with $method $thisUri $relativeUri absolute: $supplierUri cachedResponse size: $ncr\n");
my $key = "$thisUri $supplierUri";
my $ua = LWP::UserAgent->new;
$ua->agent("$0/0.1 " . $ua->agent);
my $req = HTTP::Request->new($method => $supplierUri);
if (!$req) {
	&PrintLog("ERROR: CachingRequest failed to create new $method HTTP:Request from $thisUri to $supplierUri\n");
	die;
	}
# Set If-Modified-Since and If-None-Match headers in request, if available.
# If the current request is GET then we have to make sure that the 
# old response ($oldRes) contains content before we can send a conditional 
# request, otherwise the result may come back as "not modified" and we
# would not have the content to return.  If the current request is HEAD
# then we don't need content anyway, so it doesn't matter if the old 
# response has content.
my $oldRes = $cachedResponse{$key} || "";
&PrintLog("CachingRequest: oldRes: $oldRes\n");
my $isConditional = "";
if ($oldRes && ($oldRes->code == RC_OK)
    && ($method eq "HEAD" || $oldRes->content) ) {
	my $oldLM = $oldRes->header('Last-Modified') || "";
	my $oldETag = $oldRes->header('ETag') || "";
	&PrintLog("CachingRequest: $method Request from $thisUri to $supplierUri settting oldLM: $oldLM oldETag $oldETag\n");
	$req->header('If-Modified-Since' => $oldLM) if $oldLM;
	$req->header('If-None-Match' => $oldETag) if $oldETag;
	$isConditional = "conditional" if $req->header('If-Modified-Since');
	}
# Send the request, recursively if it's a local FileNode.
my $reqString = $req->as_string;
my $isLocal = &IsLocalFileNode($supplierUri);
my $local = ($isLocal ? "local" : "NON-local");
&PrintLog("CachingRequest: Sending $local $isConditional $method Request from $thisUri to $supplierUri :\n[[\n$reqString\n]]\n");
# TODO: This optimization for a local node is not right/done yet, 
# because HandleFileNode currently does
# an internal_redirect, whereas that should only be done for the
# original request -- not for recursive requests.
# my $res = ($isLocal ? &HandleFileNode($req, $supplierUri) : $ua->request($req));
my $res = $ua->request($req);
if (!$res) {
	&PrintLog("CachingRequest: $isConditional $method Request from $thisUri to $supplierUri returned null response!\n");
	delete $cachedResponse{$key};
	return undef;
	}
my $code = $res->code;
if (($code != RC_NOT_MODIFIED) && !$res->is_success) {
	&PrintLog("CachingRequest: $isConditional $method Request from $thisUri to $supplierUri failed: "
		. $res->status_line . "\n");
	delete $cachedResponse{$key};
	return undef;
	}
&PrintLog("CachingRequest: $isConditional $method Request from $thisUri to $supplierUri returned $code\n");
# Return the cached content if the response was 304 Not Modified.
# I'm not sure here exactly which fields I should set from $oldRes, but from
# http://www.w3.org/Protocols/rfc2616/rfc2616-sec13.html#sec13.5 
# http://www.w3.org/Protocols/rfc2616/rfc2616-sec9.html#sec9.4
# http://search.cpan.org/~gaas/HTTP-Message-6.01/lib/HTTP/Message.pm
# it looks like I should only set the "content" field.
$res->content($oldRes->content) 
	if ($code == RC_NOT_MODIFIED) && !($res->content);
# Only update $cachedResponse if it changed:
$cachedResponse{$key} = $res if ($code != RC_NOT_MODIFIED);
return $res;
}

################### Changed #####################
# Issue HTTP "GET" request from $thisUri to $supplierUri to
# see if it changed since the last GET between these URIs.
# Uses global %cachedResponse.
sub Changed
{
my $thisUri = shift @_;
my $supplierUri = shift @_;
&PrintLog("  Changed: Called with $thisUri $supplierUri\n");
my $res = &CachingRequest("GET", $thisUri, $supplierUri) || return undef;
my $code = $res->code;
&PrintLog("  Changed: GET Request from $thisUri to $supplierUri returned $code\n");
return 0 if $code == RC_NOT_MODIFIED;
return 1;
}


################### AnyChanged #####################
# Update the caches of all of the given @supplierUris, and return 1
# if any of them had changed since $thisUri's output was last updated.
sub AnyChanged
{
my $thisUri = shift @_;
my @supplierUris = @_;
&PrintLog("AnyChanged called with thisUri: $thisUri supplierUris: @supplierUris\n");
my %seen = ();
my $changed = 0;
foreach my $supplierUri (@supplierUris)
        {
	# &PrintLog("  AnyChanged checking $thisUri $supplierUri\n");
	next if $seen{$supplierUri};
        if (&Changed($thisUri, $supplierUri)) {
		$changed = 1;
		}
	$seen{$supplierUri} = 1;
        }
&PrintLog("AnyChanged($thisUri @supplierUris) returning: $changed\n");
return $changed;
}

################### CheatLoadN3 #####################
# Not proper n3 parsing, but good enough for this purpose.
# Returns a hash map that maps: "$s $p" --> $o
# Global $prefix is also stripped off from terms.
# Example: "http://localhost/a fileCache" --> "c/cp-cache.txt"
sub CheatLoadN3
{
my $ontFile = shift;
my $configFile = shift;
$configFile || die;
-e $configFile || die;
my $cwmCmd = "cwm --n3=ps $ontFile $internalsFile $configFile --think |";
&PrintLog("cwmCmd: $cwmCmd\n");
open(my $fh, $cwmCmd) || die;
my $nc = " " . join(" ", map { chomp; 
	s/^\s*\#.*//; 		# Strip full line comments
	s/\.(\W)/ .$1/g; 	# Add space before period except in a word
	$_ } <$fh>) . " ";
close($fh);
# &PrintLog("-" x 60 . "\n") if $debug;
# &PrintLog("nc: $nc\n") if $debug;
# &PrintLog("-" x 60 . "\n") if $debug;
while ($nc =~ s/\{[^\}]*\}/ /) {}	# Delete subgraphs: { ... } 
my @triples = grep { m/\S/ } 
	map { s/[()\"]/ /g; 		# Strip: ( ) "
		s/<([^<>\s]+)>/$1/g; 	# Strip < > but Keep empty <>
		s/\A\s+//; s/\s+\Z//; 
		s/\A\s*\@.*//; s/\s\s+/ /g; $_ } 
	split(/\s+\./, $nc);
my $nTriples = scalar @triples;
&PrintLog("nTriples: $nTriples\n") if $debug;
# &PrintLog("-" x 60 . "\n") if $debug;
# &PrintLog("triples: \n" . join("\n", @triples) . "\n") if $debug;
&PrintLog("-" x 60 . "\n") if $debug;
my %config = ();
foreach my $t (@triples) {
	# Strip ont prefix from terms:
	$t = join(" ", map { s/\A$prefix([a-zA-Z])/$1/;	$_ }
		split(/\s+/, $t));
	my ($s, $p, $o) = split(/\s+/, $t, 3);
	next if !$o;
	# $o may actually be a space-separate list of URIs
	&PrintLog("  s: $s p: $p o: $o\n") if $debug;
	# Append additional values for the same property:
	$config{"$s $p"} = "" if !exists($config{"$s $p"});
	$config{"$s $p"} .= " " if $config{"$s $p"};
	$config{"$s $p"} .= $o;
	}
&PrintLog("-" x 60 . "\n") if $debug;
return %config;
}

############ InferFileNodeCaches ############
# For inputs and parameters, infer default caches.
##### UNTESTED!  And it assumes a function FileNodeCache that
# has not been written yet.  FileNodeCache is supposed to return
# a local filename of whatever input/parameter cache is used
# from $s to $ip.
sub InferFileNodeCaches
{
&PrintLog("InferFileNodeCaches called.\n");
my %config = @_;
# For convenience, make a ternary predicate map.
my %ternary = ();	# Maps: "$s $p $v1" -> $v2
			# from ternary predicate triple: $s $p ($v1 $v2) .
foreach my $sp (sort keys %config) {
	my @v = split(/\s+/, $config{$sp});
	next if @v <= 1;
	my $v = shift @v;
	my $cdr = join(" ", @v);
	# Append additional values (space separated) for the same property:
	$ternary{"$sp $v"} = "" if !exists($ternary{"$sp $v"});
	$ternary{"$sp $v"} .= " " if $ternary{"$sp $v"};
	$ternary{"$sp $v"} .= $cdr;
	my $t = $ternary{"$sp $v"};
	&PrintLog("  InferFileNodeCaches ternary{$sp $v}: $t.\n");
	}
# Now set cache properties for those inputs/parameters that are not
# already set.
foreach my $sp (sort keys %config) {
	my ($s, $p) = split(/\s+/, $sp);
	$p || die;
	next if $p ne "inputs" || $p ne "parameters";
	&PrintLog("  Listing inputs/parameters for $s ...\n");
	my @ips = split(/\s+/, $config{$sp});
	foreach my $ip (@ips) {
		# Skip if cache is already asserted:
		next if $ternary{"$s cache $ip"};
		my $c = &FileNodeCache($s, $ip);
		&PrintLog("  FileNodeCache($s, $ip): $c\n");
		$config{"$s cache"} = "$ip $c";
		}
	}
return %config;
&PrintLog("InferFileNodeCaches returning.\n");
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
open(my $fh, $ff) || die;
print $fh $all;
close($fh) || die;
}

############ ReadFile ##########
# Read a file and return its contents.  Examples:
#   my $all = &ReadFile("<$f")
sub ReadFile
{
@_ == 1 || die;
my ($f) = @_;
open(my $fh, $f) || return undef;
my $all = join("", <$fh>);
close($fh) || die;
return $all;
}

##### DO NOT DELETE THE FOLLOWING LINE!  #####
1;

