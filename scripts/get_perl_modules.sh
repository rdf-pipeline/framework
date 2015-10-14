#!/bin/bash

# Clear the variables we are going to use here
if [ ! -z "$TOOLS" ]; then
   unset TOOLS
fi 

if [ ! -z "$MODULES" ]; then
   unset MODULES
fi

export TOOLS=`find ../tools -type f -print | perl -n -e 'chomp; print "$_\n" if !system("file $_ | grep -q -i perl")'`

echo "TOOLS:"
echo $TOOLS
echo ""

export MODULES=`cat ../RDF-Pipeline/lib/RDF/Pipeline.pm ../RDF-Pipeline/lib/RDF/Pipeline/* $TOOLS | grep -P '^(use|require) ' | perl -p -e 's/^.*? //; s/[ ;].*$//; s/^[0-9].*//; s/^(strict|warnings)$//; s/^RDF::Pipeline.*//; s/^(Apache2::Const)$//' | sort -u`

echo "MODULES:"
echo $MODULES
echo ""

export PERL_MM_USE_DEFAULT=1

echo Installing modules... may take 20 minutes or so.  Be patient
cpan $MODULES

echo Picking up RDF helper constants module
cpan RDF::Helper::Constants
echo cpan module update completed successfully.


