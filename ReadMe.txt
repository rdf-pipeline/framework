RDF Pipeline Framework, Copyright 2011 David Booth <david@dbooth.org>
http://code.google.com/p/rdf-pipeline/
See license info in License.txt

These are my (dbooth) personal notes and "To Do" list from
before I used code.google.com and had any formal bug tracker
or issues list. 

11/25/11: May want to separate out recursive from non-recursive refresh,
thus handling a conditional GET like this:
 - Recursively freshen inputs (if recursive)
 - Check if thisLM is stale wrt inputs
 - Update thisLM if stale
 - Check if callerLM is stale
 - Return updated content if stale
Local FRESHEN event types might have args: $recursive, $force.
An external GET corresponds to a recursive freshen.

11/24/11: Info about flock and locking:
http://perl.apache.org/docs/1.0/guide/debug.html
http://modperlbook.org/html/6-9-2-2-Safe-resource-locking-and-cleanup-code.html

11/14/11: Typical HTTP response headers:
[[
HTTP/1.1 200 OK
Date: Mon, 14 Nov 2011 19:51:49 GMT
Server: Apache/2.2.20
X-Powered-By: PHP/5.3.8
P3P: CP="NOI NID ADMa OUR IND UNI COM NAV"
ETag: "8002cca87d79536d4479bd9da0b8f977"
Vary: Accept-Encoding
Last-Modified: Fri, 17 Dec 2010 09:51:23 GMT
Content-Length: 5971
Connection: close
Content-Type: text/html; charset=iso-8859-1
]]

11/11/11: Thinking about how to rewrite FileNodeHandler to be
closer to a generic NodeHandler.
This is for a lazy update policy.  Rough pseudo-code:
[[
sub ForeignNodeHandler
{
my $r = shift; 		# Apache2::RequestRec passed to handler()
my $thisUri = shift; 	# URI of node requested (w/o query string)
my $nodeFunctions = shift; # Hash of node-type-specific functions

my $thisMetadata = $nodeMetadata{$thisUri};

#    1. Recursively call LocalNodeHandler on $thisUri/serializer
#    2. return $error if $error
#    3. sendfile $thisUri/serializer/state
my $serializerUri = $thisMetadata->{serializerUri}; 
my $callerLMH = $r->headers{If-Modified-Since};
my $callerETagH = $r->headers{If-None-Match};
my $callerLM = &HeadersToLM($callerLMH, $callerETagH);
my ($error, undef, undef) = &LocalNodeHandler($serializerUri, $callerLM, $callerETag, $nodeFunctions, $r);
return $error if $error;
my $serializerStateUri = $thisMetadata->{serializerStateUri};
TODO: use sendfile instead:
$r->internal_redirect($serializerStateUri);
return "";	# No error
}

# There three special cases to handle when this node is: (a) a getter;
# (b) a serializer; or (c) a deserializer.
# $thisMetadata->{isGetter}, $thisMetadata->{isSerializer} etc.
# are used in the code below to handle these cases.

sub LocalNodeHandler
{
# Called as:
# my $LM = &LocalNodeHandler($thisUri, $callerLM);
my $thisUri = shift; 	# URI of node requested (w/o query string)
my $callerLM = shift;	# Hi-res Last-Modified sent from downstream caller
my $thisMetadata = $nodeMetadata{$thisUri};
my ($thisIsStale, $pInLMs) = &CheckIfStale_Lazy($thisUri);
if ($thisIsStale) {
  my ($prevLM, %prevInLMs) = &LookupLMs($thisUri);
  my $updater = $thisMetadata->{updater};
  my $fRunUpdater = $thisMetadata->{fRunUpdater};
  my $newLM = &{$fRunUpdater}($updater, $thisUri, $prevLM, $r, $nodeMetadata);
  # %inLMs are saved even if $newLM did not change, because it will
  # make the node less likely to be considered stale (wrt inputs) and
  # thus less likely to run the updater unnecessarily.
  &SaveInLMs($thisUri, \%inLMs);
  # These are compared as strings because they are sent in headers as strings:
  if ($newLM ne $prevLM) {
    &SaveLM($thisUri, $newLM);
    # So we don't have to look it up again to return it:
    $prevLM = $newLM;
    }
  }
return $prevLM;
}

sub CheckIfStale_Lazy
{
# Is this node's state stale, using lazy update policy?
# New input LMs are returned in $pInLMs parameter.
# Called as:
# my $thisIsStale = &CheckIfStale(\%inLMs, $thisUri, $event, $nodeFunctions, $r);
my ($pInLMs, $thisUri, $event, $nodeFunctions, $r) = @_;
my $thisMetadata = $nodeMetadata{$thisUri};
my $fStateExists = $thisMetadata->{fStateExists});
return 1 if !&{$fStateExists}($thisUri);
my ($prevThisLM, %prevInLMs) = &LookupLMs($thisUri);
return 1 if !$prevThisLM;
my $fRefreshInput = $thisMetadata->{fRefreshInput});
my $thisIsStale = 0;		# Default (fresh) if no input changed
# Don't exit the loop early if an input changed, because we still
# want to ensure that other inputs are fresh.
foreach my $inUri (@{$thisMetadata->{dependsOn}}) {
  my $prevInLM = $prevInLMs{$inUri};
  my $newInLM = &{$fRefreshInput}($thisUri, $inUri, $prevInLM, $nodeFunctions, $r);
  # String comparison because LMs are also sent in HTTP ETag headers:
  $thisIsStale = 1 if $newInLM ne $prevInLM;
  $pInLMs->{$inUri} = $newInLM;
  }
return $thisIsStale;
}


