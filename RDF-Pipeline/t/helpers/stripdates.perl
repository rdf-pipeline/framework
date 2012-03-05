#! /usr/bin/perl -w

# Remove dates and ETags, to enable easier comparison of output.
# Actually, we change them to constants.

use strict;

my $dayP = "(Sun|Mon|Tue|Wed|Thu|Fri|Sat)";
my $monP = "(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)";

while (<>) {
	# [Sun Mar 04 21:34:09 2012] 
	s/\[$dayP $monP \d\d \d\d\:\d\d\:\d\d \d\d\d\d\]/\[Sun Mar 04 21:34:09 2012\]/g;

	# Date: Thu, 19 Jan 2012 18:26:00 GMT
	# s/^Date:.*/Date: Thu, 19 Jan 2012 18:26:00 GMT/;
	s/^Date: $dayP\, \d+ $monP \d\d\d\d \d+\:\d\d\:\d\d GMT/Date: Thu, 19 Jan 2012 18:26:00 GMT/;

	# Last-Modified: Wed, 18 Jan 2012 01:30:56 GMT
	# s/^Last-Modified:.*/Last-Modified: Wed, 18 Jan 2012 01:30:56 GMT/;
	s/^Last-Modified: $dayP\, \d+ $monP \d\d\d\d \d+\:\d\d\:\d\d GMT/Last-Modified: Wed, 18 Jan 2012 01:30:56 GMT/;

	# ETag: "LM1326850256.504565000001"
	s/^ETag:.*/ETag: "LM1326850256.504565000001"/;

	print;
	}

