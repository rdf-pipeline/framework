#! /usr/bin/perl -w 
package HashLog;

# Sharable persistent hashmap.  This module implements a hashmap that is backed
# by a persistent logFile, and may be shared by multiple processes and/or
# threads that need to access a shared hashmap.  Access is controlled by
# advisory file locking (using flock).  Changes to the hashmap are written
# to the logFile, which is automatically rewritten when the number of 
# obsolete entries exceeds given threshold settings.
#
# This code has been tested -- see "Unit Testing" below --  but 
# not well documented (yet), and it might be nice to make it
# object-oriented at some point, with a constructor and all.
# For the moment, you can see how it works in the unit tests.
# 
# Copyright 2021 by David Booth <david@dbooth.org>
# This software is available as free and open source under
# the Apache 2.0 software license, which may be viewed at
# http://www.apache.org/licenses/LICENSE-2.0.html
# Code home: https://github.com/rdf-pipeline/

use 5.10.1; 	# It has not been tested on other versions.
use strict;
use warnings;

use Exporter qw(import);
 
our @EXPORT = qw(
	HLClear
	HLInsert
	HLDelete
	HLGet
	HLGetKeys
	HLForceRewriteLog
	HLPrintAll
	);

our $VERSION = '0.01';

use Carp;
use Fcntl qw( :flock :seek );

use File::Path qw(make_path remove_tree);
use File::Touch 0.12;
use Getopt::Long;
# use Test::Simple;
use Test2::Suite;
use Test2::V0;

my $debug = 0;

######################################################
################## Unit Testing ######################
######################################################
# To run unit tests, manually set $runUnitTests to 1 or 2 below, then
# 	run: perl HashLog.pm
#
# Values for $runUnitTests:
#	0: For production use only -- not testing.
#    	1: Run the regular unit tests
#	2: Run locking (flock) tests
# For the locking tests, this
# file (HashLog.pm) MUST be in the current working directory, because 
# the locking tests will run another instance of this code as a 
# separate process.  The locking tests take a long time to run, 
# because they sleep a lot to
# simulate slow functions.  Proper locking is detected by measuring
# the timings.

my $runUnitTests = 0;
&HLUnitTests() if $runUnitTests == 1;
&HLLockingTests() if $runUnitTests == 2;

my @functionList = qw(
	HLGet
	HLGetKeys
	HLInsert
	HLDelete
	HLClear
	HLForceRewriteLog
	HLPrintAll
	HLIsTimeToRewrite
	MakeParentDirs
	HLLock
	HLUnlock
	HLRefresh 
	HLRewriteLogInternal 
	);

#######################################################################
###################### Functions start here ###########################
#######################################################################

############ HLGet ##########
# Get values from a cached KV logFile for the given keys:
# my ($v1, $v2, ...) = &HLGet($hlConfig, $k1, $k2, ...);
sub HLGet
{
@_ >= 2 || die;
my ($hlConfig, @keys) = @_;
&HLLock($hlConfig, LOCK_SH);
&HLRefresh($hlConfig);
my @values = map { $hlConfig->{hash}->{$_} } @keys;
&HLUnlock($hlConfig);
return @values;
}

############ HLGetKeys ##########
# Get keys from a cached KV logFile for the given values:
# my ($k1, $k2, ...) = &HLGetKeys($hlConfig, $v1, $v2, ...);
sub HLGetKeys
{
@_ >= 2 || die;
my ($hlConfig, @values) = @_;
my $inverseHash = $hlConfig->{inverseHash} // confess;
&HLLock($hlConfig, LOCK_SH);
&HLRefresh($hlConfig);
my @keys = map { $inverseHash->{$_} } @values;
&HLUnlock($hlConfig);
return @keys;
}

############ HLInsert ##########
# Insert key/value pairs into the given hash map,
# and append them to the logFile.
# Called as: &HLInsert($hlConfig, k1, v1, k2, v2, ... );
# The same key with a new value will overwrite the old value.
# Values are not required to be unique, but if they are not unique,
# then the inverseHash map won't work very well.
# (Existence of the inverseHash property indicates whether that
# inverse mapping should be maintained.)
# Inserting a key/value pair that already exists will have no effect.
# A key MUST NOT be undefined, be the empty string, or contain whitespace
# or newline.  A value MUST NOT be undefined or contain leading or 
# trailing whitespace or newline, though it may be an empty string.
sub HLInsert
{
@_ >= 2 || die;
my ($hlConfig, @pairs ) = @_;
scalar(@pairs) % 2 == 0 || die;
# This needs to be an exclusive lock to prevent potential deadlock,
# even though initially this will only be reading, to refresh.
&HLLock($hlConfig, LOCK_EX);
&HLRefresh($hlConfig);
# $logFile is expected to already exist.
my $logFile = $hlConfig->{logFile};
my $newLogFile = $hlConfig->{newLogFile};
if ($debug) {
	my $allNames = join(" ", @pairs );
	print "HLInsert $allNames\n" if $debug;
	}
my $isTimeToRewrite = &HLIsTimeToRewrite($hlConfig);
# print "HLInsert $f isTimeToRewrite: $isTimeToRewrite\n";
(open(my $fh, ">>", $logFile) 
	|| confess "[ERROR] HLInsert: failed to open >> $logFile: $!")
		if !$isTimeToRewrite;
# Now write the new hash pairs.
my $nNewLines = 0;
my $hash = $hlConfig->{hash};
my $inverseHash = $hlConfig->{inverseHash};
for (my $i=0; $i<@pairs; $i += 2) {
	my $key = $pairs[$i];
	# In perl it is not actually possible to have an undefined hash key, because
	# perl converts all would-be keys to strings before using them as hash keys,
	# so undef silently becomes string "undef" when used as a key.
	# To catch potential errors, we therefore forbid "undef" as a key.
	if (!defined($key) || $key =~ m/\s/ || $key eq "undef" || $key eq "") {
		my $k = $key // "(undef)";
		die "[INTERNAL ERROR] HLInsert attempt to insert a bad key: {$k}\n";
		}
	my $value = $pairs[$i+1];
	if (!defined($value) || $value =~ m/\A\s/ || $value =~ m/\s\Z/
			|| $value =~ m/\n/) {
		my $v = $value // "(undef)";
		confess "[INTERNAL ERROR] HLInsert attempt to insert a bad value: {$v}\n";
		}
	# print "HLInsert key: $key value: $value\n";
	my $oldValue = $hash->{$key};
	next if defined($oldValue) && $oldValue eq $value;
	print $fh "i $key $value\n" if !$isTimeToRewrite;
	$nNewLines++;
	if ($inverseHash) {
		delete $inverseHash->{$oldValue} if defined($oldValue);
		$inverseHash->{$value} = $key;
		}
	$hash->{$key} = $value;
	}
$hlConfig->{nLines} += $nNewLines;
(close($fh) || die) if !$isTimeToRewrite;
$hlConfig->{oldSize} = -s $logFile if !$isTimeToRewrite;
&HLRewriteLogInternal($hlConfig) if $isTimeToRewrite;
&HLUnlock($hlConfig);
}

