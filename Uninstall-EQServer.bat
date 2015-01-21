@echo off
REM $Id$
REM Define some variables
set PRODUCT=EQServer
set VERSION=2.0

set EQPERL=%CD%\perl5

set PERLBIN=%EQPERL%\bin
set PERLLIB=%EQPERL%\lib
set PERLSITELIB=%EQPERL%\site\lib
set PERL5LIB=%PERLLIB%;%PERLSITELIB%;%CD%\lib

%PERLBIN%\perl .\Install-EQServer.pl uninstall