sub RefreshLocalInput
{
# Ensure that the input is fresh, recursively.
# Called as:
# my $newInLM = &RefreshInput($thisUri, $inUri, $prevInLM, $nodeFunctions, $r);
my ($thisUri, $inUri, $prevInLM, $nodeFunctions, $r) = @_;
my $thisMetadata = $nodeMetadata{$thisUri};
my ($prevLM, $prevETag) = &LookupHeaders($thisUri, $inUri);
my $newInLM = &LocalNodeHandler($inUri, $prevLM, $prevETag, $nodeFunctions, $r);
return($error, undef) if $error;
my $inChanged = ($prevLM ne $inLM || $prevETag ne $inETag);
return("", $inChanged);
}



sub ConditionalGet
{
my ($inUri, $fileName, $prevLM, $prevETag, $isLocal, $nodeFunctions) = @_;
my ($prevLMH, $prevETagH) = &HeadersFromLM($prevLM);
my $req = HTTP::Request->new('GET' => $inUri);
$req->header('If-Modified-Since' => $prevLMH) if $prevLMH;
$req->header('If-None-Match' => $prevETagH) if $prevETagH;
my $ua = LWP::UserAgent->new;
$ua->agent("$0/RDF-Pipeline/0.01 " . $ua->agent);
my $res = $ua->request($req);
$res || die "ConditionalGet: Failed to GET from $inUri ");
$status = $res->code;
Save content to $fileName
my $newLMH = Last-Modified header 
my $newETagH = ETag header 
my $newLM = &HeadersToLM($newLMH, $newETagH);

return $newLM;
}

sub HeadersFromLM
{
# Converts hi-res last modified time to Last-Modified and ETag HTTP headers.
}

sub HeadersToLM
{
# Converts hi-res last modified time to Last-Modified and ETag HTTP headers.
}

sub TimeToLM
{
# Converts numeric hi-res last modified time to string LM time suitable
# for string comparison.
}

]]

11/12/11:
# Documentation on handlers:
# http://perl.apache.org/docs/2.0/user/handlers/http.html#PerlResponseHandler
# http://perl.apache.org/docs/2.0/api/Apache2/RequestRec.html
# Getting the request URI:
# http://search.cpan.org/~rkobes/CGI-Apache2-Wrapper-0.215/lib/CGI/Apache2/Wrapper.pm#Apache2::URI
# Header examples/viewer: http://web-sniffer.net/
# Apparently the handler is called with an Apache2::RequestIO object:
# http://perl.apache.org/docs/2.0/api/Apache2/RequestIO.html
# and Apache2::RequestIO extends Apache2::RequestRec:
# http://perl.apache.org/docs/2.0/api/Apache2/RequestRec.html

11/10/11: It looks like the main body of Chain.pm (outside 
of any functions) is executed once when a request comes in
and a new PerlInterpreter needs to be initialized.
Thereafter, each PerlInterpreter instance retains all
of the "my" variables that are in the main body, in
between requests.  However, I believe each PerlInterpreter
instance has its own separate set of "my" variables.
Reading on Apache2 thread support and the PerlInterpreters pool:
http://perl.apache.org/docs/2.0/user/design/design.html#Interpreter_Management
http://modperlbook.org/html/24-3-1-Thread-Support.html