############ HLDelete ##########
# Delete key-value pairs from the given hash map and
# inverseHash map (if provided), and log them as deleted in logFile.
# Called as: &HLDelete($hlConfig, $key1, $key2, ... ]);
# It will rewrite logFile if there are too many obsolete lines in it.  
# Calling HLDelete for a name that was already deleted has no effect.
sub HLDelete
{
@_ >= 2 || die;
my ($hlConfig, @list) = @_;
&HLLock($hlConfig, LOCK_EX);
&HLRefresh($hlConfig);
# Time to rewrite the $logFile?  If so, then don't
# bother to write them to the current $logFile.
my $isTimeToRewrite = &HLIsTimeToRewrite($hlConfig);
print "HLDelete called, isTimeToRewrite: $isTimeToRewrite\n" if $debug;
# $logFile is expected to already exist.
(open(my $fh, ">>", $hlConfig->{logFile}) 
	|| confess "[ERROR] HLDelete: failed to open $hlConfig->{logFile} for append: $!")
		if !$isTimeToRewrite;
my $nNewLines = 0;
foreach my $key ( @list ) {
	die if !defined($key) || $key =~ m/\s/;
	my $oldValue = $hlConfig->{hash}->{$key};
	next if !defined($oldValue);	# $key was already deleted?
	print $fh "d $key\n" if !$isTimeToRewrite;
	$nNewLines++;
	delete $hlConfig->{hash}->{$key};
	delete $hlConfig->{inverseHash}->{$oldValue} if $hlConfig->{inverseHash};
	}
$hlConfig->{nLines} += $nNewLines;
(close($fh) || die) if !$isTimeToRewrite;
$hlConfig->{oldSize} = -s $hlConfig->{logFile} if !$isTimeToRewrite;
&HLRewriteLogInternal($hlConfig) if $isTimeToRewrite;
&HLUnlock($hlConfig);
}

############ HLClear ##########
# Clear all key-value pairs from the given hash map and
# inverseHash map (if provided)
# Called as: &HLClear($hlConfig);
# It will rewrite logFile if there are too many obsolete lines in it.  
# HLClear can also be used to auto-create and initialize a new (empty) logFile.
# (For safety, other HashLog functions will NOT auto-create a missing logFile.)
sub HLClear
{
@_ == 1 || die;
my ($hlConfig) = @_;
&HLLock($hlConfig, LOCK_EX);
my $logFile = $hlConfig->{logFile}; 
# HLClear is the only function that allows the logFile to not previously exist,
# because if the hashmap is being cleared anyway, then it is safe for the logFile
# to not exist.  This also means that HLClear can be used to create and 
# initialize a new (empty) logFile.  Parent directories will have already been
# created by HLLock.
touch($logFile) if !-e $logFile;
print "HLClear called\n" if $debug;
&HLRefresh($hlConfig);
# Time to rewrite the $logFile?  If so, then don't
# bother to write them to the current $logFile.
my $isTimeToRewrite = &HLIsTimeToRewrite($hlConfig);
# print "HLClear called, isTimeToRewrite: $isTimeToRewrite\n" if $debug;
# $logFile is expected to already exist.
(open(my $fh, ">>", $logFile) 
	|| confess "[ERROR] HLClear: failed to open $logFile for append: $!")
		if !$isTimeToRewrite;
print $fh "clear\n" if !$isTimeToRewrite;
$hlConfig->{nLines}++;
# Clear without changing the hashrefs:
%{$hlConfig->{hash}} = ();
%{$hlConfig->{inverseHash}} = () if $hlConfig->{inverseHash};
(close($fh) || die) if !$isTimeToRewrite;
$hlConfig->{oldSize} = -s $logFile if !$isTimeToRewrite;
&HLRewriteLogInternal($hlConfig) if $isTimeToRewrite;
&HLUnlock($hlConfig);
}

