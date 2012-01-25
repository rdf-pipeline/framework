#! /bin/sh

# Set environment variables needed for testing RDF::Pipeline.
# These should be customized for your installation.

# Apache DOCUMENT_ROOT for RDF-Pipeline:
export RDF_PIPELINE_WWW_DIR=/home/dbooth/rdf-pipeline/trunk/www

# Module directory for RDF::Pipeline (which must have "t" subdirectory):
export RDF_PIPELINE_MODULE_DIR=/home/dbooth/rdf-pipeline/trunk/RDF-Pipeline

# Add test utilities to $PATH:
export PATH="$PATH:$RDF_PIPELINE_MODULE_DIR/t"

