000-default is an Apache2 configuration file for the RDF
Pipeline framework.  Under Ubuntu 10.04 it lives at
/etc/apache2/sites-enabled (and owned by root).  The location may differ
under other operating systems.   

You will need to modify the contents of 000-default to run
the RDF Pipeline Framework.  To see what portions should be
modified, compare it to 000-default.old to see what lines I (dbooth)
changed to enable it on my system.  Actually, i think I goofed
and clobbered the .old file, as it does not seem to be the original.

Note also that other applications may be using this configuration file
as well, so you should be careful not to mess them up.

WARNING: Do not create an extra .old file in /etc/apache2/sites-enabled ,
as *every* file in that directory seems to be read as a configuration file.
http://www.debian-administration.org/articles/412
 
