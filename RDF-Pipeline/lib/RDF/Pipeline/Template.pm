#! /usr/bin/perl -w 
package RDF::Pipeline::Template;

# RDF Pipeline Framework -- Template
# Copyright 2011 & 2012 David Booth <david@dbooth.org>
# Code home: http://code.google.com/p/rdf-pipeline/
# See license information at http://code.google.com/p/rdf-pipeline/ 

use 5.10.1; 	# It *may* work under lower versions, but has not been tested.
use strict;
use warnings;
use Carp;

require Exporter;
our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use RDF::Pipeline::Template ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = ( 'all' => [ qw(

			&ScanAndAddInputs
			&ScanAndAddOutputs
			&ScanAndAddParameters
			&ScanForList
			&ScanAndAddEnvs
			&AddPairsToHash
			&ParseQueryString
			&ExpandTemplate
			&ProcessTemplate
			&GetArgsAndProcessTemplate 

			) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(
);

our $VERSION = '0.01';

#file:RDF-Pipeline/lib/RDF/Pipeline/Template.pm
#----------------------

use URI::Escape;

# Sparql Template Expander

##################################################################
###################           MAIN            ####################
##################################################################

unless (caller) {
  print "This is the script being executed\n";
  &GetArgsAndProcessTemplate();
  exit 0;
}


##################################################################
###################         FUNCTIONS         ####################
##################################################################

################### ScanAndAddInputs ####################
# Called as: 
# ($template, $pHash) = 
#    &ScanAndAddInputs($template, $pValues, $pHash, $warningTemplate);
sub ScanAndAddInputs
{
return &ScanAndAddToHash("inputs", @_);
}

################### ScanAndAddOutputs ####################
# Called as: 
# ($template, $pHash) = 
#    &ScanAndAddOutputs($template, $pValues, $pHash, $warningTemplate);
sub ScanAndAddOutputs
{
return &ScanAndAddToHash("outputs", @_);
}

################### ScanAndAddToHash ####################
# Scan $template for a list of variables specified by the given $keyword,
# then add variable/value pairs to the given hashref, using that list 
# and the given list of values, which must be the same length.
# If no hashRef is given, a new one will be created.
# The hashref is returned.
sub ScanAndAddToHash
{
@_ <= 5 or confess "$0: ScanAndAddToHash called with too many arguments\n";
@_ >= 3 or confess "$0: ScanAndAddToHash called with too few arguments\n";
my ($keyword, $template, $pValues, $pHash, $warningTemplate) = @_;
$pHash ||= {};
my $pVars;
($template, $pVars) = &ScanForList($keyword, $template);
# my $warningTemplate = "$0: Duplicate $keyword variable name: %s\n";
&AddPairsToHash($pVars, $pValues, $pHash, $warningTemplate);
return ($template, $pHash);
}

################### ScanAndAddParameters ####################
# Scan $template for a list of parameters, which is removed from
# the returned $template.  Then, to the given hashref,
# add the corresponding values from the given $queryString.
# In selecting the values from the $queryString, delimiters are
# stripped from the variables, using &BaseVar($_).
sub ScanAndAddParameters
{
@_ <= 4 or confess "$0: ScanAndAddParameters called with too many arguments\n";
@_ >= 1 or confess "$0: ScanAndAddParameters called with too few arguments\n";
my ($template, $queryString, $pHash, $warningTemplate) = @_;
$pHash ||= {};
$queryString ||= "";
my $pVars;
($template, $pVars) = &ScanForList("parameters", $template);
my $qsHash = &ParseQueryString($queryString);
my %pWanted = map 
	{
	my $value = $qsHash->{&BaseVar($_)};
	($_, defined($value) ? $value : "")
	} @{$pVars};
foreach my $var (@{$pVars}) {
	# my $warningTemplate = "$0: Duplicate $keyword variable name: %s\n";
	warn sprintf($warningTemplate, $var)
		if $warningTemplate && exists($pHash->{$var});
	$pHash->{$var} = $pWanted{$var};
	}
return ($template, $pHash);
}

################### ScanForList ####################
# Scan $template for a declared list of variable names, such as:
#	#inputs ( $foo ${fum} )
# which is removed from the returned $template.  Also returns a hashref 
# of the variable names found in the declared list.
# The given $keyword should normally be "inputs", "outputs" or "parameters",
# but may be some other word.
sub ScanForList
{
@_ == 2 or confess "Bad args";
my $keyword = shift or confess "$0: ScanForList called with no keyword\n";
my $template = shift;
defined($template) or confess "$0: ScanForList called with undefined template\n";
my @inVars = ();
# Given keyword "inputs", the pattern matches the first line like:
#	#inputs ( $foo ${fum} )
if ($template =~ s/^\#\s*$keyword\s*\(\s*([^\)]+?)\s*\)(.*)(\n|$)//m) {
	my $inList = $1;
	my $extra = $2;
	my $line = $&;
	# warn "FOUND inList: ($inList) extra: ($extra) line: ($line)\n";
	$extra =~ s/\A\s*//;
	$extra =~ s/\A\#.*//;
	warn "$0: WARNING: Extra text ignored after \#$keyword list: $extra\n" if $extra;
	push(@inVars, split(/\s+/, $inList));
	}
return ($template, \@inVars);
}

################### ScanAndAddEnvs ####################
# Scan $template for $ENV{foo} references and add each one (as a key)
# to the given hashref, where its value will be the value of that
# environment variable (or empty string, if not set).
# If no hashref is given, one will be created.
# The hashref is returned.  Existing values in the hashref will be
# silently overwritten if a duplicate key is used.
# The $template is not modified, and therefore not returned.
sub ScanAndAddEnvs
{
my $template = shift;
my $pEnvs = shift || {};
defined($template) or confess "$0: ScanAndAddEnvs called with undefined template\n";
my @vars = ($template =~ m/\$ENV\{(\w+)\}/gi);
# warn "env vars: @vars\n";
foreach (@vars) {
	$pEnvs->{"\$ENV{$_}"} = (defined($ENV{$_}) ? $ENV{$_} : "");
	}
# my @envs = %{$pEnvs};
# warn "envs: @envs\n";
return $pEnvs;
}

################### AddPairsToHash #####################
# Add pairs of corresponding values from the two arrayrefs to the
# given hashref.  If no hashref is given, a new one will be created.
# The hashref is returned.  If an optional warning string template is 
# supplied then a warning will be generated if a duplicate key is seen.
# E.g.:
# $warningTemplate = "$0: AddPairsToHash called with duplicate variable name: %s\n";
sub AddPairsToHash
{
my ($pVars, $pVals, $pRep, $warningTemplate) = @_;
$pRep ||= {};
$pVars && $pVals or confess "$0: AddPairsToHash called with insufficient arguments\n";
my $nVars = scalar(@{$pVars});
my $nVals = scalar(@{$pVals});
$nVars == $nVals or warn "$0: WARNING: $nVals values (@{$pVals}) provided for $nVars template variables (@{$pVars}) but\n";

for (my $i=0; $i<@{$pVars}; $i++) {
	warn sprintf($warningTemplate, ${$pVars}[$i])
		if $warningTemplate && exists($pRep->{${$pVars}[$i]});
	my $val = ${$pVals}[$i];
	$val = "" if !defined($val);
	$pRep->{${$pVars}[$i]} = $val;
	}
return $pRep;
}

################### ParseQueryString ####################
# Create (or add to) a hashref that maps query string variables to values.
# Both variables and values are uri_unescaped.
# Example:
#   'foo=bar&fum=bif'  --> { 'foo'=>'bar', 'fum'=>'bif' }
# If there is a duplicate variable then the latest one silently
# takes priority.  If no hashref is given, a new one will be created.
# The hashref is returned.
sub ParseQueryString
{
my $qs = shift || "";
my $hashref = shift || {};
foreach ( split(/\&/, $qs) ) {
        my ($var, $val) = split(/\=/, $_, 2);
        $val = "" if !defined($val);
	$hashref->{uri_unescape($var)} = uri_unescape($val) if $var;
	}
return $hashref;
}

################# BaseVar ####################
# Given a string like '${fum}' (representing a declared variable), 
# return a new string with the delimiters stripped off: 'fum'.
sub BaseVar
{
my $dv = shift or confess "Bad args";	# ${fum}   -- declared variable
$dv =~ s/\A\W+//i; 	# fum}
$dv =~ s/\W+\Z//i; 	# fum
return $dv;
}

################### ExpandTemplate ####################
# Expand the given template, substituting variables for values.
# Variable/value pairs are provided in the given hashref.
sub ExpandTemplate
{
@_ == 2 or confess "Bad args";
my ($template, $pRep) = @_;
defined($template) or return undef;
# Make a pattern to match all formals:
my $pattern = join(")|(", 
	# Ensure that words aren't run together:
	# \$foo --> \$foo\b ;  foo --> \bfoo\b
	map {s/\A(\w)/\\b$1/; s/(\w)\Z/$1\\b/; $_}  
	map {quotemeta($_)} keys %{$pRep});
# warn "pattern: (($pattern))\n";
# Do the replacement and return the result:
$template =~ s/(($pattern))/$pRep->{$1}/eg 
	if defined($pattern) && length($pattern) > 0;
return $template;
}

##################### ProcessTemplate #######################
# Scan and expand a template containing variable declarations like:
#	#inputs ( $in1 ${in2} )
#	#outputs ( {out1} [out2] )
# 	#parameters( $foo ${fum} )
# $queryString supplies values for variables declared as "#parameters",
# such as: foo=bar&fum=bif&foe=bah 
# Environment variables will also be substituted where they occur
# like $ENV{foo}, though if $thisUri is set then it will be used as the 
# value of $ENV{THIS_URI} regardless of what was set in the environment.
# $pInputs and $pOutputs are array references supplying values
# for declared "#inputs" and "#outputs".
# The function warns of duplicate declared variables if $warningTemplate
# is supplied.
sub ProcessTemplate
{
@_ >= 1 && @_ <= 6 or confess "Bad args";
my ($template, $pInputs, $pOutputs, $queryString, $warningTemplate, $thisUri) = @_;
defined($template) or confess "Bad args";
$pInputs ||= {};
$pOutputs ||= {};
$queryString ||= "";
# Scan for $ENV{foo} vars:
my $pRep = &ScanAndAddEnvs($template);
# $thisUri (if set) takes precedence:
$pRep->{'$ENV{THIS_URI}'} = $thisUri if defined($thisUri);
# Scan for input, output and parameter vars and add them:
# my $warningTemplate = "$0: Duplicate $keyword variable name: %s\n";
($template, $pRep) = 
	&ScanAndAddInputs($template, $pInputs, $pRep, $warningTemplate);
($template, $pRep) = 
	&ScanAndAddOutputs($template, $pOutputs, $pRep, $warningTemplate);
($template, $pRep) = 
	&ScanAndAddParameters($template, $queryString, $pRep, $warningTemplate);
# Expand the template and we're done:
my $result = &ExpandTemplate($template, $pRep);
return $result;
}

################### GetArgsAndProcessTemplate ###################
sub GetArgsAndProcessTemplate 
{
my %args = map {($_,[])} qw(file in out param this);
my $argType = "file";
my @files = ();
my $gotParam = 0;
while (@ARGV) {
	my $arg = shift @ARGV;
	if ($arg eq "-i") { $argType = "in"; }
	elsif ($arg eq "-o") { $argType = "out"; }
	elsif ($arg eq "-p") { $argType = "param"; $gotParam = 1; }
	elsif ($arg eq "-t") { $argType = "this"; }
	elsif ($arg =~ m/\A\-/) { &Usage("$0: Unknown argument: $arg\n"); }
	else	{
		push(@{$args{$argType}}, $arg);
		}
	}
my @ins = @{$args{"in"}};
my @outs = @{$args{"out"}};
my $params = $gotParam ? join("&", @{$args{"param"}}) : $ENV{QUERY_STRING};
$params ||= "";
my @this = @{$args{"this"}};
die "$0: ERROR: Too many values given with -t option: @this\n" if @this > 1;
my $thisUri = shift @this;	# Okay if it's undef
@ARGV = @{$args{"file"}};
my $template = join("", <>);

# warn "ins: @ins\n";
# warn "outs: @outs\n";

my $warningTemplate = "$0: WARNING: Duplicate template variable declared: %s\n";
my $result = &ProcessTemplate($template, \@ins, \@outs, $params, $warningTemplate, $thisUri);

# Output the result:
print $result;
exit 0;
}

####################### Usage #######################
sub Usage
{
warn @_ if @_;
die "Usage: $0 [template] [ -i iVal1 ...] [ -o oVal1 ...] [ -p pVar1=pVal1 ...]
" . 'Arguments:
  template	
	Filename of SPARQL template to use instead of stdin.

Options:
  -i iVal1 ...		
	Values to be substituted into variables specified
	by "#inputs ( $iVar1 ... )" line in template.

  -o oVal1 ...		
	Values to be substituted into variables specified
	by "#outputs ( $oVar1 ... )" line in template.

  -p pVar1=pVal1 ...	
	URI encoded variable/value pairs to be substituted
	into variables specified by "#parameters( $pVar1 ... )"
	line in template.  Both variables and
	values will be uri_unescaped before use.  Multiple
	variable/value pairs may be specified together using
	"&" as separator: foo=bar&fum=bah&foe=bif .  If -p
	option is not used, then URI-encoded variable/value
	pairs will be taken from the QUERY_STRING environment
	variable, which is ignored if -p is used.

  -t thisUri
	Causes thisUri to be substituted for $ENV{THIS_URI}
	in template, overriding whatever value was set in 
	the environment.
';
}


##### DO NOT DELETE THE FOLLOWING TWO LINES!  #####
1;
__END__

=head1 NAME

RDF::Pipeline::Template - Perl extension for very simple template substitution.

=head1 SYNOPSIS

From the command line (ste.perl merely calls &GetArgsAndProcessTemplate):

  ste.perl [template] [ -i iVal1 ...] [ -o oVal1 ...] [ -p pVar1=pVal1 ...]

For use as a module, from within perl:

  use RDF::Pipeline::Template qw( :all );
  my $result = &ProcessTemplate($template, \@ins, \@outs, $queryString, $warningTemplate, $thisUri);

=head1 DESCRIPTION

This page documents both the RDF::Pipeline::Template module and
ste.perl, which is a tiny shell script that merely invokes
&RDF::Pipeline::Template::GetArgsAndProcessTemplate.

This module provides a very simple template substitution facility.
It was intended primarily for writing SPARQL query templates for use
in the context of the RDF Pipeline Framework, but can be used for other
things.  

Template expansion involves replacing template variables with their
values.  No other features are provided.  Template variables include
those that are declared explicitly, as described next, and environment
variables.

=head2 Declaring Template Variables

Template variables may be declared using lines like this:

  #inputs ( iVar1 iVar2 ... iVarN )
  #outputs ( oVar1 oVar2 ... oVarN )
  #parameters ( pVar1 pVar2 ... pVarN )

This declares variables iVar1 ... iVarN, oVar1 ... oVarN and pVar1 ... pVarN
for use elsewhere in the template.
It does not supply values for these variables; that is a separate step.

The hash (#) MUST be the first character of the line.  Each of these
lines is optional and is removed when the template is processed.

There is no difference in the way #input, #output and #parameter variables
are processed when a template is expanded -- they all cause values
to be substituted for the variable names when the template is expanded.
However, they differ in their purpose, the ways you can set them,
and their syntax.

Variable names listed as #inputs or #outputs 
are intended to be used for a node's inputs or outputs (respectively)
in the RDF Pipeline Framework, but you don't have to use them this way.
They can use any syntax except whitespace or parentheses:
they are not required to start or end with special characters.
However, common variable syntax conventions like $max or ${max} are a 
good idea for readability.  On the other hand, you could use a
string like <http://example/var#> as a variable name, which would
give you the effect of replacing that string throughout your template.

Variable syntax is more restrictive for #parameters variables,
because of the way they are set: each #parameters variable 
should be a word starting with a dollar sign (such as $max).  
Otherwise you won't be able to supply values for them.

=head2 Value Substitution

When a template is processed, values are substituted for all #inputs,
#outputs, #parameters and environment variables (per the syntax
described below).  If a value is not supplied
for a variable, then the empty string is silently substituted.

The template processor has no idea what you are
intending to generate, and values be any text 
(limited in size only by memory),
so for the most part
this is a simple, blind, textual substitution.

This means that if you are using this template system to generate 
queries, commands, HTML or
anything else that could be dangerous if inappropriate text were
injected, then you had better be careful to scrub your values
before invoking this template processor.

There is one small exception to this blind substitution:
the template processor will not break a word in the template.  
This means that you
can safely use a variable name like $f without fear that it will be 
substituted into template text containing the string $fred.  
Specifically, a variable beginning or ending with a "word" character
(alphanumeric plus "_") will have \b prepended or appended (or both) to
the substitution pattern, thus forcing the match to
only occur on a word boundary.
Template processing can, however, cause words to be joined together.
For example, if template variable ${eff} has the value PH , 
then a template string "ELE${eff}ANT" will become "ELEPHANT".

=head2 Supplying Values for Template Variables

The way to supply a value for a template variable depends on what kind
of template variable it is. 

=over

=item #input or #output variables

Input or output variables are set using the -i or -o command-line options, 
respectively, or passed in array references if you are calling
&ProcessTemplate directly from Perl.

=item #parameter variables

Parameter variables by default are set through the $QUERY_STRING environment
variable, which provides an ampersand-delimited list of variable=value pairs.
However, an implied dollar sign ($) is prepended to each variable 
before performing the template substitution.  In other words, parameters $min
and $max that are declared in a template as

  #parameters ( $min $max )

and used as

  The minimum is $min and the maximum is $max.

correspond to min and max in a $QUERY_STRING such as min=2&max=99 .

Parameter variables may also be set via the -p command-line option, 
which overrides the values in $QUERY_STRING, and uses the
exact same variable=value pair syntax.

If you are calling &ProcessTemplate directly from Perl, then parameter
values are supplied in a $queryString argument as a string, which has the exact
same syntax as the $QUERY_STRING environment variable.

If you specify the same variable name twice, such as in min=2&max=99&min=5 , 
the earlier value will be silently ignored, so $min will be 5.

=back 

=head2 ACCESSING ENVIRONMENT VARIABLES

In addition to any input, output or parameters that you have declared
explicitly as described above, the template expander processes 
certain variables that can be set from the environment:

=over

=item $ENV{VAR}

For any environment variable $VAR, $ENV{VAR} Will be replaced with 
the value of the $VAR environment variable (if set)
or the empty string (if unset).

=item $ENV{QUERY_STRING}

This is a special case of $ENV{VAR}.  $ENV{QUERY_STRING}
will be replaced with the value of the $QUERY_STRING environment variable
(if set) or the empty string (if unset).   This is useful if you need
access to the raw $QUERY_STRING.  Normally it is not needed, 
because #parameters variables are set from the $QUERY_STRING environment
variable, so they are usually
more convenient.  See the -p option of ste.perl.

=item $ENV{THIS_URI}

This is another special case of $ENV{VAR}.  $ENV{THIS_URI}
will be replaced with the value of the $THIS_URI environment variable
(if set) or the empty string (if unset).   See the -t option of ste.perl.

=back

=head2 EXAMPLE

Here is a complete template example:

  Template variable names are listed here:

  #inputs ( $inUri Bill ${Taft} )               # Comment okay here
  #outputs ( $outUri )
  #parameters ( $max $min )

  Below you can see the effect of template expansion:

  Inputs, outputs:
    inUri: $inUri
    B_i_l_l: Bill  "Bill"  money@Bill.me
    Taft: ${Taft}
  Parameters (either from QUERY_STRING or from -p option):
    min: $min
    max: $max
  Environment examples:
    THIS_URI: $ENV{THIS_URI}
    FOO: $ENV{FOO}
  QUERY_STRING:
    $ENV{QUERY_STRING}

  Note that the following are NOT changed, because template expansion
  will NOT break words, and it is case sensitive:

    $inUriExtra  Billion  EmBill bill

If this template is expanded using the following shell commands:

  export QUERY_STRING='min=2&max=99'
  ./ste.perl sample-template.txt -t http://example/this -i http://example/in William Taffy -o http://example/out

then the following result will be written to STDOUT:

  Template variable names are listed here:


  Below you can see the effect of template expansion:

  Inputs, outputs:
    inUri: http://example/in
    B_i_l_l: William  "William"  money@William.me
    Taft: Taffy
  Parameters (either from QUERY_STRING or from -p option):
    min: 2
    max: 99
  Environment examples:
    THIS_URI: http://example/this
    FOO: BAR
  QUERY_STRING:
    min=2&max=99

  Note that the following are NOT changed, because template expansion
  will NOT break words, and it is case sensitive:

    $inUriExtra  Billion  EmBill bill

=head2 EXPORT

None by default.

=head1 COMMAND LINE OPTIONS

When this module is used from the command line (as ste.perl, which
simply calls &GetArgsAndProcessTemplate), it has the following options:

  ste.perl [template] [ -i iVal1 ...] [ -o oVal1 ...] [ -p pVar1=pVal1 ...]

=over

=item  -i iVal1 ...

Values to be substituted into variables specified
by "#inputs ( $iVar1 ... )" line in template.

=item  -o oVal1 ...

Values to be substituted into variables specified
by "#outputs ( $oVar1 ... )" line in template.

=item  -p pVar1=pVal1 ...

URI encoded variable/value pairs to be substituted
into variables specified by "#parameters( $pVar1 ... )"
line in template.  Both variables and
values will be uri_unescaped before use.  Multiple
variable/value pairs may be specified together using
"&" as separator: foo=bar&fum=bah&foe=bif .  If -p
option is not used, then URI-encoded variable/value
pairs will be taken from the QUERY_STRING environment
variable, which is ignored if -p is used.

At present, the -p option does not actually set the $ENV{QUERY_STRING} 
variable: $ENV{QUERY_STRING} always gives the value
of the $QUERY_STRING environment variable, regardless of whether
the -p option was used.  
This is inconsistent with the -t option, which does set
the value of $ENV{THIS_URI}.
I don't know if this is a bug or not.  :)

item  -t thisUri

Causes thisUri to be substituted for $ENV{THIS_URI}
in template, overriding whatever value was set in
the environment.

=back

=head1 SEE ALSO

RDF Pipeline Framework: http://code.google.com/p/rdf-pipeline/ 

=head1 AUTHOR

David Booth <lt>david@dbooth.org<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2011 & 2012 David Booth <david@dbooth.org>
See license information at http://code.google.com/p/rdf-pipeline/ 

=cut