############## HLPrintAll ################
# This function is NOT thread safe if multiple threads access the same
# $hlConfig->{hash} in memory, though the disk access to the logFile is safe.
sub HLPrintAll
{
@_ == 1 || @_ == 2 || die;
my ($hlConfig, $refresh) = @_;
return if !$debug;
if ($refresh) {
	&HLLock($hlConfig, LOCK_SH);
	&HLRefresh($hlConfig);
	&HLUnlock($hlConfig);
	}
my $logFile = $hlConfig->{logFile};
my $newLogFile = $hlConfig->{newLogFile};
my $lockFile = $hlConfig->{lockFile};
my $lockFH = $hlConfig->{lockFH} // "(undef)";
my $hash = $hlConfig->{hash};
my $shortName = $logFile;
my $nLines = $hlConfig->{nLines};
my $oldSize = $hlConfig->{oldSize} // "(undef)";
my $oldInode = $hlConfig->{oldInode} // "(undef)";
my $size = -s $logFile;
$shortName =~ s|.*\/||;
$shortName =~ s/\.[^\.]+$//;
print "\n";
print "==================== $shortName =======================\n";
print "logFile: $logFile\n";
print "newLogFile: $newLogFile\n";
print "lockFile: $lockFile\n";
print "lockFH: $lockFH\n";
print "nLines: $nLines\n";
print "oldSize: $oldSize size: $size\n";
print "oldInode: $oldInode\n";
for my $key (sort keys %{$hlConfig->{hash}}) {
	my $v = $hash->{$key};
	print ("  $key" . " => $v\n");
	}
print "-------------------- $logFile ----------------------\n";
my $content = `cat '$logFile'`;
print $content;
print "========================================================\n";
print ("\n");
}

########## MakeParentDirs ############
# Ensure that parent directories of the given files exist, creating
# them if necessary.
# Optionally, directories that have already been created are remembered, so
# we won't waste time trying to create them again.
sub MakeParentDirs
{
my $optionRemember = 0; 
foreach my $f (@_) {
        next if $MakeParentDirs::fileSeen{$f} && $optionRemember;
        $MakeParentDirs::fileSeen{$f} = 1; 
        my $fDir = "";
        $fDir = $1 if $f =~ m|\A(.*)\/|;
        next if $MakeParentDirs::dirSeen{$fDir} && $optionRemember;
        $MakeParentDirs::dirSeen{$fDir} = 1; 
        next if $fDir eq "";    # Hit the root?
        make_path($fDir);
        -d $fDir || die "[ERROR] HashLog/MakeParentDirs: Failed to create directory: $fDir\n ";
        }
}

############ HLIsTimeToRewrite ##########
# Time to rewrite the logFile?  
sub HLIsTimeToRewrite
{
@_ == 1 || die;
my ($hlConfig) = @_;
$hlConfig->{lockFH} // die;
#### For safety, don't auto rewrite if the file is missing:
# return 1 if !-e $hlConfig->{logFile};
# $oldSize should never be undefined here, because Refresh should always
# be called first:
my $oldSize = $hlConfig->{oldSize} // confess;
# Force rewrite if the $oldSize is zero, because that means that it is
# a completely new logFile -- never properly initialized.
return 1 if $oldSize == 0;
my $nLinesNeeded = scalar(%{$hlConfig->{hash}});
my $nExtraLines = $hlConfig->{nLines} - $nLinesNeeded;
my $isTimeToRewrite = ($nExtraLines > $hlConfig->{extraLinesFactor}*$nLinesNeeded 
	&& $nExtraLines > $hlConfig->{extraLinesThreshold});
# print "HLIsTimeToRewrite nLinesNeeded: $nLinesNeeded nLines: $hlConfig->{nLines}\n";
return $isTimeToRewrite || 0;
}

############ HLLock ##########
# Lock the given KV.  A separate lockFile is used -- separate from
# the logFile -- because the inode of logFile will change
# when it gets too big and is rewritten.   (In essence, it is an inode
# that is locked -- not the filename.)
# 
# Usage: HLLock($hlConfig, $lockType);
# $lockType should be LOCK_EX (exclusive/write) or LOCK_SH (shared/read).
sub HLLock
{
@_ == 2 || die;
my ($hlConfig, $lockType) = @_;
# If a previous lockFH exists then this is already locked:
die if $hlConfig->{lockFH};
print "HLLock called\n" if $debug;
# Make sure the lockFile exists:
my $lockFile = $hlConfig->{lockFile} // die;
if (!-e $lockFile) {
	&MakeParentDirs($lockFile);
	open(my $fh, ">>", $lockFile) || die "[ERROR] Cannot open lockFile $lockFile for append: $!\n";
	close($fh) || die "[ERROR] Cannot close lockFile $lockFile: $!\n";
	}
my $mode = "<";
$mode = ">>" if $lockType == LOCK_EX;
open(my $fh, $mode, $lockFile) || die "[ERROR] Cannot open lockFile '$mode' $lockFile: $!\n";
$hlConfig->{lockFH} = $fh // die;
# Got this flock code pattern from
# https://www.perlmonks.org/?node_id=7058
# http://www.stonehenge.com/merlyn/UnixReview/col23.html
# See also http://docstore.mik.ua/orelly/perl/cookbook/ch07_12.htm
# Another good example: https://www.perlmonks.org/?node_id=869096
# And some good info here:
# https://stackoverflow.com/questions/34920/how-do-i-lock-a-file-in-perl
flock($fh, $lockType) || die "[ERROR] Cannot lock ($lockType) $lockFile: $!\n";
# During testing, force locked functions to be locked this long:
our $functionLockSeconds;		
sleep $functionLockSeconds if $functionLockSeconds
}

