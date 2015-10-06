This framework allows a data production pipeline, described in an RDF graph, to automatically invoke update mechanisms in downstream nodes after changes in upstream node data.

See "The RDF Pipeline Framework: Automating Distributed, Dependency-Driven Data Pipelines
":
http://dbooth.org/2013/dils/pipeline/

**The code has moved to github:** https://github.com/dbooth-boston/rdf-pipeline
At present, issue tracking is still here at http://code.google.com/p/rdf-pipeline/issues/list

The code is in "developer release" status: it runs and passes regression tests, but is not yet ready for general production release, as documentation and installation procedures still need development.  Code for the first two wrappers (FileNode and GraphNode) are written in Perl using Apache2 mod\_perl.  Future wrappers for Java objects are planned.  You should contact david@dbooth.org if you wish to try it, as assistance will surely be needed for configuration, etc., until the documentation and installation procedures are further developed.

Contact david@dbooth.org if you are interested in this project, either as a user or potential contributor.