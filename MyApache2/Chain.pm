#! /usr/bin/perl -w 

# Command line test:
#  MyApache2/Chain.pm --test --debug http://localhost/hello

# TODO:
# 0. Check SERVER_NAME is set in ENV.
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
use Apache2::RequestUtil ();
use Apache2::Const -compile => qw( HTTP_METHOD_NOT_ALLOWED );
use Test::MockObject;	# For testing from the command line ($test)

use HTTP::Date;
use APR::Table ();
use LWP::UserAgent;
use HTTP::Status;
use Apache2::URI ();
use URI::Escape;
use Time::HiRes ();
use File::Path qw(make_path remove_tree);
use WWW::Mechanize;

my $configFile = "/home/dbooth/rdf-pipeline/trunk/pipeline.n3";
my $ontFile = "/home/dbooth/rdf-pipeline/trunk/ont.n3";
my $internalsFile = "/home/dbooth/rdf-pipeline/trunk/internals.n3";
my $prefix = "http://purl.org/pipeline/ont#";	# Pipeline ont prefix
$ENV{DOCUMENT_ROOT} ||= "/home/dbooth/rdf-pipeline/trunk/www";	# Set if not set
### TODO: Set $baseUri properly.  Needs port?
$ENV{SERVER_NAME} ||= "localhost";
# $baseUri is the URI prefix that corresponds directly to DOCUMENT_ROOT.
# It is *not* necessarily the same as a particular scope, because there
# could be more than one scope hosted within the same Apache server.
my $baseUri = "http://$ENV{SERVER_NAME}";  # TODO: Should become "scope"?
my $baseUriPattern = quotemeta($baseUri);
my $basePath = $ENV{DOCUMENT_ROOT};	# Synonym, for convenience
my $basePathPattern = quotemeta($basePath);
my $PCACHE = "PCACHE"; # Used in forming env vars
my $rdfsPrefix = "http://www.w3.org/2000/01/rdf-schema#";
# my $subClassOf = $rdfsPrefix . "subClassOf";
my $subClassOf = "rdfs:subClassOf";

my $logFile = "/tmp/rdf-pipeline-log.txt";
# unlink $logFile || die;

my %config = ();		# Maps: "?s ?p" --> "v1 v2 ... vn"
my %configValues = ();		# Maps: "?s ?p" --> {v1 => 1, v2 => 1, ...}

# Node Metadata hash maps for mapping from subject
# to predicate to single value ($nmv), list ($nml) or hashmap ($nmh).  
#  For single-valued predicates:
#    my $nmv = $nm->{value};	
#    my $value = $nmv->{$subject}->{$predicate};
#  For list-valued predicates:
#    my $nml = $nm->{list};	
#    my $listRef = $nml->{$subject}->{$predicate};
#    my @list = @{$listRef};
#  For hash or multi-valued predicates:
#    my $nmh = $nm->{hash};	
#    my $hashRef = $nmh->{$subject}->{$predicate};
#    # Multi-valued (maps to 1 if present):
#    if ($hashRef->{$someValue}) { ... }
#    # Hash valued (maps a key to a value):
#    my $value = $hashRef->{$key};
my $nm = {"value"=>{}, "list"=>{}, "hash"=>{}};

my %cachedResponse = ();	# Previous HTTP response to GET or HEAD.
				# Key: "$thisUri $supplierUri"
my $configLastModified = 0;
my $ontLastModified = 0;
my $internalsLastModified = 0;

&PrintLog("="x30 . " START9 " . "="x30 . "\n");
&PrintLog(`date`);
&PrintLog("SERVER_NAME: $ENV{SERVER_NAME}\n");
&PrintLog("DOCUMENT_ROOT: $ENV{DOCUMENT_ROOT}\n");
# my $hasHiResTime = &Time::HiRes::d_hires_stat()>0 ? "true" : "false";
# &PrintLog("Has HiRes time: $hasHiResTime\n");

