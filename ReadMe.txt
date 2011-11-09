RDF Pipeline Framework, David Booth <david@dbooth.org>
http://code.google.com/p/rdf-pipeline/
See license info in License.txt

These are my (dbooth) personal notes and "To Do" list from
before I used code.google.com and had any formal bug tracker
or issues list. 

TODO:
 - Get recursive invocations working.
 - Need to be able to specify document root dirs for various prefixes.
 - Get RDF parsing working (Trine)

11/8/11: This finally worked for importing the files to code.google's
svn:

  dbooth@dbooth-laptop:~/rdf-pipeline/trunk$ svn import . https://rdf-pipeline.googlecode.com/svn/trunk/ --username david@dbooth.org -m "Initial import"

10/17/11: Need to add predicates to tell the server where to look
for caches and updaters for URIs under a particular prefix, like:
[[
 n: p:cacheRoot   ( p:FileNode "/home/dbooth/pcache/www" ) .
 n: p:updaterRoot ( p:FileNode "/home/dbooth/pcache/www" ) .
]]
This means that for any FileNode foo in namespace n: , by default the caches 
for n:foo would be at:
 	/home/dbooth/pcache/www/foo/output 
 	/home/dbooth/pcache/www/foo/inputs/...a 
 	/home/dbooth/pcache/www/foo/inputs/...b 
 	/home/dbooth/pcache/www/foo/parameters/...x 
 	/home/dbooth/pcache/www/foo/parameters/...y 
And the updater for FileNode f:foo would be at:
 	/home/dbooth/pcache/www/foo/updater 
I'm not sure whether that syntax or the following would be best:
[[
 p:FileNode p:cacheRoot   ( n: "/home/dbooth/pcache/www" ) .
 p:FileNode p:updaterRoot ( n: "/home/dbooth/pcache/www" ) .
]]

For a SPARQL server it might be something like this: 
[[
 n: p:cacheRoot   ( p:SparqlNode "http://localhost/" ) .
 n: p:cacheRoot   ( p:SparqlNode <http://localhost/> ) .  # Alternate way
 n: p:updaterRoot ( p:SparqlNode "/home/dbooth/pcache/www" ) .
]]

These facts might be stored in a graph named n: like this:
 {
 p:FileNode p:cacheRoot   "/home/dbooth/pcache/www" .
 p:FileNode p:updaterRoot "/home/dbooth/pcache/www" .
 }
This may allow easy defaulting by allowing assertions to be copied
from one named graph to another (if not already asserted).
Or maybe just use rules like:
  {
  ?hostingDomain a p:HostingDomain .	# Node prefix
  p:GlobalDefaults p:cacheRoot ( ?nodeType ?cacheRoot ) .
  FILTER NOT EXISTS {
    ?hostingDomain p:cacheRoot ( ?nodeType ?cacheRootOther ) .
    } 
  } 
  =>
  {
  ?hostingDomain p:cacheRoot ( ?nodeType ?cacheRoot ) .
  }

And:
  {
  ?nodeType rdfs:subClassOf p:Node .
  ?node a ?nodeType ; p:hostingDomain ?hostingDomain .
  # Or: 
  #   ?hostingDomain a p:HostingDomain .	# Node prefix
  #   FILTER( STR(?node) starts-with STR(?hostingDomain) )
  ?hostingDomain p:cacheRoot ( ?nodeType ?cacheRoot ) .
  FILTER NOT EXISTS {
    ?node p:cacheRoot ( ?nodeType ?cacheRootOther ) .
    } 
  } 
  =>
  {
  ?node p:cacheRoot ( ?nodeType ?cacheRoot ) .
  }

Or maybe define a general purpose p:defaultsFrom relation:
  p:hostingDomain p:defaultsFrom p:globalDefaults .
  p:HostingDomainMembers p:defaultsFrom p:globalDefaults .

Another issue: how should the SPARQL rules be specified in a way that is easy
to test in isolation, but also generalizable as a node in a pipeline?
Temp graphs would have to be unique in order to run multiple nodes
safely on the same host. 


10/14/11: Decided to use the dir/path structure described below
on 4/28/11.
[[
 - Decide what dir/path structure to use for nodes, caches, etc.
   Bear in mind that cache URIs may be arbitrarily different from node URIs,
   e.g., for a database.
]]

10/11/11: I changed 000-default back to enable pcache to run.
PanGenX cytoscape is using Tomcat on a different port now.

9/2/11: Modified /etc/apache2/sites-enabled/000-default
to make the www directory point to ~/pangenx/www instead
of ~/pcache/www , so I can run pangenx cytoscape.  It will
have to be changed back to use pcache again.

6/9/11: I should explain and hype the term "virtual cache".

6/5/11: I've been thinking about mapcar.  When B does a
conditional GET to A, A should return the concatenation of
HEAD requests to each Ai in the response body.  Therefore, 
if the conditional GET
to A yields Not-Modified, then we know that none of the Ai's
contents have changed and we don't need to request any
of them.  But if any have changed, then we'll know which
Ai changed by parsing the response body, so we can then
request only the ones that have changed.  The downside of
this is that it means that, internally, A will do two requests
to each Ai that changed: first the HEAD request, and then
later the GET request.  Instead, it would be better to be
able to do a group conditional request, sending previous
ETags for all Ai's, and getting back a list of all Ai's
with their latest ETags, and for those that had changed,
also their content.  Could this be done with a GET?  Can
a GET request include a body?  Or would all these ETags
have to be encoded into the URL?  Or would we have to use
POST?


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

5/1/11: I did some hacking on CachingRequest to try to make it
optimize local requests, because I discovered that when an HTTP
request is done recursively, it seems to create new perl instance
variables, so %config is reloaded and %cachedResponse is empty.  
That got me thinking that the RDF should assert cache filenames
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
I'm thinking of changing the directory structure for FileNodes:
	.../n			-- Node n
	.../n/updater		-- Default updater for n
	.../n/output		-- Default output cache for n
	.../n/input/		-- Directory for input caches for n
	.../n/input/...a	-- Input cache for node a (encoded URI)
	.../n/parameter/	-- Directory for parameters caches for n
	.../n/parameter/...e	-- Parameter cache for node e (encoded URI)

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