############ HLUnlock ##########
sub HLUnlock
{
@_ == 1 || die;
my ($hlConfig) = @_;
my $fh = $hlConfig->{lockFH} // die;
my $lockFile = $hlConfig->{lockFile} // die;
print "HLUnlock called\n" if $debug;
close($fh) || die "[ERROR] Cannot close lockFile $lockFile: $!\n";
$hlConfig->{lockFH} = undef;
}

############ HLRefresh ##########
# Refresh the given KV cache from its logFile, which must already exist.
# The reason it must already exist is to prevent the pipeline from silently 
# taking actions if the file was accidentally moved or deleted, and needs to be
# restored from a backup or such.  Instead, it will die if the file does not
# already exist.  The lockFile must already be locked (either LOCK_SH
# or LOCK_EX) before calling this.
sub HLRefresh
{
@_ == 1 || die;
my ($hlConfig) = @_;
$hlConfig->{lockFH} // die;
my $logFile = $hlConfig->{logFile} // die;
my ($inode, $size) = &InodeAndSize($logFile);
die "[ERROR] HLRefresh stat failed on $logFile: $!\n" if !defined($size);
my $oldSize = $hlConfig->{oldSize};
my $oldInode = $hlConfig->{oldInode};
if ($debug) {
	my $os = $oldSize // "(undef)"; 
	my $oi = $oldInode // "(undef)"; 
	print "HLRefresh called, oldsize: $os size: $size oldInode: $oi inode: $inode\n";
	}
if (!defined($oldInode) || $inode != $oldInode) {
	# First time, or new inode (which means the file was rewritten).  
	# Flush cache and read from the beginning.
	print "  HLRefresh first time, or new inode\n" if $debug;
	$oldSize = 0;	
	$hlConfig->{oldSize} = 0;
	$hlConfig->{oldInode} = $inode;
	$hlConfig->{nLines} = 0;
	$hlConfig->{hash} //= {};  # Create the hashRef if it didn't exist
	# Clear without changing the hashref:
	%{$hlConfig->{hash}} = ();
	%{$hlConfig->{inverseHash}} = () if $hlConfig->{inverseHash};
	}
# This should never happen, because the file should only grow:
die "[ERROR] HLRefresh corrupt $logFile detected: size $size < oldSize $oldSize\n"
	if $size < $oldSize;
# Already fresh if it is the same size.
if ($size != $oldSize) {
	# Size changed.  Need to refresh.
	open(my $fh, "<", $logFile) || die "[ERROR} HLRefresh could not open logFile for read: $logFile\n";
	# Start reading where we previously left off:
	seek($fh, $oldSize, SEEK_SET) or die "[ERROR] Cannot seek to $oldSize in $logFile: $! ";
	my $hash = $hlConfig->{hash};
	my $inverseHash = $hlConfig->{inverseHash};
	my $nNewLines = 0;
	while (my $line = <$fh>) {
		next if $line =~ m/^\s*\#/;	# Skip comment lines
		chomp $line;
		$line = &Trim($line);
		next if $line eq "";		# Skip empty lines
		$nNewLines++;
		my ($action, $key, $value) = split(/\s+/, $line, 3);
		$key //= "";
		$value //= "";
		if ($action eq "i") {
			# i key1 value1
			die "[ERROR] HLRefresh bad insert line in $logFile: $line\n"
				if $key eq "";
			if ($inverseHash) {
				my $oldValue = $hash->{$key};
				delete $inverseHash->{$oldValue} if defined($oldValue);
				$inverseHash->{$value} = $key;
				}
			$hash->{$key} = $value;
			}
		elsif ($action eq "d") {
			# d key1
			die "[ERROR] HLRefresh bad delete line in $logFile: $line\n"
				if $key eq "";
			my $oldValue = $hash->{$key};
			next if !defined($oldValue);	# Already deleted?
			delete $hash->{$key};
			delete $inverseHash->{$oldValue} if $inverseHash;
			}
		elsif ($action eq "clear") {
			# clear
			warn "HLRefresh CLEAR\n" if $debug;
			die "[ERROR] HLRefresh bad clear line in $logFile: $line\n"
				if $key ne "";
			# Clear without changing the hashref:
			%$hash = ();
			%$inverseHash = () if $inverseHash;
			}
		else	{
			die "[ERROR] HLRefresh unknown directive in $logFile: $line\n"
			}
		}
	$hlConfig->{nLines} += $nNewLines;
	close($fh) || die "[ERROR] HLRefresh close of $logFile failed: $!\n";
	}
$hlConfig->{oldSize} = $size;
$hlConfig->{oldInode} = $inode;
print "  HLRefresh set oldSize = $size\n" if $debug;
}

