#! /usr/bin/perl -w

# Remove dates and ETags, to enable easier comparison of output.

use strict;

while (<>) {
	# Date: Thu, 19 Jan 2012 18:26:00 GMT
	s/^Date:.*/Date: Thu, 19 Jan 2012 18:26:00 GMT/;

	# Last-Modified: Wed, 18 Jan 2012 01:30:56 GMT
	s/^Last-Modified:.*/Last-Modified: Wed, 18 Jan 2012 01:30:56 GMT/;

	# ETag: "1326850256.504565000001"
	s/^ETag:.*/ETag: "1326850256.504565000001"/;

	print;
	}

