#!/bin/sh
# $Id$
# Perl 5.10.1
export PRODUCT=EQServer
export VERSION=2.0
export DATFILE=./EQServer.dat

# Directory to store files during build process
export BUILD_BASE=../EQBuild

# Set EQPERL to directory where perl is installed.  Just extract ./perl-<os>.tar 
# anywhere on your host and update EQPERL path to specify the location.
# <os> must be 'aix', 'solaris', or 'linux'.  For example, for linux:
# mkdir ~/home/eqperl
# cd ~/home/eqperl
# tar xvf /path/to/eqserver/perl-linux.tar
# Either edit this file to set EQPERL equal to '/home/eqperl/perl5' or export EQPERL
# from the command line before running this script to build EQServer

export EQPERL=$PWD/../perl5

export PERLBIN=$EQPERL/bin
export PERLLIB=$EQPERL/lib
export PERLSITELIB=$EQPERL/lib/site_perl
export PERL5LIB=$EQPERL/lib:$EQPERL/lib/site_perl;$PWD/lib

export PERL2EXE_PATH=$PERLBIN
export PERL2EXE_CMD=pp
export PPOPTIONS="-f Bleach -M XML::SAX::PurePerl -M URI"

date
$PERLBIN/perl ./Build.pl
date
