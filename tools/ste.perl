#! /usr/bin/perl -w

# Sparql Template Expander
# See the documentation for Perl module RDF::Pipeline::Template

# You may need to set the library path environment variable $PERL5LIB 
# See http://www.perlhowto.com/extending_the_library_path
# Setting it here it this code is not really the right way to do it:
# use lib qw( /home/dbooth/rdf-pipeline/trunk/RDF-Pipeline/lib );

use RDF::Pipeline::Template qw( :all );
&GetArgsAndProcessTemplate();
exit 0;

