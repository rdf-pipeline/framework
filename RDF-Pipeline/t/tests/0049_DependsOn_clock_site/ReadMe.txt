Verify that a node that dependsOn a clock site (which cannot
be cached because it changes every time it is retrieved)
causes the node's updater to be fired on every request.

See issue 126:
https://github.com/rdf-pipeline/framework/issues/126

