#! /usr/bin/perl -w 

package MyApache2::Chain;
use strict;
use Apache2::Const -compile => qw(:common);
use Apache2::SubRequest ();       # for $r->internal_redirect

### Comment out the following line and the Apache2 child 
### segmentation fault no longer occurs:
use Test::MockObject;

sub handler 
{
my $r = shift || die;
my $f = $ENV{DOCUMENT_ROOT} . "/date.txt";
system("date >> $f 2> /dev/null");
$r->internal_redirect("/date.txt");
return Apache2::Const::OK;
}

##### DO NOT DELETE THE FOLLOWING LINE!  #####
1;

