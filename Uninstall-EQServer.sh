#!/bin/sh
export PRODUCT=EQServer
export VERSION=2.0
export EQHOME=`pwd`
export EQPERL=$EQHOME/perl5

export PERLBIN=$EQPERL/bin
export PERLLIB=$EQPERL/lib
export PERLSITELIB=$EQPERL/lib/site_perl
export PERL5LIB=$EQPERL/lib:$EQPERL/lib/site_perl:$EQHOME/lib

$PERLBIN/perl  ./Install-EQServer.pl uninstall
