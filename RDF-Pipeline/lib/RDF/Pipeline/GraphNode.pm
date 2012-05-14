#! /usr/bin/perl -w 
package RDF::Pipeline::GraphNode;

# RDF Pipeline Framework -- GraphNode
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

# This allows declaration	use RDF::Pipeline::GraphNode ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = ( 'all' => [ qw(
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(
);

our $VERSION = '0.01';

#file:RDF-Pipeline/lib/RDF/Pipeline/GraphNode.pm
#----------------------

############# GraphNodeRegister ##############
sub GraphNodeRegister
{
@_ == 1 || die;
my ($nm) = @_;
$nm->{value}->{GraphNode} = {};
$nm->{value}->{GraphNode}->{fSerializer} = \&GraphNodeSerializer;
$nm->{value}->{GraphNode}->{fDeserializer} = \&GraphNodeDeserializer;
$nm->{value}->{GraphNode}->{fUriToNativeName} = undef;
$nm->{value}->{GraphNode}->{fRunUpdater} = \&RDF::Pipeline::FileNodeRunUpdater;
$nm->{value}->{GraphNode}->{fRunParametersFilter} = \&RDF::Pipeline::FileNodeRunParametersFilter;
$nm->{value}->{GraphNode}->{fExists} = \&RDF::Pipeline::FileExists;
$nm->{value}->{GraphNode}->{defaultContentType} = "text/html";
}

############# GraphNodeSerializer ##############
sub GraphNodeSerializer
{
@_ == 4 || die;
my ($serFilename, $deserName, $contentType, $hostRoot) = @_;
$serFilename or die;
$deserName or die;
die if $serFilename eq $deserName;
die if $contentType && $contentType !~ m|html|i;
$hostRoot = $hostRoot;  # Avoid unused var warning
open(my $deserFH, $deserName) || die;
my $all = join("", <$deserFH>);
close($deserFH) || die;
# Write to the serialized file:
open(my $serFH, ">$serFilename") || die;
# Add HTML tags:
print $serFH "<html>\n<body>\n";
print $serFH $all;
print $serFH "</body>\n</html>\n";
close($serFH) || die;
return 1;
}

############# GraphNodeDeserializer ##############
sub GraphNodeDeserializer
{
@_ == 4 || die;
my ($serFilename, $deserName, $contentType, $hostRoot) = @_;
$serFilename or die;
$deserName or die;
die if $serFilename eq $deserName;
die if $contentType && $contentType !~ m|html|i;
$hostRoot = $hostRoot;  # Avoid unused var warning
open(my $serFH, $serFilename) || confess "ERROR ";
my $all = join("", <$serFH>);
close($serFH) || die;
# Get rid of HTML tags:
($all =~ s/\<html\b[^\>]*\>/ /ig) or die;
$all =~ s/\<[^\>]*\>/ /g;
$all =~ s/\A[\s\n]+//;
$all =~ s/[\s\n]+\Z/\n/;
# Write to the deserialized file:
&RDF::Pipeline::MakeParentDirs($deserName);
open(my $deserFH, ">$deserName") || confess "ERROR: Cannot write to $deserName\n ";
print $deserFH $all;
close($deserFH) || die;
return 1;
}



##### DO NOT DELETE THE FOLLOWING TWO LINES!  #####
1;
__END__

=head1 NAME

RDF::Pipeline::GraphNode - Perl extension for blah blah blah

=head1 SYNOPSIS

  use RDF::Pipeline::GraphNode;
  blah blah blah

=head1 DESCRIPTION

Stub documentation for RDF::Pipeline::GraphNode, created by h2xs. It looks like the
author of the extension was negligent enough to leave the stub
unedited.

Blah blah blah.

=head2 EXPORT

None by default.


=head1 SEE ALSO

Mention other useful documentation such as the documentation of
related modules or operating system documentation (such as man pages
in UNIX), or any relevant external documentation such as RFCs or
standards.

If you have a mailing list set up for your module, mention it here.

If you have a web site set up for your module, mention it here.

=head1 AUTHOR

David Booth <lt>david@dbooth.org<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2011 & 2012 David Booth <david@dbooth.org>
See license information at http://code.google.com/p/rdf-pipeline/ 

=cut

