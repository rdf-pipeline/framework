#file:MyApache2/Rocks.pm
#----------------------

# See http://perl.apache.org/docs/2.0/user/intro/start_fast.html

package MyApache2::Rocks;

use strict;
use warnings;

use Apache2::RequestRec ();
use Apache2::RequestIO ();

use Apache2::Const -compile => qw(OK);

sub handler {
	my $r = shift;

	$r->content_type('text/plain');
	print "mod_perl 2.0 rocks!\n";

	return Apache2::Const::OK;
}
1;

