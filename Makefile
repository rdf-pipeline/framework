# This Makefile is not really used much.

# Touch all files, to force caches to be stale.
touch:	
	touch www/* ont.n3 internals.n3 pipeline.n3

hello:
	cp test/hello-pipeline.n3 pipeline.n3

ex1:
	cp test/ex1-pipeline.n3 pipeline.n3

ex2:
	cp test/ex2-pipeline.n3 pipeline.n3

