#!C:/dean/EQ-Working/EQServer/perl5/bin/perl

#
#	StatusExec.pl - Sample of a STATUSEXEC script
#
#	Written by Capital Software Corporation - All Rights Reserved
#

if	((@ARGV == 1)&&($ARGV[0] eq "-v"))
{
	print '$Id: StatusExec.pl,v 1.3 2006/11/24 20:54:08 csdev Exp $', "\n";
	exit (0);
}
# Get EQ configuration data
$s = $ENV{EQHOME} . "/cfg/setup_env.pl";
open (IN_FILE, "$s") || &LogMsg( "Cannot open file '$s': $!\n", 1);
$s = join ("", <IN_FILE>);
close (IN_FILE);
eval "$s";

# Use enterprise-Q library for socket I/O, etc.
require ("$xc_EQ_PATH/lib/eqclientlib.pl");

( $buf ) = @ARGV;

# Parse command line arguments into hash named 'G_MsgHash' 
%G_MsgHash = &HashMsg( \$buf );

$mid      = $G_MsgHash{"T_MID"};
$trans    = $G_MsgHash{"T_TRANS"};
$label    = $G_MsgHash{"T_PROFILE"} || "";
$result   = $G_MsgHash{"T_RESULT"};
$reason   = $G_MsgHash{"T_REASON"};
$target   = $G_MsgHash{"T_TARGET"};
$type     = $G_MsgHash{"T_TARGETTYPE"} || "\@$xc_DEFTARGETTYPE";
$script   = $G_MsgHash{"SCRIPT"} || "";

# Do something creative with the information...
#
# Send message to TEC...
#
# @a = `postemsg 2>&1`;
#
# Example to change status of target's failed transaction to ONHOLD
#if( $result != 0 ) 
#{
#	&SendMsg( \"T_MSG=Status;T_MID=$mid;T_MSGSTATUS=ONHOLD;T_REASON=Set status from Status Exec script" ); 
#}

exit( 0 );