############ HLRewriteLogInternal ##########
# Write the current %hash into a $newLogFile, then atomically rename 
# it to be the current $logFile.  Must be already locked.
sub HLRewriteLogInternal
{
@_ == 1 || die;
my ($hlConfig) = @_;
$hlConfig->{lockFH} // die;
my $logFile = $hlConfig->{logFile} // die;
my $newLogFile = $hlConfig->{newLogFile} // die;
my $oldLines = $hlConfig->{nLines};
my $newLines = scalar(%{$hlConfig->{hash}});
(open(my $fh, ">", $newLogFile) 
	|| confess "[ERROR] HLRewriteLogInternal: failed to open $newLogFile: $!");
print "HLRewriteLogInternal of $logFile oldLines: $oldLines -> newLines: $newLines\n" if $debug;
print $fh "# RDF Pipeline HashLog.\n";
# Now write the new hash pairs.
my $hash = $hlConfig->{hash};
# Sort before writing, to be deterministic (for easier regression testing):
my @iKeys = sort keys %{$hash};
my $nNewLines = scalar(@iKeys);
foreach my $key ( @iKeys ) {
	my $value = $hash->{$key};
	# print "HLRewriteLogInternal key: $key value: $value\n";
	print $fh "i $key $value\n";
	}
(close($fh) || die);
my ($inode, $size) = &InodeAndSize($newLogFile);
$hlConfig->{oldInode} = $inode;
$hlConfig->{oldSize} = $size;
$hlConfig->{nLines} = $nNewLines;
print "  HLRewriteLogInternal set oldSize = $size\n" if $debug;
if ($debug) {
	my $s = -s $newLogFile;
	die "HLRewriteLogInternal wrong s: $s != size $size\n"
		if $s != $size;
	}
rename($newLogFile, $logFile) 
	|| die "[ERROR] HLRewriteLogInternal failed to rename $newLogFile to $logFile\n";
}

############ HLForceRewriteLog ##########
# Write the current %hash into a $newLogFile (even if the current logFile
# isn't "full"), then atomically rename it to be the current $logFile.
sub HLForceRewriteLog
{
@_ == 1 || die;
my ($hlConfig) = @_;
&HLLock($hlConfig, LOCK_EX);
&HLRefresh($hlConfig);
&HLRewriteLogInternal($hlConfig);
&HLUnlock($hlConfig);
}

############# InodeAndSize ##############
# Return the inode and size of a file.
sub InodeAndSize
{
@_ == 1 || die;
my $f = shift;
my ($dev,$inode,$mode,$nlink,$uid,$gid,$rdev,$size,
              $atime,$mtime,$ctime,$blksize,$blocks)
                  = stat($f);
# Avoid unused var warning:
($dev,$inode,$mode,$nlink,$uid,$gid,$rdev,$size,
              $atime,$mtime,$ctime,$blksize,$blocks)
        = ($dev,$inode,$mode,$nlink,$uid,$gid,$rdev,$size,
              $atime,$mtime,$ctime,$blksize,$blocks);
# warn "MTime($f): $mtime\n";
return ($inode, $size);
}

########## Trim ############
# Perl function to remove whitespace from beginning and end of a string.
sub Trim
{
my $s = shift @_;
$s =~ s/\A[\s\n\r]+//s;
$s =~ s/[\s\n\r]+\Z//s;
return $s;
}