11/10/11: I tried the following, but then discovered that
I had been working on a different copy of Chain.pm, and
thus none of my tests had taken effect.  So I need to
try them again.  They are:
[[
I tried changing %config and a few other variables to
package variables, but ont.n3 still gets reloaded on every HTTP
request.  I then tried using threads::shared and marking them
as shared (both as package and as my variable), but got the 
same behavior.  Then I tried Apache::Session::File, but I
could not figure out any way to initialize the session ID.
The documentation unhelpfully says:
http://search.cpan.org/~chorny/Apache-Session-1.89/lib/Apache/Session.pm#Sharing_data_between_Apache_processes
[[
When you share data between Apache processes, you need to decide on a
session ID number ahead of time and make sure that an object with that
ID number is in your object store before starting your Apache. How you
accomplish that is your own business. I use the session ID "1".
]]
AFAICT, I would have to figure out how to use Storable (since
Apache::Session::File seems to use that) to initialize the
session ID, which seems like a ridiculous pain.  The alternate
seems to be to use undef for the session ID when starting,
let it generate one for me, and then store that somewhere
where all Apache threads/processes can access it.  (In a
file?  Trying to put it in $ENV{RDF_PIPELINE_SESSION_ID} 
did not work, as it was cleared on each HTTP request.)
]]

11/10/11: Apache2::Reload did not seem to work for me when
I tried it:
[[
package MyApache2::Chain;
# http://perl.apache.org/docs/2.0/api/Apache2/Reload.html
use Apache2::Reload;
]]
I still seem to have to stop and restart apache2 to get it
to use my latest Chain.pm.

11/10/11: Based on the example I have added to my slides:
[[
Input caching: Foreign environments
 - “Foreign environment” means different servers or node types
 - Node inputs are locally cached.  E.g. for node C: 
   - A-output' is a local copy of A-output
   - B-output' is a local copy of B-output

Input caching: Local environment
 - “Local environment” means same server and node type
 - Node inputs are accessed directly from predecessor node outputs
   - No separate copy
 - Node C accesses A-output and B-output directly

Input caching: Mixed foreign and local
 - Local cache is used for foreign input nodes
 - Direct access is used for local input nodes

Input caching: Shared local caches
 - Nodes C and E share the same local cache B-output'

Internals: Freshness and response headers
 - For each output cache, the server remembers the input response headers on which the current output was based, e.g., Last-Modified, ETag, etc.
 - E-output is stale
 - C-output is fresh
]]

It looks like a special, hidden node could be used for B-output', 
and then AnyChanged would always do the equivalent of HEAD 
requests -- never GETs -- though they are internal to server.

11/10/11: A node dependsOn both its inputs and its parameters
(which could be viewed as a subclass of inputs) and potentially
other things, such as its updater.  What should these things
be called collectively?  "Dependency" is ambiguous about its
direction.  How about "intakes" or even "ins"?  Might be good enough.

Example of ambiguity of "dependency": In "George has an alcohol
dependency", George dependsOn alcohol.  But in "England has
India as a dependency", India dependsOn England, which is
the opposite way around.  I.e., it is not clear whether
"X hasDependency Y" means "X dependsOn Y" or "Y dependsOn X".

11/9/11: If an RDF Pipeline is going to be used with many rapid requests
then it will become necessary to make nodes have the usual ACID
database properties. 

11/8/11: This finally worked for importing the files to code.google's
svn:

  dbooth@dbooth-laptop:~/rdf-pipeline/trunk$ svn import . https://rdf-pipeline.googlecode.com/svn/trunk/ --username david@dbooth.org -m "Initial import"

10/17/11: Another issue: how should the SPARQL rules be specified in a way that is easy
to test in isolation, but also generalizable as a node in a pipeline?
Temp graphs would have to be unique in order to run multiple nodes
safely on the same host. 

9/2/11: Modified /etc/apache2/sites-enabled/000-default
to make the www directory point to ~/pangenx/www instead
of ~/pcache/www , so I can run pangenx cytoscape.  It will
have to be changed back to use pcache again.

6/9/11: I should explain and hype the term "virtual cache".

5/26/11: I got RDF::LinkedData working using Plack, thanks to
http://www.perlrdf.org/slides/perlrdf-intro.xhtml
This provides a LinkedData server, so that individual RDF URIs
can be dereferenced, which isn't quite what I need.  I need
to set up a SPARQL server that responds to HTTP requests.


5/25/11: Why INSERT instead of CONSTRUCT?  Efficiency: CONSTRUCT merely
*returns* the constructed graph, so in SPARQL it would be necessary
to re-insert it into a new graph anyway.

5/9/11: PURL domain was approved, so I'm renaming all of
the p: namespaces to use it.

5/1/11: I did some hacking on CachingRequest . . . and that
got me thinking that the RDF should assert cache filenames
for a node's:
	output cache:      :c p:output "c/output" .
	input caches:      :c p:cache (:a "c/cache/a") .
	                   :c p:cache (:b "c/cache/b") .
	parameter caches:  :c p:cache (:d "c/cache/d") .
	                   :c p:cache (:e "c/cache/e") .