if (1)
{
  use Apache::Session::File;
my $sessionsDir = '/tmp/rdf-pipeline-sessions';
my $locksDir = '/tmp/rdf-pipeline-locks';

-d $sessionsDir || mkdir($sessionsDir) || die;
-d $locksDir || mkdir($locksDir) || die;

  my %session;
  my $sessionIdFile = "/tmp/rdf-pipeline-sessionID";
  my $sessionId = &ReadFile($sessionIdFile);
  $sessionId = undef if !$sessionId;
  my $isNewSessionId = !$sessionId;
  #make a fresh session for a first-time visitor
 tie %session, 'Apache::Session::File', $sessionId, {
    Directory => $sessionsDir,
    LockDirectory   => $locksDir,
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

&RegisterWrappers($nm);

my $testUri = shift @ARGV || "http://localhost/chain";
my $testArgs = "";
if ($testUri =~ m/\A([^\?]*)\?/) {
	$testUri = $1;
	$testArgs = $';
	}
if ($test)
	{
	# Invoked from the command line, instead of through Apache.
	# Fake a RequestReq object:
	my $r = &MakeFakeRequestReq();
	$r->content_type('text/plain');
	$r->args($testArgs || "");
	$r->set_content_length(0);
	$r->set_content_length(time);
	$r->method("GET");
	$r->header_only(0);
	$r->meets_conditions(1);
	$r->construct_url($testUri); 
	$testUri =~ m|\Ahttp(s?)\:\/\/[^\/]+\/| or die;
	my $path = "/" . $';
	$r->uri($path);
	my $code = &handler($r);
	&PrintLog("\nReturn code: $code\n");
	exit 0;
	}

#######################################################################
###################### Functions start here ###########################
#######################################################################

############### MakeFakeRequestRec ###############
sub MakeFakeRequestReq
{
# Fake a RequestRec object.
# This did NOT work:
# my $r = Apache2::RequestRec->Apache2::RequestRec::new(undef); # Will this work?
# See: http://www.perlmonks.org/?node_id=667221
my $r = Test::MockObject->new();
$r->mock( pool => sub { return APR::Pool->new; } );
my @setterGetters = qw( uri content_type construct_url args
	set_content_length set_last_modified method header_only
	meets_conditions sendfile headers_in headers_out internal_redirect );
foreach my $sg (@setterGetters) {
	$r->mock( $sg => sub { my $r=shift; return @_ ? $r->{$sg}=shift : $r->{$sg}; } );
	}
my $hi = Test::MockObject->new();
$hi->mock( set => sub { my $r=shift; return @_ ? $r->{set}=shift : $r->{set}; } );
$hi->mock( get => sub { my $r=shift; return @_ ? $r->{get}=shift : $r->{get}; } );
$r->headers_in($hi);
my $ho = Test::MockObject->new();
$ho->mock( set => sub { my $r=shift; return @_ ? $r->{set}=shift : $r->{set}; } );
$ho->mock( get => sub { my $r=shift; return @_ ? $r->{get}=shift : $r->{get}; } );
$r->headers_in($ho);
return $r;
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
my $cmtime = &MTime($configFile);
my $omtime = &MTime($ontFile);
my $imtime = &MTime($internalsFile);
if ($configLastModified != $cmtime
		|| $ontLastModified != $omtime
		|| $internalsLastModified != $imtime) {
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
		last if !$debug;
		my $hr = $configValues{$sp};
		foreach my $v (sort keys %{$hr}) {
			&PrintLog("  $sp $v\n");
			}
		}
	&LoadNodeMetadata($nm, $ontFile, $configFile);
	my $nmv = $nm->{value};
	my $nml = $nm->{list};
	my $nmh = $nm->{hash};
	&PrintLog("Node Metadata:\n") if $debug;
	my %allSubjects = (%{$nmv}, %{$nml}, %{$nmh});
	foreach my $s (sort keys %allSubjects) {
		last if !$debug;
		my %allPredicates = ();
		%allPredicates = (%allPredicates, %{$nmv->{$s}}) if $nmv->{$s};
		%allPredicates = (%allPredicates, %{$nml->{$s}}) if $nml->{$s};
		%allPredicates = (%allPredicates, %{$nmh->{$s}}) if $nmh->{$s};
		foreach my $p (sort keys %allPredicates) {
			if ($nmv && $nmv->{$s} && $nmv->{$s}->{$p}) {
			  my $v = $nmv->{$s}->{$p};
			  &PrintLog("  $s -> $p -> $v\n");
			  }
			if ($nml && $nml->{$s} && $nml->{$s}->{$p}) {
			  my @vList = @{$nml->{$s}->{$p}};
			  my $vl = join(" ", @vList);
			  &PrintLog("  $s -> $p -> ($vl)\n");
			  }
			if ($nmh && $nmh->{$s} && $nmh->{$s}->{$p}) {

			  my %vHash = %{$nmh->{$s}->{$p}};
			  my @vHash = map {($_,$vHash{$_})} sort keys %vHash;
			  # @vHash = map {defined($_) ? $_ : '*undef*'} @vHash;
			  my $vh = join(" ", @vHash);
			  &PrintLog("  $s -> $p -> {$vh}\n");
			  }
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
return &HandleHttpEvent($nm, $r);
# Old dead code:
if ($subtype eq "FileNode") { 
	&PrintLog("Dispatching to HandleFileNode\n") if $debug;
	return &HandleFileNode($nm, $r, $thisUri);
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
my $nm = shift;
my $r = shift;
my $thisUri = shift || die;
my $nmv = $nm->{value};
my $nml = $nm->{list};
my $nmh = $nm->{hash};
my $thisValue = $nmv->{$thisUri};
my $thisList = $nml->{$thisUri};
my $thisHash = $nmh->{$thisUri};
my $cache = $thisValue->{cache} || die;
my $cacheUri = $thisValue->{cacheUri} || die;
my $updater = $thisValue->{updater};
$updater = &AbsPath($updater) if $updater;
$thisValue->{updater} = $updater;

my $inputs = $config{"$thisUri inputs"} || "";
my $parameters = $config{"$thisUri parameters"} || "";
my $dependsOn = $config{"$thisUri dependsOn"} || "";
my @inputs = ($inputs ? split(/\s+/, $inputs) : ());
my @parameters = ($parameters ? split(/\s+/, $parameters) : ());
my @dependsOn = ($dependsOn ? split(/\s+/, $dependsOn) : ());

&PrintLog("Initial cache: $cache\n") if $debug;
my $useStdout = 0;
if ($updater && !$thisValue->{cacheOriginal}) {
	$useStdout = 1;
	}
&PrintLog("useStdout: $useStdout updater: {$updater}\n") if $debug;
&PrintLog("cache after useStdout block: $cache\n") if $debug;
&PrintLog("cache: $cache\n") if $debug;

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
my $args = $test ? $testArgs : ($r->args() || "");
&PrintLog("Query string: $args\n") if $debug;
my %args = &ParseQueryString($args);
foreach my $k (keys %args) {
	my $v = $args{$k};
	&PrintLog("	$k = $v\n") if $debug;
	}

if ((!-e $cache) || &AnyChanged($thisUri, @dependsOn))
	{
	# Run updater if there is one:
	if ($updater) {
		if (!-x $updater) {
			&PrintLog("ERROR: updater is not executable by web server\n") if $debug;
			# &PrintLog("Perhaps you need to setuid:  chmod a+s $updater\n";
			}
		# The FileNode updater args will be local filenames for all
		# inputs and parameters.
		my @inputFiles = &LocalFiles($thisUri, @inputs);
		my @parameterFiles = &LocalFiles($thisUri, @parameters);
		&PrintLog("inputFiles: @inputFiles\n");
		&PrintLog("parameterFiles: @parameterFiles\n");
		my $stderr = $nm->{value}->{$thisUri}->{stderr};
		# Make sure parent dirs exist for $stderr and $cache:
		&MakeParentDirs($stderr, $cache);
		# my $cmd = "/home/dbooth/rdf-pipeline/trunk/setuid-wrapper $updater $thisUri $cache $inputs $parameters > $stderr 2>&1";
		# my $cmd = "$updater $thisUri $cache $inputs $parameters > $stderr 2>&1";
		# $cmd = "$updater $thisUri $inputs $parameters > $cache 2> $stderr"
			# if $useStdout;
		# TODO: Check for unsafe chars before invoking $cmd
		my $cmd = "( export $PCACHE\_THIS_URI=\"$thisUri\" ; $updater $cache @inputFiles @parameterFiles > $stderr 2>&1 )";
		$cmd = "( export $PCACHE\_THIS_URI=\"$thisUri\" ; $updater @inputFiles @parameterFiles > $cache 2> $stderr )"
			if $useStdout;
		&PrintLog("cmd: $cmd\n") if $debug;
		my $result = (system($cmd) >> 8);
		my $saveError = $?;
		&PrintLog("Updater returned " . ($result ? "error code:" : "success:") . " $result.\n");
		if (-s $stderr) {
			&PrintLog("Updater stderr" . ($useStdout ? "" : " and stdout") . ":\n[[\n") if $debug;
			# system("cat $stderr >> $logFile") if $debug;
			&PrintLog(&ReadFile("<$stderr")) if $debug;
			&PrintLog("]]\n") if $debug;
			}
		# unlink $stderr;
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
my $serCache = $thisValue->{serCache};
my $mtime = &MTime($serCache);
my $size = -s $serCache;
&PrintLog("HandleFileNode serCache: $serCache size: $size\n") if $debug;
my $lm = time2str($mtime);
&PrintLog("HandleFileNode: Last-Modified: $lm\n") if $debug;

&PrintLog("HandleFileNode: Trying sendfile...\n") if $debug;
if ($test) {
	&PrintLog("HandleFileNode: (skipped sending due to -test option)\n");
	}
else	{
	# We must set headers explicitly here.
	# This works for returning 304:
	# $r->status(Apache2::Const::HTTP_NOT_MODIFIED);
	$r->content_type('text/plain');
	# This works also: $r->content_type('application/rdf+xml');
	$r->set_content_length($size);
	$r->set_last_modified($mtime);
	# my $cacheUri = $r->construct_url($cache); 
	my $cacheUri = $nm->{value}->{$thisUri}->{serCacheUri};
	$r->headers_out->set('Content-Location' => $cacheUri); 
	# TODO: Set proper ETag, perhaps using Time::HiRes mtime.
	# "W/" prefix on ETag means that it is weak.
	# $r->headers_out->set('ETag' => 'W/"640e9-a-4b269027adb7d;4b142a708a8ad"'); 
	$r->headers_out->set('ETag' => 'W/"fake-etag"'); 
	# Did not work: $r->sendfile($cache);
	# sendfile seems to want a full file system path:
	$r->sendfile($serCache);
	my $m = $r->method;
	my $ho = $r->header_only;
	&PrintLog("HandleFileNode: method: $m header_only: $ho\n") if $debug;
	}

# These work:
# $r->internal_redirect("/fchain.txt") if !$debug;
# $r->internal_redirect("http://localhost/fchain.txt");
# Apache2::Const::OK indicates that this handler ran successfully.
# It is not the HTTP response code being returned.  See:
# http://perl.apache.org/docs/2.0/user/handlers/intro.html#C_RUN_FIRST_
return Apache2::Const::OK;
}

################### SendHttpRequest ##################
# Send a remote GET, QGET or HEAD to $inUri if $inLM is newer than 
# the stored LM of $thisUri's local serNameUri LM for $inLM.
# The reason for checking $inLM here instead of checking it in
# &RequestLatestIns(...) is because the check requires a call to
# &LookupLMs($inSerNameUri), which needs to be done here anyway
# in order to look up the old LM headers.
# Also remember that $thisUri is not necessarily a node: it may be 
# an arbitrary URI source, in which case the $method will be HEAD.
sub SendHttpRequest
{
@_ == 5 or die;
my ($nm, $method, $thisUri, $inUri, $inLM) = @_;
# Send conditional GET, QGET or HEAD to inUri with inUri*/serCopyLM
# my $ua = LWP::UserAgent->new;
my $ua = WWW::Mechanize->new();
$ua->agent("$0/0.01 " . $ua->agent);
my $requestUri = $inUri;
my $httpMethod = $method;
if ($method eq "QGET" || $method eq "NOTIFY") {
	$httpMethod = "GET";
	$requestUri .= "?method=$method";
	}
# Set If-Modified-Since and If-None-Match headers in request, if available.
my $inSerName = $nm->{hash}->{$thisUri}->{dependsOnSerName}->{$inUri} || die;
my $inSerNameUri = $nm->{hash}->{$thisUri}->{dependsOnSerNameUri}->{$inUri} || die;
my ($oldLM, $oldLMHeader, $oldETagHeader) = &LookupLMs($inSerNameUri);
if ($inLM && $oldLM, && $oldLM ge $inLM) {
	return $oldLM;
	}
my $req = HTTP::Request->new($httpMethod => $requestUri);
$req || die;
$req->header('If-Modified-Since' => $oldLMHeader) if $oldLMHeader;
$req->header('If-None-Match' => $oldETagHeader) if $oldETagHeader;
my $isConditional = "conditional" if $req->header('If-Modified-Since');
my $reqString = $req->as_string;
&PrintLog("SendHttpRequest: Sending remote $isConditional $method Request from $thisUri to $inUri :\n[[\n$reqString\n]]\n");
my $res = $ua->request($req) or die;
my $code = $res->code;
$code == RC_NOT_MODIFIED || $code == RC_OK or die;
&PrintLog("SendHttpRequest: $isConditional $method Request from $thisUri to $inUri returned $code\n");
my $newLMHeader = $res->header('Last-Modified') || "";
my $newETagHeader = $res->header('ETag') || "";
my $newLM = &HeadersToLM($newLMHeader, $newETagHeader);
if ($code == RC_OK && $newLM && $newLM ne $oldLM) {
	$newLM gt $oldLM || die; # Verify monotonic LM
	# Need to save the content to file $inSerName.
	# TODO: Figure out whether the content should be decoded first.  
	# If not, should the Content-Type and Content-Encoding headers 
	# be saved with the LM perhaps? Or is there a more efficient way 
	# to save the content to file $inSerName, such as using 
	# $ua->get($url, ':content_file'=>$filename) ?  See
	# http://search.cpan.org/~gaas/libwww-perl-6.03/lib/LWP/UserAgent.pm
	$ua->save_content( $inSerName ) if $method ne 'HEAD';
	&SaveLMs($inSerNameUri, $newLM, $newLMHeader, $newETagHeader);
	}
return $newLM;
}

################### OldHandleRemoteRequest ##################
# Handle a remote Request.
sub OldHandleRemoteRequest
{
@_ == 2 or die;
my ($nm, $r) = @_;
# construct_url omits the query params
my $thisUri = $r->construct_url(); 
&PrintLog("thisUri: $thisUri\n") if $debug;
my $thisValue = $nm->{value}->{$thisUri};
if (!$thisValue) {
	&PrintLog("ERROR: $thisUri is not a Node.\n");
	return Apache2::Const::NOT_FOUND;
	}
my $thisType = $thisValue->{nodeType} || "";
if (!$thisType) {
	&PrintLog("ERROR: $thisUri has no nodeType.\n");
	return Apache2::Const::NOT_FOUND;
	}
my $args = $r->args() || "";
&PrintLog("Query string: $args\n") if $debug;
my %args = &ParseQueryString($args);
my $callerUri = $args{callerUri} || "";
my $callerLM = $args{callerLM} || "";
my $method = $args{method} || $r->method;
$method = "GET" if $method eq "HEAD";
&PrintLog("HandleRemoteRequest method: $method callerUri: $callerUri callerLM: $callerLM\n") if $debug;
if ($method eq "GET") {
	return &HandleRemoteGET($nm, $r, $thisUri, $callerUri);
	}
elsif ($method eq "QGET") {
	return &HandleRemoteQGET($nm, $r, $thisUri);
	}
elsif ($method eq "NOTIFY") {
	return &HandleRemoteNOTIFY($nm, $r, $thisUri, $callerUri, $callerLM);
	}
return Apache2::Const::HTTP_METHOD_NOT_ALLOWED;
}

################### HandleHttpEvent ##################
sub HandleHttpEvent
{
@_ == 2 or die;
my ($nm, $r) = @_;
# construct_url omits the query params
my $thisUri = $r->construct_url(); 
&PrintLog("thisUri: $thisUri\n") if $debug;
my $thisValue = $nm->{value}->{$thisUri};
if (!$thisValue) {
	&PrintLog("INTERNAL ERROR: $thisUri is not a Node.\n");
	return Apache2::Const::SERVER_ERROR;
	}
my $thisType = $thisValue->{nodeType} || "";
if (!$thisType) {
	&PrintLog("INTERNAL ERROR: $thisUri has no nodeType.\n");
	return Apache2::Const::SERVER_ERROR;
	}
my $args = $r->args() || "";
&PrintLog("Query string: $args\n") if $debug;
my %args = &ParseQueryString($args);
my $callerUri = $args{callerUri} || "";
my $callerLM = $args{callerLM} || "";
my $method = $args{method} || $r->method;
return Apache2::Const::HTTP_METHOD_NOT_ALLOWED 
  if $method ne "HEAD" && $method ne "GET" && $method ne "QGET" 
	&& $method ne "NOTIFY";
# TODO: If $r has fresh content, then store it.
&PrintLog("HandleRemoteRequest method: $method callerUri: $callerUri callerLM: $callerLM\n") if $debug;
my $newThisLM = &FreshenAndSerialize($method, $thisUri, $callerUri, $callerLM)
####### Ready to generate the HTTP response. ########
my $serCache = $thisValue->{serCache} || die;
my $size = -s $serCache || 0;
$r->set_content_length($size);
# TODO: Should use Accept header in choosing contentType.
my $contentType = $thisValue->{contentType}
	|| $nm->{value}->{$thisType}->{defaultContentType}
	|| "text/plain";
# These work:
# $r->content_type('text/plain');
# $r->content_type('application/rdf+xml');
$r->content_type($contentType);
$r->headers_out->set('Content-Location' => $serCacheUri); 
my ($lmHeader, $eTagHeader) = &LMToHeaders($serCacheLM);
# These work:
# "W/" prefix on ETag means that it is weak.
# $r->headers_out->set('ETag' => 'W/"640e9-a-4b269027adb7d;4b142a708a8ad"'); 
# $r->headers_out->set('ETag' => 'W/"fake-etag"'); 
# Don't use this method, because $lmHeader is already formatted:
# $r->set_last_modified($mtime);
$r->headers_out->set('Last-Modified' => $lmHeader) if $lmHeader; 
$r->headers_out->set('ETag' => $eTagHeader) if $eTagHeader; 
# Done setting headers.  Determine status code to return, and
# send content body if 200 and not HEAD.
my $status = $r->meets_conditions();
if($status != Apache2::Const::OK || $r->header_only) {
  # $r->status(Apache2::Const::HTTP_NOT_MODIFIED);
  # Also returns 304 if appropriate:
  return $status;
  }
# sendfile seems to want a full file system path:
$r->sendfile($serCache);
return Apache2::Const::OK;
}

################### FreshenAndSerialize ##################
sub FreshenAndSerialize
{
@_ == 5 or die;
my ($nm, $method, $thisUri, $callerUri, $callerLM) = @_;
my $thisValue = $nm->{value}->{$thisUri} || die;
my $thisType = $thisValue->{nodeType} || die;
my $cache = $thisValue->{cache} || die;
my $serCache = $thisValue->{serCache} || die;
my $cacheUri = $thisValue->{cacheUri} || die;
my $serCacheUri = $thisValue->{serCacheUri} || die;
my $newThisLM = &CheckPolicyAndFreshen($nm, 'GET', $thisUri, $callerUri, $callerLM);
if ($method eq 'NOTIFY' || $cacheUri eq $serCacheUri) {
  return $newThisLM;
  }
# Need to update serCache?
my ($serCacheLM) = &LookupLMs($serCacheUri);
if (!$serCacheLM || $cacheLM ne $serCacheLM) {
  die if $cacheLM && $serCacheLM && $cacheLM lt $serCacheLM;
  # TODO: Set $acceptHeader from $r, and use it to choose $contentType:
  # This could be done by making {fSerialize} a hash from $contentType
  # to the serialization function.
  # my $acceptHeader = $r->headers_in->get('Accept') || "";
  # warn "acceptHeader: $acceptHeader\n";
  my $fSerialize = $thisValue->{fSerialize} || die;
  &{$fSerialize}($cache, $serCache) or die;
  $serCacheLM = $cacheLM;
  &SaveLMs($serCacheUri, $serCacheLM);
  }
return $serCacheLM
}

################### HandleRemoteQGET ##################
# This is used by HandleRemoteGET after refreshing, or
# when handling a NOTIFY, when thisUri
# is known to be fresh.  The downstream node QGETs the serialized 
# state from $thisUri without causing $thisUri to be refreshed.
# No new events are generated or sent.
sub HandleRemoteQGET
{
@_ == 3 or die;
my ($nm, $r, $thisUri) = @_;
# if thisUri/serCache is stale wrt thisUri/cache
my $thisValue = $nm->{value}->{$thisUri} || die;
my $thisType = $thisValue->{nodeType} || die;
my $cache = $thisValue->{cache} || die;
my $serCache = $thisValue->{serCache} || die;
my $cacheUri = $thisValue->{cacheUri} || die;
my $serCacheUri = $thisValue->{serCacheUri} || die;
my $serCacheLM;
my ($cacheLM) = &LookupLMs($cacheUri);
$cacheLM || die "QGET on null cacheLM -- internal error or race condition ";
if ($cacheUri eq $serCacheUri) {
  $serCacheLM = $cacheLM;
  }
else {
  # Need to update serCache?
  ($serCacheLM) = &LookupLMs($serCacheUri);
  if ($cacheLM ne $serCacheLM) {
    !$cacheLM || !$serCacheLM || $cacheLM gt $serCacheLM || die;
    # TODO: Set $acceptHeader from $r, and use it to choose $contentType:
    # This could be done by making {fSerialize} a hash from $contentType
    # to the serialization function.
    my $acceptHeader = $r->headers_in->get('Accept') || "";
    warn "HandleRemoteQGET acceptHeader: $acceptHeader\n";
    my $fSerialize = $thisValue->{fSerialize} || die;
    &{$fSerialize}($cache, $serCache) or die;
    $serCacheLM = $cacheLM;
    &SaveLMs($serCacheUri, $serCacheLM);
    }
  }
# Ready to generate the HTTP response.
my $size = -s $serCache;
$r->set_content_length($size);
# TODO: Should use Accept header in choosing contentType.
my $contentType = $thisValue->{contentType}
	|| $nm->{value}->{$thisType}->{defaultContentType}
	|| "text/plain";
# These work:
# $r->content_type('text/plain');
# $r->content_type('application/rdf+xml');
$r->content_type($contentType);
$r->headers_out->set('Content-Location' => $serCacheUri); 
my ($lmHeader, $eTagHeader) = &LMToHeaders($serCacheLM);
# These work:
# "W/" prefix on ETag means that it is weak.
# $r->headers_out->set('ETag' => 'W/"640e9-a-4b269027adb7d;4b142a708a8ad"'); 
# $r->headers_out->set('ETag' => 'W/"fake-etag"'); 
# Don't use this method, because $lmHeader is already formatted:
# $r->set_last_modified($mtime);
$r->headers_out->set('Last-Modified' => $lmHeader) if $lmHeader; 
$r->headers_out->set('ETag' => $eTagHeader) if $eTagHeader; 
# Done setting headers.  Determine status code to return, and
# send content body if 200 and not HEAD.
my $status = $r->meets_conditions();
if($status != Apache2::Const::OK || $r->header_only) {
  # $r->status(Apache2::Const::HTTP_NOT_MODIFIED);
  # Also returns 304 if appropriate:
  return $status;
  }
# sendfile seems to want a full file system path:
$r->sendfile($serCache);
return Apache2::Const::OK;
}

################### RequestLatestIns ################### 
sub RequestLatestIns
{
@_ == 5 or die;
my ($nm, $thisUri, $callerUri, $callerLM, $oldInLMs) = @_;
# callerUri and callerLM are only used to avoid requesting the latest 
# state from an input/parameter that is already known fresh, because 
# it was the one that notified thisUri.
# Thus, they are not used when this was called because of a GET.
my $thisValue = $nm->{value}->{$thisUri};
my $thisType = $thisValue->{nodeType};
my $thisIsStale = 0;
my $thisDependsOn = $nm->{hash}->{$thisUri}->{dependsOn};
my $newInLMs = {};
foreach my $inUri (sort keys %{$thisDependsOn}) {
  # Bear in mind that a node may dependsOn a non-node arbitrary http 
  # or file:// source, so $inValue may be undef.
  my $inValue = $nm->{value}->{$inUri};
  my $inType = $inValue ? $inValue->{nodeType} : "";
  my $newInLM;
  my $method = $inType ? 'GET' : 'HEAD' ;
  my $inLM = undef;
  # TODO: Future optimization: if inUri is in %knownFresh ...
  if ($inUri eq $callerUri) {
    $method = 'QGET';
    $inLM = $callerLM;
    }
  if (!$inType || !&IsSameServer($thisUri, $inUri)) {
    $newInLM = &SendHttpRequest($nm, $method, $thisUri, $inUri, $inLM);
    }
  elsif (!&IsSameType($thisType, $inType)) {
    # Neighbor: Same server but different type.
    $newInLM = &FreshenAndSerialize($nm, $method, $thisUri);
    }
  else {
    # Local: Same server and type.
    $newInLM = ($inUri eq $callerUri) ? $callerLM
	: &CheckPolicyAndFreshen($nm, 'GET', $inUri, undef, undef);
    }
  $thisIsStale = 1 if $newInLM ne $oldInLMs->{$inUri};
  $newInLMs->{$inUri} = $newInLM;
  }
return( $thisIsStale, $newInLMs )
}

################### LoadNodeMetadata #################
sub LoadNodeMetadata
{
@_ == 3 or die;
my ($nm, $ontFile, $configFile) = @_;
my %config = &CheatLoadN3($ontFile, $configFile);
my $nmv = $nm->{value};
my $nml = $nm->{list};
my $nmh = $nm->{hash};
foreach my $k (sort keys %config) {
	# &PrintLog("  LoadNodeMetadata key: $k\n") if $debug;
	my ($s, $p) = split(/\s+/, $k) or die;
	my $v = $config{$k};
	die if !defined($v);
	my @vList = split(/\s+/, $v); 
	my %vHash = map { ($_, 1) } @vList;
	$nmv->{$s}->{$p} = $v;
	$nml->{$s}->{$p} = \@vList;
	$nmh->{$s}->{$p} = \%vHash;
	# &PrintLog("  $s -> $p -> $v\n") if $debug;
	}
&PresetGenericDefaults($nm);
# Run the initialization function to set defaults for each node type 
# (i.e., wrapper type), starting with leaf nodes and working up the hierarchy.
my @leaves = &LeafClasses($nm, keys %{$nmh->{Node}->{subClass}});
my %done = ();
while(@leaves) {
	my $nodeType = shift @leaves;
	next if $done{$nodeType};
	$done{$nodeType} = 1;
	my @superClasses = keys %{$nmh->{$nodeType}->{$subClassOf}};
	push(@leaves, @superClasses);
	my $fSetNodeDefaults = $nmv->{$nodeType}->{fSetNodeDefaults};
	next if !$fSetNodeDefaults;
	&{$fSetNodeDefaults}($nm);
	}
return $nm;
}

################### PresetGenericDefaults #################
# Preset essential generic $nmv, $nml, $nmh defaults that must be set
# before nodeType-specific defaults are set.  In particular, the
# following are set for every node: nodeType.  Plus the following
# are set for every node on this server:
# cacheOriginal, cache, cacheUri, serCache, serCacheUri, stderr.
sub PresetGenericDefaults
{
@_ == 1 or die;
my ($nm) = @_;
my $nmv = $nm->{value};
my $nml = $nm->{list};
my $nmh = $nm->{hash};
&PrintLog("PresetGenericDefaults:\n");
# First set defaults that are set directly on each node: 
# nodeType, cache, cacheUri, serCache, serCacheUri, stderr.
foreach my $thisUri (keys %{$nmh->{Node}->{member}}) 
  {
  # Make life easier in this loop:
  my $thisValue = $nmv->{$thisUri};
  my $thisList = $nml->{$thisUri};
  my $thisHash = $nmh->{$thisUri};
  # Set nodeType, which should be most specific node type.
  my @types = keys %{$thisHash->{a}};
  my @nodeTypes = LeafClasses($nm, @types);
  die if @nodeTypes > 1;
  die if @nodeTypes < 1;
  my $thisType = $nodeTypes[0];
  $thisValue->{nodeType} = $thisType;
  # Nothing more to do if $thisUri is not hosted on this server:
  next if !&IsSameServer($baseUri, $thisUri);
  # Save original cache before changing it:
  $thisValue->{cacheOriginal} = $thisValue->{cache};
  # Set cache, cacheUri, serCache and serCacheUri if not set.  
  # cache is a local name; serCache is a file path.
  my $thisFUriToLocalName = $nmv->{$thisType}->{fUriToLocalName} || "";
  my $defaultCacheUri = "$baseUri/caches/" . &QuickName($thisUri) . "/cache";
  my $defaultCache = $defaultCacheUri;
  $defaultCache = &{$thisFUriToLocalName}($defaultCache) 
	if $thisFUriToLocalName;
  my $thisName = $thisFUriToLocalName ? &{$thisFUriToLocalName}($thisUri) : $thisUri;
  $thisValue->{cache} ||= 
    $thisValue->{updater} ? $defaultCache : $thisName;
  $thisValue->{cacheUri} ||= 
    $thisValue->{updater} ? $defaultCacheUri : $thisUri;
  $thisValue->{serCache} ||= 
    $nmv->{$thisType}->{fSerializer} ?
      "$basePath/caches/" . &QuickName($thisUri) . "/serCache"
      : $thisValue->{cache};
  $thisValue->{serCacheUri} ||= &PathToUri($thisValue->{serCache});
  # For capturing stderr:
  $nmv->{$thisUri}->{stderr} ||= 
	  "$basePath/caches/" . &QuickName($thisUri) . "/stderr";
  # Simplify later code:
  &MakeValuesAbsoluteUris($nmv, $nml, $nmh, $thisUri, "inputs");
  &MakeValuesAbsoluteUris($nmv, $nml, $nmh, $thisUri, "parameters");
  &MakeValuesAbsoluteUris($nmv, $nml, $nmh, $thisUri, "dependsOn");
  die "Cannot have inputs without an updater " 
	if !$thisValue->{updater} && @{$thisList->{inputs}};
  }

&PrintLog("SetNodeDefaults:\n");
# Now go through each node again, setting values related to each
# node's dependsOns, which may make use of properties that were
# set in the previous loop.
foreach my $thisUri (keys %{$nmh->{Node}->{member}}) 
  {
  # Nothing to do if $thisUri is not hosted on this server:
  next if !&IsSameServer($baseUri, $thisUri);
  # Make life easier in this loop:
  my $thisValue = $nmv->{$thisUri};
  my $thisList = $nml->{$thisUri};
  my $thisHash = $nmh->{$thisUri};
  my $thisType = $thisValue->{nodeType};
  # The dependsOnName hash is used for inputs from other environments
  # and maps from dependsOn URIs (or inputs/parameter URIs) to the local names 
  # that will be used by $thisUri's updater when
  # it is invoked.  It will either use a new name (if the input is from
  # a different environment) or the input's cache directly (if in the 
  # same env).  A non-node dependsOn is treated like a foreign
  # node with no serializer.  
  # The dependsOnSerName hash similarly maps
  # from dependsOn URIs to the local serNames (i.e., file names of 
  # inputs) that will be used to refresh the local copy if the
  # input is foreign.  However, since different node types within
  # the same server can share the serialized inputs, then 
  # the dependsOnSerName may be set using the input's serCache.
  # The dependsOnNameUri and dependsOnSerNameUri hashes are URIs corresponding
  # to dependsOnName and dependsOnSerName, and are used as keys for LMs.
  # Factors that affect these settings:
  #  A. Is $inUri a node?  It may be any other URI data source (http: or file:).
  #  B. Is $inUri on the same server (as $thisUri)?
  #  C. Is $inType the same node type $thisType?
  #  D. Does $inType have a deserializer?
  #  E. Does $inType have a fUriToLocalName function?
  $thisHash->{dependsOnName} ||= {};
  $thisHash->{dependsOnSerName} ||= {};
  $thisHash->{dependsOnNameUri} ||= {};
  $thisHash->{dependsOnSerNameUri} ||= {};
  foreach my $inUri (keys %{$thisHash->{dependsOn}}) {
    # Ensure non-null hashrefs for all ins (because they may not be nodes):
    $nmv->{$inUri} = "" if !$nmv->{$inUri};
    $nml->{$inUri} = [] if !$nml->{$inUri};
    $nmh->{$inUri} = {} if !$nmh->{$inUri};
    # my $inUriEncoded = uri_escape($inUri);
    my $inUriEncoded = &QuickName($inUri);
    # $inType will be false if $inUri is not a node:
    my $inType = $nmv->{$inUri}->{nodeType} || "";
    # First set dependsOnSerName and dependsOnSerNameUri.
    if ($inType && &IsSameServer($baseUri, $inUri)) {
      # Same server, so re-use the input's serCache.
      $thisHash->{dependsOnSerName}->{$inUri} = $nmv->{$inUri}->{serCache};
      }
    else {
      # Different servers, so make up a new file path.
      # dependsOnSerName file path does not need to contain $thisType, because 
      # different node types on the same server can share the same serCopy's.
      my $inSerName = "$basePath/caches/$inUriEncoded/serCopy";
      $thisHash->{dependsOnSerName}->{$inUri} = $inSerName;
      }
    $thisHash->{dependsOnSerNameUri}->{$inUri} ||= 
	      &PathToUri($thisHash->{dependsOnSerName}->{$inUri}) || die;
    # Now set dependsOnName and dependsOnNameUri.
    my $fDeserializer = $inType ? $nmv->{$inType}->{fDeserializer} : "";
    if (&IsSameServer($baseUri, $inUri) && &IsSameType($thisType, $inType)) {
      # Same env.  Reuse the input's cache.
      $thisHash->{dependsOnName}->{$inUri} = $nmv->{$inUri}->{cache};
      $thisHash->{dependsOnNameUri}->{$inUri} = $nmv->{$inUri}->{cacheUri};
      # warn "thisUri: $thisUri inUri: $inUri Path 1\n";
      }
    elsif ($fDeserializer) {
      # There is a deserializer, so we must create a new {copy} name.
      # Create a URI and convert it
      # (if necessary) to an appropriate local name.
      my $fUriToLocalName = $nmv->{$inType}->{fUriToLocalName};
      my $copyName = "$baseUri/caches/$thisType/$inUriEncoded/copy";
      $thisHash->{dependsOnNameUri}->{$inUri} = $copyName;
      $copyName = &{$fUriToLocalName}($copyName) if $fUriToLocalName;
      $thisHash->{dependsOnName}->{$inUri} = $copyName;
      # warn "thisUri: $thisUri inUri: $inUri Path 2\n";
      }
    else {
      # No deserializer, so dependsOnName will be the same as dependsOnSerName.
      my $path = $thisHash->{dependsOnSerName}->{$inUri};
      $thisHash->{dependsOnName}->{$inUri} = $path;
      $thisHash->{dependsOnNameUri}->{$inUri} = &PathToUri($path);
      # warn "thisUri: $thisUri inUri: $inUri Path 3\n";
      }
    # my $don = $thisHash->{dependsOnName}->{$inUri};
    # my $dosn = $thisHash->{dependsOnSerName}->{$inUri};
    # my $donu = $thisHash->{dependsOnNameUri}->{$inUri};
    # my $dosnu = $thisHash->{dependsOnSerNameUri}->{$inUri};
    # warn "thisUri: $thisUri inUri: $inUri $inType $don $dosn $donu $dosnu\n";
    }
  }
}

################# MakeValuesAbsoluteUris ####################
sub MakeValuesAbsoluteUris 
{
@_ == 5 or die;
my ($nmv, $nml, $nmh, $thisUri, $predicate) = @_;
my $oldV = $nmv->{$thisUri}->{$predicate} || "";
my $oldL = $nml->{$thisUri}->{$predicate} || [];
my $oldH = $nmh->{$thisUri}->{$predicate} || {};
# In the case of a hash, it is the key that is made absolute:
my %hash = map {(&AbsUri($_), $oldH->{$_})} keys %{$oldH};
my @list = map {&AbsUri($_)} @{$oldL};
my $value = join(" ", @list);
$nmv->{$thisUri}->{$predicate} = $value;
$nml->{$thisUri}->{$predicate} = \@list;
$nmh->{$thisUri}->{$predicate} = \%hash;
return;
}

################### DefaultScope #################
# Default scope is the URI before the path but without the trailing slash.
# E.g., http://example.com/foo?bar --> http://example.com
# E.g., file:///home/dbooth/foo/bar --> file://
sub DefaultScope
{
my $thisUri = shift;
die if $thisUri !~ m|\A([a-zA-Z]+\:\/\/[^\/]+)\/|;
my $scope = $1;
return $scope;
}

################### LeafClasses #################
# Given a list of classes (with rdfs:subClassOf relations in $nmv, $nml, $nmh), 
# return the ones that are not a 
# superclass of any of them.  The list of classes is expected to
# be complete, e.g., for if you have:
#	:a rdfs:subClassOf :b .
#	:b rdfs:subClassOf :c .
# then if :a is in the given list of classes then :b (and :c) must be also.
sub LeafClasses
{
@_ >= 1 or die;
my ($nm, @classes) = @_;
my $nmh = $nm->{hash};
my @leaves = ();
# Simple n-squared algorithm should be okay for small numbers of classes:
foreach my $t (@classes) {
	my $isSuperclass = 0;
	foreach my $subType (@classes) {
		next if $t eq $subType;
		next if !$nmh->{$subType};
		next if !$nmh->{$subType}->{$subClassOf};
		next if !$nmh->{$subType}->{$subClassOf}->{$t};
		$isSuperclass = 1;
		last;
		}
	push(@leaves, $t) if !$isSuperclass;
	}
return @leaves;
}

################### BuildQueryString #################
# Given a hash of key/value pairs, escape both keys and values and
# put them into a query string (not including the "?"), which is returned.
sub BuildQueryString
{
my %args = @_;
my $args = join("&", 
	map { uri_escape($_) . "=" . uri_escape($args{$_}) }
	keys %args);
return $args;
}

################### ParseQueryString #################
# Returns a hash of key/value pairs, with both keys and values unescaped.
# If the same key appears more than once in the query string,
# the last value given wins.
# TODO: Not sure this function is needed.  Maybe $r->param can be used
# instead?  See:
# https://metacpan.org/module/Apache2::Request#param
sub ParseQueryString
{
my $args = shift || "";
my %args = map { 
	my ($k,$v) = split(/\=/, $_); 
	$v = "" if !defined($v); 
	$k ? (uri_unescaped($k), uri_unescape($v)) : ()
	} split(/\&/, $args);
return %args;
}

################### LocalFiles #####################
# For each given input or parameter URI $uri, return a filename 
# that is local to $thisUri and contains the current cached
# content of $uri.
sub LocalFiles
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
		my $filename = $ENV{DOCUMENT_ROOT} . "/$f-stdout";
		$filename = $ENV{DOCUMENT_ROOT} . "/$f"
			if !$config{"$uri updater"};
		&PrintLog("LocalFiles: uri: $uri f: $f filename: $filename\n");
		push(@filenames, $filename);
		}
	else	{
		# TODO: This is currently only being done correctly for
		# for local inputs.  For remote inputs, it should be
		# using the localized copy.
		&PrintLog("LocalFiles: Not yet implemented\n");
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
# Example: "http://localhost/a cache" --> "c/cp-cache.txt"
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
	# Convert rdfs: namespace to "rdfs:" prefix:
	$t = join(" ", map { s/\A$rdfsPrefix([a-zA-Z])/rdfs:$1/;	$_ }
		split(/\s+/, $t));
	my ($s, $p, $o) = split(/\s+/, $t, 3);
	next if !$o;
	# $o may actually be a space-separate list of URIs
	# &PrintLog("  s: $s p: $p o: $o\n") if $debug;
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
# Parent directories are automatically created as needed.
sub WriteFile
{
@_ == 2 || die;
my ($f, $all) = @_;
my $ff = (($f =~ m/\A\>/) ? $f : ">$f");    # Default to ">$f"
$ff =~ m/\A\>(\>?)/ or die;
my $nameOnly = $';
&MakeParentDirs($nameOnly);
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

############# UriToLmFile #############
# Convert $thisUri to a LM file path.
sub UriToLmFile
{
my $thisUri = shift;
my $lmFile = $UriToLmFile::lmFile{$thisUri};
if (!$lmFile) {
	$lmFile = &UriToPath($thisUri);
	if ($lmFile && $lmFile =~ m|\A$basePathPattern\/caches\/|) {
		$lmFile .= "LM";
		}
	else	{
		my $t = uri_escape($thisUri);
		$lmFile = "$basePath/lm/$t";
		}
	$UriToLmFile::lmFile{$thisUri} = $lmFile;
	}
return $lmFile;
}

############# SaveLMs ##############
# Save Last-Modified times of $thisUri and its inputs (actually its dependsOns).
# Called as: &SaveLMs($thisUri, $thisLM, %inLMs);
sub SaveLMs
{
@_ >= 2 || die;
my ($thisUri, $thisLM, @inLMs) = @_;
my $f = &UriToLmFile($thisUri);
my $s = join("\n", $thisLM, @inLMs) . "\n";
&WriteFile($f, $s);
}

############# LookupLMs ##############
# Lookup LM times of $thisUri and its inputs (actually its dependsOns).
# Called as: my ($thisLM, %inLMs) = &LookupLMs($thisUri);
sub LookupLMs
{
@_ == 1 || die;
my ($thisUri) = @_;
my $f = &UriToLmFile($thisUri);
open(my $fh, $f) or return ("", ());
my ($thisLM, @inLMs) = map {chomp; $_} <$fh>;
close($fh) || die;
return($thisLM, @inLMs);
}

############# RegisterWrappers ##############
sub RegisterWrappers
{
@_ == 1 || die;
my ($nm) = @_;
&RegisterFileNode($nm);
}

############# RegisterFileNode ##############
sub RegisterFileNode
{
@_ == 1 || die;
my ($nm) = @_;
$nm->{value}->{FileNode}->{fUriToLocalName} = \&UriToPath;
}


############# MTime ##############
# Return the $mtime (modification time) of a file.
sub MTime
{
@_ == 1 || die;
my $f = shift;
my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
	      $atime,$mtime,$ctime,$blksize,$blocks)
		  = stat($f);
# Avoid unused var warning:
($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
	      $atime,$mtime,$ctime,$blksize,$blocks)
	= ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
	      $atime,$mtime,$ctime,$blksize,$blocks);
return $mtime;
}

############## QuickName ##############
# Generate a relative filename based on the given URI.
#### TODO:  This is a quick and dirty POC hack that makes the
#### filenames easier to read, for debugging purposes.  
#### Production code should url-encode the URI into the filename.
sub QuickName
{
my $t = shift;
# $t = uri_escape($t);
$t =~ s|\A.*\/||;	# Chop off all but the last part of the path
$t =~ s/[^a-zA-Z0-9\.\-\_]/_/g;	# Change any bad chars to _
return $t;
}

########## AbsUri ############
# Converts (possibly relative) URI to absolute URI, using $baseUri.
sub AbsUri
{
my $uri = shift;
if ($uri !~ m/\Ahttp(s?)\:/) {
	# Relative URI
	$uri =~ s|\A\/||;	# Chop leading / if any
	$uri = "$baseUri/$uri";
	}
return $uri;
}

########## UriToPath ############
# Converts (possibly relative) URI to absolute file path (if local) 
# or returns "".
sub UriToPath
{
my $uri = shift;
my $path = &AbsUri($uri);
if ($path =~ s/\A$baseUriPattern\b/$basePath/e) {
	return $path;
	}
return "";
}

########## AbsPath ############
# Converts (possibly relative) file path to absolute path,
# using $basePath.
sub AbsPath
{
my $path = shift;
if ($path !~ m|\A\/|) {
	# Relative path
	$path = "$basePath/$path";
	}
return $path;
}

########## PathToUri ############
# Converts (possibly relative) file path to absolute URI (if local) 
# or returns "".
sub PathToUri
{
my $path = shift;
my $uri = &AbsPath($path);
if ($uri =~ s/\A$basePathPattern\b/$baseUri/e) {
	return $uri;
	}
return "";
}

########## PrintLog ############
sub PrintLog
{
open(my $fh, ">>$logFile") || die;
print $fh @_;
close($fh);
return 1;
}

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

########## MakeParentDirs ############
# Ensure that parent directories exist before creating these files.
# Directories that have already been created are remembered, so
# we won't waste time trying to create them again.
sub MakeParentDirs
{
foreach my $f (@_) {
	next if $MakeParentDirs::fileSeen{$f};
	$MakeParentDirs::fileSeen{$f} = 1;
	$f =~ m|\A(.*)\/| or die;
	my $fDir = $1 or die;
	next if $MakeParentDirs::dirSeen{$fDir};
	$MakeParentDirs::dirSeen{$fDir} = 1;
	next if $fDir eq "";	# Hit the root?
	make_path($fDir);
	-d $fDir || die;
	}
}

########## IsSameServer ############
# Is $thisUri on the same server as $baseUri?
sub IsSameServer
{
@_ == 2 or die;
my ($baseUri, $thisUri) = @_;
return ($thisUri =~ m/\A$baseUri\b/);
}

########## IsSameType ############
# Are $thisType and $inType both set and the same?  
sub IsSameType
{
@_ == 2 or die;
my ($thisType, $inType) = @_;
return $thisType && $inType && $thisType eq $inType;
}

########## LMToHeaders ############
# Turn LM (high-res last-modified) into Last-Modified and ETag headers.
sub SetLMHeaders
{
@_ == 1 or die;
# $lm should actually be a float represented as a string -- not a 
# float -- to ease comparison and avoid accidentally dropping decimal places.
my ($lm) = @_;
return("", "") if !$lm;
my $lmHeader = time2str($lm);
# ETag syntax:
# http://www.w3.org/Protocols/rfc2616/rfc2616-sec3.html#sec3.11
# and quoted-string at the end of sec 2.2:
# http://www.w3.org/Protocols/rfc2616/rfc2616-sec2.html#sec2.2
my $eTagHeader = '"' . $lm . '"';
return($lmHeader, $eTagHeader);
}

########## TimeToLM ############
# Turn a floating Time::HiRes time into an LM string, for use in headers, etc.
# The string is paddded with leading zeros for easy string comparison,
# ensuring that $a lt $b iff $a < $b.
# An empty string "" will be returned if the time is 0.
sub TimeToLM
{
@_ == 1 or die;
my ($t) = @_;
return "" if !$t || $t == 0;
# Enough digits to work through year 2286:
my $lm = sprintf("%010.6f", $t);
length($lm) == 10+1+6 or die;
return $lm;
}

########## HeadersToLM ############
# Turn Last-Modified and ETag headers into LM (high-res last-modified).
sub HeadersToLM
{
@_ == 2 or die;
my ($lmHeader, $eTagHeader) = @_;
my $lm = "";
$lm = &TimeToLM(str2time($lmHeader)) if $lmHeader;
# ETag syntax:
# http://www.w3.org/Protocols/rfc2616/rfc2616-sec3.html#sec3.11
# and quoted-string at the end of sec 2.2:
# http://www.w3.org/Protocols/rfc2616/rfc2616-sec2.html#sec2.2
if ($eTagHeader) {
  if ($eTagHeader =~ m|\A(W\/)?\"(.*)\"\Z|) {
    $lm = $2;
    }
  else {
    warn "WARNING: Bad ETag header: $eTagHeader ";
    }
  }
return $lm;
}


##### DO NOT DELETE THE FOLLOWING LINE!  #####
1;

