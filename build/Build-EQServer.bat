@echo off
REM $Id$
REM Define some variables
set PRODUCT=EQServer
set VERSION=2.0
set DATFILE=./EQServer.dat

REM Directory to store files during build process. 
REM Should not be under the EQServer directory so 'git' doesn't get it.
set BUILD_BASE=../EQBuild

REM Set EQPERL to directory where perl is installed.  Just extract ./perl-MSWin32.tar 
REM anywhere on your REM host and update EQPERL path to specify the location. For example,
REM extract the archive to 'c:\users\dean', then edit this file to set EQPERL equal to 
REM 'c:/users/dean/perl5'. Notice we use forward slashes instead of the typical Windows 
REM backslash for specifying the path.

set EQPERL=%CD%/../perl5

set PERLBIN=%EQPERL%/bin
set PERLLIB=%EQPERL%/lib
set PERLSITELIB=%EQPERL%/site/lib
set PERL5LIB=%PERLLIB%;%PERLSITELIB%;%CD%/lib

set PPOPTIONS=-f Bleach -M XML::SAX::PurePerl -M URI
set PERL2EXE_PATH=%PERLBIN%
set PERL2EXE_CMD=pp

%PERLBIN%\perl build.pl