################# HLUnitTests ####################
# Unit tests.
sub HLUnitTests
{
use Data::Dump qw(dump dd);

#### nmc ###
# $nmc holds HashLog for testing.
# Changes to this hash are logged in logFile. Usually mapping
# insertions and deletions are merely appended to this file (like
# a log), but periodically (when it gets too big) it is rewritten
# by writing a new version to newLogFile and then renaming
# that back to logFile.
#
# extraLinesThreshold and extraLinesFactor are configuration 
# parameters that control when the logFile should be auto-rewritten
# (because it has too many unneeded lines in it).   Rewriting is not triggered
# until both of these parameters are exceeded, e.g., at least
# a million extra lines AND 3 times as many lines as needed.
my $nmc = {
	'hash' => {},
	'inverseHash' => {},
	# These files MUST be in the same directory:
	'logFile' => "/tmp/nameMap.txt",
	'newLogFile' => "/tmp/newNameMap.txt",
	'lockFile' => "/tmp/nameMap.lock",
	'lockFH' => undef,
	'nLines' => 0,   # Not counting comment or empty lines
	# 'extraLinesFactor' => 3,
	'extraLinesFactor' => 2,
	# 'extraLinesThreshold' => 1000 * 1000 * 1000,
	'extraLinesThreshold' => 3,
	};

unlink $nmc->{logFile};
unlink $nmc->{newLogFile};
unlink $nmc->{lockFile};
# Should die if called without logFile:
# &HLGet($nmc, 'x');
# HLGetKeys($nmc, 'x');
# HLInsert($nmc, 'a', 'aa');
# HLDelete($nmc, 'x');
# HLPrintAll($nmc);
my $logFile = $nmc->{logFile};
my $newLogFile = $nmc->{newLogFile};
my $lockFile = $nmc->{lockFile};

HLClear($nmc);	# This will create the missing logFile
is( -s $logFile,                   24,            'New initialized logFile size');
is( $nmc->{hash},                  {},            'hash is empty');
is( $nmc->{inverseHash},           {},            'inverseHash is empty');
is( $nmc->{nLines},                 0,            'No lines in logFile yet');
is( $nmc->{lockFH},             undef,            'Not locked');
is( $nmc->{oldSize},               24,            'oldSize');

HLInsert($nmc, qw(a aa) );
is( $nmc->{hash},                  {qw(a aa)},    'hash now has {a aa}');
is( $nmc->{inverseHash},           {qw(aa a)},    'inverseHash now has {aa a}');
is( $nmc->{nLines},                 1,            'Lines in logFile');
is( -s $logFile,                   31,            'logFile size');
is( $nmc->{oldSize},               31,            'oldSize');
is( $nmc->{lockFH},             undef,            'Not locked');
is( [ sort keys %{$nmc} ],
			[ sort qw( hash inverseHash logFile
			newLogFile lockFile lockFH nLines
			extraLinesFactor extraLinesThreshold 
			oldInode oldSize ) ],
                                                 'hash has correct keys' );
my $oldInode = $nmc->{oldInode} // "(undef)";

HLInsert($nmc, qw(a aa) );
is( $nmc, { 	
		hash => {qw(a aa)},
		inverseHash => {qw(aa a)},
		extraLinesFactor => 2,
		extraLinesThreshold => 3,
		lockFH => undef,
		lockFile => $lockFile,
		logFile => $logFile,
		newLogFile => $newLogFile,
		nLines => 1,
		oldInode => $oldInode,
		oldSize => 31
		},
						 'Added {a aa} again (no effect)' );

HLInsert($nmc, qw(a AA) );
is( $nmc, { 	
		hash => {qw(a AA)},
		inverseHash => {qw(AA a)},
		extraLinesFactor => 2,
		extraLinesThreshold => 3,
		lockFH => undef,
		lockFile => $lockFile,
		logFile => $logFile,
		newLogFile => $newLogFile,
		nLines => 2,
		oldInode => $oldInode,
		oldSize => 38
		},
						 'Added {a AA}' );

HLInsert($nmc, qw(a a2) );
is( $nmc, { 	
		hash => {qw(a a2)},
		inverseHash => {qw(a2 a)},
		extraLinesFactor => 2,
		extraLinesThreshold => 3,
		lockFH => undef,
		lockFile => $lockFile,
		logFile => $logFile,
		newLogFile => $newLogFile,
		nLines => 3,
		oldInode => $oldInode,
		oldSize => 45
		},
						 'Added {a a2}' );

HLInsert($nmc, qw(a a3) );
is( $nmc, { 	
		hash => {qw(a a3)},
		inverseHash => {qw(a3 a)},
		extraLinesFactor => 2,
		extraLinesThreshold => 3,
		lockFH => undef,
		lockFile => $lockFile,
		logFile => $logFile,
		newLogFile => $newLogFile,
		nLines => 4,
		oldInode => $oldInode,
		oldSize => 52
		},
						 'Added {a a3}' );

HLInsert($nmc, qw(a a4) );
is( $nmc, { 	
		hash => {qw(a a4)},
		inverseHash => {qw(a4 a)},
		extraLinesFactor => 2,
		extraLinesThreshold => 3,
		lockFH => undef,
		lockFile => $lockFile,
		logFile => $logFile,
		newLogFile => $newLogFile,
		nLines => 5,
		oldInode => $oldInode,
		oldSize => 59
		},
						 'Added {a a4}' );

HLInsert($nmc, qw(a a5) );
$oldInode = $nmc->{oldInode};
is( $nmc, { 	
		hash => {qw(a a5)},
		inverseHash => {qw(a5 a)},
		extraLinesFactor => 2,
		extraLinesThreshold => 3,
		lockFH => undef,
		lockFile => $lockFile,
		logFile => $logFile,
		newLogFile => $newLogFile,
		nLines => 1,
		oldInode => $oldInode,
		oldSize => 31
		},
						 'Added {a a5}, trigger rewrite' );

HLInsert($nmc, qw(b b1) );
is( $nmc, { 	
		hash => {qw(a a5 b b1)},
		inverseHash => {qw(a5 a b1 b)},
		extraLinesFactor => 2,
		extraLinesThreshold => 3,
		lockFH => undef,
		lockFile => $lockFile,
		logFile => $logFile,
		newLogFile => $newLogFile,
		nLines => 2,
		oldInode => $oldInode,
		oldSize => 38
		},
						 'Added {b b1}' );

HLDelete($nmc, qw(cNonExist dNonExist) );
is( $nmc, { 	
		hash => {qw(a a5 b b1)},
		inverseHash => {qw(a5 a b1 b)},
		extraLinesFactor => 2,
		extraLinesThreshold => 3,
		lockFH => undef,
		lockFile => $lockFile,
		logFile => $logFile,
		newLogFile => $newLogFile,
		nLines => 2,
		oldInode => $oldInode,
		oldSize => 38
		},
						 'Delete non-existent' );

HLDelete($nmc, qw(a b) );
is( $nmc, { 	
		hash => {},
		inverseHash => {},
		extraLinesFactor => 2,
		extraLinesThreshold => 3,
		lockFH => undef,
		lockFile => $lockFile,
		logFile => $logFile,
		newLogFile => $newLogFile,
		nLines => 4,
		oldInode => $oldInode,
		oldSize => 46
		},
						 'Delete both' );

HLInsert($nmc, qw(a a1 b b1) );
$oldInode = $nmc->{oldInode};
is( $nmc, { 	
		hash => {qw(a a1 b b1)},
		inverseHash => {qw(a1 a b1 b)},
		extraLinesFactor => 2,
		extraLinesThreshold => 3,
		lockFH => undef,
		lockFile => $lockFile,
		logFile => $logFile,
		newLogFile => $newLogFile,
		nLines => 2,
		oldInode => $oldInode,
		oldSize => 38
		},
						 'Added {a a1 b b1}, rewritten' );

HLClear($nmc);
is( $nmc, { 	
		hash => {},
		inverseHash => {},
		extraLinesFactor => 2,
		extraLinesThreshold => 3,
		lockFH => undef,
		lockFile => $lockFile,
		logFile => $logFile,
		newLogFile => $newLogFile,
		nLines => 3,
		oldInode => $oldInode,
		oldSize => 44
		},
						 'Clear' );

HLForceRewriteLog($nmc);
$oldInode = $nmc->{oldInode};

is( $nmc, { 	
		hash => {},
		inverseHash => {},
		extraLinesFactor => 2,
		extraLinesThreshold => 3,
		lockFH => undef,
		lockFile => $lockFile,
		logFile => $logFile,
		newLogFile => $newLogFile,
		nLines => 0,
		oldInode => $oldInode,
		oldSize => 24
		},
						 'HLForceRewriteLog of empty hash' );

HLInsert($nmc, qw(a a1 b b1) );
is( $nmc, { 	
		hash => {qw(a a1 b b1)},
		inverseHash => {qw(a1 a b1 b)},
		extraLinesFactor => 2,
		extraLinesThreshold => 3,
		lockFH => undef,
		lockFile => $lockFile,
		logFile => $logFile,
		newLogFile => $newLogFile,
		nLines => 2,
		oldInode => $oldInode,
		oldSize => 38
		},
						 'Added {a a1 b b1}' );

##### HLInsert
# Perl silently converts undef to string "undef" when used as a key:
is( { undef => "aa" },    { "undef" => "aa" }, 	'undef == "undef" as hash key' );

# Bad key should die:
# HLInsert($nmc, undef => "aa" );
# Bad key should die:
# HLInsert($nmc, "undef" => "aa" );
# Bad key should die:
# HLInsert($nmc, " a" => "aa" );
# Bad key should die:
# HLInsert($nmc, "a " => "aa" );
# Bad key should die:
# HLInsert($nmc, "a\t" => "aa" );
# Bad key should die:
# HLInsert($nmc, "a\n" => "aa" );
# Bad key should die:
# HLInsert($nmc, "" => "aa" );

# Bad value should die:
# HLInsert($nmc, 'a' => "\n" );
# Bad value should die:
# HLInsert($nmc, 'a' => "x\ny" );
# Bad value should die:
# HLInsert($nmc, 'a' => " aa" );
# Bad value should die:
# HLInsert($nmc, 'a' => "aa " );
# Bad value should die:
# HLInsert($nmc, 'a' => "aa\t" );
# Bad value should die:
# HLInsert($nmc, 'a' => "aa\r" );

##### HLGet, HLGetKeys
# Bad calls should die:
# &HLGet();
# &HLGet($nmc);
# &HLGet(1, 1);
# &HLGetKeys();
# &HLGetKeys($nmc);
# &HLGetKeys(1, 1);

is( [&HLGet($nmc, "a")], 		[qw(a1)],		"Get a => a1" );
is( [&HLGet($nmc, qw(a b))], 		[qw(a1 b1)],		"Get a b" );
is( [&HLGet($nmc, qw(b a))], 		[qw(b1 a1)],		"Get b a" );
is( [&HLGet($nmc, qw(a b a))], 		[qw(a1 b1 a1)],		"Get a b a" );
is( [&HLGet($nmc, qw(a xx a))],		['a1', undef, 'a1'],	"Get non-existent" );

is( [&HLGetKeys($nmc, "a1")], 		[qw(a)],		"GetK a1 => a" );
is( [&HLGetKeys($nmc, qw(a1 b1))], 	[qw(a b)],		"GetK a1 b1" );
is( [&HLGetKeys($nmc, qw(b1 a1))], 	[qw(b a)],		"GetK b1 a1" );
is( [&HLGetKeys($nmc, qw(a1 b1 a1))], 	[qw(a b a)],		"GetK a1 b1 a1" );
is( [&HLGetKeys($nmc, qw(a1 xx a1))],	['a', undef, 'a'],	"GetK non-existent" );

##### No inverseHash
delete $nmc->{inverseHash};
HLInsert($nmc, qw(a a1 b b1) );
is( [&HLGet($nmc, qw(a b))], 		[qw(a1 b1)],		"(No inv) GetK a1 b1" );
HLDelete($nmc, qw(a) );
is( $nmc->{inverseHash}, 		undef,			"(No inv) inverseHash is undef" );
HLForceRewriteLog($nmc);
is( $nmc->{inverseHash}, 		undef,			"(No inv) inverseHash still undef" );
# This should die:
# &HLGetKeys($nmc, "aa");

##### logFile
my $tmpFile = "/tmp/tempHL_LogFile.txt";
`cp -p '$logFile' '$tmpFile'`;
`cat /dev/null > '$logFile'`;
# Should die:
# &HLGet($nmc, "a");
`echo "CORRUPT" > '$logFile'`;
# Should die:
# &HLGet($nmc, "a");
`mv '$tmpFile' '$logFile'`;

##### Simulate async mod of logFile by another process:
`echo 'd a' >> '$logFile'`;
is( [&HLGet($nmc, qw(a b))], 		[undef, "b1"],		"Async delete a" );
`echo 'i a a3' >> '$logFile'`;
is( [&HLGet($nmc, qw(a b))], 		["a3", "b1"],		"Async insert a a3" );
`echo 'clear' >> '$logFile'`;
is( [&HLGet($nmc, qw(a b))], 		[undef, undef],		"Async clear" );

##### Simulate loading logFile on startup:
`echo 'i a a4' > '$logFile'`;
`echo 'i b b4' >> '$logFile'`;
# Empty out the cache:
$nmc = {
	'hash' => {},
	'inverseHash' => {},
	# These files MUST be in the same directory:
	'logFile' => "/tmp/nameMap.txt",
	'newLogFile' => "/tmp/newNameMap.txt",
	'lockFile' => "/tmp/nameMap.lock",
	'lockFH' => undef,
	'nLines' => 0,   # Not counting comment or empty lines
	'extraLinesFactor' => 2,
	'extraLinesThreshold' => 3,
	};
is( [&HLGet($nmc, qw(a b))], 		["a4", "b4"],		"Load, get a b" );

##### HLLock / HLUnlock
# These should die if called without locking first:
# &HLIsTimeToRewrite($nmc);
# &HLUnlock($nmc);
# &HLRefresh($nmc);
# &HLRewriteLogInternal($nmc);

&HLLock($nmc, LOCK_SH);
is( ($nmc->{lockFH} && 1), 1,     	'lockFH is defined' );
# These should die if called while already locked:
# &HLLock($nmc, LOCK_SH);
# &HLClear($nmc);
# &HLInsert($nmc, 1);
# &HLDelete($nmc, 'x');
# &HLGet($nmc, 'aa');
# &HLGetKeys($nmc, 'aa');
# &HLForceRewriteLog($nmc);
&HLUnlock($nmc);

done_testing();
exit 0;
}


