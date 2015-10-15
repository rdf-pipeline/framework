#! /bin/sh

<<<<<<< HEAD
# This script sets the environment variables needed for testing RDF::Pipeline.
# These should be customized for your installation.

# Pick up the directory where this script is currently executing.  We use $_ 
# here because our script may be sourced or simply executed manually - we want
# to handle both cleanly
export RDF_PIPELINE_DEV_DIR=$(dirname "$_")

# Helper function to see if a substring is contained within a string or not.  
contains() {
    string="$1"
    substring="$2"
    if test "${string#*$substring}" != "$string"
    then
        return 0    # $substring is in $string
    else
        return 1    # $substring is not in $string
    fi
}
=======
# Set environment variables needed for testing RDF::Pipeline.

# Only the RDF_PIPELINE_DEV_DIR and APACHECONFIG must be set manually.
# All others are (normally) set automatically by this script.
#
# RDF_PIPELINE_DEV_DIR must be set to the top development directory 
# for the RDF::Pipeline project (as checked out from github), which must
# contain the module directory "RDF-Pipeline".

export RDF_PIPELINE_DEV_DIR=/home/dbooth/rdf-pipeline/trunk
APACHECONFIG="/etc/apache2/sites-enabled/000-default"

#################################################################
# All variables beyond this point are set automatically (unless
# something goes wrong).
#################################################################

# Set RDF_PIPELINE_WWW_DIR.  Use $DOCUMENT_ROOT if set, or look
# in the default Apache2 config file for the DocumentRoot definition.
if [ ! "$DOCUMENT_ROOT" ]
then
	DOCROOT=`expand "$APACHECONFIG" | grep '^ *DocumentRoot ' | sed 's/^ *DocumentRoot *//'`
	WORDCOUNT=`echo "$DOCROOT" | wc -w`
	if [ $WORDCOUNT = 1 ]
	then
		export DOCUMENT_ROOT="$DOCROOT"
	elif [ $WORDCOUNT = 0 ]
	then
		echo '[ERROR] DocumentRoot not found in' "$APACHECONFIG" 1>&2
	else
		echo '[ERROR] Multiple DocumentRoot definitions found in' "$APACHECONFIG": "$DOCROOT" 1>&2
	fi
fi
export RDF_PIPELINE_WWW_DIR="$DOCUMENT_ROOT"
>>>>>>> deb2898aa51980190bdc824d340d997befd84a55

# Perl library path - avoid duplicate additions to it  
RDF_PIPELINE_PERL_PATH="${RDF_PIPELINE_DEV_DIR}/RDF-Pipeline/lib"
if ! contains "$PERL5LIB" "$RDF_PIPELINE_PERL_PATH"; then
    if [ -z "$PERL5LIB" ]; then
        export PERL5LIB=${RDF_PIPELINE_PERL_PATH}
    else 
        export PERL5LIB="${PERL5LIB}:${RDF_PIPELINE_PERL_PATH}"
    fi
fi

# Add test utilities to $PATH:
export PATH="$PATH:$RDF_PIPELINE_DEV_DIR/RDF-Pipeline/t"
export PATH="$PATH:$RDF_PIPELINE_DEV_DIR/RDF-Pipeline/t/helpers"

# Add tools utilities to $PATH:
export PATH="$PATH:$RDF_PIPELINE_DEV_DIR/tools"

# Add generic sparql utilities to path (initially sesame,
# but eventually should become generic):
export PATH="$PATH:$RDF_PIPELINE_DEV_DIR/tools/gsparql/scripts/sesame2_6"


# if the DOCUMENT_ROOT env var is NOT set or is empty, then dyamically 
# look up the Apache document root  and set it.  This code handles both 
# a hard coded path, and the case where the apache DocumentRoot is set to
# an environment variable.
if [ -z "$DOCUMENT_ROOT" ]; then

    # Depending on apache version, we may have 000-default or 000-default.conf
    # get the right config file for this system
    if [ -f /etc/apache2/sites-enabled/000-default ]; then
        APACHECONFIG="/etc/apache2/sites-enabled/000-default"
    elif [ -f /etc/apache2/sites-enabled/000-default.conf ]; then
        APACHECONFIG="/etc/apache2/sites-enabled/000-default.conf"
    else
        echo "Apache configuration was not found!"
        exit 1
    fi

    # Search for DocumentRoot in the apache config
    DOCROOT=`expand "$APACHECONFIG" | grep '^ *DocumentRoot ' | sed 's/^ *DocumentRoot *//'`

    # Check to see if we found one and only one DocumentRoot in the apache config
    WORDCOUNT=`grep "DocumentRoot" $APACHECONFIG | wc -l`
    if [ $WORDCOUNT -eq 1 ]; then

        # Is the DocumentRoot a simple string containing the path to use, 
        # or is it an environment variable? Check to see if starts with a $ char
        if [ "`expr \"$DOCROOT\" : \"$.*\"`" != "0" ];then

            # Got an env var for document root, not a simple file path -> check apache envvars for the value
            # First, check that we have an envvars file to look at 
            if [ -f /etc/apache2/envvars ]; then
                APACHE_ENVVARS="/etc/apache2/envvars"
            else
                echo DocumentRoot is a variable but no Apache envvars file was found to resolve it.
                exit 1
            fi

            # Remove the first char (the $) from the env variable name
            DOCROOT_VAR=`echo $DOCROOT | cut -d "$" -f 2` 

            # Are there braces on that DocumentRoot env var?
            if [ "`expr \"$DOCROOT_VAR\" : \"{.*\"`" != "0" ];then
                DOCROOT_VAR=`echo $DOCROOT_VAR | cut -d "{" -f 2 | cut -d "}" -f 1`
            fi

            # Extract the environment variable value from the apache envvars file
            DOCROOT=`expand "$APACHE_ENVVARS" | grep "$DOCROOT_VAR" | cut -d "=" -f 2`
        fi

        # Set the Document Root that was found in the apache config, or in the env var lookup
        export DOCUMENT_ROOT="$DOCROOT"

    elif [ $WORDCOUNT -eq 0 ];  then
        echo '[ERROR] DocumentRoot not found in' "$APACHECONFIG"
    else
        echo '[ERROR] Multiple DocumentRoot definitions found in' "$APACHECONFIG": "$DOCROOT"
    fi
fi

# If it is not already set, default RDF_PIPELINE_WWW_DIR to use whatever
# the Apache Document Root is set to.
if [ -z "$RDF_PIPELINE_WWW_DIR" ]; then
   export RDF_PIPELINE_WWW_DIR="$DOCUMENT_ROOT"
fi

