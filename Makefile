# This Makefile is not really used much.

# Touch all files, to force caches to be stale.
touch:	
	( cd $(RDF_PIPELINE_WWW_DIR) ; rm -rf lm cache )

hello:
	cp test/hello-pipeline.n3 pipeline.n3

ex1:
	cp test/ex1-pipeline.n3 pipeline.n3

ex2:
	cp test/ex2-pipeline.n3 pipeline.n3