################### HLLockingTests ####################
# Test locking by running a second process at the same time.  By timing
# how long various functions take, we can deduce that locking is working.
sub HLLockingTests
{
##### Threading & locking
use Math::Round qw(round); 
my $nmc = {
	'hash' => {},
	'inverseHash' => {},
	# These files MUST be in the same directory:
	'logFile' => "/tmp/nameMap.txt",
	'newLogFile' => "/tmp/newNameMap.txt",
	'lockFile' => "/tmp/nameMap.lock",
	'lockFH' => undef,
	'nLines' => 0,   # Not counting comment or empty lines
	'extraLinesFactor' => 2,
	'extraLinesThreshold' => 3,
	};
 
# Try all two-function combinations of these functions:
#	HLClear
#	HLInsert
#	HLDelete
#	HLGet
#	HLGetKeys
#	HLForceRewriteLog

my @fCalls = (
	'&HLClear($nmc)',
	'&HLInsert($nmc, 1, 11)',
	'&HLDelete($nmc, 1)',
	'&HLGet($nmc, 1)',
	'&HLGetKeys($nmc, 11)',
	'&HLForceRewriteLog($nmc)',
	);

# Figure out which process we're running in: the initial process (if $AA is 1)
# or the other process that we spawn below (if $BB is 1).
# $AA and $BB indicate which process we're running in:
my $AA = (@ARGV == 0);
my $BB = (@ARGV == 2 && $ARGV[0] eq "BB");
my $ffBB = "";
$BB && ($ffBB = $ARGV[1]);	# Function to be run by BB
my $pName = "AA";		# Process name (AA or BB)
$pName = "BB" if $BB;
$AA && `(cat /dev/null ; echo "\n\n\n\n" ) > /tmp/timing`;
use Time::HiRes ();
our $functionLockSeconds = 1;		# Force functions to take this long
# Try different combinations of two functions, to verify blocking (from flock).
# These loops are only actually run by AA: BB always exits after the first
# iteration.  But AA starts a new BB process in each iteration.
my $iterationLimit = scalar(@fCalls) * scalar(@fCalls);
OUTER: for my $fA (@fCalls) {
	my $fAName = $fA;
	$fAName =~ s/\(.*//;
	$fAName =~ s/\A\&//;
	for my $fB (@fCalls) {
		my $fBName = $fB;
		$BB && ($fBName = $ffBB);
		$fBName =~ s/\(.*//;
		$fBName =~ s/\A\&//;
		# Start the second process (BB):
		$AA && `/usr/bin/nohup perl HashLog.pm BB '$fB' > /dev/null 2>&1 &`;
		my ($tStart, $tElapsed, $tError, $tRounded);
		$tStart = Time::HiRes::time();
		`echo $pName Starting >> /tmp/timing`;
		$AA && `echo calling $pName '$fAName' ... >> /tmp/timing`;
		$AA && eval $fA;  	# will sleep n seconds
			$BB && `echo $pName sleeping half time ... >> /tmp/timing`;
			$BB && sleep $functionLockSeconds/2;			# 1 sec
			$BB && `echo $pName calling '$fBName'... >> /tmp/timing`;
			$BB && eval($ffBB); 		# Blocks, then runs

			$BB && `echo $pName Done >> /tmp/timing`;
		$AA && `echo $pName $fBName again ... >> /tmp/timing`;
		$AA && eval $fA;  	# Block halftime, then run
		$AA && `echo $pName Done $fAName >> /tmp/timing`;
		$tElapsed = (Time::HiRes::time() - $tStart);
		$tRounded = round($tElapsed);
		$tError = $tElapsed - $tRounded;
		`echo '[ERROR] \$tError is too big ($tError).  Increase \$functionLockSeconds.' >> /tmp/timing`
			if abs($tError) > 0.2;
		my $tExpected = $functionLockSeconds*3;
		# The "Get" functions use shared (read) locks, so if both
		# functions are using shared (read) locks then they will
		# not block:
		$tExpected = $functionLockSeconds*2 
			if $fAName =~ m/Get/ && $fBName =~ m/Get/;
		$AA && is( $tRounded, 		$tExpected,	"$fAName-$fBName blocking" );
		`echo $pName $tRounded error: $tError >> /tmp/timing`;
		$BB && (exit 0);
		$iterationLimit--;
		if ($AA && $iterationLimit <= 0) {
			last OUTER;
			}
		}
	}
	done_testing();
	sleep $functionLockSeconds; 	# Make sure BB is finished
	my $errorMessage = `grep ERROR /tmp/timing 1>&2`;
	die "$errorMessage\n" if $errorMessage =~ m/ERROR/;
	exit 0;

}

# This MUST be the last executed line in the file:
1;

