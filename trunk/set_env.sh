#! /bin/sh

# Set environment variables needed for testing RDF::Pipeline.
# These should be customized for your installation.

# Apache DOCUMENT_ROOT for RDF-Pipeline:
export RDF_PIPELINE_WWW_DIR=/home/dbooth/rdf-pipeline/trunk/www

# Top development directory for the RDF::Pipeline project, which must
# contain the module directory "RDF-Pipeline", and the module
# directory must contain the test directory "t":
export RDF_PIPELINE_DEV_DIR=/home/dbooth/rdf-pipeline/trunk

# Add test utilities to $PATH:
export PATH="$PATH:$RDF_PIPELINE_DEV_DIR/RDF-Pipeline/t"
export PATH="$PATH:$RDF_PIPELINE_DEV_DIR/RDF-Pipeline/t/helpers"

