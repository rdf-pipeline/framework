# RDF Pipeline Framework

This framework allows a data production pipeline, described in an RDF graph, to automatically invoke update mechanisms in downstream nodes after changes in upstream node data.

For an overview, please read <a href="http://dbooth.org/2013/dils/pipeline/">"The RDF Pipeline Framework: Automating Distributed, Dependency-Driven Data Pipelines "</a>

There is additional information on the <a href="https://github.com/rdf-pipeline/framework/wiki">project Wiki</a>.

Contact david@dbooth.org if you are interested in this project, either as a user or potential contributor. 

## Perl Implementation
This is the original implementation, described in 
<a href="http://dbooth.org/2013/dils/pipeline/">the paper mentioned above</a>.
The RDF Pipeline Framework is now being ported to JavaScript (described
below), so the perl implementation may become orphaned unless there is
other interest in it.

The perl code is in "developer release" status: it runs and passes regression tests, but is not yet ready for general production release, as documentation and installation procedures still need development. Code for the first two wrappers (FileNode and GraphNode) are written in Perl using Apache2 mod_perl. Future wrappers for Java objects are planned. You should contact david@dbooth.org if you wish to try it, as assistance will surely be needed for configuration, etc., until the documentation and installation procedures are further developed.

## JavaScript Implementation
We are currently porting the RDF Pipeline Framework to JavaScript under
node.js, using the <a href="http://noflojs.org/">NoFlo library</a>,
primarily for the GUI.  We expect to have an initial version of
this port ready for use and documented by September 2016.  If you
are interested in using it and helping with its development before
then, contact david@dbooth.org for help getting started.

