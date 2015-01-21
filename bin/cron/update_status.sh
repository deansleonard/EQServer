#!/bin/sh

# $Id: update_status.sh,v 1.7 2014/11/07 00:07:33 eqadmin Exp $
set +x

# Source environment
. ~/.profile

#EQ_HOME=~EQ_PATH~
EQ_HOME=C:/dean/EQ-Working/EQServer

#IGNORE_LINE
$EQHOME/perl5/bin/perl -I $EQHOME/perl5/lib $EQHOME/bin/update_status.pl > $EQHOME/temp/update_status.out 2>&1
