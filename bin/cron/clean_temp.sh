#!/bin/sh

# $Id: clean_temp.sh,v 1.5 2014/11/06 23:32:01 eqadmin Exp $
set +x

# Source environment
. ~/.profile

#EQHOME=~EQ_PATH~
EQHOME=C:/dean/EQ-Working/EQServer

$EQHOME/perl5/bin/perl -I $EQHOME/perl5/lib $EQHOME/bin/clean_temp.pl > $EQHOME/temp/clean_temp.out 2>&1