I added these two properties to rules.n3, though I'm thinking
that maybe I should move p:cache to an internals.n3 file.
The output cache might be asserted by the user, but others
would be asserted by the framework.  But this involves 
string operations on the URIs, and I don't know how to
do this in n3.  BTW, I don't think caches need to be used
for other p:dependsOn nodes, because the framework does
not pass them as parameters to the updater.
I also started writing InferFileNodeCaches but got bogged
down and realized it would take too long to get it working,
so I abandoned it for the moment, in order to focus on
jena and my presentation.

4/28/11:
TODO: I think I have the logic of AnyChanged wrong.  I need to think
through HEAD versus GET requests, and figure out whether AnyChanged
should ever issue HEAD requests, and if so, under what conditions.
(Perhaps only if the original request is HEAD?)  Basically, if the
original request is GET, then it seems like AnyChanged should issue
conditional GETs, because if any node has changed, then we would have
to do another GET on it anyway, to get the latest content.  But if
the original request was HEAD, what should be done?  In order to return
a new Last-Modified header, it seems to me that the node *must* update
its output cache, and that would mean that upstream request should
all be conditional GETs, instead of HEADs, just as if the original
request were a GET.  In other words, it seems like the 
transitive behavior would be the same as with a GET request.  It
is only the original request that would become an internal redirect
to a HEAD request on the output cache.

TODO: Furthermore, the caching should only use files, and (to optimize)
when possible the file that is returned by CachingRequest should be 
the input/parameter node's output cache (if local).  I don't think
there's a need for hashmap caching of inputs/parameters in memory,
because all we need to do is pass the filenames as arguments to the 
updaters.

4/28/11:
TODO: I should fix the file cache naming to use URL encoding.
Package URI::Escape seems to work beautifully.  This test program:
[[
#!/usr/bin/perl
use URI::Escape;
my $string = shift;
my $encode = uri_escape($string);
my $s = uri_unescape($encode);
print "Original string: $string\n";
print "URL Encoded string: $encode\n";
print "Original string: $s\n";
]]
produced this output:
[[
$ ./test.perl 'http://www.perlhowto.com/encode_and_decode_url_strings'
Original string: http://www.perlhowto.com/encode_and_decode_url_strings
URL Encoded string: http%3A%2F%2Fwww.perlhowto.com%2Fencode_and_decode_url_strings
Original string: http://www.perlhowto.com/encode_and_decode_url_strings
]]


4/28/11:
I did an experiment to see if a GET request on a file://... URI
using LWP::UserAgent would return a 200 code and Last-Modified,
and it does!  Code:
[[
	# Testing whether a GET on a file: URI will work and
	# return a 200 code and Last-Modified, and it does!
	# This means that I could always use URIs, instead of
	# sometimes using URIs and sometimes filenames.
	my $fUri = "file:///home/dbooth/pcache/update.txt";
	my $res = &CachingRequest("GET", $thisUri, $fUri);
	my $t = $res->decoded_content() || "(undef)";
	my $success = $res->is_success || "(undef)";
	my $code = $res->code || "(undef)";
	my $oldLM = $res->header('Last-Modified') || "(undef)";
	my $oldETag = $res->header('ETag') || "(undef)";
	&PrintLog("CachingRequest($thisUri, $fUri) returned success: $success code: $code oldLM: $oldLM oldETag: $oldETag content:\n[[\n$t]]\n");
]]
Log file result:
[[
CachingRequest(http://localhost/b, file:///home/dbooth/pcache/update.txt) returned success: 1 code: 200 oldLM: Wed, 27 Apr 2011 16:02:40 GMT oldETag: (undef) content:
[[
1. /* Called before getting data from child */
2. function LazyUpdate(PCache child) {
3.   /* “contributes to” is the inverse of “depends on” */
4.   foreach PCache parent that contributes to child {
5.       LazyUpdate(parent);
6.     }
7.   if IsOutOfDate(child) then child.update();
8. }
]]
]]


3/11/11:
Apache normally runs under user www-data.  This means that my updater
scripts cannot write to a dbooth-owned directory unless setuid is done.
I wrote a setuid-wrapper that works (though it probably opens a big
security hole), but then when I tried to let a script write to stdout
and redirect that to a file, I again had a problem.  So I wrote
redirect-stdout, but then decided that this path is not the right
approach, because it requires that every updater be setuid.  

I've now decided to change Apache to run under user dbooth instead
of www-data.  For security, it is important that it only respond
to local requests (from 127.0.0.1).  Instructions for setting this:
https://help.ubuntu.com/10.04/serverguide/C/httpd.html
The setting was made in /etc/apache2/ports.conf

I changed the Apache user to dbooth in
/etc/apache2/envvars
and expect to also have do chown the logs.  Actually, I see that
/var/log/apache2/access.log
is already owned by root, so I guess I don't have to chown the logs.

