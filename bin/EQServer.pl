#!C:/dean/EQ-Working/EQServer/perl5/bin/perl

#
#	EQServer.pl - server process to queue transactions
#
#	Copyright Capital Software Corporation - All Rights Reserved
#

#use strict;
#use strict 'refs';
#use strict 'vars';

$x_no_cleanup = 1;
$x_version = '$Id: EQServer.pl,v 1.11 2014/11/07 00:06:02 eqadmin Exp $';
if	((@ARGV == 1)&&($ARGV[0] eq "-v"))
{
	print $x_version, "\n";
	exit (0);
}

#
#	Use and Requires
#

use Carp;
use IO;
use IO::Select;
use IO::Socket;
use Getopt::Std;

# Get EQ configuration data
$s = $ENV{EQHOME} . "/cfg/setup_env.pl";
open (IN_FILE, "$s") || &LogMsg( "Cannot open file '$s': $!\n", 1);
$s = join ("", <IN_FILE>);
close (IN_FILE);
eval "$s";

if( $^O =~ /win/i )
{
	require "Win32.pm";
	require	"Win32/Process.pm";
}

$x_no_cleanup = 0;

#
#	Defines
#

# Process exit codes
# Status msg returned to client
$SUCCESS_MSG	= "SUCCESS";
$FAILURE_MSG	= "FAILURE";
$LAST_MSG		= "THE END";
$DEF_PORT		= 2345;

%G_ResultHash =
(
	"SUCCESS"		=> 0,
	"FAILURE"		=> 1,
	"BAD_CONN"		=> 2,
	"TIMEOUT"		=> 3,
	"PID_DOWN"		=> 4,
	"NO_STATUS"		=> 5,
	"Q_RESTORED"	=> 6
);

# Transaction and Message statuses
$QUEUED	= "QUEUED";		# message waiting to be assigned to trans
$ASSIGNED	= "ASSIGNED";	# message associated with TID
$FAILED	= "FAILED";		# non-zero status, started, or finished recd
$RETRY	= "RETRY";		# message waiting to be retried
$ONHOLD	= "ONHOLD";		# do not process anything else for target if ONHOLD
$DELAYED	= "DELAYED";	# set to this status by client
$SCHEDULED	= "SCHED";		# indicates message is scheduled
$RESTRICTED = "RESTRICT";	# distribution time restricted
$EXCLUDED = "EXCLUDED";	# Transaction cannot meet conditions provided by user
						# (IP address is excluded, etc)
$EXPIRED  = "EXPIRED";	# Transaction expired (by time, by maximum number
						# of failures, etc).

$STARTED	= "STARTED";	# trans waiting for t_msg=started
$RUNNING	= "RUNNING";	# trans waiting for t_msg=finished
$MONITORING	= "MONITORING";	# trans being monitored by ICMon, SPMon, DMMon, etc.
$TIMEOUT	= "TIMEOUT";	# trans timed out, waiting for t_msg=finished

# Initialize the OS variable
$OS		= "$^O";	# "MSWin32" if NT
$NT		= "MSWin32";

# Default configuration file
$DEF_CFG		= "$xc_EQ_PATH/cfg/eqserver.cfg";

#
#	Globals Variables
#
$G_Now = 0;		# Holds UTS after message read from socket or socket timer expires
@G_mons = ( "JAN", "FEB", "MAR", "APR", "MAY", "JUN",
            "JUL", "AUG", "SEP", "OCT", "NOV", "DEC" );

$G_LogFile		= "";	# current log file name

# Tells if the current version is production or evaluation version
$G_Product = "~~~PRODUCT~~~";
$G_Version = "~~~VERSION~~~";
$G_Patch = "~~~PATCH~~~";

# Timestamps indicating when queus were last stored
$G_LastDQStore = $G_LastMQStore = $G_LastTQStore = time( );

# Used for assigning MIDs, TIDs, and DIDs
$G_LastMsg 	= 0;
$G_MsgSeq 	= 0;

# Counters for statistical analysis
$G_MaxMsgsPerSec = 0;
$G_CurMsgsPerSec = 0;
$G_MsgCnt = 0;
$G_MsgCntMax = 0;
$G_DispCnt = 0;
$G_DispCntMax= 0;
$G_TransCnt = 0;
$G_TransCntMax = 0;
$G_SockCnt = 0;
$G_SockCntMax = 0;
$G_SuccessTrans	= 0;
$G_FailureTrans	= 0;

# Keeps main processing loop going
$G_Continue 	= 1;
$G_CheckQ		= 0;
$G_StoreQ		= 0;
$G_CheckTrans	= 0;

# Restoring the queue: 2 - restoring queue files, 1 - restoring update file,
# 0 - normal operation.
$G_RestoringQ	= 0;

# Stores strings destined for client. Init & clear.
@G_ReturnArray = "";
shift(@G_ReturnArray);

# DEbugging on(1)/off (0)
$G_Debugging = 0;

# init yearday counters to 0
$G_LastLogfileYDay = 0;		# For LogMsg routine

# Store array of AppArgs to exclude from duplicate message check
%G_DupAppArgsExcl = ();	# No longer implemented - 02-26-99

# List of excluded IPs. All dispatch messages with IPs in the range from
# this list will be ignored. The number of addresses in the list should be even:
# every even (0,2,4,...) element is a start of IP range, every odd element is
# an end of the range.
@G_ExcludeIPs = ();

# Hash of valid EQ Clients
%G_ValidClientIP = ( );
@G_ValidClientIPRange = ();

# Key = Transaction Type; Value = Hash of Keywords. I.E. $G_DispatchVarHash{FPBlock}{MN} = 1
# When a Dispatch msg is received with MN keyword set, all FPBlock msgs for the dispatched target
# will be updated with MN=<new value>.  
%G_DispatchVarHash = ( );
$G_DispatchVarCount = 0;

# Maintain counter for # of records in STATUS file
$G_StatusCount = 0;

# Socket related globals
$G_ServerIP = "";
$G_ServerSocket = 0;
$G_ServerSocketAlt = 0;
$G_Select = 0;
$G_EQSchedSocket = 0;


#
#	*** CONFIG RELATED THINGS ***
#

%G_ConfigMod = ();

%G_Config =
(
	BINDDELAY		=> 5,
	CLASSFILE		=> "$xc_EQ_PATH/cfg/classes.cfg",
	CONFIGFILE		=>  $DEF_CFG,
	CLIMAXLEN		=> 4095,
	DEBUG			=> 0,
	DISPATCHSTORE	=> "DispatchQueue",
	DISPATCHVARCFG	=> "$xc_EQ_PATH/cfg/DispatchVar.cfg",
	DUPAPPARGSEXCL	=> "",
	ENVFILE			=> "$xc_EQ_PATH/cfg/env.cfg",
	EQSCHEDPORT		=> 0,
	EQPRODUCT		=> $G_Product,
	EQVERSION		=> $G_Version,
	EQPATCHES		=> "",
	EXCLUDEIPS		=> "",
	FINISHEDEXEC	=> "",
	FINONFAILONLY	=> 0,
	LOGFILEDIR		=> "$xc_EQ_PATH/logs",
	MSGFILEDIR		=> "$xc_EQ_PATH/qstore",
	MSGSTORE		=> "MsgQueue",
	NTPROCINFO		=> "$xc_EQ_PATH/bin/eqps.exe",
	PORT			=>  $DEF_PORT,
	PORTALT			=> 0,
	QSTOREDIR		=> "$xc_EQ_PATH/qstore",
	RECDETAILS		=> 0,
	SCHEDSTORE		=> "SchedQueue",
	SKIP_MONITORING => 1,
	STARTCMD		=> "/perl/bin/perl",
	STARTMAX		=> 5,
	STARTTIMEOUT	=> 10,
	STORESECS		=> 30,
	SUSPEND			=> 0,
	TIMEOUTEXEC		=> "",
	TIMERSECS		=> 300,
	TIMELIMITSECS	=> 60,
	TRACEREQUESTS	=> 1,
	TRACEDISPATCH	=> 0,
	TRACERESPONSES	=> 0,
	TRACESTARTCMD	=> 1,
	TRACEDQ			=> 0,
	TRACEMQ			=> 0,
	TRACETQ			=> 0,
	TRACE_TIMER		=> 0,
	TRANSCFGDIR		=> "$xc_EQ_PATH/cfg/trans",
	VALIDCLIENTIPS	=> "",
	XACTIONSTORE	=> "XactionQueue",
	"*" 			=>  0
);


#
#	*** Time Restricted Distribution related things ***
#
# Design:
#
# Whenever a rec is added to message queue with a non-null T_TIMELIMIT,
# add an entry to this hash.  
#
# Set value of hash to $QUEUED or $RESTRICTED, depending on the T_TIMELIMIT 
# and time of day.  
#
# Check this hash each loop cycle for a change in status.
#
# If status changes, 
#    o  set Q_MsgStatusHash of each matching T_TIMELIMIT value
#    o  return number of messages affected
#
# Remove entry from hash if no messages affected by change in status
#

%G_TimeLimitHash = ( );


#
#	*** Transaction expiration ***
#
# Design:
#
# Whenever a rec is added to message queue with a non-null T_EXPIRE,
# add an entry to this hash.  
#
# Check this hash each loop cycle for expiration. If transaction expires
# remove transaction from message queue with EXPIRED status.
#

%G_ExpireMHash = ();
$G_NextExpireMRec = 0;

#
#	*** Dispatch record expiration ***
#
# Design:
#
# Whenever a rec is added to dispatch queue with a non-null T_EXPIRE,
# add an entry to this hash.  
#
# Check this hash each loop cycle for expiration. If transaction expires
# remove transaction from message queue with EXPIRED status.
#

%G_ExpireDHash = ();
$G_NextExpireDRec = 0;

#
#	*** Schedule related things ***
#

# Flag for displaying Scheduled Records
$S_ExcludeRecs = 0;
$S_IncludeRecs = 1;
$S_SRecsOnly   = 2;

%S_DupSIDKeyHash = ( );		# key = T_TRANS,T_PROFILE,T_SCHEDULE; value = T_SID

$S_Key = "T_SID";

%S_EQUserHash	= ( );
%S_ProfileHash	= ( );
%S_ScheduleHash	= ( );
%S_SIDHash		= ( );
%S_TransHash	= ( );
%S_UTSHash		= ( );

%S_EQUserDesc =
(
	keyword 		=> "T_EQUSER",
	reqkey		=> 0,		# 0=no, 1=yes
	keytype   	 	=> "STRING",
	hashptr 		=> \%S_EQUserHash,
	defval		=> "Unknown"
);

%S_ProfileDesc =
(
	keyword 		=> "T_PROFILE",
	reqkey		=> 0,		# 0=no, 1=yes
	keytype   	 	=> "STRING",
	hashptr 		=> \%S_ProfileHash,
	defval		=> ""
);

%S_ScheduleDesc =
(
	keyword 		=> "T_SCHEDULE",
	reqkey		=> 1,		# 0=no, 1=yes
	keytype   	 	=> "STRING",
	hashptr 		=> \%S_ScheduleHash,
	defval		=> "0"
);

%S_SIDDesc =
(
	keyword 		=> "T_SID",
	reqkey		=> 1,		# 0=no, 1=yes
	keytype   	 	=> "STRING",
	hashptr 		=> \%S_SIDHash,
	defval		=> "0"
);

%S_TransDesc =
(
	keyword 		=> "T_TRANS",
	reqkey		=> 1,		# 0=no, 1=yes
	keytype   	 	=> "STRING",
	hashptr 		=> \%S_TransHash,
	defval		=> "0"
);

%S_UTSDesc =
(
	keyword 		=> "T_UTS",
	reqkey		=> 1,		# 0=no, 1=yes
	keytype   	 	=> "NUMBER",
	hashptr 		=> \%S_UTSHash,
	defval		=> 0
);

%S_KeyDesc =
(
	"T_EQUSER"		=> \%S_EQUserDesc,
	"T_PROFILE"		=> \%S_ProfileDesc,
	"T_SCHEDULE"	=> \%S_ScheduleDesc,
	"T_SID"		=> \%S_SIDDesc,
	"T_TRANS"		=> \%S_TransDesc,
	"T_UTS"		=> \%S_UTSDesc
);


#
#	*** Dispatch related things ***
#

$D_Key = "T_DID";

%D_DIDHash			= ( );
%D_EQUserHash		= ( );
%D_EQGroupHash		= ( );
%D_ExpireHash		= ( );
%D_TIDHash			= ( );
%D_TargetHash		= ( );
%D_TargetTypeHash	= ( );
%D_PriorityHash		= ( );
%D_TransHash		= ( );
%D_ProfileHash		= ( );

%D_DIDDesc =
(
	keyword 		=> "T_DID",
	reqkey		=> 1,		# 0=no, 1=yes
	keytype   	 	=> "STRING",
	hashptr 		=> \%D_DIDHash,
	defval		=> "0"
);

%D_EQUserDesc =
(
	keyword 		=> "T_EQUSER",
	reqkey			=> 0,		# 0=no, 1=yes
	keytype   	 	=> "STRING",
	hashptr 		=> \%D_EQUserHash,
	defval			=> ""
);

%D_EQGroupDesc =
(
	keyword 		=> "T_EQGROUP",
	reqkey			=> 0,		# 0=no, 1=yes
	keytype   	 	=> "STRING",
	hashptr 		=> \%D_EQGroupHash,
	defval			=> ""
);

%D_ExpireDesc =
(
	keyword 		=> "T_EXPIRE",
	reqkey			=> 0,		# 0=no, 1=yes
	keytype   	 	=> "STRING",
	hashptr 		=> \%D_ExpireHash,
	defval			=> ""
);

%D_ExcludeIPDesc =
(
	keyword 		=> "T_EXCLUDEIP",
	reqkey			=> 0,		# 0=no, 1=yes
	keytype   	 	=> "NUMBER",
	hashptr 		=> \%D_ExcludeIPHash,
	defval			=> 0
);

%D_ExpireDesc =
(
	keyword 		=> "T_EXPIRE",
	reqkey			=> 0,		# 0=no, 1=yes
	keytype   	 	=> "STRING",
	hashptr 		=> \%D_ExpireHash,
	defval			=> ""
);

%D_TIDDesc =
(
	keyword 		=> "T_TID",
	reqkey		=> 0,		# 0=no, 1=yes
	keytype   	 	=> "STRING",
	hashptr 		=> \%D_TIDHash,
	defval		=> "0"
);

%D_TargetDesc =
(
	keyword 		=> "T_TARGET",
	reqkey		=> 1,		# 0=no, 1=yes
	keytype   	 	=> "STRING",
	hashptr 		=> \%D_TargetHash,
	defval		=> "0"
);

%D_TargetTypeDesc =
(
	keyword 		=> "T_TARGETTYPE",
	reqkey		=> 0,		# 0=no, 1=yes
	keytype   	 	=> "STRING",
	hashptr 		=> \%D_TargetTypeHash,
	defval		=> "\@$xc_DEFTARGETTYPE"
);

%D_PriorityDesc =
(
	keyword 		=> "T_PRIORITY",
	reqkey		=> 0,		# 0=no, 1=yes
	keytype   	 	=> "NUMBER",
	hashptr 		=> \%D_PriorityHash,
	defval		=> 5
);

%D_TransDesc =
(
	keyword 		=> "T_TRANS",
	reqkey			=> 0,		# 0=no, 1=yes
	keytype   	 	=> "STRING",
	hashptr 		=> \%D_TransHash,
	defval			=> 5
);

%D_ProfileDesc =
(
	keyword 		=> "T_PROFILE",
	reqkey			=> 0,		# 0=no, 1=yes
	keytype   	 	=> "STRING",
	hashptr 		=> \%D_ProfileHash,
	defval			=> 5
);

%D_KeyDesc =
(
	"T_DID"			=> \%D_DIDDesc,
	"T_EQUSER"		=> \%D_EQUserDesc,
	"T_EQGROUP"		=> \%D_EQGroupDesc,
	"T_EXCLUDEIP"	=> \%D_ExcludeIPDesc,
	"T_EXPIRE"		=> \%D_ExpireDesc,
	"T_TARGET"		=> \%D_TargetDesc,
	"T_TARGETTYPE"	=> \%D_TargetTypeDesc,
	"T_TID"			=> \%D_TIDDesc,
	"T_PRIORITY"	=> \%D_PriorityDesc,
	"T_TRANS"		=> \%D_TransDesc,
	"T_PROFILE"		=> \%D_ProfileDesc,
);

#
#	*** Message related things ***
#
# Each hash represents a Message Type, as in T_MSG=<Msg Type>.  
# Each Message Type hash contains these keywords:
#
#	help		=	Text message displayed in response to T_MSG=HELP
#	example		=	Additional text displayed in response to T_MSG=HELP
#	allowremote	=	Flag indicating whether (1) or not (0) the message is allowed from
#					a remote computer.
#	reqkeys		=	Comma-separated list of keywords required for message type.
#					Message will be rejected unless message includes all 'reqkeys' 
#					Also, the 'reqkeys' are displayed in response to T_MSG=HELP
#	checkq 		=	Flag indicating whether (1) or not (0), after this message 
#					is processed, the queues must be checked for changes.
#	func		=	Function to invoke to process the Message Type.  
#					The function is passed one argument; a hash pointer containing all 
#					the Keyword/Value pairs parsed from the command line string. 
#					The function must "return( $err, $msg );", where '$err' indicates
#					success (0), or failure (non-zero).  '$msg' is returned to the 
#					calling script, user, etc.
#

$M_Key = "T_MSG";

%M_AddDesc =
(
	help		=> "Add transaction to queue",
	example		=> "t_msg=add;t_trans=doit",
	allowremote	=> 0,
	checkq		=> 1,
	func		=> \&M_Add,
	reqkeys		=> "T_TRANS",
);

%M_AddMDesc =
(
	help		=> "",
	example		=> "",
	allowremote	=> 0,
	checkq		=> 1,
	func		=> \&M_AddMRec,
	reqkeys		=> "",
);

%M_AddSDesc =
(
	help		=> "",
	example		=> "",
	allowremote	=> 0,
	checkq		=> 1,
	func		=> \&M_AddSRec,
	reqkeys		=> "",
);

%M_AddTDesc =
(
	help		=> "",
	example		=> "",
	allowremote	=> 0,
	checkq		=> 1,
	func		=> \&M_AddTRec,
	reqkeys		=> "",
);

%M_AddDDesc =
(
	help		=> "",
	example		=> "",
	allowremote	=> 0,
	checkq		=> 1,
	func		=> \&M_AddDRec,
	reqkeys		=> "",
);

%M_ClearQDesc =
(
	help		=> "Causes EQ to clear all queues",
	example		=> "t_msg=clearq",
	allowremote	=> 0,
	checkq		=> 0,
	func		=> \&M_ClearQ,
	reqkeys		=> "",
);

%M_ClearMQDesc =
(
	help		=> "Causes EQ to clear the message queue",
	example		=> "t_msg=clearmq",
	allowremote	=> 0,
	checkq		=> 0,
	func		=> \&M_ClearMQ,
	reqkeys		=> "",
);

%M_ClearSQDesc =
(
	help		=> "Causes EQ to clear the EQ Scheduler",
	example		=> "t_msg=clearsq",
	allowremote	=> 0,
	checkq		=> 0,
	func		=> \&M_ClearSQ,
	reqkeys		=> "",
);

%M_ClearTQDesc =
(
	help		=> "Causes EQ to clear the transaction queue",
	example		=> "t_msg=cleartq",
	allowremote	=> 0,
	checkq		=> 0,
	func		=> \&M_ClearTQ,
	reqkeys		=> "",
);


%M_CmdDesc =
(
	help		=> "",
	example		=> "",
	allowremote	=> 0,
	checkq		=> 0,
	func		=> \&M_Cmd,
	reqkeys		=> "",
);

%M_DispatchDesc =
(
	help		=> "Add target to dispatch queue",
	example		=> "t_msg=Dispatch;t_target=node1",
	allowremote	=> 1,
	checkq		=> 1,
	func		=> \&M_Dispatch,
	reqkeys		=> "",
);

%M_DispatchMIDDesc =
(
	help		=> "Add target to dispatch queue",
	example		=> "t_msg=DispatchMID;t_mid=m1,m2,m3,...",
	allowremote	=> 1,
	checkq		=> 1,
	func		=> \&M_DispatchMID,
	reqkeys		=> "",
);

%M_DeleteMDesc =
(
	help		=> "Delete one or more messages from queue that match all '<key>=<val>' arguments.",
	example		=> "t_msg=delmrec;<key>=<val>[;<key>=<val>;...]",
	allowremote	=> 0,
	checkq		=> 1,
	func		=> \&M_DeleteMRec,
	reqkeys		=> "",
);

%M_DeleteSDesc =
(
	help		=> "Delete Scheduled transaction from queue",
	example		=> "t_msg=delsrec;t_sid=<SID>",
	allowremote	=> 0,
	checkq		=> 1,
	func		=> \&M_DeleteSRec,
	reqkeys		=> "",
);

%M_DeleteTDesc =
(
	help		=> "Delete transaction from queue",
	example		=> "t_msg=deltrec;t_tid=<TID>",
	allowremote	=> 0,
	checkq		=> 1,
	func		=> \&M_DeleteTRec,
	reqkeys		=> "T_TID",
);

%M_DeleteDDesc =
(
	help		=> "Delete dispatch from queue",
	example		=> "t_msg=deldrec;t_did=<DID>",
	allowremote	=> 0,
	checkq		=> 1,
	func		=> \&M_DeleteDRec,
	reqkeys		=> "T_DID",
);

%M_FilterDDesc =
(
	help		=> "Returns dispatch queue recs to client based on key=val",
	example		=> "t_msg=filterdq;t_target=TARGET1",
	allowremote	=> 0,
	checkq		=> 0,
	func		=> \&M_FilterDRecs,
	reqkeys		=> "",
);

%M_DumpSpecialArraysDesc =
(
	help		=> "Logs contents of Special Hashes",
	example		=> "t_msg=DumpSpecial",
	allowremote	=> 1,
	checkq		=> 0,
	func		=> \&M_DumpSpecialArrays,
	reqkeys		=> "",
);

%M_FilterMDesc =
(
	help		=> "Returns msg queue recs to client based on key=val",
	example		=> "t_msg=filtermq;t_mid=123456789000",
	allowremote	=> 0,
	checkq		=> 0,
	func		=> \&M_FilterMRecs,
	reqkeys		=> "",
);

%M_FilterDesc =
(
	help		=> "Returns recs for all queues to client based on key=val",
	example		=> "t_msg=filterq;t_target=node1",
	allowremote	=> 0,
	checkq		=> 0,
	func		=> \&M_FilterRecs,
	reqkeys		=> "",
);

%M_FilterTDesc =
(
	help		=> "Returns trans queue recs to client based on key=val",
	example		=> "t_msg=filtertq;t_status=$RUNNING",
	allowremote	=> 0,
	checkq		=> 0,
	func		=> \&M_FilterTRecs,
	reqkeys		=> "",
);

%M_FinishedDesc =
(
	help		=> "For clients to return status of transaction termination",
	example		=> "t_msg=finished;t_tid=<TID>;t_pid=<client_PID>;t_result=0",
	allowremote	=> 0,
	checkq		=> 1,
	func		=> \&M_Finished,
	reqkeys		=> "T_TID",
);

%M_ForceSuccessDesc =
(
	help		=> "For clients to return status of transaction termination",
	example		=> "t_msg=forcesuccess;t_mid=<TID>;t_equser=user1",
	allowremote	=> 0,
	checkq		=> 1,
	func		=> \&M_ForceSuccess,
	reqkeys		=> "",
);

%M_HelpDesc =
(
	help		=> "Returns help information to client",
	example		=> "t_msg=help",
	allowremote	=> 1,
	checkq		=> 0,
	func		=> \&M_Help,
	reqkeys		=> "",
);

%M_InfoDesc =
(
	help		=> "For clients to send information to be logged",
	example		=> "t_msg=info",
	allowremote	=> 0,
	checkq		=> 0,
	func		=> \&M_Info,
	reqkeys		=> "",
);

%M_ModifyMDesc =
(
	help		=> "",
	example		=> "",
	allowremote	=> 0,
	checkq		=> 1,
	func		=> \&M_ModifyMRec,
	reqkeys		=> "",
);

%M_ModifySDesc =
(
	help		=> "",
	example		=> "",
	allowremote	=> 0,
	checkq		=> 1,
	func		=> \&M_ModifySRec,
	reqkeys		=> "",
);

%M_ModifyTDesc =
(
	help		=> "",
	example		=> "",
	allowremote	=> 0,
	checkq		=> 1,
	func		=> \&M_ModifyTRec,
	reqkeys		=> "",
);

%M_ModifyDDesc =
(
	help		=> "",
	example		=> "",
	allowremote	=> 0,
	checkq		=> 1,
	func		=> \&M_ModifyDRec,
	reqkeys		=> "",
);

%M_NewStatusFileDesc =
(
	help		=> "Close current STATUS file and open new one",
	example		=> "t_msg=newstatusfile",
	allowremote	=> 1,
	checkq		=> 0,
	func		=> \&M_NewStatusFile,
	reqkeys		=> "",
);

%M_QInfoDDesc =
(
	help		=> "Returns dispatch queue summary information to client",
	example		=> "t_msg=qinfod",
	allowremote	=> 0,
	checkq		=> 0,
	func		=> \&M_QInfoD,
	reqkeys		=> "",
);

%M_QInfoMDesc =
(
	help		=> "Returns message queue summary information to client",
	example		=> "t_msg=qinfom",
	allowremote	=> 0,
	checkq		=> 0,
	func		=> \&M_QInfoM,
	reqkeys		=> "",
);

%M_QInfoTDesc =
(
	help		=> "Returns transaction queue summary information to client",
	example		=> "t_msg=qinfot",
	allowremote	=> 0,
	checkq		=> 0,
	func		=> \&M_QInfoT,
	reqkeys		=> "",
);

%M_ReadQDesc =
(
	help		=> "Returns message, transaction, and dispatch queue records to client",
	example		=> "t_msg=readq",
	allowremote	=> 0,
	checkq		=> 0,
	func		=> \&M_ReadQ,
	reqkeys		=> "",
);

%M_ReadDQDesc =
(
	help		=> "Returns dispatch queue records to client",
	example		=> "t_msg=readdq",
	allowremote	=> 0,
	checkq		=> 0,
	func		=> \&M_ReadDQ,
	reqkeys		=> "",
);

%M_ReadMQDesc =
(
	help		=> "Returns message queue records to client",
	example		=> "t_msg=readmq",
	allowremote	=> 0,
	checkq		=> 0,
	func		=> \&M_ReadMQ,
	reqkeys		=> "",
);

%M_ReadSQDesc =
(
	help		=> "Returns schedule queue records to client",
	example		=> "t_msg=readsq",
	allowremote	=> 0,
	checkq		=> 0,
	func		=> \&M_ReadSQ,
	reqkeys		=> "",
);

%M_ReadTQDesc =
(
	help		=> "Returns transaction queue records to client",
	example		=> "t_msg=readtq",
	allowremote	=> 0,
	checkq		=> 0,
	func		=> \&M_ReadTQ,
	reqkeys		=> "",
);

%M_ReloadCfgDesc =
(
	help		=> "Reloads data from class.cfg and trans.cfg files",
	example		=> "t_msg=reloadcfg",
	allowremote	=> 0,
	checkq		=> 0,
	func		=> \&M_ReloadCfg,
	reqkeys		=> "",
);

%M_ResetMQInfoDesc =
(
	help		=> "Reset queue summary information",
	example		=> "t_msg=resetmqinfo",
	allowremote	=> 0,
	checkq		=> 0,
	func		=> \&M_ResetMQInfo,
	reqkeys		=> "",
);

%M_ResetTQInfoDesc =
(
	help		=> "Reset queue summary information",
	example		=> "t_msg=resettqinfo",
	allowremote	=> 0,
	checkq		=> 0,
	func		=> \&M_ResetTQInfo,
	reqkeys		=> "",
);

%M_SaveStatusDesc =
(
	help		=> "Save status information into current STATUS file",
	example		=> "t_msg=savestatus",
	allowremote	=> 0,
	checkq		=> 0,
	func		=> \&M_SaveStatus,
	reqkeys		=> "",
);

%M_ScheduleDesc =
(
	help		=> "Add entry to EQ Scheduler.  Returns Schedule ID (SID) upon success.",
	example		=> "t_msg=schedule;t_action=FilePackage:Visio;t_time=1800;t_date=19990101;t_equser=DEMO",
	allowremote	=> 0,
	checkq		=> 0,
	func		=> \&M_AddSRec,
	reqkeys		=> "",
);

%M_SetDIDDesc =
(
	help		=> "Valid T_DID required to set one or more values based on DID.",
	example		=> "t_msg=setdid;t_did=<did>;t_tid=0",
	allowremote	=> 0,
	checkq		=> 0,
	func		=> \&M_SetDID,
	reqkeys		=> "",
);

%M_SetMIDDesc =
(
	help		=> "Valid T_MID required to set one or more values based on MID.",
	example		=> "t_msg=setmid;t_mid=<mid>;t_msgstatus=ONHOLD",
	allowremote	=> 0,
	checkq		=> 0,
	func		=> \&M_SetMID,
	reqkeys		=> "",
);

%M_SetSIDDesc =
(
	help		=> "Valid T_SID required to set one or more values based on TID.",
	example		=> "t_msg=setsid;t_sid=<sid>;t_time=1800",
	allowremote	=> 0,
	checkq		=> 0,
	func		=> \&M_SetSID,
	reqkeys		=> "",
);

%M_SetTIDDesc =
(
	help		=> "Valid T_TID required to set one or more values based on TID.",
	example		=> "t_msg=settid;t_tid=<tid>;t_profile=newone",
	allowremote	=> 0,
	checkq		=> 0,
	func		=> \&M_SetTID,
	reqkeys		=> "",
);

%M_SetParmsDesc =
(
	help		=> "Set one or more EQ Server parameters",
	example		=> "t_msg=setparms;TRACEREQUESTS=1;TRACERESPONSES=1",
	allowremote	=> 0,
	checkq		=> 0,
	func		=> \&M_SetParms,
	reqkeys		=> "",
);

%M_SockInfoDesc =
(
	help		=> "Display information about socket counts",
	example		=> "t_msg=sockinfo",
	allowremote	=> 0,
	checkq		=> 0,
	func		=> \&M_SockInfo,
	reqkeys		=> "",
);

%M_ShowClientsDesc =
(
	help		=> "Return IP addresses of valid clients",
	example		=> "t_msg=showclients",
	allowremote	=> 0,
	checkq		=> 0,
	func		=> \&M_ShowClients,
	reqkeys		=> "",
);

%M_ShowParmsDesc =
(
	help		=> "Return current parameter settings",
	example		=> "t_msg=showparms",
	allowremote	=> 0,
	checkq		=> 0,
	func		=> \&M_ShowParms,
	reqkeys		=> "",
);

%M_ShowTransDesc =
(
	help		=> "Return current Transaction definitions",
	example		=> "t_msg=showtrans",
	allowremote	=> 0,
	checkq		=> 0,
	func		=> \&M_ShowTrans,
	reqkeys		=> "",
);

%M_ShowClassesDesc =
(
	help		=> "Return current Class definitions",
	example		=> "t_msg=showclasses",
	allowremote	=> 0,
	checkq		=> 0,
	func		=> \&M_ShowClasses,
	reqkeys		=> "",
);

%M_StartedDesc =
(
	help		=> "For clients to return status of transaction startup",
	example		=> "t_msg=started;t_tid=<TID>;t_pid=<client_PID>;t_result=0",
	allowremote	=> 0,
	checkq		=> 1,
	func		=> \&M_Started,
	reqkeys		=> "",
);

%M_StatusDesc =
(
	help		=> "For clients to return status of each transaction target",
	example		=> "t_msg=status;t_tid=<TID>;t_target=<target>;t_result=0",
	allowremote	=> 0,
	checkq		=> 1,
	func		=> \&M_Status,
	reqkeys		=> "",
);

%M_StopDesc =
(
	help		=> "Stop the EQ Server",
	example		=> "t_msg=stop;t_pass=<PASSWORD>",
	allowremote	=> 0,
	checkq		=> 0,
	func		=> \&M_Stop,
	reqkeys		=> "",
);

%M_StoreQDesc =
(
	help		=> "Causes EQ to store all queues to disk",
	example		=> "t_msg=StoreQ",
	allowremote	=> 0,
	checkq		=> 0,
	func		=> \&M_StoreQ,
	reqkeys		=> "",
);

%M_StoreDQDesc =
(
	help		=> "Causes EQ to write dispatch queue to disk",
	example		=> "t_msg=StoreDQ",
	allowremote	=> 0,
	checkq		=> 0,
	func		=> \&M_StoreDQ,
	reqkeys		=> "",
);

%M_StoreMQDesc =
(
	help		=> "Causes EQ to write message queue to disk",
	example		=> "t_msg=StoreMQ",
	allowremote	=> 0,
	checkq		=> 0,
	func		=> \&M_StoreMQ,
	reqkeys		=> "",
);

%M_StoreSQDesc =
(
	help		=> "Causes EQ to write schedule queue to disk",
	example		=> "t_msg=StoreSQ",
	allowremote	=> 0,
	checkq		=> 0,
	func		=> \&M_StoreSQ,
	reqkeys		=> "",
);

%M_StoreTQDesc =
(
	help		=> "Causes EQ to write transaction queue to disk",
	example		=> "t_msg=StoreTQ",
	allowremote	=> 0,
	checkq		=> 0,
	func		=> \&M_StoreTQ,
	reqkeys		=> "",
);

%M_TransStatusDesc =
(
	help		=> "Used to change the state of a transaction to $MONITORING",
	example		=> "t_msg=transstatus;t_tid=<TID>;t_status=$MONITORING",
	allowremote	=> 0,
	checkq		=> 1,
	func		=> \&M_TransStatus,
	reqkeys		=> "",
);

%M_MsgDesc =
(
	"ADD"			=> \%M_AddDesc,
	"ADDMREC"		=> \%M_AddMDesc,
	"ADDSREC"		=> \%M_AddSDesc,
	"ADDTREC"		=> \%M_AddTDesc,
	"ADDDREC"		=> \%M_AddDDesc,
	"CLEARQ"		=> \%M_ClearQDesc,
	"CLEARMQ"		=> \%M_ClearMQDesc,
	"CLEARSQ"		=> \%M_ClearSQDesc,
	"CLEARTQ"		=> \%M_ClearTQDesc,
	"DELMREC"		=> \%M_DeleteMDesc,
	"DELSREC"		=> \%M_DeleteSDesc,
	"DELTREC"		=> \%M_DeleteTDesc,
	"DELDREC"		=> \%M_DeleteDDesc,
	"DISPATCH"		=> \%M_DispatchDesc,
	"DISPATCHMID"	=> \%M_DispatchMIDDesc,
	"DUMPSPECIAL"	=> \%M_DumpSpecialArraysDesc,
	"FILTERDQ"		=> \%M_FilterDDesc,
	"FILTERMQ"		=> \%M_FilterMDesc,
	"FILTERQ"		=> \%M_FilterDesc,
	"FILTERTQ"		=> \%M_FilterTDesc,
	"FINISHED"		=> \%M_FinishedDesc,
	"FORCESUCCESS"	=> \%M_ForceSuccessDesc,
	"HELP"			=> \%M_HelpDesc,
	"INFO"			=> \%M_InfoDesc,
	"MODMREC"		=> \%M_ModifyMDesc,
	"MODSREC"		=> \%M_ModifySDesc,
	"MODTREC"		=> \%M_ModifyTDesc,
	"MODDREC"		=> \%M_ModifyDDesc,
	"NEWSTATUSFILE"	=> \%M_NewStatusFileDesc,
	"QINFOD"		=> \%M_QInfoDDesc,
	"QINFOM"		=> \%M_QInfoMDesc,
	"QINFOT"		=> \%M_QInfoTDesc,
	"READQ"			=> \%M_ReadQDesc,
	"READDQ",		=> \%M_ReadDQDesc,
	"READMQ",		=> \%M_ReadMQDesc,
	"READSQ",		=> \%M_ReadSQDesc,
	"READTQ",		=> \%M_ReadTQDesc,
	"RELOADCFG",	=> \%M_ReloadCfgDesc,
	"RESETMQINFO"	=> \%M_ResetMQInfoDesc,
	"RESETTQINFO"	=> \%M_ResetTQInfoDesc,
	"SAVESTATUS"	=> \%M_SaveStatusDesc,
	"SCHEDULE"		=> \%M_ScheduleDesc,
	"SETDID"		=> \%M_SetDIDDesc,
	"SETMID"		=> \%M_SetMIDDesc,
	"SETSID"		=> \%M_SetSIDDesc,
	"SETTID"		=> \%M_SetTIDDesc,
	"SETPARMS"		=> \%M_SetParmsDesc,
	"SHOWCLIENTS"	=> \%M_ShowClientsDesc,
	"SHOWPARMS"		=> \%M_ShowParmsDesc,
	"SHOWTRANS"		=> \%M_ShowTransDesc,
	"SHOWCLASSES"	=> \%M_ShowClassesDesc,
	"SOCKINFO"		=> \%M_SockInfoDesc,
	"STARTED"		=> \%M_StartedDesc,
	"STATUS"		=> \%M_StatusDesc,
	"STOP"			=> \%M_StopDesc,
	"STOREQ"		=> \%M_StoreQDesc,
	"STOREDQ"		=> \%M_StoreDQDesc,
	"STOREMQ"		=> \%M_StoreMQDesc,
	"STORESQ"		=> \%M_StoreSQDesc,
	"STORETQ"		=> \%M_StoreTQDesc,
	"TRANSSTATUS"	=> \%M_TransStatusDesc,
);

#
#
#	Transaction Class definitions
#
#

$DEF_CLASS = "DefClass";

$C_Key = "T_CLASS";

%C_ClassHash		= ( );
%C_LimitHash		= ( );

%C_ClassDesc =
(
	keyword 	=> "T_CLASS",
	reqkey	=> 0,
	keytype	=> "STRING",
	hashptr	=> \%C_ClassHash,
	defval 	=> "$DEF_CLASS"
);

%C_LimitDesc =
(
	keyword 	=> "T_CLASSMAX",
	reqkey	=> 0,
	keytype	=> "NUMBER",
	hashptr	=> \%C_LimitHash,
	defval 	=> 1
);

%C_KeyDesc =
(
	"T_CLASS"		=> \%C_ClassDesc,
	"T_CLASSMAX"	=> \%C_LimitDesc,
);


#
#	*** TRANS DEFINITION RELATED THINGS ***
#
#  Default Transactions:  To add a new reserverd trans keyword:
#
#	1.  Specify hash to contain values of NewKey like
#		%T_NewKeyHash
#
#	2.  Create hash describing the new keyword:
#		keyword 		=> "T_NEWKEY",
#		reqkey		=> 1,		# 0=no, 1=yes
#		keytype    		=> "STRING",
#		hashptr 		=> \%T_NewKeyHash,
#		defval		=> "Default - New Key"
#
#	3.  Add and entry in %T_DefKeyDesc like the others
#		"T_NEWKEY"		=> \%T_NewKeyDesc,
#

$T_DefKey = "T_TRANS";

%T_DefBatchDelayHash	= ( );
%T_DefBatchMaxHash		= ( );
%T_DefBatchIdHash		= ( );
%T_DefClassHash 		= ( );
%T_DefClientIPs			= ( );
%T_DefEQUserHash		= ( );
%T_DefEQGroupHash		= ( );
%T_DefExecHash			= ( );
%T_DefStatusFlagHash	= ( );
%T_DefStatusExecHash	= ( );
%T_DefIgnoreProfileHash = ( );
%T_DefKillHash			= ( );
%T_DefRecdTSHash		= ( );
%T_DefStatusHash		= ( );
%T_DefTimeoutHash		= ( );
%T_DefTimeoutExecHash	= ( );
%T_DefTFileFlagHash 	= ( );
%T_DefTransHash 		= ( );
%T_DefUniqueHash		= ( );
%T_DefUseEQTransWrapperHash = ( );

%T_DefBatchDelayDesc=
(
	keyword 	=> "T_BATCHDELAY",
	reqkey		=> 0,
	keytype		=> "NUMBER",
	hashptr		=> \%T_DefBatchDelayHash,
	defval 		=> 0
);

%T_DefBatchMaxDesc=
(
	keyword 	=> "T_BATCHMAX",
	reqkey		=> 0,
	keytype		=> "NUMBER",
	hashptr		=> \%T_DefBatchMaxHash,
	defval 		=> 10
);

%T_DefBatchIdDesc=
(
	keyword 	=> "T_BATCHID",
	reqkey		=> 0,
	keytype		=> "STRING",
	hashptr		=> \%T_DefBatchIdHash,
	defval 		=> ""
);

%T_DefClassDesc=
(
	keyword 	=> "T_CLASS",
	reqkey		=> 0,
	keytype		=> "STRING",
	hashptr		=> \%T_DefClassHash,
	defval 		=> "$DEF_CLASS"
);

%T_DefClientIPsDesc =
(
	keyword 	=> "T_CLIENTIPS",
	reqkey		=> 0,
	keytype		=> "STRING",
	hashptr		=> \%T_DefClientIPsHash,
	defval 		=> ""
);

%T_DefEQUserDesc =
(
	keyword 	=> "T_EQUSER",
	reqkey		=> 0,
	keytype		=> "STRING",
	hashptr		=> \%T_DefEQUserHash,
	defval		=> ""
);

%T_DefEQGroupDesc =
(
	keyword 	=> "T_EQGROUP",
	reqkey		=> 0,
	keytype		=> "STRING",
	hashptr		=> \%T_DefEQGroupHash,
	defval		=> ""
);

%T_DefExecDesc =
(
	keyword 	=> "T_EXEC",
	reqkey		=> 0,
	keytype		=> "STRING",
	hashptr		=> \%T_DefExecHash,
	defval		=> ""
);

%T_DefStatusExecDesc =
(
	keyword 	=> "T_STATUSEXEC",
	reqkey		=> 0,
	keytype		=> "STRING",
	hashptr		=> \%T_DefStatusExecHash,
	defval		=> ""
);

%T_DefStatusFlagDesc =
(
	keyword 	=> "T_STATUSFLAG",
	reqkey		=> 0,
	keytype		=> "NUMBER",
	hashptr		=> \%T_DefStatusFlagHash,
	defval		=> 0
);

%T_DefIgnoreProfileDesc =
(
	keyword 	=> "T_IGNOREPROFILE",
	reqkey		=> 0,
	keytype		=> "NUMBER",
	hashptr		=> \%T_DefIgnoreProfileHash,
	defval		=> 0
);


%T_DefKillDesc=
(
	keyword 	=> "T_KILL",
	reqkey		=> 0,
	keytype		=> "STRING",
	hashptr		=> \%T_DefKillHash,
	defval 		=> ""
);

%T_DefRecdTSDesc =
(
	keyword		=> "T_RECDTS",
	reqkey		=> 0,
	keytype		=> "TIMESTAMP",
	hashptr		=> \%T_DefRecdTSHash,
	defval		=> "NOW"
);

%T_DefStatusDesc =
(
	keyword		=> "T_TRANSTATUS",
	reqkey		=> 0,
	keytype		=> "STRING",
	hashptr		=> \%T_DefStatusHash,
	defval		=> $QUEUED
);

%T_DefTimeoutDesc =
(
	keyword		=> "T_TIMEOUT",
	reqkey		=> 0,
	keytype		=> "NUMBER",
	hashptr		=> \%T_DefTimeoutHash,
	defval		=> 0
);

%T_DefTimeoutExecDesc =
(
	keyword		=> "T_TIMEOUTEXEC",
	reqkey		=> 0,
	keytype		=> "STRING",
	hashptr		=> \%T_DefTimeoutExecHash,
	defval		=> ""
);

%T_DefTFileFlagDesc =
(
	keyword		=> "T_TFILEFLAG",
	reqkey		=> 0,
	keytype		=> "NUMBER",
	hashptr		=> \%T_DefTFileFlagHash,
	defval		=> 0
);

%T_DefTransDesc =
(
	keyword		=> "T_TRANS",
	reqkey		=> 1,		# 0=no, 1=yes
	keytype		=> "STRING",
	hashptr		=> \%T_DefTransHash,
	defval		=> ""
);

%T_DefUniqueDesc=
(
	keyword		=> "T_UNIQUEKEYS",
	reqkey		=> 0,
	keytype		=> "STRING",
	hashptr		=> \%T_DefUniqueHash,
	defval		=> ""
);

%T_DefUseEQTransWrapperDesc=
(
	keyword		=> "T_USEEQTRANSWRAPPER",
	reqkey		=> 0,
	keytype		=> "NUMBER",
	hashptr		=> \%T_DefUseEQTransWrapperHash,
	defval		=> 1
);

%T_DefKeyDesc =
(
	"T_BATCHDELAY"	=> \%T_DefBatchDelayDesc,
	"T_BATCHMAX"	=> \%T_DefBatchMaxDesc,
	"T_BATCHID"		=> \%T_DefBatchIdDesc,
	"T_CLASS"		=> \%T_DefClassDesc,
	"T_CLIENTIPS"	=> \%T_DefClientIPsDesc,
	"T_EXEC"		=> \%T_DefExecDesc,
	"T_STATUSEXEC"	=> \%T_DefStatusExecDesc,
	"T_STATUSFLAG"	=> \%T_DefStatusFlagDesc,
	"T_IGNOREPROFILE"	=> \%T_DefIgnoreProfileDesc,
	"T_KILL"		=> \%T_DefKillDesc,
	"T_TIMEOUT"		=> \%T_DefTimeoutDesc,
	"T_TIMEOUTEXEC"	=> \%T_DefTimeoutExecDesc,
	"T_TFILEFLAG"	=> \%T_DefTFileFlagDesc,
	"T_TRANS"		=> \%T_DefTransDesc,
	"T_UNIQUEKEYS"	=> \%T_DefUniqueDesc,
	"T_USEEQTRANSWRAPPER"	=> \%T_DefUseEQTransWrapperDesc
);

#
# Outstanding transactions are defined as follows:
#

$T_Key = "T_TID";

%T_TIDHash			= ( );
%T_AppArgsHash		= ( );
%T_BatchDelayHash	= ( );
%T_BatchMaxHash		= ( );
%T_BatchIdHash		= ( );
%T_ClassHash		= ( );
%T_EQUserHash		= ( );
%T_EQGroupHash		= ( );
%T_ExecHash			= ( );
%T_StatusExecHash	= ( );
%T_StatusFlagHash	= ( );
%T_InvokedTSHash	= ( );
%T_KillHash			= ( );
%T_LastTSHash		= ( );
%T_ModTSHash		= ( );
%T_PIDHash			= ( );
%T_ProfileHash		= ( );
%T_RecdTSHash		= ( );
%T_TranStatusHash 	= ( );
%T_TargetsHash		= ( );
%T_TargetFileHash	= ( );
%T_TargetTypeHash	= ( );
%T_TimeoutHash		= ( );
%T_TimeoutExecHash	= ( );
%T_TFileFlagHash	= ( );
%T_TransHash		= ( );
%T_UseEQTransWrapperHash =( );

%T_AppArgsDesc =
(
	keyword	=> "T_APPARGS",
	reqkey	=> 0,
	keytype	=> "STRING",
	hashptr	=> \%T_AppArgsHash,
	stdarg	=> 0,
	batchfield	=> 1,
	defval 	=> ""
);

%T_BatchDelayDesc =
(
	keyword 	=> "T_BATCHDELAY",
	reqkey	=> 0,
	keytype	=> "NUMBER",
	hashptr	=> \%T_BatchDelayHash,
	stdarg	=> 0,
	batchfield	=> 0,
	defval 	=> 0
);

%T_BatchMaxDesc =
(
	keyword 	=> "T_BATCHMAX",
	reqkey	=> 0,
	keytype	=> "NUMBER",
	hashptr	=> \%T_BatchMaxHash,
	stdarg	=> 0,
	batchfield	=> 0,
	defval 	=> 10
);

%T_BatchIdDesc =
(
	keyword 	=> "T_BATCHID",
	reqkey	=> 0,
	keytype	=> "STRING",
	hashptr	=> \%T_BatchIdHash,
	stdarg	=> 0,
	batchfield	=> 1,
	defval 	=> ""
);

%T_ClassDesc =
(
	keyword 	=> "T_CLASS",
	reqkey	=> 0,
	keytype	=> "STRING",
	hashptr	=> \%T_ClassHash,
	stdarg	=> 0,
	batchfield	=> 1,
	defval 	=> "$DEF_CLASS"
);

%T_EQUserDesc =
(
	keyword 	=> "T_EQUSER",
	reqkey	=> 0,
	keytype	=> "STRING",
	hashptr	=> \%T_EQUserHash,
	stdarg	=> 1,
	batchfield	=> 0,
	defval 	=> ""
);

%T_EQGroupDesc =
(
	keyword 	=> "T_EQGROUP",
	reqkey	=> 0,
	keytype	=> "STRING",
	hashptr	=> \%T_EQGroupHash,
	stdarg	=> 1,
	batchfield	=> 1,
	defval 	=> ""
);

%T_ExecDesc =
(
	keyword	=> "T_EXEC",
	reqkey	=> 1,
	keytype	=> "STRING",
	hashptr	=> \%T_ExecHash,
	stdarg	=> 0,
	batchfield	=> 1,
	defval	=> ""
);

%T_StatusExecDesc =
(
	keyword	=> "T_STATUSEXEC",
	reqkey	=> 0,
	keytype	=> "STRING",
	hashptr	=> \%T_StatusExecHash,
	stdarg	=> 0,
	batchfield	=> 0,
	defval	=> ""
);

%T_StatusFlagDesc =
(
	keyword	=> "T_STATUSFLAG",
	reqkey	=> 0,
	keytype	=> "STRING",
	hashptr	=> \%T_StatusFlagHash,
	stdarg	=> 0,
	batchfield	=> 0,
	defval	=> ""
);

%T_JobIDDesc =
(
	keyword 	=> "T_JOBID",
	reqkey	=> 0,
	keytype	=> "STRING",
	hashptr	=> \%T_JobIDHash,
	stdarg	=> 1,
	batchfield	=> 1,
	defval 	=> "NOW"
);

%T_InvokedTSDesc =
(
	keyword 	=> "T_INVOKEDTS",
	reqkey	=> 0,
	keytype	=> "TIMESTAMP",
	hashptr	=> \%T_InvokedTSHash,
	stdarg	=> 0,
	batchfield	=> 0,
	defval 	=> "NOW"
);

%T_KillDesc =
(
	keyword 	=> "T_KILL",
	reqkey	=> 0,
	keytype	=> "STRING",
	hashptr	=> \%T_KillHash,
	stdarg	=> 0,
	batchfield	=> 0,
	defval 	=> ""
);

%T_LastTSDesc =
(
	keyword 	=> "T_LASTTS",
	reqkey	=> 0,
	keytype	=> "TIMESTAMP",
	hashptr	=> \%T_LastTSHash,
	stdarg	=> 0,
	batchfield	=> 0,
	defval 	=> 0
);

%T_ModTSDesc =
(
	keyword 	=> "T_MODTS",
	reqkey	=> 0,
	keytype	=> "TIMESTAMP",
	hashptr	=> \%T_ModTSHash,
	stdarg	=> 0,
	batchfield	=> 0,
	defval 	=> "NOW"
);

%T_PIDDesc =
(
	keyword 	=> "T_PID",
	reqkey	=> 0,
	keytype	=> "STRING",
	hashptr	=> \%T_PIDHash,
	stdarg	=> 0,
	batchfield	=> 0,
	defval 	=> "0"
);

%T_ProfileDesc =
(
	keyword 	=> "T_PROFILE",
	reqkey	=> 0,
	keytype	=> "STRING",
	hashptr	=> \%T_ProfileHash,
	stdarg	=> 1,
	batchfield	=> 1,
	defval 	=> ""
);

%T_RecdTSDesc =
(
	keyword 	=> "T_RECDTS",
	reqkey	=> 0,
	keytype	=> "TIMESTAMP",
	hashptr	=> \%T_RecdTSHash,
	stdarg	=> 0,
	batchfield	=> 0,
	defval 	=> "NOW"
);

%T_TargetsDesc =
(
	keyword 	=> "T_TARGETS",
	reqkey	=> 0,		# 0=no, 1=yes
	keytype    	=> "STRING",
	hashptr 	=> \%T_TargetsHash,
	stdarg	=> 1,
	batchfield	=> 0,
	defval	=> ""
);

%T_TargetFileDesc =
(
	keyword 	=> "T_TARGETFILE",
	reqkey	=> 0,		# 0=no, 1=yes
	keytype    	=> "STRING",
	hashptr 	=> \%T_TargetFileHash,
	stdarg	=> 0,
	batchfield	=> 0,
	defval	=> ""
);

%T_TargetTypeDesc =
(
	keyword 	=> "T_TARGETTYPE",
	reqkey	=> 0,		# 0=no, 1=yes
	keytype    	=> "STRING",
	hashptr 	=> \%T_TargetTypeHash,
	stdarg	=> 1,
	batchfield	=> 1,
	defval	=> "\@$xc_DEFTARGETTYPE"
);

%T_TIDDesc =
(
	keyword 	=> "T_TID",
	reqkey	=> 1,		# 0=no, 1=yes
	keytype    	=> "STRING",
	hashptr 	=> \%T_TIDHash,
	stdarg	=> 1,
	batchfield	=> 0,
	defval	=> "0"
);

%T_TimeoutDesc =
(	keyword	=> "T_TIMEOUT",
	reqkey	=> 0,
	keytype	=> "NUMBER",
	hashptr	=> \%T_TimeoutHash,
	stdarg	=> 0,
	batchfield	=> 1,
	defval	=> 0
);

%T_TimeoutExecDesc =
(	keyword	=> "T_TIMEOUTEXEC",
	reqkey	=> 0,
	keytype	=> "STRING",
	hashptr	=> \%T_TimeoutExecHash,
	stdarg	=> 0,
	batchfield	=> 1,
	defval	=> ""
);

%T_TFileFlagDesc =
(	keyword	=> "T_TFILEFLAG",
	reqkey	=> 0,
	keytype	=> "NUMBER",
	hashptr	=> \%T_TFileFlagHash,
	stdarg	=> 0,
	batchfield	=> 1,
	defval	=> 0
);

%T_TransDesc =
(
	keyword 	=> "T_TRANS",
	reqkey	=> 1,		# 0=no, 1=yes
	keytype    	=> "STRING",
	hashptr 	=> \%T_TransHash,
	stdarg	=> 1,
	batchfield	=> 1,
	defval	=> ""
);

%T_TranStatusDesc =
(
	keyword 	=> "T_TRANSTATUS",
	reqkey	=> 0,
	keytype	=> "STRING",
	hashptr	=> \%T_TranStatusHash,
	stdarg	=> 0,
	batchfield	=> 0,
	defval 	=> "$QUEUED"
);

%T_UseEQTransWrapperDesc=
(
	keyword		=> "T_USEEQTRANSWRAPPER",
	reqkey		=> 0,
	keytype		=> "NUMBER",
	hashptr		=> \%T_UseEQTransWrapperHash,
	stdarg		=> 0,
	batchfield	=> 1,
	defval		=> 1
);

%T_KeyDesc =
(
	"T_APPARGS"		=> \%T_AppArgsDesc,
	"T_BATCHDELAY"	=> \%T_BatchDelayDesc,
	"T_BATCHMAX"	=> \%T_BatchMaxDesc,
	"T_BATCHID"		=> \%T_BatchIdDesc,
	"T_CLASS"		=> \%T_ClassDesc,
	"T_EQUSER"		=> \%T_EQUserDesc,
	"T_EQGROUP"		=> \%T_EQGroupDesc,
	"T_EXEC"		=> \%T_ExecDesc,
	"T_STATUSEXEC"	=> \%T_StatusExecDesc,
	"T_STATUSFLAG"	=> \%T_StatusFlagDesc,
	"T_JOBID"		=> \%T_JobIDDesc,
	"T_INVOKEDTS"	=> \%T_InvokedTSDesc,
	"T_KILL"		=> \%T_KillDesc,
	"T_LASTTS"		=> \%T_LastTSDesc,
	"T_PID"			=> \%T_PIDDesc,
	"T_PROFILE"		=> \%T_ProfileDesc,
	"T_RECDTS"		=> \%T_RecdTSDesc,
	"T_TARGETS"		=> \%T_TargetsDesc,
	"T_TARGETFILE"	=> \%T_TargetFileDesc,
	"T_TARGETTYPE"	=> \%T_TargetTypeDesc,
	"T_TID"			=> \%T_TIDDesc,
	"T_TIMEOUT"		=> \%T_TimeoutDesc,
	"T_TIMEOUTEXEC"	=> \%T_TimeoutExecDesc,
	"T_TFILEFLAG"	=> \%T_TFileFlagDesc,
	"T_TRANS"		=> \%T_TransDesc,
	"T_TRANSTATUS"	=> \%T_TranStatusDesc,
	"T_USEEQTRANSWRAPPER" => \%T_UseEQTransWrapperDesc
);


#
#	Transaction Queue related things
#
#	Every "record" in the queue must have an ID assigned
#	to it.  And every message from a client that needs to
#	reference a queued transaction must supply this info
#	in the msg using "T_TID=<tid>" keyword=value combination
#

%Q_DupMIDKeyHash = ( );	# keys=combo of type,target,trans,source; value=mid
%Q_DupMIDKeyRevHash = ( ); # The opposite of Q_DupMIDKeyHash, used
						# for deleting records
%Q_TargetKeyHash = ( );	# keys=type+target; value=hash of mid--->tid
%Q_TID2MIDHash = ( );	# keys=tid; value=hash of mid--->tid
%Q_TID2DIDHash = ( );	# keys=tid; value=hash of did--->target

# Dispatch Priority Hash maintains dispatched targets in priority/FIFO order
%G_DispatchPriorityHash = ( );	# Key = Priority,  Val = {$did} => target
%G_DispatchTargetHash = ( );	# Keys = $type, Val = {$target} => did
@G_CheckDispatchedTarget = ( );

# Maintain list of Classes under contention
%G_ClassContention = ( );
@G_CheckQueue = ( );

$Q_Key = "T_MID";

%Q_AppArgsHash 	= ( );
%Q_AttemptsHash 	= ( );
%Q_AutoBatchHash 	= ( );
%Q_BatchDelayHash	= ( );
%Q_BatchMaxHash	= ( );
%Q_BatchIdHash	= ( );
%Q_ClassHash	= ( );
%Q_EQUserHash	= ( );
%Q_EQGroupHash	= ( );
%Q_ExcludeIPHash	= ( );
%Q_ExecHash 	= ( );
%Q_ExpireHash	= ( );
%Q_FailTSHash	= ( );
%Q_JobIdHash	= ( );
%Q_KillHash		= ( );
%Q_MaxAttemptsHash	= ( );
%Q_MIDHash 		= ( );
%Q_MsgStatusHash	= ( );
%Q_NextTransHash	= ( );
%Q_PriorityHash	= ( );
%Q_ProfileHash	= ( );
%Q_ReasonHash 	= ( );
%Q_RecdTSHash 	= ( );
%Q_ResultHash 	= ( );
%Q_RetryHash 	= ( );
%Q_RetryCntHash 	= ( );
%Q_RetryIntHash 	= ( );
%Q_ScheduleHash	= ( );
%Q_SIDHash		= ( );
%Q_SkipHash		= ( );
%Q_StatusExecHash = ( );
%Q_StatusFlagHash = ( );
%Q_TargetHash	= ( );
%Q_TargetTypeHash	= ( );
%Q_TIDHash		= ( );
%Q_TimeLimitHash 	= ( );
%Q_TimeoutHash 	= ( );
%Q_TimeoutExecHash = ( );
%Q_TFileFlagHash 	= ( );
%Q_TransHash 	= ( );
%Q_UniqueValHash	= ( );
%Q_UseEQTransWrapperHash = ( );

%Q_AppArgsDesc =
(
	keyword 	=> "T_APPARGS",
	reqkey	=> 0,
	keytype	=> "STRING",
	hashptr	=> \%Q_AppArgsHash,
	statusexecvar	=> 1,
	function => "",
	defval 	=> "",
);

%Q_AttemptDesc =
(
	keyword 	=> "T_ATTEMPTS",
	reqkey	=> 0,
	keytype	=> "NUMBER",
	hashptr	=> \%Q_AttemptsHash,
	statusexecvar	=> 1,
	function => "",
	defval 	=> 0
);

%Q_AutoBatchDesc =
(
	keyword 	=> "T_AUTOBATCH",
	reqkey	=> 0,
	keytype	=> "NUMBER",
	hashptr	=> \%Q_AutoBatchHash,
	statusexecvar	=> 0,
	function => "",
	defval 	=> 0
);

%Q_BatchDelayDesc =
(
	keyword 	=> "T_BATCHDELAY",
	reqkey	=> 1,
	keytype	=> "NUMBER",
	hashptr	=> \%Q_BatchDelayHash,
	statusexecvar	=> 0,
	function => "",
	defval 	=> 0
);

%Q_BatchMaxDesc =
(
	keyword 	=> "T_BATCHMAX",
	reqkey	=> 1,
	keytype	=> "NUMBER",
	hashptr	=> \%Q_BatchMaxHash,
	statusexecvar	=> 0,
	function => "",
	defval 	=> 10
);

%Q_BatchIdDesc =
(
	keyword 	=> "T_BATCHID",
	reqkey	=> 0,
	keytype	=> "STRING",
	hashptr	=> \%Q_BatchIdHash,
	statusexecvar	=> 1,
	function => "",
	defval 	=> ""
);

%Q_ClassDesc =
(
	keyword 	=> "T_CLASS",
	reqkey	=> 1,
	keytype	=> "STRING",
	hashptr	=> \%Q_ClassHash,
	statusexecvar	=> 0,
	function => "",
	defval 	=> "$DEF_CLASS"
);

%Q_EQUserDesc =
(
	keyword 	=> "T_EQUSER",
	reqkey	=> 0,
	keytype	=> "STRING",
	hashptr	=> \%Q_EQUserHash,
	statusexecvar	=> 1,
	function => "",
	defval 	=> ""
);

%Q_EQGroupDesc =
(
	keyword 	=> "T_EQGROUP",
	reqkey	=> 0,
	keytype	=> "STRING",
	hashptr	=> \%Q_EQGroupHash,
	statusexecvar	=> 1,
	function => "",
	defval 	=> ""
);

%Q_ExcludeIPDesc =
(
	keyword 	=> "T_EXCLUDEIP",
	reqkey	=> 0,
	keytype    	=> "STRING",
	hashptr 	=> \%Q_ExcludeIPHash,
	statusexecvar	=> 0,
	function => "",
	defval	=> ""
);

%Q_ExecDesc =
(
	keyword 	=> "T_EXEC",
	reqkey	=> 1,
	keytype	=> "STRING",
	hashptr	=> \%Q_ExecHash,
	statusexecvar	=> 0,
	function => "",
	defval	=> ""
);

%Q_ExpireDesc = 
(
	keyword 	=> "T_EXPIRE",
	reqkey	=> 0,
	keytype    	=> "STRING",
	hashptr 	=> \%Q_ExpireHash,
	statusexecvar	=> 0,
	function => "Q_ExpireFunction",
	defval	=> "",
);

%Q_FailTSDesc =
(
	keyword 	=> "T_FAILTS",
	reqkey	=> 0,
	keytype	=> "TIMESTAMP",
	hashptr	=> \%Q_FailTSHash,
	statusexecvar	=> 0,
	function => "",
	defval	=> 0
);

%Q_JobIdDesc =
(
	keyword 	=> "T_JOBID",
	reqkey	=> 0,
	keytype	=> "STRING",
	hashptr	=> \%Q_JobIdHash,
	statusexecvar	=> 1,
	function => "Q_JobIDFunction",
	defval	=> ""
);

%Q_KillDesc =
(
	keyword 	=> "T_KILL",
	reqkey	=> 0,
	keytype	=> "STRING",
	hashptr	=> \%Q_KillHash,
	statusexecvar	=> 0,
	function => "",
	defval	=> 0
);

%Q_MaxAttemptsDesc =
(
	keyword 	=> "T_MAXATTEMPTS",
	reqkey		=> 0,
	keytype    	=> "NUMBER",
	hashptr 	=> \%Q_MaxAttemptsHash,
	statusexecvar		=> 0,
	function => "",
	defval		=> "0"
);

%Q_MIDDesc =
(
	keyword 	=> "T_MID",
	reqkey	=> 1,
	keytype    	=> "STRING",
	hashptr 	=> \%Q_MIDHash,
	statusexecvar	=> 1,
	function => "",
	defval	=> "0"
);

%Q_MsgStatusDesc =
(
	keyword 	=> "T_MSGSTATUS",
	reqkey	=> 0,
	keytype	=> "STRING",
	hashptr	=> \%Q_MsgStatusHash,
	statusexecvar	=> 0,
	function => "",
	defval 	=> "$QUEUED"
);

%Q_NextTransDesc =
(
	keyword 	=> "T_NEXTTRANS",
	reqkey	=> 0,
	keytype    	=> "STRING",
	hashptr 	=> \%Q_NextTransHash,
	statusexecvar	=> 0,
	function => "",
	defval	=> ""
);

%Q_PriorityDesc =
(
	keyword 	=> "T_PRIORITY",
	reqkey	=> 0,
	keytype	=> "NUMBER",
	hashptr	=> \%Q_PriorityHash,
	statusexecvar	=> 0,
	function => "",
	defval 	=> 5
);

%Q_ProfileDesc =
(
	keyword 	=> "T_PROFILE",
	reqkey	=> 0,
	keytype	=> "STRING",
	hashptr	=> \%Q_ProfileHash,
	statusexecvar	=> 1,
	function => "",
	defval 	=> ""
);

%Q_ReasonDesc =
(
	keyword 	=> "T_REASON",
	reqkey	=> 0,
	keytype	=> "STRING",
	hashptr	=> \%Q_ReasonHash,
	statusexecvar	=> 1,
	function => "",
	defval	=> ""
);

%Q_RetryDesc =
(
	keyword 	=> "T_RETRY",
	reqkey	=> 0,
	keytype	=> "NUMBER",
	hashptr	=> \%Q_RetryHash,
	statusexecvar	=> 0,
	function => "",
	defval	=> 3
);

%Q_RetryCntDesc =
(
	keyword 	=> "T_RETRYCNT",
	reqkey	=> 0,
	keytype	=> "NUMBER",
	hashptr	=> \%Q_RetryCntHash,
	statusexecvar	=> 0,
	function => "",
	defval	=> 0
);

%Q_RetryIntDesc =
(
	keyword 	=> "T_RETRYINT",
	reqkey	=> 0,
	keytype	=> "NUMBER",
	hashptr	=> \%Q_RetryIntHash,
	statusexecvar	=> 0,
	function => "",
	defval 	=> 0
);

%Q_RecdTSDesc =
(
	keyword 	=> "T_RECDTS",
	reqkey	=> 0,
	keytype	=> "TIMESTAMP",
	hashptr	=> \%Q_RecdTSHash,
	statusexecvar	=> 1,
	function => "",
	defval 	=> "NOW",
);

%Q_ResultDesc =
(
	keyword 	=> "T_RESULT",
	reqkey	=> 0,
	keytype	=> "NUMBER",
	hashptr	=> \%Q_ResultHash,
	statusexecvar	=> 1,
	function => "",
	defval 	=> 0
);

%Q_ScheduleDesc =
(
	keyword 	=> "T_SCHEDULE",
	reqkey	=> 0,
	keytype    	=> "STRING",
	hashptr 	=> \%Q_ScheduleHash,
	statusexecvar	=> 0,
	function => "Q_ScheduleFunction",
	defval	=> ""
);

%Q_SIDDesc =
(
	keyword 	=> "T_SID",
	reqkey	=> 0,
	keytype    	=> "STRING",
	hashptr 	=> \%Q_SIDHash,
	statusexecvar	=> 0,
	function => "",
	defval	=> "0"
);

%Q_SkipDesc =
(
	keyword 	=> "T_SKIP",
	reqkey	=> 0,
	keytype    	=> "NUMBER",
	hashptr 	=> \%Q_SkipHash,
	statusexecvar	=> 0,
	function => "",
	defval	=> 1
);

%Q_StatusExecDesc =
(
	keyword 	=> "T_STATUSEXEC",
	reqkey	=> 0,
	keytype	=> "STRING",
	hashptr	=> \%Q_StatusExecHash,
	statusexecvar	=> 0,
	function => "",
	defval	=> ""
);

%Q_StatusFlagDesc =
(
	keyword 	=> "T_STATUSFLAG",
	reqkey	=> 0,
	keytype	=> "NUMBER",
	hashptr	=> \%Q_StatusFlagHash,
	statusexecvar	=> 0,
	function => "",
	defval	=> 0
);


%Q_TargetDesc =
(
	keyword 	=> "T_TARGET",
	reqkey	=> 1,
	keytype	=> "STRING",
	hashptr	=> \%Q_TargetHash,
	statusexecvar	=> 1,
	function => "",
	defval 	=> ""
);

%Q_TargetTypeDesc =
(
	keyword 	=> "T_TARGETTYPE",
	reqkey	=> 0,
	keytype	=> "STRING",
	hashptr	=> \%Q_TargetTypeHash,
	statusexecvar	=> 1,
	function => "",
	defval 	=> "\@$xc_DEFTARGETTYPE"
);

%Q_TIDDesc =
(
	keyword 	=> "T_TID",
	reqkey	=> 0,
	keytype    	=> "STRING",
	hashptr 	=> \%Q_TIDHash,
	statusexecvar	=> 1,
	function => "",
	defval	=> "0"
);

%Q_TransDesc =
(
	keyword 	=> "T_TRANS",
	reqkey	=> 1,
	keytype    	=> "STRING",
	hashptr 	=> \%Q_TransHash,
	statusexecvar	=> 1,
	function => "",
	defval	=> "",
);

%Q_TimeLimitDesc = 
(
	keyword 	=> "T_TIMELIMIT",
	reqkey	=> 0,
	keytype    	=> "STRING",
	hashptr 	=> \%Q_TimeLimitHash,
	statusexecvar	=> 0,
	function => "Q_TimeLimitFunction",
	defval	=> "",
);

%Q_TimeoutDesc =
(	keyword	=> "T_TIMEOUT",
	reqkey	=> 0,
	keytype	=> "NUMBER",
	hashptr	=> \%Q_TimeoutHash,
	statusexecvar	=> 0,
	function => "",
	defval	=> 0
);

%Q_TimeoutExecDesc =
(	keyword	=> "T_TIMEOUTEXEC",
	reqkey	=> 0,
	keytype	=> "STRING",
	hashptr	=> \%Q_TimeoutExecHash,
	statusexecvar	=> 0,
	function => "",
	defval	=> ""
);

%Q_TFileFlagDesc =
(	keyword	=> "T_TFILEFLAG",
	reqkey	=> 0,
	keytype	=> "NUMBER",
	hashptr	=> \%Q_TFileFlagHash,
	statusexecvar	=> 0,
	function => "",
	defval	=> 0
);

%Q_UniqueValDesc =
(
	keyword 	=> "T_UNIQUEVAL",
	reqkey	=> 0,
	keytype    	=> "STRING",
	hashptr 	=> \%Q_UniqueValHash,
	statusexecvar	=> 0,
	function => "",
	defval	=> ""
);

%Q_UseEQTransWrapperDesc =
(
	keyword 	=> "T_USEEQTRANSWRAPPER",
	reqkey	=> 0,
	keytype    	=> "NUMBER",
	hashptr 	=> \%Q_UseEQTransWrapperHash,
	statusexecvar	=> 0,
	function => "",
	defval	=> 1
);


%Q_KeyDesc =
(
	"T_APPARGS"		=> \%Q_AppArgsDesc,
	"T_ATTEMPTS"	=> \%Q_AttemptDesc,
	"T_AUTOBATCH"	=> \%Q_AutoBatchDesc,
	"T_BATCHDELAY"	=> \%Q_BatchDelayDesc,
	"T_BATCHMAX"	=> \%Q_BatchMaxDesc,
	"T_BATCHID"		=> \%Q_BatchIdDesc,
	"T_CLASS"		=> \%Q_ClassDesc,
	"T_EQUSER"		=> \%Q_EQUserDesc,
	"T_EQGROUP"		=> \%Q_EQGroupDesc,
	"T_EXCLUDEIP"	=> \%Q_ExcludeIPDesc,
	"T_EXEC"		=> \%Q_ExecDesc,
	"T_EXPIRE"		=> \%Q_ExpireDesc,
	"T_FAILTS"		=> \%Q_FailTSDesc,
	"T_JOBID"		=> \%Q_JobIdDesc,
	"T_KILL"		=> \%Q_KillDesc,
	"T_MAXATTEMPTS"	=> \%Q_MaxAttemptsDesc,
	"T_MID"			=> \%Q_MIDDesc,
	"T_MSGSTATUS"	=> \%Q_MsgStatusDesc,
	"T_NEXTTRANS"	=> \%Q_NextTransDesc,
	"T_PRIORITY"	=> \%Q_PriorityDesc,
	"T_PROFILE"		=> \%Q_ProfileDesc,
	"T_REASON"		=> \%Q_ReasonDesc,
	"T_RECDTS"		=> \%Q_RecdTSDesc,
	"T_RESULT"		=> \%Q_ResultDesc,
	"T_RETRY"		=> \%Q_RetryDesc,
	"T_RETRYCNT"	=> \%Q_RetryCntDesc,
	"T_RETRYINT"	=> \%Q_RetryIntDesc,
	"T_SCHEDULE"	=> \%Q_ScheduleDesc,
	"T_SID"			=> \%Q_SIDDesc,
	"T_SKIP"		=> \%Q_SkipDesc,
	"T_STATUSEXEC"	=> \%Q_StatusExecDesc,
	"T_STATUSFLAG"	=> \%Q_StatusFlagDesc,
	"T_TARGET"		=> \%Q_TargetDesc,
	"T_TARGETTYPE"	=> \%Q_TargetTypeDesc,
	"T_TID"			=> \%Q_TIDDesc,
	"T_TIMELIMIT"	=> \%Q_TimeLimitDesc,
	"T_TIMEOUT"		=> \%Q_TimeoutDesc,
	"T_TIMEOUTEXEC"	=> \%Q_TimeoutExecDesc,
	"T_TFILEFLAG"	=> \%Q_TFileFlagDesc,
	"T_TRANS"		=> \%Q_TransDesc,
	"T_UNIQUEVAL"	=> \%Q_UniqueValDesc,
	"T_USEEQTRANSWRAPPER" => \%Q_UseEQTransWrapperDesc
);


#
#	sub prototypes / forward declarations
#


sub	M_Add;
sub	M_AddMRec;
sub	M_AddSRec;
sub	M_AddTRec;
sub	M_AddDRec;
sub	M_ClearQ;
sub	M_ClearDQ;
sub	M_ClearMQ;
sub	M_ClearSQ;
sub	M_ClearTQ;
sub	M_DeleteDRec;
sub	M_DeleteMRec;
sub	M_DeleteSRec;
sub	M_DeleteTRec;
sub	M_Dispatch;
sub	M_DispatchMID;
sub	M_FilterDRecs;
sub	M_FilterMRecs;
sub	M_FilterRecs;
sub	M_FilterTRecs;
sub	M_Finished;
sub	M_ForceSuccess;
sub	M_Help;
sub	M_ModifyDRec;
sub	M_ModifyMRec;
sub	M_ModifySRec;
sub	M_ModifyTRec;
sub	M_QInfoD;
sub	M_QInfoM;
sub	M_QInfoT;
sub	M_ReadQ;
sub	M_ReadDQ;
sub	M_ReadMQ;
sub	M_ReadSQ;
sub	M_ReadTQ;
sub	M_ReloadCfg;
sub	M_ResetMQInfo;
sub	M_ResetTQInfo;
sub	M_SetDID;
sub	M_SetMID;
sub	M_SetSID;
sub	M_SetTID;
sub	M_SetParms;
sub	M_ShowParms;
sub	M_ShowTrans;
sub	M_ShowClasses;
sub	M_SockInfo;
sub	M_Started;
sub	M_Status;
sub	M_Stop;
sub	M_StoreQ;
sub	M_StoreDQ;
sub	M_StoreMQ;
sub	M_StoreSQ;
sub	M_StoreTQ;
sub	M_Timer;

sub	Sched2UTS;
sub ValidateTID;
sub	ValidateResult;
sub	ValidateTarget;
sub	CheckRetryAttempts;
sub CheckUniqueVal;
sub	BatchMsg;
sub	BatchMatch;
sub CheckBatchMax;
sub	UpdateBatchID;
sub	ResetTargetRetry;
sub	ResetAssignedMRecs;
sub	AssignMessageVals;

sub	CheckTimeLimitHash;
sub	CheckExpiredRecords;
sub	AddTimeLimitRec;
sub	UpdateExpirationTimeRec;
sub	CheckTimeLimit;
sub	Limit2UTS;
sub	StartedTrans;

sub	StartQueuedTrans;
sub	CheckQueue;
sub	CheckTrans;
sub	CheckClass;
sub	CheckForTimeout;
sub	GetPriorityHash;

sub	DumpPPIDHash;
sub	GetChildPIDs;
sub	CreateProcHash;
sub	KillTransaction;
sub	CheckRunningTrans;

sub	LogMsg;
sub	InitConfigMod;
sub	GetCommandLine;
sub	ReadCfgFile;
sub	DisplayParms;

sub	ParseTransFiles;

sub	ClearQ;
sub	ClearXQ;

sub	AddXRec;
sub	ModifyXRec;
sub	DeleteXRec;
sub	DeleteXRecs;
sub	FilterXRecs;

sub	DeleteDRec;
sub	DeleteMRec;
sub	DeleteSRec;
sub	DeleteTRec;

sub	UpdateMRec;

sub	AddTargetKeyRec;
sub	UpdateTargetKeyRec;
sub	DelTargetKeyRec;
sub	AddDupMIDKeyRec;
sub	DelDupMIDKeyRec;
sub	ChkDupMIDKeyRec;
sub	AddDupSIDKeyRec;
sub	DelDupSIDKeyRec;
sub	DupSIDKeyCheck;
sub	AddTID2MIDRec;
sub	DelTID2MIDRec;
sub	AddTID2DIDRec;
sub	DelTID2DIDRec;

sub	FilterMQRecs;
sub	FilterTQRecs;

sub	ReturnDRecs;
sub	ReturnMRecs;
sub	ReturnSRecs;
sub	ReturnTRecs;

sub	DisplayDefTransRecs;
sub	DumpHash;
sub	DumpHashRecs;

sub	HashMsg;
sub	DelHashRec;
sub	AddTransHash;

sub	AssignUniqueVal;
sub	AssignAppArgs;
sub	AssignID;
sub	ProcessMsg;
sub	SendResponse;

sub	GetSocketIPAddrPort;
sub	ServerListen;

sub	InvokeExec;
sub	InvokeTimeoutExec;
sub	InvokeStatusExec;

sub	StatusFileOpen;
sub	StatusFileClose;
sub	StatusFileUpdate;

sub	StoreMsg;
sub	StoreQ;
sub	StoreDQ;
sub	StoreMQ;
sub	StoreSQ;
sub	StoreTQ;
sub	StoreXQ;
sub	RenameDataFiles;
sub	RestoreQ;
sub	RestoreFile;

sub	CTime;
sub	SigHandler;

sub	ResetDQTID;
sub	ResetMQTID;
sub	ResetDQRec;
sub	ResetMQRec;

sub	BuildValidClientIPList;
sub	BuildExcludeIPList;
sub	BuildDispatchVarHash;
sub	CheckDispatchVarHash;
sub	SubstituteDispatchVars;

sub	SetEnv;

sub	MainLoop;


#-------------------------------------------------------#
#
# Main Line Code Starts Here
# ==========================
#	||	||	||	||
#	\/	\/	\/	\/
#
#-------------------------------------------------------#

$EQServer_Initialized = 1;

# Store queue before exiting if needed
END {
	if	($EQServer_Initialized)
	{
		($err, $msg) = &StatusFileClose( );
		&StoreQ if( $G_StoreQ );
		&LogMsg( "Program Exiting Gracefully\n" );
	}
};

# Set up signal handlers
$SIG{INT}  = 'SigHandler';
$SIG{TERM} = 'SigHandler';
$SIG{PIPE} = 'SigHandler';

# Pre-build some data arrays
@Q_KeyDesc_keys = keys %Q_KeyDesc;
@Q_KeyDesc_values = values %Q_KeyDesc;
@Q_KeyDesc_functions = ();
# Q_KeyDesc_fkeys is the same as Q_KeyDesc_keys with the exception that
# all keys, which have associated functions, are located at the end of array
# (i.e. they will be processed after all other keys).
@Q_KeyDesc_fkeys = ();
foreach $k (@Q_KeyDesc_keys)
{
	$p_deschash = $Q_KeyDesc{$k};
	push (@Q_KeyDesc_functions, $k)		if	($$p_deschash{function});
	push (@Q_KeyDesc_fkeys, $k)		unless	($$p_deschash{function});
}
push (@Q_KeyDesc_fkeys, @Q_KeyDesc_functions);

# Initialize the Config Mod hash
&InitConfigMod( \%G_Config, \%G_ConfigMod );

# Parse command line for switches
&GetCommandLine( \%G_Config, \%G_ConfigMod );

# Read configuration file
&ReadCfgFile( \$G_Config{"CONFIGFILE"}, \%G_Config, \%G_ConfigMod );

# Include perl5 dirs in path
if( length($G_Config{ENVFILE}) ) { &SetEnv( $G_Config{ENVFILE} ); }
else { $ENV{PATH} = "$xc_PERL_BIN_PATH;$xc_PERL_LIB_PATH;$ENV{PATH}"; }

# Create some directories
&CreateConfigDirs( );

# Parse class file and display
&ParseClassFile( \$G_Config{"CLASSFILE"}, 1 );

# Parse trans file to create valid transaction list and display
my ($err, $msg) = &ParseTransFiles( \$G_Config{"TRANSCFGDIR"} );
print "$msg\n" if( $msg );
exit( $err ) if( $err );

#($err, $msg) = &M_ShowTrans( );
#print join( "\n\n", @G_ReturnArray ) . "\n";
#print "$msg\n";
#exit( $err );

# Process EQ Msg config file
($err, $msg) = &ParseEQMsg( "$xc_EQ_PATH/cfg/eqmsg.cfg" );
if( $err )
{
	print "$msg\n";
	exit( $err );
}

# Build Dup App Args Exclusion array
&BuildDupExclList( );

# Build list of excluded IPs
&BuildExcludeIPList( );

# Build hash of valid client IPs
&BuildValidClientIPList( );

# Build hash of valid Dispatch Variable Substitutions
&BuildDispatchVarHash( );

# Hang listen on $server_port, and add to select
$G_ServerSocket = &ServerListen( $G_Config{PORT} );
&LogMsg( "Server socket successfully created" ) if( $G_Config{DEBUG} );
$G_ServerSocket->sockopt( SO_REUSEADDR, 1 );

if( $G_Config{PORTALT} )
{
	$G_ServerSocketAlt = &ServerListen( $G_Config{PORTALT} );
	&LogMsg( "Server alternate socket successfully created" ) if( $G_Config{DEBUG} );
	$G_ServerSocketAlt->sockopt( SO_REUSEADDR, 1 );
}

# Ensure EQ Server IP in list of valid clients
$G_ServerIP = $G_ServerSocket->sockhost( );
$G_ValidClientIP{$G_ServerIP} = 1;

# Create Global Select object and add sockets
$G_Select = IO::Select->new( );
$G_Select->add( $G_ServerSocket );
$G_Select->add( $G_ServerSocketAlt ) if( $G_ServerSocketAlt );

# Restore queue
&RestoreQ();

&LogMsg( "    ###   EQ Server Started   ###\n" );

select( STDOUT ); $| = 1;

# Close old status file (if exists) and open new one
($err, $msg) = &StatusFileClose( 1 );
&LogMsg( $msg ) if( $err );
($err, $msg) = &StatusFileOpen( );
&LogMsg( $msg ) if( $err );

# Okay, now let's get down to business!!!
&MainLoop( );

# Exit success
exit( 0 );



	
#-------------------------------------------------------#
#                 S U B R O U T I N E S                 #
#-------------------------------------------------------#
#-------------------------------------------------------#
#	Main Loop
#-------------------------------------------------------#
sub MainLoop
{
my( @Ready, $Select, %InbufHash ); 
my( $now, $last_qcheck, $last_qstore, $did, $class, $timer, $msg, $msg_processed );

&LogMsg( "MAIN LOOP" ) if( $G_Config{DEBUG} );

# Init some variables
%InbufHash = ( );
$last_tlcheck = $last_qstore = 0;

$timer = undef;
while( $G_Continue ) 
{
	# Wait socket_timer seconds for socket I/O
	@Ready = $G_Select->can_read( $timer );
	
	$G_Now = time( );

	# socket_timer popped, meaning it's time to process schedule, or read a message from socket
	if( scalar(@Ready) )
	{
		$msg_processed = &SockIOCheck( \@Ready, \%InbufHash );
		# don't loop on socket connections/terminations, or Stop msg
		last unless( $G_Continue );
		next unless( $msg_processed );	
	}

	$now = time ();
	
	# Check/set start/stop time restrictions
	if( $now >= $last_tlcheck + $G_Config{TIMELIMITSECS} )
	{
		$last_tlcheck = $now;
		&CheckTimeLimitHash( );
	}

	# Process dispatched targets
	while( $did = shift( @G_CheckDispatchedTarget ) )
	{
		&CheckDispatchedTarget( $did );
	}
	
	# Check queue for class ready to process
	while( $class = shift( @G_CheckQueue ) )
	{
		&CheckQueue( $class );
	}
	
	# Check trans for timeouts and/or time to invoke
	&CheckTrans( );
	
	# Check for expired MIDs and DIDs
	&CheckExpiredRecords ( );
		
	# See if it's time to store the queue
	if( $G_StoreQ && $now >= $last_qstore + $G_Config{STORESECS} )
	{
		$last_qstore = $now;
		&StoreQ( );
	}
	
	# Detemine next timer pop based on transaction queue stuff
	$timer = &SetSocketTimer( );
	
}	# end of while 1 loop

# Close Server Socket
close( $G_ServerSocket );
close( $G_ServerSocketAlt ) if( $G_ServerSocketAlt );

}	# end of Main Loop


#********************************************************
#	SOCKET RELATED ROUTINES
#********************************************************


#-------------------------------------------------------#
#	Set Socket Timer
#-------------------------------------------------------#
sub SetSocketTimer
{
my( $now, $tid, $check_ts, $diff, $msg, $timer );

$now = time( );
$timer = undef;

if( scalar(@G_CheckDispatchedTarget) || scalar(@G_CheckQueue) )
{
	$timer = 0;
}

# Check each transaction for timecheck conditions
else
{
	foreach $tid( keys %T_TIDHash )
	{
		# Transaction queued, so wait up to BatchDelay seconds
		if( $T_TranStatusHash{$tid} eq $QUEUED )
		{
			$check_ts = $T_RecdTSHash{$tid} + $T_BatchDelayHash{$tid};
		}
		
		# Transaction started, so wait up to STARTTIMEOUT seconds
		elsif( $T_TranStatusHash{$tid} eq $STARTED )
		{
			$check_ts = $T_InvokedTSHash{$tid} + $G_Config{STARTTIMEOUT};
		}

		# Check if last target status received for transaction
		elsif( $T_LastTSHash{$tid} )
		{
			$check_ts = $T_LastTSHash{$tid} + $G_Config{STARTTIMEOUT};
		}
	
		# Transaction running, so wait up to timeout seconds, if specified
		elsif( $T_TimeoutHash{$tid} > 0 && 
				($T_TranStatusHash{$tid} eq $RUNNING || $T_TranStatusHash{$tid} eq $MONITORING) )
		{
			$check_ts = $T_InvokedTSHash{$tid} + $T_TimeoutHash{$tid};
		}
	
		# Ignore all other conditions
		else
		{
			next;
		}
	
		$diff = $check_ts - $now;
		$diff = 0 if( $diff < 0 );

		# Skip it if timer already less than this one	
		next if( defined($timer) && $timer < $diff );
	
		$G_CheckTrans = $tid;
		$timer = $diff;
		last if( $timer == 0 );		# Can't get less than zero, so no need to check other TIDs
	} 
}

# Now, see if expired timers are sooner
unless( $timer == 0 )
{
	if( $G_NextExpireMRec )
	{
		$diff = $G_NextExpireMRec - $now;
		$diff = 0 if( $diff < 0 );
		$timer = $diff if( $diff < $timer );
	}

	if( $G_NextExpireDRec )
	{
		$diff = $G_NextExpireDRec - $now;
		$diff = 0 if( $diff < 0 );
		$timer = $diff if( $diff < $timer );
	}
}

# Finally, see if it's time to create new logfile (midnight)

if( $G_Config{TRACE_TIMER} )
{
	$msg = "TRACE_TIMER: ";
	if( defined($timer) ) { $msg .= "Next Check in $timer seconds"; }
	else { $msg .= "Waiting for next message"; }
	$msg .= " for T_TID='$G_CheckTrans'" unless( $G_CheckTrans eq "0" );
	&LogMsg( $msg );
}

return( $timer );

}	 # end of Set Socket Timer


#-------------------------------------------------------#
#	Server Listen
#-------------------------------------------------------#
sub ServerListen
{
my( $port ) = @_;
my( $s, $host, $err, $secs );

$host = $xc_HOSTNAME;
$secs = $G_Config{STARTTIMEOUT};
$port = 2345	if	((!defined ($port))||($port eq ""));
&LogMsg( "Invalid port number '$port'\n", 1)
	if	($port !~ /^\d+$/);
&LogMsg( "Port '$port' is out of range\n", 1)
	if	(($port == 0)||($port > 65535));

# Listen to port
while( 1 ) {
	$s = IO::Socket::INET->new(	LocalAddr => $host,
						LocalPort => $port,
						Proto	    => "tcp",
						Listen    => SOMAXCONN,
						Reuse     => 1);
	return( $s ) if( $s );
	$err = "$!";
	$err = "$^E"	if	($err =~ /^Unknown error$/i);
	&LogMsg( "Socket Error ($err) on $host:$port. Retrying in $secs seconds\n");
	print( "Socket Error ($err) on $host:$port. Retrying in $secs seconds\n" );
	sleep( $secs );
}

}	# end of Server Listen


#-------------------------------------------------------#
#	Sock IO Check
#	Requires global variable G_Select
#-------------------------------------------------------#
sub SockIOCheck
{
my( $p_Ready, $p_InbufHash ) = @_;
my( $S, $Data, $rc, $response, $err, $msg, @arr, $msg_processed );

$msg_processed = 0;
foreach $S( @$p_Ready ) 
{
	# If it's on server socket, accept connection
	if( $S == $G_ServerSocket || $S == $G_ServerSocketAlt ) 
	{
		($err, $msg) = &SockAcceptCheck( $S, $p_InbufHash );		
		&LogMsg( "SockIOCheck:$msg" ) if( $err );
		next;
	}

	# Otherwise, it's data to be read, so get it
	$rc = $S->recv($Data, 1024, 0 );

	# unless we read data, close the socket...
	unless( defined($rc) && length($Data) ) 
	{
		#eof, so close socket
		delete( $p_InbufHash->{$S} );
		$G_Select->remove( $S );
		$S->close;
		$G_SockCnt -= 1;
		next;
	}

	# Add data to inbuf
	$p_InbufHash->{$S}{DATA} .= $Data;

	# Don't process data if not a complete message
	next unless( $p_InbufHash->{$S}{DATA} =~ /.*\n$/ );

	# Check if it from the EQScheduler
	if( $S == $G_EQSchedSocket )
	{
		# Make sure the message has been received in it's entirety
		next unless( $p_InbufHash->{$S} =~ s/\nTHE END\n$// );
		
		&LogMsg( "EQSCHEDULER RESPONSE: $p_InbufHash->{$S}{DATA}" );	# Log EQScheduler response
		$G_EQSchedSocket = 0;			# Reset EQScheduler socket
		delete( $p_InbufHash->{$S} );	# Remove input buffer for socket
		$G_Select->remove( $S );		# Remove from selected sockets
		$S->close( );					# Close the socket
		next;
	}
	
	$response = &ProcessMsg( $p_InbufHash->{$S}{DATA}, $p_InbufHash->{$S}{IP} );
	&SendResponse( $S, $response );

	# Reset buffer for more data...
	$p_InbufHash->{$S}{DATA} = "";
	$msg_processed = 1;

}	# end of foreach client loop

return( $msg_processed );

}	# end of Sock IO Check


#-------------------------------------------------------#
#	Sock Accept Check
#-------------------------------------------------------#
sub SockAcceptCheck
{
my( $S, $p_InbufHash ) = @_;
my( $NS, $ClientIP ); 

# First, make sure it's from a valid IP...
$NS = $S->accept();
return( 1, "SockAcceptCheck: Error accepting socket. Socket Count = $G_SockCnt: $!\n" ) 
	unless( $NS );

$ClientIP = $NS->peerhost( );
unless( defined( $G_ValidClientIP{$ClientIP} ) || &CheckValidClient( $ClientIP, \@G_ValidClientIPRange ) )
{
	close( $NS );
	return( 1, "SockAcceptCheck: TCP/IP Connection from Invalid Host: '$ClientIP'\n" );
}

&LogMsg( "TCP/IP Connection from Host: '$ClientIP'\n" ) if( $ClientIP ne $G_ServerIP );

#select($NS); $| = 1; select(STDOUT);
$NS->autoflush( 1 );
$G_Select->add($NS);
$p_InbufHash->{$NS}{DATA} = "";
$p_InbufHash->{$NS}{IP} = $ClientIP;

$G_SockCnt += 1;
$G_SockCntMax = $G_SockCnt if( $G_SockCnt > $G_SockCntMax );

return( 0, "" );

}	# end of Sock Accept Check


#-------------------------------------------------------#
#	Send Response - Send contents of G_ReturnArray to client
#-------------------------------------------------------#
sub SendResponse
{
my( $Socket, $response ) = @_;
my( $buf );

$response = 1 unless( defined($response) );

# Respond to client msg
while( 1 )
{
	$buf = "";
	$buf = shift( @G_ReturnArray );
	last unless( defined( $buf ) );
	
	# Make sure buf ends with newline
	$buf =~ s/\n*$/\n/;

	print $Socket "\~$buf";
	if( $G_Config{"TRACERESPONSES"} == 1 ) { &LogMsg( "RESPONSE: $buf" ); }
	elsif ($buf =~ /^$FAILURE_MSG:\s+/i) { &LogMsg( "RESPONSE: $buf" ); }
}

return if( $response == 0 );
print $Socket "\n$LAST_MSG\n";

}	# end of Send Response


#-------------------------------------------------------#
#	Send EQ Msg
#-------------------------------------------------------#
sub SendEQMsg
{
my( $msg, $title ) = @_;

# Print message if title provided
&LogMsg( "$title: $msg\n" ) if( defined($title) && $G_Config{LOGEQMSGS} );

$msg =~ s/\n+$//;
push( @G_EQServerData, $msg );
return;

}	# end of Send EQ Msg


#-------------------------------------------------------#
#	Get Socket IP Addr Port
#-------------------------------------------------------#
sub GetSocketIPAddrPort
{
my( $socket ) = @_;
my( $RemoteSide, $RemoteIP, $RemoteIAddr, $RemotePort );

$RemoteSide = getpeername($socket) || &LogMsg( "Can't ID Remote Side", 1);
( $RemotePort, $RemoteIAddr ) = unpack_sockaddr_in($RemoteSide);
$RemoteIP =  inet_ntoa( $RemoteIAddr );

return( $RemoteIP, $RemotePort );

}	# end of Get Socket IP Port


#-------------------------------------------------------#
#	Verify Req Keys
#-------------------------------------------------------#
sub VerifyReqKeys
{
my( $p_hash, $keys ) = @_;
my( @arr, $k, $buf );

@arr = split( /,/, $keys );

$buf = "";
foreach $k( @arr ) {
	next if( exists($$p_hash{$k}) );
	$buf .= "$k, ";
}

# return if all required keys exist in hash
return( 0, "" ) if( $buf eq "" );

$buf =~ s/, $//;	# Remove last ", "
return( 1, "VerifyReqKeys: Required keyword(s) ($buf) missing from message\n" );

}	# end of Verify Req Keys


#-------------------------------------------------------#
# 	Process Msg
#-------------------------------------------------------#
sub ProcessMsg
{
my( $Msg, $src_ip ) = @_;
my( %hash, $buf, $msgtype, $p_msgsub, $kw, $response, $err, $msg );

$src_ip = $xc_IP unless( $src_ip );
&LogMsg( "Process Msg from '$src_ip'\n$Msg" ) if( $G_Config{DEBUG} );

# Clear left over messages pushed onto return array
@G_ReturnArray = ( );
# Replace all control characters in the message with spaces
$Msg =~ tr/\x00-\x1F\x7F-\xFF/ /s;

&HashMsg( \$Msg, \%hash );

# Make sure message contains the $M_Key ("T_MSG") keyword
$msgtype = $hash{$M_Key};
if( !defined( $msgtype ) )
{
	# Log message if parm set as such...
	&LogMsg( "REQUEST: $Msg\n")	if	($G_Config{"TRACEREQUESTS"} == 1);

	$buf = "$FAILURE_MSG: Required keyword missing: $M_Key\n";
	push( @G_ReturnArray, $buf );
	return 1;
}

# Message types should be all caps, so force it
$msgtype =~ tr/[a-z]/[A-Z]/;

if	($msgtype eq "DISPATCH")
{
	# Log message if parm set as such...
	&LogMsg( "REQUEST: $Msg\n" )	if	($G_Config{"TRACEDISPATCH"} == 1);
}
# Log message if parm set as such...
elsif	(($G_Config{"TRACEREQUESTS"} == 1)&&($msgtype ne "TIMER"))
{
	&LogMsg( "REQUEST: $Msg\n" );
}

# Is it a supported message type?  Check for entry in M_Function list
$p_msgsub = $M_MsgDesc{$msgtype}{func};
if( !defined( $p_msgsub ) )
{
	$buf = "$FAILURE_MSG: Message type not supported: $msgtype\n";
	push( @G_ReturnArray, $buf );
	return 1;
}

# DSL - 20110322 - Make sure message type allows external hosts to send
my $allowremote = defined($M_MsgDesc{$msgtype}{allowremote}) ? $M_MsgDesc{$msgtype}{allowremote} : 0;
if( $src_ip ne $xc_IP && $allowremote == 0 )
{
	$buf = "Message Type not allowed from external host; $src_ip\n";
	push( @G_ReturnArray, $buf );
	return 1;
}

# Verify required keys provided
($err, $msg) = &VerifyReqKeys( \%hash, $M_MsgDesc{$msgtype}{reqkeys} );
if( $err ) 
{
	push( @G_ReturnArray, "$FAILURE_MSG: ProcessMsg:$msg" );
	return( $err );
}

# Do not process AddDRec and DelDRec messages when we restore the queue
return	if	(($G_RestoringQ)&&
			 (($msgtype eq "ADDDREC")||($msgtype eq "DELDREC")));

# Set time the message was received if needed
#$hash{($Q_RecdTSDesc{keyword})} = time() if( $M_MsgDesc{$msgtype}{checkq} );

# Remove M_Key ("T_MSG") from hash
delete( $hash{$M_Key} );

if	(defined ($hash{RESPONSE}))
{
	$response = $hash{RESPONSE};
	delete ($hash{RESPONSE});
}
elsif	(defined ($hash{T_RESPONSE}))
{
	$response = $hash{T_RESPONSE};
	delete ($hash{T_RESPONSE});
}

# Invoke the routine that supports this message type
#&$p_msgsub( \%hash );

# Invoke the routine that supports this message type
($err, $msg) = &$p_msgsub( \%hash );
if( defined($msg) && $msg ne "" ) 
{
	if( $err ) 
	{
		$buf = $msg =~ /^$FAILURE_MSG: / ? $msg : "$FAILURE_MSG: $msg";
	}
	else
	{
		$buf = $msg =~ /^$SUCCESS_MSG: / ? $msg : "$SUCCESS_MSG: $msg";
	}
	push( @G_ReturnArray, $buf ); 
}

$G_CheckQ = $M_MsgDesc{$msgtype}{checkq};

return $response;

}	# end of process msg


#-------------------------------------------------------#
#                                                       #
# Gen trans id, and update Max Msg Per Sec
#                                                       #
# Returns:	ID as string in format <timestamp><seq#>
#		where <timestamp> = secs since Jan.1, 1970
#		<seq#> = range "00000" - "99999"
#                                                       #
#-------------------------------------------------------#
sub AssignID
{
my( $Now, $TID );

$Now = time;
if( $G_LastMsg == $Now )
{
	$G_CurMsgCnt += 1;
	if( $G_CurMsgCnt > $G_MaxMsgCnt ) { $G_MaxMsgCnt = $G_CurMsgCnt; }
	$G_MsgSeq += 1;
	$TID = sprintf( "%d%05d", $G_LastMsg, $G_MsgSeq );
}
else
{
	$G_LastMsg = $Now;
	$G_CurMsgCnt = 0;
	$G_MsgSeq = 0;
	$TID = sprintf( "%d00000", $Now );
}

return( $TID );

}	# end of Assign TID


#-------------------------------------------------------#
#	Get Command Line
#-------------------------------------------------------#
sub GetCommandLine
{
my( $p_config, $p_config_mod ) = @_;
my( $s );

&getopts('hc:d');

# Help?
&Syntax( 0 ) if( $opt_h );

# Processing delay?
if( $opt_c )
{	# Check if there is one more argument on command line
	&LogMsg( "\n$opt_c not a readable file\n", 1 ) unless( -f $opt_c && -r $opt_c );
	$$p_config{"CONFIGFILE"} = $opt_c;
	$$p_config_mod{"CONFIGFILE"} = "as command line argument";
}

if( $opt_d ) {
	$G_Debugging = 1;
	$G_Config{DEBUG} = 1;
	warn ("Debugging turned on\n");
}

}	# end of Get Command Line


#-------------------------------------------------------#
#	Display Parms
#-------------------------------------------------------#
sub DisplayParms
{
my( $p_config, $p_config_mod ) = @_;
my( $s );

#if( defined($ENV{'sourceExe'}) ) {
#	&LogMsg( "Source Version: $ENV{'sourceExe'}\n" ); }

&LogMsg( "Version: $x_version\n");

foreach $s ( sort keys( %$p_config ) )
{
	&LogMsg( "$s - $$p_config{$s} $$p_config_mod{$s}\n" );
}

&LogMsg( "\n" );

}	# end of Display Parms


#-------------------------------------------------------#
#	Init Config Mod
#-------------------------------------------------------#
sub InitConfigMod
{
my( $p_config, $p_config_mod ) = @_;
my( $s );

# Initialize data
# G_ConfigMod array is used to keep a name of function/module
# that did the last modification to the parameter's value

foreach $s ( keys( %$p_config ) ) {
	$$p_config_mod{$s} = "by default";
}

}  # end of Init Config Mod


#-------------------------------------------------------#
#	Read Cfg File
#-------------------------------------------------------#
sub ReadCfgFile
{
my( $p_filename, $p_config, $p_config_mod ) = @_;
my( $s, $cmd, $val, $c, $c1, $i );

# If configuration file does not exist
unless (-f $$p_filename)
{
	&LogMsg( "Configuration file $$p_filename does not exist\n" );
	return;
}

# Open configuration file and process it line by line
open (IN_FILE, $$p_filename) ||
	&LogMsg( "Cannot open configuration file '$$p_filename': $!\n", 1);
for( $i = 1; defined( $s = <IN_FILE> ); $i++ )
{
	# Skip comments and empty lines
	next	if	($s =~ /^\s*$/);
	next	if	($s =~ /^\s*#/);

	# Get name and value
	if	($s =~ /^\s*(\S+)\s*=(.*)$/)
	{
		$cmd = "\U$1";	#uppercase parm
		$val = $2;

		# Do we expect this parameter?
		if( !defined( $$p_config{$cmd} ) )
		{	next if( defined ( $$p_config{"*"} ) );
			&LogMsg( "Error in file '$p_filename' on line $i: Invalid parameter name\n", 1);
		}

		# Remove any heading/trailing spaces in value
		$val =~ s/^\s+//;
		$val =~ s/\s+$//;

		# If the value is enclosed into quotes
		if	($val =~ /^['"]/)
		{
			# Remove quotes
			$c = substr ($val, 0, 1);
			substr ($val, 0, 1) = "";
			$c1 = chop ($val);
			&LogMsg( "Error in file '$$p_filename' on line $i: Unterminated quote\n", 1)
				if	($c ne $c1);
		}

		# Save parameter's value
		$$p_config{$cmd} = $val;
		$$p_config_mod{$cmd} = "in cfg file";
	}
	else
	{
		&LogMsg( "Error in file '$$p_filename' on line $i: Invalid data\n", 1);
	}
}
close (IN_FILE);
}	# end of Read Cfg File


#-------------------------------------------------------#
#	Parse Class File
#-------------------------------------------------------#
sub ParseClassFile
{
my( $p_FileName, $p_exit ) = @_;
my( $s, $key, $val, $c, $c1, $i );
my( %hash, $buf, $kw, $status );

# If configuration file does not exist
unless (-f $$p_FileName)
{
	&LogMsg( "Class file $$p_FileName does not exist\n" );
	return "";
}

# Open class file and process it line by line
unless	(open (IN_FILE, $$p_FileName))
{
	$s = "File open error '$$p_FileName': $!\n";
	&LogMsg( $s, $p_exit );
	return $s;
}

# First, delete all class records
&DeleteXRecs( \%C_KeyDesc );

for( $i = 1; defined( $s = <IN_FILE> ); $i++ )
{
	chomp($s);

	# Skip comments and empty lines
	next	if	($s =~ /^\s*$/);
	next	if	($s =~ /^\s*#/);

	&HashMsg( \$s, \%hash );
	($status,$buf) = &AddXRec( \%hash, $C_Key, \%C_KeyDesc );
	unless( $status )
	{
		&LogMsg( "AddXRec Error for $s: $buf\n" );
		&LogMsg( "Correct or remove from $$p_FileName \n" );
		&LogMsg( "\n" );
	}

}	# end of for loop

close (IN_FILE);

return "";
}	# end of Parse Class File


#-------------------------------------------------------#
#	Parse Trans Files
#-------------------------------------------------------#
sub ParseTransFiles
{
my( $p_dir ) = @_;
my( $err, $msg, $dir, $path, $file, @files, $defaults_file, %defhash, $options, $mask, $trans, %transhash, $p_hash, $success, $return_buf );

$dir = $$p_dir;
# The first parameter of this subroutine is a directory name. For existing
# installations that didn't update TRANSFILE (now called TRANSCFGDIR) parameter we need to replace
# the file name with correct directory name.
if	($dir =~ m#/trans\.cfg$#i)
{
	$dir =~ s#/[^/]+$##;
	$dir .= '/trans';
}
$dir =~ s#/$##;

return( 1, "Error opening directory '$dir': $!" ) unless( opendir (IN_DIR, $dir) );

@files = ();
$options = ($^O =~ /win/i)? '(?i)': '';
$mask = "$options^.+\\.cfg\$";
while (defined ($file = readdir (IN_DIR)))
{
	next	if	(($file eq '.')||($file eq '..'));
	$path = $dir . '/' . $file;
	if( $file =~ /Defaults\.cfg$/i )
	{
		$default_file = $path;
	}
	else
	{
		push( @files, $path ) if( $file =~ /$mask/ && -f $path );
	}
}
closedir (IN_DIR);

return( 1, "No transaction files found in '$dir'" ) if( @files == 0 );

# First, delete all trans records
&DeleteXRecs( \%T_DefKeyDesc );

# Set transaction defaults if 'Defaults.cfg' exists
%defhash = ( );
if( -f $default_file )
{
	($err, $msg) = &ProcessTransFile( $default_file, \%defhash );
	return( 1, $msg ) if( $err );
}

foreach $file( @files )
{
	# Restore transaction defaults if Defaults.cfg exists
	&SetTransDefaults( $defhash{Defaults} ) if( defined( $defhash{Defaults} ) );
	
	%transhash = ( );
	($err, $msg) = &ProcessTransFile( $file, \%transhash );
 	if( $err )
 	{
	 	print "$msg\n";
	 	next;
 	}
 	
 	# Set new transaction defaults if [Defaults] defined in file
	&SetTransDefaults( $transhash{Defaults} ) if( defined( $transhash{Defaults} ) );
 	
 	foreach $trans( keys %transhash )
 	{
 	 	next if( $trans eq "Defaults" );	# Skip 'Defaults' section
		$p_hash = $transhash{$trans};
 		($success, $msg) = &AddXRec( $p_hash, $T_DefKey, \%T_DefKeyDesc );
		$return_buf .= "ParseTransFiles Error: $msg\n" unless( $success );
	}
}

# Restore transaction defaults if Defaults.cfg exists
&SetTransDefaults( $defhash{Defaults} ) if( defined( $defhash{Defaults} ) );

return( 0, $return_buf );

}	# end of Parse Trans Files


#--------------------------------------	
#	Process Trans File
#--------------------------------------	
sub ProcessTransFile
{
my( $file, $p_transhash ) = @_;	
my( $k, $v );

return( 1, "Error opening '$file': $!" ) unless( open( TRANSFILE, "$file" ) );
my @a = <TRANSFILE>;
close( TRANSFILE );

# Strip all GUI-related fields from the configuration file
my $trans = "";
foreach my $s( @a )
{
	$s =~ s/\s+$//;
	$s =~ s/^\s+//;
	next if( $s eq "" || $s =~ /^#/ );
	
	# Get section name
	if	($s =~ /^\[(.+)\]$/)
	{
		$trans = $1;
		$p_transhash->{$trans} = ( );
		$p_transhash->{$trans}->{T_TRANS} = $trans;
		next;
	}
	
	# Skip GUI configuration lines
	next if( $s !~ /^T_/i || $s =~ /^T_(MSG|TRANS|PROFILE)/i );
	
	next unless( $s =~ /^\s*(\S+)\s*=\s*(.*)$/ ) ;

	$k  = $1;
	$v = $2;
	$k =~ tr/a-z/A-Z/;
	
	# Process T_CLIENTIPS keyword
	&ProcessClientIPs( \$v ) if( $k eq "T_CLIENTIPS" && $v );
	
	$p_transhash->{$trans}->{$k} = $v; 
}

return( 0, "" );

}	# end of Parse Trans Files


#-------------------------------------------------------#
#	Set Trans Defaults
#-------------------------------------------------------#
sub SetTransDefaults
{
my( $p_hash ) = @_;
my( $key );

foreach $key( keys %$p_hash )
{
	next unless( defined($T_DefKeyDesc{$key} ) );
	$T_DefKeyDesc{$key}->{defval} = $p_hash->{$key};
}

return( 0, "" );

}	# end of Set Trans Defaults


#-------------------------------------------------------#
#   Process Client IPs
#-------------------------------------------------------#
sub ProcessClientIPs
{
my	($p_list) = @_;
my	(@a, $s, @ips);

return;

$s = $$p_list;
$s =~ s/\s+$//;
$s =~ s/^\s+//;
@a = split (/\s*,\s*/, $s);
foreach $s (@a)
{
	if	($s =~ /^EQ$/i)
	{
		push (@ips, "1");
	}
	elsif	($s =~ /^TMR$/i)
	{
		push (@ips, "2");
	}
	elsif	($s =~ /^MN$/i)
	{
		push (@ips, "1");
	}
	elsif	($s =~ /^\d+\.\d+\.\d+\.\d+$/)
	{
		push (@ips, 4, $s);
	}
	elsif	($s =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)\s*\-\s*(\d+)\.(\d+)\.(\d+)\.(\d+)$/)
	{
		push (@ips, 5, (($1 * 256 + $2) *256 + $3) * 256 + $4,
			(($5 * 256 + $6) *256 + $7) * 256 + $8);
	}
}



}	# end of Process Client IPs


#-------------------------------------------------------#
#	Parse EQ Msg
#-------------------------------------------------------#
sub ParseEQMsg
{
my( $file ) = @_;
my( @data, $p_hash, $s, $msg, $k, $v );

# Just return if file doesn't exist
return( 0, "" ) unless( -f "$file" );

return( 1, "Error opening '$file': $!" ) unless( open( FH, "$file" ) );
@data = <FH>;
close( FH );

$p_hash = undef;
foreach $s( @data )
{
	# trim leading/trailing spaces, and skip blank lines and comments
	$s =~ s/^\s+|\s+$//g; 
	next if( $s =~ /^\#/ || $s eq "" );
	
	# see if we found a [section] line
	if( $s =~ /^\[(.+)\]$/ )
	{
		$msg = $1;
		$p_hash = $M_MsgDesc{$msg};
		next;
	}
	
	# nothing to do if we don't have a valid message type
	next unless( defined($p_hash) );
	
	# skip lines that don't look like 'key = value'
	next unless( $s =~ /^([^=]+)=(.*)$/ );
	
	$k = $1;
	$v = $2;
	$k =~ s/\s+$//;
	$v =~ s/^\s+//;
	$p_hash->{$k} = $v;
}

#use Data::Dumper;
#$msg = &Dumper( \%M_MsgDesc );
#&LogMsg( $msg );

return( 0, "" );

}	# end of Parse EQ Msg


#-------------------------------------------------------#
#	Dump Hash Recs
#-------------------------------------------------------#
sub DumpHashRecs
{
my( $p_Key, $p_DescHash ) = @_;
my( $p_masterdesc, $p_masterhash, $masterkey );
my( $buf, $p_tempdesc, $p_temphash, $reccnt );

# Find master desc and hash ptr
$p_masterdesc = $$p_DescHash{$$p_Key};
$p_masterhash = $$p_masterdesc{hashptr};

$reccnt = 0;
# Now, for each element in master hash,
foreach $masterkey ( sort keys( %$p_masterhash ) )
{
	$reccnt += 1;
	# first, clear buf and append
	$buf = "";
	$buf .= "$$p_Key=$masterkey;";

	# find match for each of the other hashes
	foreach $p_tempdesc ( sort values( %$p_DescHash ) )
	{
		# skip master key description
		next if( $p_tempdesc == $p_masterdesc );

		# set pointer to hash for keyword
		$p_temphash = $$p_tempdesc{hashptr};

		# put keyword and value in output buffer
		$buf .= "$$p_tempdesc{keyword}=$$p_temphash{$masterkey};";
	}
	# lop off last ';'
	chop( $buf );
	&LogMsg( "$buf\n" );
}

if( $reccnt == 0 ){ $buf = "No records in hash\n"; }
else { $buf = "Total Records ed = $reccnt\n"; }

&LogMsg( $buf );

}	# end of Dump Hash Recs


#-------------------------------------------------------#
#	Display Def Trans Recs
#-------------------------------------------------------#
sub DisplayDefTransRecs
{
my( $mkey, $buf, $p_tempdesc, $p_temphash, $reccnt, $p_transhash );

$reccnt = 0;

# Now, for each element in master hash,
$p_transhash = $T_DefKeyDesc{$T_DefKey}{hashptr};

foreach $mkey ( sort keys( %$p_transhash ) )
{
	$reccnt += 1;
	# first, clear buf and append
	$buf = "";
	$buf .= "$T_DefKey=$mkey;";

	# find match for each of the other hashes
	foreach $p_tempdesc ( sort values( %T_DefKeyDesc ) )
	{
		# skip master key description
		next if( $$p_tempdesc{keyword} eq "$T_DefKey" );

		# set pointer to hash for keyword
		$p_temphash = $$p_tempdesc{hashptr};

		# put keyword and value in output buffer
		$buf .= "$$p_tempdesc{keyword}=$$p_temphash{$mkey};";
	}
	# lop off last ';'
	chop( $buf );
	&LogMsg( "$buf\n" );
}

if( $reccnt == 0 ){ $buf = "No records in hash\n"; }
else { $buf = "Total Records Displayed = $reccnt\n"; }

&LogMsg( $buf );
&LogMsg( "\n" );

}	# end of Display Def Trans Recs


#-------------------------------------------------------#
#	Display C Recs
#-------------------------------------------------------#
sub DisplayCRecs
{
my( $mkey, $buf, $p_tempdesc, $p_temphash, $reccnt );

$reccnt = 0;
# Now, for each element in master hash,
foreach $mkey ( sort keys( %C_ClassHash ) )
{
	$reccnt += 1;
	# first, clear buf and append
	$buf = "";
	$buf .= "$C_Key=$mkey;";

	# find match for each of the other hashes
	foreach $p_tempdesc ( sort values( %C_KeyDesc ) )
	{
		# skip master key description
		next if( $$p_tempdesc{keyword} eq "$C_Key" );

		# set pointer to hash for keyword
		$p_temphash = $$p_tempdesc{hashptr};

		# put keyword and value in output buffer
		$buf .= "$$p_tempdesc{keyword}=$$p_temphash{$mkey};";
	}
	# lop off last ';'
	chop( $buf );
	&LogMsg( "$buf\n" );
}

if( $reccnt == 0 ){ $buf = "No records in hash\n"; }
else { $buf = "Total Records Displayed = $reccnt\n"; }

&LogMsg( $buf );
&LogMsg( "\n" );

}	# end of Display C Recs


#-------------------------------------------------------#
#	Log Dispatch Priority Hash
#-------------------------------------------------------#
sub LogDispatchPriorityHash
{
my( $pri, $p_hash, $buf, $did );

foreach $pri ( sort keys %G_DispatchPriorityHash ) {
	$p_hash = $G_DispatchPriorityHash{$pri};
	$buf = "PRI: $pri\n";
	foreach $did( sort keys %$p_hash ) { $buf .= "\tDID: $did  TGT: $$p_hash{$did}\n"; }
	&LogMsg( "TRACEDQ: $buf" );
}

}	# end of Log Dispatch Priority Hash


#-------------------------------------------------------#
#	Delete Dispatch Pri Rec
#-------------------------------------------------------#
sub DeleteDispatchPriRec
{
my( $did ) = @_;
my( $pri, $target, $buf );

$pri = $D_PriorityHash{$did};
$target = $D_TargetHash{$did};

delete( $G_DispatchPriorityHash{$pri}{$did} );

if( $G_Config{TRACEDQ} ) 
{
	$buf = "TRACEDQ: Deleted $target from Dispatch Priority Hash";
	&LogMsg( $buf );
#	&Carp::cluck( $buf );
#	&LogDispatchPriorityHash( );
}

}	# end of Delete Dispatch Pri Rec


#-------------------------------------------------------#
#	Add Dispatch Pri Rec
#-------------------------------------------------------#
sub AddDispatchPriRec
{
my( $did ) = @_;
my( $pri, $target, $buf, $p_hash );

$pri = $D_PriorityHash{$did};
$target = $D_TargetHash{$did};
$G_DispatchPriorityHash{$pri}{$did} = $target;

if( $G_Config{TRACEDQ} ) {
	$buf = "Added $target to Dispatch Priority ($pri) Hash\n";
	&LogMsg( "TRACEDQ: $buf" );
#	&LogDispatchPriorityHash( );
}

}	# end of Add Dispatch Pri Rec


#-------------------------------------------------------#
#	Delete Dispatch Target Rec
#-------------------------------------------------------#
sub DeleteDispatchTargetRec
{
my( $did ) = @_;
my( $target, $target_type, $buf );

$target = $D_TargetHash{$did};
$target_type = $D_TargetTypeHash{$did};
delete( $G_DispatchTargetHash{$target_type}{$target} );

if( $G_Config{TRACEDQ} ) {
	$buf = "Deleted $target_type:$target from Dispatch Target Hash\n";
	&LogMsg( "TRACEDQ: $buf" );
}

}	# end of Delete Dispatch Target Rec


#-------------------------------------------------------#
#	Add Dispatch Target Rec
#-------------------------------------------------------#
sub AddDispatchTargetRec
{
my( $did ) = @_;
my( $target, $target_type, $buf );

$target = $D_TargetHash{$did};
$target_type = $D_TargetTypeHash{$did};
$G_DispatchTargetHash{$target_type}{$target} = $did;

if( $G_Config{TRACEDQ} ) {
	$buf = "Added $target_type:$target to Dispatch Target Hash\n";
	&LogMsg( "TRACEDQ: $buf" );
}

}	# end of Add Dispatch Target Rec


#-------------------------------------------------------#
#	M Add D Rec
#-------------------------------------------------------#
sub M_AddDRec
{
my( $p_hash ) = @_;
my( $buf, $did );

($did,$buf) = &AddXRec( $p_hash, $D_Key, \%D_KeyDesc, "AddDRec", 1 );
return( 1, "Error adding Dispatch Rec: $buf" ) if( $did == 0 );

# Add record to Dispatch Priority Hash
&AddDispatchPriRec( $did );
&AddDispatchTargetRec( $did );

# Maintain count of records in queue and maximum value
$G_DispCnt += 1;
$G_DispCntMax = $G_DispCnt if( $G_DispCnt > $G_DispCntMax );

# Check if dispatch message can expire
if( $D_ExpireHash{$did} !~ /^\s*$/ ) 
{
	# Add expiration time
	$buf = &UpdateExpirationTimeRec( $D_ExpireHash{$did}, $did, \%G_ExpireDHash, 1, \$G_NextExpireDRec );
	if	($buf ne "")
	{
		$buf =~ s/\n$//;
		return( 1, $buf );
	}
}

$buf  = "Added $D_TargetHash{$did} ($D_Key=$did) to Dispatch Queue.";
$buf .= " (T_TRANS='$$p_hash{T_TRANS}')" if( defined($$p_hash{T_TRANS}) && $$p_hash{T_TRANS} ne "" );
$buf .= " (T_PROFILE='$$p_hash{T_PROFILE}')" if( defined($$p_hash{T_PROFILE}) && $$p_hash{T_PROFILE} ne "" );
&LogMsg( "TRACEDQ: $buf" ) if( $G_Config{TRACEDQ} );

$$p_hash{$D_Key} = $did;

return( 0, $buf );

}	# end of M Add D Rec


#-------------------------------------------------------#
#	M Add T Rec
#-------------------------------------------------------#
sub M_AddTRec
{
my( $p_hash ) = @_;
my( $tid, $buf, $apparg_kw );

$apparg_kw = $T_AppArgsDesc{keyword};
if( defined($$p_hash{$apparg_kw}) ) { $$p_hash{$apparg_kw} =~ s/^\'|\'$//g; }

($tid,$buf) = &AddXRec( $p_hash, $T_Key, \%T_KeyDesc, "AddTRec", 1 );
return( 1, "Error adding Trans Rec: $buf" ) if( $tid == 0 );

$$p_hash{T_TID} = $tid;
&AddTID2MIDRec( $tid );

# Maintain count of records in queue and maximum value
$G_TransCnt += 1;
$G_TransCntMax = $G_TransCnt if( $G_TransCnt > $G_TransCntMax );

$buf = "Added $T_TransHash{$tid} ($T_Key=$tid) to Trans Queue\n";
&LogMsg( "TRACETQ: $buf" ) if( $G_Config{TRACETQ} );

return( 0, $buf );

}	# end of M Add T Rec


#-------------------------------------------------------#
#	M Add M Rec
#-------------------------------------------------------#
sub M_AddMRec
{
my( $p_hash ) = @_;
my( $status, $apparg_kw, $mid, $buf, $k, $p_deschash, %hash);

#$apparg_kw = $Q_AppArgsDesc{keyword};
#if( defined($$p_hash{$apparg_kw}) ) { $$p_hash{$apparg_kw} =~ s/^\'|\'$//g; }

($mid,$buf) = &AddXRec( $p_hash, $Q_Key, \%Q_KeyDesc, "AddMRec", 1 );
return( 1, "Error adding Msg Rec: $buf" ) if( $mid == 0 );

#&AddTargetKeyRec( $mid );
$Q_TargetKeyHash{$Q_TargetTypeHash{$mid} . $Q_TargetHash{$mid}}{$mid} = 0;
&AddDupMIDKeyRec( $mid );

%hash = ();
# Call all necessary keyword post-processing functions
#foreach $k (@Q_KeyDesc_keys)
# Q_KeyDesc_functions array contains only elements from Q_KeyDesc array
# that have 'function' defined
foreach $k (@Q_KeyDesc_functions)
{
	$p_deschash = $Q_KeyDesc{$k};
	if	((defined ($$p_hash{$k}))&&($$p_hash{$k} ne ""))
	{
		$buf = &{$$p_deschash{function}} ($mid, $$p_hash{$k}, "", \%hash);
		if	($buf ne "")
		{
			&DeleteMRec( $mid );
			$buf =~ s/\n$//;
			return( 1, $buf );
		}
	}
}

# Save record modifications
if	(%hash)
{
	$hash{$M_Key} = "ModMRec";
	$hash{$Q_Key} = $mid;
	&StoreMsg( \%hash );
}

# Maintain count of records in queue and maximum value
$G_MsgCnt += 1;
$G_MsgCntMax = $G_MsgCnt if( $G_MsgCnt > $G_MsgCntMax );

$buf = "Added $Q_TargetHash{$mid} ($Q_Key=$mid) to message queue\n";
&LogMsg( "TRACEMQ: $buf" ) if( $G_Config{TRACEMQ} );

$$p_mid{T_MID} = $mid;

return( 0, $buf );

}	# end of M Add M Rec


#-------------------------------------------------------#
#	M Add S Rec
#-------------------------------------------------------#
sub M_AddSRec
{
my( $p_hash ) = @_;
my( $sched, $uts, $msg, $sid, $buf, $action );

# convert schedule if not already UTS
if( !defined($$p_hash{T_SCHEDULE}) || $$p_hash{T_SCHEDULE} eq "" ) {
	push( @G_ReturnArray, "$FAILURE_MSG: T_SCHEDULE keyword missing from message\n" );
	return( 0 );
}

($uts,$msg) = &Sched2UTS( $$p_hash{T_SCHEDULE} );
if( $msg ne "" ) {
	push( @G_ReturnArray, "$FAILURE_MSG: Error scheduling record: $msg\n" );
	return( 0 );
}

$$p_hash{T_UTS} = $uts;

# Check if schedule record exists already
$sid = &ChkDupSIDKeyRec( $p_hash );
if( $sid ne "0" ) {
	$buf = "$SUCCESS_MSG: Use duplicate schedule record ($S_Key=$sid)\n";
	push( @G_ReturnArray, $buf );
	return( $sid );
}

($sid,$msg) = &AddXRec( $p_hash, $S_Key, \%S_KeyDesc, "AddSRec", 1 );
if( $sid == 0 ) {
	push( @G_ReturnArray, "$FAILURE_MSG: Error adding Schedule Rec: $msg\n" );
	return( 0 );
}

&AddDupSIDKeyRec( $sid );

$action = $S_TransHash{$sid};
$action .= ":$S_ProfileHash{$sid}" if( $S_ProfileHash{$sid} ne "" );

$buf = localtime( $S_UTSHash{$sid} );
$msg = "Added $action ($S_Key=$sid) to schedule queue to start at ($S_UTSHash{$sid}) $buf\n";
push( @G_ReturnArray, "$SUCCESS_MSG: $msg" );

return( $sid );

}	# end of M Add S Rec


#-------------------------------------------------------#
#	Add X Rec
#-------------------------------------------------------#
sub AddXRec
{
my( $p_NewHash, $Key, $p_DescHash, $msgtype, $store ) = @_;
my( $p_masterdesc, $p_masterhash, $masterkey );
my( $id, $kw, $p_desc, $p_hash, $p_hashhash, $old_id );
my	($buf);

# Get unique id and assign to hash
if( defined($msgtype) &&
	(!defined($$p_NewHash{$Key}) || ($$p_NewHash{$Key} eq "0") ) ) {
	$id = &AssignID( );
	$$p_NewHash{$Key} = $id;
}
else {
	$id = $$p_NewHash{$Key};
	if( !defined($id) )
	{
		use Data::Dumper;
		$buf = &Dumper( $p_NewHash );
		return( 0, "AddXRec: $Key keyword/value missing\n$buf" );
	}
}

# Find master desc and hash ptr
$p_masterdesc = $$p_DescHash{$Key};
$p_masterhash = $$p_masterdesc{hashptr};

return( 0, "Duplicate master value: $Key=$id" ) if( exists($$p_masterhash{$id}) );

# Not there, so let's add it
#$$p_masterhash{$id} = $id;

$buf = ($msgtype)? "$M_Key=$msgtype": "";

# Now, for each "field" in hash "record"
foreach $p_desc ( values( %$p_DescHash ) )
{
	# skip master since it's already been assigned
#	next if( $p_desc == $p_masterdesc );

	$kw = $$p_desc{keyword};

	# set pointer to correct hash for this keyword
	$p_hash = $$p_desc{hashptr};

	# if not passed in hash argument, use default
	if( !exists( $$p_NewHash{$kw} ) )
	{
		# check if keyword required for transaction
		if( $$p_desc{reqkey} == 1 )
		{
			# Remove from list
			delete( $$p_masterhash{$id} );
			use Data::Dumper;
			$buf = &Dumper( $p_NewHash ); 
			return( 0, "AddXRec: Required keyword missing: $kw\n$buf" );
		}
		$$p_hash{$id} = (($$p_desc{keytype} eq "TIMESTAMP")&&($$p_desc{defval} eq "NOW"))?
			time (): $$p_desc{defval};
	}
	else
	{
		$$p_hash{$id} = $$p_NewHash{$kw};
	}

	$buf .= ";$kw='$$p_hash{$id}'";
}	# end of foreach desc

if( defined($msgtype) && $store)
{
	print MSGFILE $buf, "\n"	if	(!$G_RestoringQ);
	$G_StoreQ = 1	if	($G_RestoringQ < 2);
}

return( $id, "" );

}	# end of Add X Rec


#-------------------------------------------------------#
#	M SetDID
#-------------------------------------------------------#
sub M_SetDID
{
my( $p_hash ) = @_;

@G_ReturnArray = &ModifyXRec( $p_hash, $D_Key, \%D_KeyDesc, \%D_DIDHash, "ModDRec", 1 );

}	# end of M SetDID


#-------------------------------------------------------#
#	M SetMID
#-------------------------------------------------------#
sub M_SetMID
{
my( $p_hash ) = @_;
my( $mid, $tid, $new_msgstatus, %statushash, $user, @arr, $ts, $reason );
my( $did, $target, $ttype, $err, $msg );

# First, make sure master keyword exists (e.g. T_MID)
return( 1, "Message must include $Q_Key" ) unless( defined($$p_hash{$Q_Key}) );

$mid = $$p_hash{$Q_Key};
return( 1, "Transaction $mid does not exist" ) unless( defined($Q_TargetHash{$mid}) );

# See if trying to change the status of an assigned MID
$tid = defined($Q_TIDHash{$mid}) ? $Q_TIDHash{$mid} : "0"; 
$new_msgstatus = defined($$p_hash{T_MSGSTATUS}) ? "\U$$p_hash{T_MSGSTATUS}" : "";
return( 1, "Cannot change status to ASSIGNED state" ) if( $new_msgstatus eq $ASSIGNED );
return( 1, "Cannot change parameters for running transaction" )if( $tid ne "0" && $new_msgstatus eq "");

# Save this info for later
$ttype	= $Q_TargetTypeHash{$mid};
$target	= $Q_TargetHash{$mid};
$did	= $G_DispatchTargetHash{$ttype}{$target} || "0";

# Set the reason for changing the MID
@arr = localtime( );
$ts = sprintf( "%02d/%02d/%04d at %02d:%02d:%02d", 
		   $arr[4] + 1, $arr[3], $arr[5] + 1900, $arr[2], $arr[1], $arr[0] );
$user = $$p_hash{T_EQUSER} || "UNKNOWN";
$reason = "ATTN: Reset by '$user' on $ts.";

# If defined, include reason passed to routine along with ATTN message
if( defined($$p_hash{T_REASON}) )
{
	$reason .= "$$p_hash{T_REASON} PREVIOUS REASON: $Q_ReasonHash{$mid}";
}

# Append to current reason if not already there
elsif( $tid eq "0" || $T_TranStatusHash{$tid} ne $MONITORING )
{
	$reason .= " PREVIOUS REASON: $Q_ReasonHash{$mid}";
}

$reason  = $1 if( $reason =~ /^(.+?PREVIOUS REASON:.+?)PREVIOUS REASON:/i );
$$p_hash{T_REASON}  = $reason;

# Do not change the owner of the record
delete ($$p_hash{T_EQUSER});
delete ($$p_hash{T_EQGROUP});

# If MID assigned to running transaction, use the TID in call to M Status to keep house in order
if( $tid ne "0" )
{
	$$p_hash{T_TID} = $tid;
	$$p_hash{T_RESULT} = 1;		# Fail distro for target
}

# Make sure target specified
$$p_hash{T_TARGET} = $Q_TargetHash{$mid};
# Make sure using uppercase status
$$p_hash{T_MSGSTATUS} = $new_msgstatus unless( $new_msgstatus eq "" );  

($err, $msg) = &M_Status( $p_hash );

# See if we changed the status of a dispatched, but not assigned, transaction
if( $new_msgstatus ne "" && $did ne "0" && $tid eq "0" )
{
	push( @G_CheckDispatchedTarget, $did );
}

return( $err, $msg );

}	# end of M SetMID


#-------------------------------------------------------#
#	M SetTID
#-------------------------------------------------------#
sub M_SetTID
{
my( $p_hash ) = @_;

@G_ReturnArray = &ModifyXRec( $p_hash, $T_Key, \%T_KeyDesc, \%T_TIDHash, "ModTRec", 1 );

}	# end of M SetTID


#-------------------------------------------------------#
#	M SetSID
#-------------------------------------------------------#
sub M_SetSID
{
my( $p_hash ) = @_;

@G_ReturnArray = &ModifyXRec( $p_hash, $S_Key, \%S_KeyDesc, \%S_SIDHash, "ModSRec", 1 );

}	# end of M SetSID


#-------------------------------------------------------#
#	M Modify D Rec
#-------------------------------------------------------#
sub M_ModifyDRec
{
my( $p_hash ) = @_;
my( @arr );

@arr = &ModifyXRec( $p_hash, $D_Key, \%D_KeyDesc, \%D_DIDHash, "ModDRec", 1 );
#return( @arr );

}	# end of M Modify D Rec


#-------------------------------------------------------#
#	M Modify S Rec
#-------------------------------------------------------#
sub M_ModifySRec
{
my( $p_hash ) = @_;
my( @arr );

@arr = &ModifyXRec( $p_hash, $S_Key, \%S_KeyDesc, \%S_SIDHash, "ModSRec", 1 );
#return( @arr );

}	# end of M Modify S Rec


#-------------------------------------------------------#
#	M Modify T Rec
#-------------------------------------------------------#
sub M_ModifyTRec
{
my( $p_hash ) = @_;
my( @arr );

@arr = &ModifyXRec( $p_hash, $T_Key, \%T_KeyDesc, \%T_TIDHash, "ModTRec", 1 );
#return( @arr );

}	# end of M Modify T Rec


#-------------------------------------------------------#
#	M Modify M Rec
#-------------------------------------------------------#
sub M_ModifyMRec
{
my( $p_hash ) = @_;
my( @arr );

@arr = &ModifyXRec( $p_hash, $Q_Key, \%Q_KeyDesc, \%Q_MIDHash, "ModMRec", 1 );
return( @arr );

}	# end of M Modify M Rec


#-------------------------------------------------------#
#	Modify X Rec
#-------------------------------------------------------#
sub ModifyXRec
{
my( $p_hash, $keyname, $p_keydesc, $p_keyhash, $msgtype, $store ) = @_;
my( $id, $oldval, $key, $newval, $descptr, $hashptr, @arr, %hash, $apparg_kw );
my( $l_target, $target_type, %l_schedhash, $sid, $buf );

%TraceHash = (
	T_MID	=> "TRACEMQ",
	T_TID	=> "TRACETQ",
	T_DID	=> "TRACEDQ",
	T_SID	=> "TRACESQ",
);

# First, make sure master keyword exists (e.g. T_MID)
if( !defined($$p_hash{$keyname}) ) {
	push( @arr, "$FAILURE_MSG: Message must include $keyname\n" );
	return( @arr );
}

# Make sure it's a valid record
$id = $$p_hash{$keyname};
if( !defined($$p_keyhash{$id}) ) {
	push( @arr, "$FAILURE_MSG: $keyname=$id not found.\n" );
	return( @arr );
}

if( defined($TraceHash{$keyname}) && $G_Config{$TraceHash{$keyname}} )
{
	$buf = "$TraceHash{$keyname}: Modifying $keyname=$id:  ";
	foreach	$key( keys %$p_hash )
	{
		next if( $key eq $keyname );
		$buf .= "$key='$$p_hash{$key}'; ";
	}
	&LogMsg( "$buf\n" );
}

$hash{$M_Key} = $msgtype;
$hash{$keyname} = $id;

# Doctor application arguments value if present
$apparg_kw = $Q_AppArgsDesc{keyword};
if( defined($$p_hash{$apparg_kw}) ) { $$p_hash{$apparg_kw} =~ s/^\'|\'$//g; }

# For each associative pair:
foreach $key (keys %$p_hash)
{
	# ignore T_MID
	next if( $key =~ /^$keyname$/i );

	$newval = $$p_hash{$key};

	# When processing T_TARGET key we also need to update internal hashes
	if	(($key =~ /^T_TARGET$/i)&&($keyname eq $Q_Key))
	{
		# Get old target name
		$l_target = $Q_TargetHash{$id};
		&LogMsg( "Changing T_TARGET for $keyname=$id from '$l_target' to '$newval'\n" );
		if	($l_target ne $newval)
		{
			$target_type = $Q_TargetTypeHash{$id};
			# Set new name for a target
			$Q_TargetHash{$id} = $newval;
			# Change target name in internal hashes
			$Q_TargetKeyHash{$target_type . $newval}{$id} =
				$Q_TargetKeyHash{$target_type . $l_target}{$id};
			&DelDupMIDKeyRec ($id);
			&AddDupMIDKeyRec ($id);
			# Delete internal data for old target name
			&DelTargetKeyRec ($target_type, $l_target, $id);
		}
	}

	# Special processing for T_SCHEDULE key
	if	(($key =~ /^T_SCHEDULE$/i)&&($keyname eq $Q_Key))
	{
		$newval =~ s/\s+$//;
		# If transaction should be rescheduled
		if	($newval)
		{
			%l_schedhash =
			(
				"T_EQUSER"		=> $Q_EQUserHash{$id},
				"T_EQGROUP"		=> $Q_EQGroupHash{$id},
				"T_PROFILE"		=> $Q_ProfileHash{$id},
				"T_SCHEDULE"	=> $newval,
				"T_TRANS"		=> $Q_TransHash{$id}
			);

			# Assign SID if T_SCHEDULE provided
			$sid = &M_AddSRec (\%l_schedhash);
			return	(@G_ReturnArray)	if	($sid eq "0");
			$Q_SIDHash{$id} = $sid;
		}
		# Remove scheduling
		else
		{
			$Q_SIDHash{$id} = "0";
		}
	}

	# validate keyword - push error message if not valid
	if( !defined($$p_keydesc{$key}) ) {
		push( @arr, "$FAILURE_MSG: Invalid keyword: $key\n" );
		next;
	}

	# store old value and set to new value
	$descptr = $$p_keydesc{$key};
	$hashptr = $$descptr{hashptr};
	$oldval = $$hashptr{$id};

	# Call keyword processing function if necessary
	if	($$descptr{function})
	{
		$buf = &{$$descptr{function}} ($id, $newval, $oldval, \%hash);
		if	($buf ne "")
		{
			$buf =~ s/\n$//;
			push (@arr, "$FAILURE_MSG: $buf\n");
			return (@arr);
		}
	}

	$$hashptr{$id} = $newval;

	# push message stating that keyword changed from old to new value
	push( @arr, "$SUCCESS_MSG: $key changed for $keyname=$id from: $oldval to: $newval\n" );
	$hash{$key} = $newval;
}

&StoreMsg( \%hash ) if( $store );

return( @arr );

}	# end of Modify X Rec


#-------------------------------------------------------#
#	Add TID 2 DID Rec
#-------------------------------------------------------#
sub AddTID2DIDRec
{
my( $tid, $did, $target ) = @_;

$Q_TID2DIDHash{$tid}{$did} = $target;
&LogMsg( "TRACETQ: Adding T_TID=$tid -> T_DID=$did -> T_TARGET=$target to TID2DID hash\n" ) if( $G_Config{TRACETQ} );

}	# end of Add TID 2 DID Rec


#-------------------------------------------------------#
#	Del TID 2 DID Rec
#-------------------------------------------------------#
sub DelTID2DIDRec
{
my( $tid, $did ) = @_;
my( $p_hash, @a );

if( defined($did) ) {
	delete( $Q_TID2DIDHash{$tid}{$did} );
	# Remove if no more did associated with tid
	$p_hash = $Q_TID2DIDHash{$tid};
	@a = keys %$p_hash;
	delete( $Q_TID2DIDHash{$tid} ) unless( scalar(@a) );
	&LogMsg( "TRACETQ: Deleting T_TID=$tid -> T_DID=$did from TID2DID hash\n" ) if( $G_Config{TRACETQ} );
}
else {
	delete( $Q_TID2DIDHash{$tid} );
	&LogMsg( "TRACETQ: Deleting T_TID=$tid from TID2DID hash\n" ) if( $G_Config{TRACETQ} );
}

}	# end of Del TID 2 DID Rec


#-------------------------------------------------------#
#	Add TID 2 MID Rec
#-------------------------------------------------------#
sub AddTID2MIDRec
{
my( $tid, $mid, $target ) = @_;
my	(%hash);

if( defined($mid) ) 
{
	$Q_TID2MIDHash{$tid}{$mid} = $target;

	# Also maintain transaction queue target assignment
	%hash = ( );
	$hash{$T_Key} = $tid;
	if( $T_TargetsHash{$tid} eq "" ) { $hash{T_TARGETS} = $target; }
	else { $hash{T_TARGETS} = $T_TargetsHash{$tid} . ",$target"; }
	&M_ModifyTRec( \%hash );
	&LogMsg( "TRACETQ: Adding T_TID=$tid -> T_MID=$mid -> T_TARGET=$target to TID2MID hash\n" ) if( $G_Config{TRACETQ} );
}
else 
{
	$Q_TID2MIDHash{$tid} = ( );
	&LogMsg( "TRACETQ: Adding T_TID=$tid to TID2MID hash\n" ) if( $G_Config{TRACETQ} );
}

}	# end of Add TID 2 MID Rec


#-------------------------------------------------------#
#	Del TID 2 MID Rec
#-------------------------------------------------------#
sub DelTID2MIDRec
{
my( $tid, $mid ) = @_;
my	($s, %hash, $targets);

# Added 20040216 by DSL - Return unless TID defined and not set to '0'
return unless( defined($tid) && $tid ne "" && $tid ne "0" );

$targets = "";
if( defined($mid) ) 
{
	delete( $Q_TID2MIDHash{$tid}{$mid} );
	&LogMsg( "TRACETQ: Deleting T_TID=$tid -> T_MID=$mid from TID2MID hash\n" ) if( $G_Config{TRACETQ} );
	
	# Rebuild list of targets
	foreach $s (keys %{$Q_TID2MIDHash{$tid}})
	{
		$targets .= ","	if	($targets);
		$targets .= $Q_TargetHash{$s};
	}
	$T_ModTSHash{$tid} = time();
	# Remove if no more mid associated with tid
	delete( $Q_TID2MIDHash{$tid} ) if( $targets eq "" );

}
else 
{
	delete( $Q_TID2MIDHash{$tid} );
	&LogMsg( "TRACETQ: Deleting T_TID=$tid from TID2MID hash\n" ) if( $G_Config{TRACETQ} );
}

# Update transaction hash target assignment
%hash = ( );
$hash{$T_Key} = $tid;
$hash{$T_TargetsDesc{keyword}} = $targets;
$hash{T_LASTTS} = time( ) if( $targets eq "" );
&M_ModifyTRec( \%hash );

}	# end of Del TID 2 MID Rec


#-------------------------------------------------------#
#	Add Target Rec
#-------------------------------------------------------#
sub AddTargetKeyRec
{
my( $mid ) = @_;

$Q_TargetKeyHash{$Q_TargetTypeHash{$mid} . $Q_TargetHash{$mid}}{$mid} = 0;

}	# end of Add Target Key Rec


#-------------------------------------------------------#
#	Add Dup MID Key Rec
#-------------------------------------------------------#
sub AddDupMIDKeyRec
{
my( $mid ) = @_;
my( $key );

$key  = join ("", $Q_TargetTypeHash{$mid}, $Q_TargetHash{$mid},
	$Q_TransHash{$mid}, $Q_ProfileHash{$mid});

$Q_DupMIDKeyHash{$key} = $mid;
$Q_DupMIDKeyRevHash{$mid} = $key;

}	# end of Add Dup MID Key Rec


#-------------------------------------------------------#
#	Add Dup SID Key Rec
#-------------------------------------------------------#
sub AddDupSIDKeyRec
{
my( $sid ) = @_;
my( $key );

$key .= $S_TransHash{$sid};
$key .= $S_ProfileHash{$sid};
$key .= $S_UTSHash{$sid};

$S_DupSIDKeyHash{$key} = $sid;

}	# end of Add Dup SID Key Rec


#-------------------------------------------------------#
#	Update Target Key Rec
#-------------------------------------------------------#
sub UpdateTargetKeyRec
{
my( $p_type, $target, $mid, $tid ) = @_;

$Q_TargetKeyHash{$p_type . $target}{$mid} = $tid;

#&LogMsg( "Updating $target -> $mid -> $tid to Target Key Hash\n" );

}	# end of Update Target Key Rec


#-------------------------------------------------------#
#	Del Target Key Rec
#-------------------------------------------------------#
sub DelTargetKeyRec
{
my( $type, $target, $mid ) = @_;
my( @arr, $key );

$key = $type . $target;

delete( $Q_TargetKeyHash{$key}{$mid} );
#&LogMsg( "Deleting $target -> $mid from Target Key Hash\n" );

@arr = keys(%{$Q_TargetKeyHash{$key}});
delete $Q_TargetKeyHash{$key} unless( scalar(@arr) );

# &LogMsg( "Deleting $target from Target Key Hash.  No more MIDs.\n" );

}	# end of Del Target Key Rec


#-------------------------------------------------------#
#	Del Dup MID Key Rec
#-------------------------------------------------------#
sub DelDupMIDKeyRec
{
my( $mid ) = @_;
my( $key );

$key = $Q_DupMIDKeyRevHash{$mid} || "";
if	($key ne "")
{
	delete $Q_DupMIDKeyHash{$key};
	delete $Q_DupMIDKeyRevHash{$mid};
	return;
}

&LogMsg( "Error deleting DupKey record for T_MID = $mid.  MID not found.\n" );

}	# end of Del Dup MID Key Rec


#-------------------------------------------------------#
#	Del Dup SID Key Rec
#-------------------------------------------------------#
sub DelDupSIDKeyRec
{
my( $sid ) = @_;
my( $key );

foreach $key( keys %S_DupSIDKeyHash ) {
	next if( $S_DupSIDKeyHash{$key} ne $sid );
	delete $S_DupSIDKeyHash{$key};
	return;
}

&LogMsg( "Error deleting DupKey record for T_SID = $sid.  SID not found.\n" );

}	# end of Del Dup SID Key Rec


#-------------------------------------------------------#
#	Hash Msg
#-------------------------------------------------------#
sub HashMsg
{
my( $p_orig_buf, $p_hash ) = @_;
my( $buf, $k, $val );
my( %hash, $l_hash );

$buf = $$p_orig_buf;
#chomp( $buf );

# Strip leading and trailing spaces from input string
#$buf =~ s/^\s+|\s+$//g;
$buf =~ s/^\s+//g;

$l_hash = (defined ($p_hash))? $p_hash: \%hash;
%$l_hash = ();

# If the value is enclosed in quotes
if	($buf !~ s/^(['"])(.*)\1$/$2/)
{
	if	($buf =~ /^['"]/)
	{
		&LogMsg( "Unmatched quote passed to HashMsg\n");
		&LogMsg( "$$p_orig_buf\n" );
		return ((defined ($p_hash))? undef: %hash);
	}
}

# 2007-MAR-15 - Do not force all KEYWORDS to uppercase, as some APPARGS may be case sensitive
#$buf =~ s/(?:^|;)\s*([^=;\s]+)\s*=\s*(?:(['"])(.*?)\2|(.*?))\s*(?=;|$)/$$l_hash{"\U$1"}=(defined ($2))? $3: $4; ";"/eg;
$buf =~ s/(?:^|;)\s*([^=;\s]+)\s*=\s*(?:(['"])(.*?)\2|(.*?))\s*(?=;|$)/$$l_hash{$1}=(defined ($2))? $3: $4; ";"/eg;

unless( $buf =~ /^;*\s*$/ )
{
	$buf =~ s/^;+//;
	&LogMsg( "Invalid data passed to HashMsg: $$p_orig_buf\n")
}

# Force only 'T_' keywords to uppercase
foreach $k( keys %$l_hash )
{
	# Skip it unless the key starts with 't_'  or 'T_' and contains a lowercase character
	next unless( $k =~ /^t_/i && $k =~ /[a-z]+/ );
	$$l_hash{"\U$k"} = $$l_hash{$k};
	delete( $$l_hash{$k} );
}

return ((defined ($p_hash))? undef: %hash);

}	# end of Hash Msg


#-------------------------------------------------------#
#	Dump Hash
#-------------------------------------------------------#
sub DumpHash
{
my( $title, $p_hash, $prefix ) = @_;
my( $key, $val );

&LogMsg( "$title\n" ) if( $title ne "" );
foreach $key( sort keys %$p_hash )
{
	$val = $$p_hash{$key};
	&LogMsg( "${prefix}${key} = ${val}\n" );
	&DumpHash( "", $val, "\t\t" ) if( ref($val) eq HASH );
}

&LogMsg( "\n" );

}	# end of Dump Hash


#-------------------------------------------------------#
#	Syntax
#-------------------------------------------------------#
sub Syntax
{
my( $p_exit ) = @_;

print "Syntax: $0 [-c config_file] [-h] [-help]\n";

exit ($p_exit);

}	# end of Syntax


#-------------------------------------------------------#
#	Update Target IP
#-------------------------------------------------------#
sub UpdateTargetIP
{
my( $p_type, $target, $ip ) = @_;
my( $mid, $p_hash, $k );

return if( !exists($Q_TargetKeyHash{$p_type . $target}) );
$p_hash = $Q_TargetKeyHash{$p_type . $target};

foreach $mid ( keys %$p_hash ) {
	next if( $Q_MsgStatusHash{$mid} eq $ASSIGNED );
	$Q_AppArgsHash{$mid} =~ s/\bIP=[^;]+/IP=$ip/i;
}

}	# end of Update Target IP


#-------------------------------------------------------#
#	Reset Target Retry
#-------------------------------------------------------#
sub ResetTargetRetry
{
my( $p_type, $target, $trans, $profile ) = @_;
my( $mid, %hash, $p_hash );

return if( !exists($Q_TargetKeyHash{$p_type . $target}) );
$p_hash = $Q_TargetKeyHash{$p_type . $target};

foreach $mid ( keys %$p_hash ) 
{
	# Skip message queue entry if different trans/profile
	next if( ($trans ne "" && $Q_TransHash{$mid} ne $trans) || 
			 ($profile ne "" && $Q_ProfileHash{$mid} ne $profile) );
	
	if	(($Q_MsgStatusHash{$mid} eq $FAILED)||($Q_MsgStatusHash{$mid} eq $EXCLUDED))
	{
		%hash = ( );
		$hash{$Q_Key} = $mid;
		$hash{$Q_RetryCntDesc{keyword}} = 0;
		$hash{$Q_MsgStatusDesc{keyword}} = $QUEUED;
		&M_ModifyMRec( \%hash );
	}
}

}	# end of Reset Target Retry


#-------------------------------------------------------#
#	Check IP Exclude
#-------------------------------------------------------#
sub CheckIPExclude
{
my( $ip, $target ) = @_;
my( $buf, $k, $i );

# Return if IP is invalid
if( $ip !~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)/ ) {
	return( 0 );
}

# Convert IP address into integer
$k = (($1 * 256 + $2) * 256 + $3) * 256 + $4;
# Check provided IP address against a list of excluded IPs
for ($i = 0; $i < @G_ExcludeIPs; $i += 2)
{
	# If IP is in range of excluded IPs
	if	(($k >= $G_ExcludeIPs[$i])&&($k <= $G_ExcludeIPs[$i + 1]))
	{
#		# Update IP in message queue for the target
#		&UpdateTargetIP( $target, $ip );
#		# Check if we have already dispatch msgs in the queue for this target
#		foreach $k (keys %D_TargetHash)
#		{
#			if	($D_TargetHash{$k} eq $target)
#			{
#				$buf = &DeleteDRec ($k);
#				push( @G_ReturnArray, $buf );
#			}
#		}
		return( 1 );
	}
}

return( 0 );

}	# end of Check IP Exclude


#-------------------------------------------------------#
#	Check Valid Client
#-------------------------------------------------------#
sub CheckValidClient
{
my( $ip, $p_ValidClientIPRange ) = @_;
my( $v, $i );

# Return if IP is invalid
return	0	if	($ip !~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)/);

# Convert IP address into integer
$v = (($1 * 256 + $2) * 256 + $3) * 256 + $4;
# Check provided IP address against a list of IP ranges
for ($i = 0; $i < @$p_ValidClientIPRange; $i += 2)
{
	# If IP is in range
	return( 1 )
		if	(($v >= $p_ValidClientIPRange->[$i]) &&
			 ($v <= $p_ValidClientIPRange->[$i + 1]));
}

return( 0 );

}	# end of Check IP Exclude


#-------------------------------------------------------#
#	Substitute Dispatch Vars
#-------------------------------------------------------#
sub SubstituteDispatchVars
{
my( $mid, $p_dispatchmsghash, $p_varptr ) = @_;
my( $p_desc, $p_hash, $k );

foreach $k( keys %$p_varptr ) {
	next unless( $$p_dispatchmsghash{$k} );
	# Check if keyword is a standard one
	if( $Q_KeyDesc{$k} ) {
		$p_desc = $Q_KeyDesc{$k};
		$p_hash = $$p_desc{hashptr};
		$$p_hash{$mid} = $$p_dispatchmsghash{$k};
		next;
	}
	# Otherwise, check if keyword part of appargs
	$Q_AppArgsHash{$mid} =~ s/\b$k=[^;]+/$k=$$p_dispatchmsghash{$k}/;
}

}	# end of Substitute Dispatch Vars


#-------------------------------------------------------#
#	Check Dispatch Var Hash
#-------------------------------------------------------#
sub CheckDispatchVarHash
{
my( $p_type, $target, $p_dispatchmsghash ) = @_;
my( $p_hash, $mid, $trans );

# Get list of mids for target
$p_hash = $Q_TargetKeyHash{$p_type . $target};
return unless( defined($p_hash ) );

# Check each msg for target for possible substitutions
foreach $mid( keys %$p_hash ) {
	# First, check the transaction
	$trans = $Q_TransHash{$mid};
	next unless( $G_DispatchVarHash{$trans} );
	&SubstituteDispatchVars( $mid, $p_dispatchmsghash, $G_DispatchVarHash{$trans} );
}

}	# end of Check Dispatch Var Hash


#-------------------------------------------------------#
#	Update Batch ID
#-------------------------------------------------------#
sub UpdateBatchID
{
my( $p_type, $target, $bid ) = @_;
my( $p_hash, $mid );

$p_hash = $Q_TargetKeyHash{$p_type . $target};
return unless( defined($p_hash ) );
foreach $mid( keys %$p_hash ) {
	next unless( $Q_AutoBatchHash{$mid} );
	$Q_BatchIdHash{$mid} = $bid;
}

}	# end of Update Batch ID 


#-------------------------------------------------------#
#	Dispatch Update Reason
#-------------------------------------------------------#
sub DispatchUpdateReason
{
my( $did, $user, $reason ) = @_;
my( $p_hash, $mid, %hash, @arr, $ts, $ttype, $target, $trans, $profile, $msg );

# Do not update reason for the target if it's already dispatched
#return if (exists ($G_DispatchTargetHash{$ttype}{$target}));
$ttype = $D_TargetTypeHash{$did};
$target = $D_TargetHash{$did};
$trans = $D_TransHash{$did};
$profile = $D_ProfileHash{$did};

$user = "UNKNOWN" unless( defined($user) );
unless( defined($reason) )
{
	@arr = localtime( );
	$ts = sprintf( "%02d/%02d/%04d at %02d:%02d:%02d", 
			   $arr[4] + 1, $arr[3], $arr[5] + 1900, $arr[2], $arr[1], $arr[0] );
	$reason = "Dispatched by '$user' on $ts."; 
}

&LogMsg( "TRACEDQ: Updating $ttype:$target reason - $reason\n" ) if( $G_Config{TRACEDQ} == 1 );

$p_hash = $Q_TargetKeyHash{$ttype . $target};
return unless( defined($p_hash ) );
foreach $mid( keys %$p_hash ) 
{
	# Skip ones assigned to transaction
	next if( $$p_hash{$mid} );
	# Don't update REASON for transactions in ONHOLD state
	next	if	(($Q_MsgStatusHash{$mid} ne $QUEUED)&&
				 ($Q_MsgStatusHash{$mid} ne $FAILED));
	
	# Support Dispatching a specific Transaction/Profile
	if( $trans ne "" )
	{
		if( $Q_TransHash{$mid} ne $trans )
		{
			$msg = "Skipping '$Q_TransHash{$mid}'. Does not match Dispatched Transaction ($trans).";
			&LogMsg( "TRACEDQ: $msg\n" ) if( $G_Config{TRACEDQ} == 1 );
			next;
		}
		elsif( $profile ne "" && $Q_ProfileHash{$mid} ne $profile )
		{
			$msg = "Skipping '$Q_ProfileHash{$mid}'. Does not match Dispatched Transaction Profile ($profile).";
			&LogMsg( "TRACEDQ: $msg\n" ) if( $G_Config{TRACEDQ} == 1 );
			next;
		}
	}
	
	&LogMsg( "TRACEDQ: Modifying T_MID='$mid' (T_TID=$$p_hash{$mid})\n" ) if( $G_Config{TRACEDQ} == 1 );

	# Otherwise, set the reason
	%hash = ( );
	$hash{$Q_Key} = $mid;
	$hash{T_REASON} = ($Q_ReasonHash{$mid})?
		"$reason PREVIOUS REASON: $Q_ReasonHash{$mid}": $reason;
	@arr = &ModifyXRec( \%hash, $Q_Key, \%Q_KeyDesc, \%Q_MIDHash, "ModMRec", 1);
}

}	# end of Dispatch Update Reason


#-------------------------------------------------------#
#	M Dispatch MID
#-------------------------------------------------------#
sub M_DispatchMID
{
my( $p_hash ) = @_;
my( $err, $buf, $mids, $mid, @mid_arr, $ttype, $target, $trans, $profile, $key, %d_hash );
my( $equser, $eqgroup );

$mids = $$p_hash{T_MID} || $$p_hash{T_MIDS} || "";
@mid_arr = split( ",", $mids );
# Make sure we have mids to process
return( 1, "No MIDs specified" ) unless( scalar(@mid_arr) );

$equser = defined ($$p_hash{T_EQUSER}) ? $$p_hash{T_EQUSER} : "";
$eqgroup = defined ($$p_hash{T_EQGROUP}) ? $$p_hash{T_EQGROUP} : "";

%d_hash = ( );
foreach $mid( @mid_arr )
{
	$trans = $Q_TransHash{$mid};
	unless( defined($trans) )
	{
		$buf = "$FAILURE_MSG: T_MID ($mid) does not exist\n";
		push( @G_ReturnArray, $buf );
		next;
	}
	$profile = $Q_ProfileHash{$mid} || "";
	$ttype = $Q_TargetTypeHash{$mid};
	$ttype =~ s/\@+//g;
	$target = $Q_TargetHash{$mid};
	$key = "$ttype:$trans:$profile";
	if( exists($d_hash{$key}) )
	{
		$d_hash{$key}{T_TARGETS} .= ",$target";
	}
	else
	{
		$d_hash{$key}{T_TRANS}   	= $trans;
		$d_hash{$key}{T_PROFILE} 	= $profile;
		$d_hash{$key}{T_TARGETTYPE}	= "\@$ttype";
		$d_hash{$key}{T_TARGETS} 	= $target;
		$d_hash{$key}{T_EQUSER}  	= $equser;
		$d_hash{$key}{T_EQGROUP}  	= $eqgroup;
	}
}

foreach $key( keys %d_hash )
{
	($err, $buf) = &M_Dispatch( $d_hash{$key} );
}

return( 0, "" );

}	# end of M Dispatch MID


#-------------------------------------------------------#
#	M Dispatch
#-------------------------------------------------------#
sub M_Dispatch
{
my( $p_hash ) = @_;
my( %d_hash, $exclude );
my( $tgtkey, $target, $buf, $v, @l_targets, $i, $InQueue, $did );
my( $program, $appargs, $l_ip, $prikey, $pri, $l_xip, $err, $msg );
my( $bidkey, $bidval, $expire, $result, $ttype, $trans, $profile );

$tgtkey = $Q_TargetDesc{keyword};
$target = $$p_hash{$tgtkey};

$bidkey = $Q_BatchIdDesc{"keyword"};
$bidval = $$p_hash{"$bidkey"};

$prikey = $D_PriorityDesc{keyword};
$pri = $$p_hash{$prikey} || 5;

# Allow user to dispatch a particular transaction/profile
$trans = $$p_hash{T_TRANS} || "";
$profile = $$p_hash{T_PROFILE} || "";

$expire = $$p_hash{T_EXPIRE} || "";
# Convert expiration time to absolute value
if	($expire)
{
	$i = &ConvertExpirationTime (\$expire);
	return( 1, "Invalid expiration time '$$p_hash{T_EXPIRE}'" ) if( $i );
	$$p_hash{T_EXPIRE} = $expire;
}

if( !defined($target) || (length($target) == 0) )
{
	# Check if a list of targets was provided instead of one target
	$target = $$p_hash{$tgtkey . "S"};
	return( 1, "Dispatch message must have $tgtkey" ) unless( defined($target) && $target ne "" );
	@l_targets = split (",", $target);
	delete $$p_hash{$tgtkey . "S"};
}
else { @l_targets = ( $target ); }

$ttype = $$p_hash{T_TARGETTYPE} || "\@$xc_DEFTARGETTYPE";
# If IP was provided, check if we should exclude it
$l_xip = $D_ExcludeIPDesc{"keyword"};
$$p_hash{$l_xip} = CheckIPExclude( $$p_hash{IP}, $target )
	if	(defined ($$p_hash{IP}));

# Invoke Default Finished Exec to capture Node Alive status...
if( $$p_hash{RECORD} || $$p_hash{T_RECORD} ) 
{
	$l_ip = $$p_hash{"IP"} || "IP Address Not Provided";
	&StatusFileUpdate( join (",", @l_targets), $ttype,
		"Dispatch", "", 0, $l_ip, "", "", "" );
	&CreateIPFile ($target, $ttype, $l_ip)
		if	(($$p_hash{IP})&&(@l_targets == 1));
}

# Dispatch a list of targets one by one
while( $target = shift( @l_targets) ) 
{
	# Don't put on Dispatch Queue if no records in Message Queue
	if( !exists($Q_TargetKeyHash{$ttype . $target}) ) 
	{
		$buf = "$SUCCESS_MSG: Nothing queued for '$target'\n";
		push( @G_ReturnArray, $buf );
		next;
	}

	# Perform Variable Substitution on Msgs Queued for Target 
	# Using Keyword/Value Pairs in Dispatch Msg
	&CheckDispatchVarHash( $ttype, $target, $p_hash )
		unless( $G_DispatchVarCount == 0 );

	# Update the Batch ID of targets queued messages
	&UpdateBatchID( $ttype, $target, $bidval ) if( defined($bidval) );

	%d_hash = ();
	$$p_hash{$tgtkey} = $target;

	&ResetTargetRetry( $ttype, $target, $trans, $profile );
	&UpdateTargetIP( $ttype, $target, $$p_hash{IP} ) if( defined $$p_hash{IP} );

	# Don't queue target if already dispatched
	if( exists($G_DispatchTargetHash{$ttype}{$target}) ) 
	{
		# Update IP exclusion parameter
		$did = $G_DispatchTargetHash{$ttype}{$target};
		$D_ExcludeIPHash{$did} = $$p_hash{$l_xip} if( defined($$p_hash{$l_xip}) );
		push( @G_ReturnArray, "$SUCCESS_MSG: '$target' already in dispatch queue\n" );
		next;
	}

	# Assign target to dispatch queue
	$d_hash{T_TARGETTYPE} = $ttype;
	$d_hash{$tgtkey} = $target;
	$d_hash{$prikey} = $pri;
	$d_hash{T_EXPIRE} = $expire;
	$d_hash{$l_xip}  = $$p_hash{$l_xip};
	$d_hash{T_TRANS} = $trans;
	$d_hash{T_PROFILE} = $profile;
	($err, $msg) = &M_AddDRec( \%d_hash );
	$buf = $err ? "$FAILURE_MSG: $msg" : "$SUCCESS_MSG: $msg";
	push( @G_ReturnArray, $buf );
	
	next if( $err );
	$did = $d_hash{$D_Key};
	if( $did )
	{
		&DispatchUpdateReason( $did, $$p_hash{T_EQUSER}, $$p_hash{T_REASON} );
		push( @G_CheckDispatchedTarget, $did );
	}
}

return( 0, "Dispatch Message processed" );

}	# end of M Dispatch


#-------------------------------------------------------#
#	Update M Rec
#-------------------------------------------------------#
sub UpdateMRec
{
my( $mid, $p_msghash ) = @_;
my( %hash, $s, $k, $p_deschash, $p_hashptr, $oldvalue, $newvalue );

%hash =
(
	"T_MSG"	=> "ModMRec",
	$Q_Key	=> $mid
);
#foreach $k (keys %Q_KeyDesc)
foreach $k (@Q_KeyDesc_fkeys)
{
	# Do not update some internal keys
	next	if	(($k eq "T_MID")||($k eq "T_TID")||($k eq "T_MSGSTATUS"));
	next	if	(!defined ($$p_msghash{$k}));

	$p_deschash = $Q_KeyDesc{$k};
	$p_hashptr = $$p_deschash{hashptr};

	$oldvalue = (defined ($$p_hashptr{$mid}))? $$p_hashptr{$mid}: "";
	$newvalue = (defined ($$p_msghash{$k}))? $$p_msghash{$k}: "";

	if	($$p_deschash{function})
	{
		$s = &{$$p_deschash{function}} ($mid, $newvalue, $oldvalue, \%hash);
		return "$FAILURE_MSG: $s\n"	if	($s ne "");
	}

	$hash{$k} = $newvalue;
	$$p_hashptr{$mid} = $newvalue;
}

$hash{T_MSGSTATUS} = $Q_MsgStatusHash{$mid};
&StoreMsg (\%hash);

return "";
}	# end of Update M Rec


#-------------------------------------------------------#
#	M Add
#-------------------------------------------------------#
sub M_Add
{
my( $p_hash ) = @_;
my( $buf, $trans, $transval, $status, $exec_kw, $mid, $dupmid );
my( $s, $i, $target, @l_targets, $l_target_key, $l_targets_key, %l_hash_copy );
my( $key, $value, $parameters, $chkdup_string, $last_mid, @target_types );
my( $ttype, $def_ttype, $file, %targets_added, $err, $msg, $equser, $eqgroup );

# Make sure hash contains $T_DefKey (T_TRANS) and value is supported
$trans = $$p_hash{$T_DefKey};
return( 1, "$T_DefKey not specified in message" ) if( !defined( $trans ) );

# See if transaction defined already
if( defined($T_DefKeyDesc{$T_DefKey}{hashptr}{$trans}) )
{
	$transval = $T_DefKeyDesc{$T_DefKey}{hashptr}{$trans};
}
# Otherwise, set to undefined
else
{
	$transval = undef;
}

# DSL - 20110314 - Add transaction if it doesn't already exist instead of requiring the Trans to be pre-defined 
#return( 1, "Transaction type $trans not supported" ) if( !defined( $transval ) );
unless( defined( $transval ) )
{
	# Process T_CLIENTIPS keyword
	&ProcessClientIPs( \$p_hash->{T_CLIENTIPS} ) if( $p_hash->{T_CLIENTIPS} );

	# We're okay if T_EXEC populated with existing file
	unless( -f $p_hash->{T_EXEC} )
	{
		# Now see if there is a file with the name "<T_TRANS> . $ext"
		my @extensions = ( "", ".pl", ".sh", ".bat", ".exe" );
		foreach my $ext( @extensions )
		{
			my $file = $xc_EQ_PATH . "/trans/" . $trans . $ext;
			next unless( -f $file );
			$p_hash->{T_EXEC} = $file;
			last;
		}
	}
	return( 1, "Transaction type $trans not supported" ) unless( -f $p_hash->{T_EXEC} );
	($success, $msg) = &AddXRec( $p_hash, $T_DefKey, \%T_DefKeyDesc );
	unless( $success )
	{
		&LogMsg( "M_Add AddXRec Error: $msg" );
	}
	
	# Use 'Default' section if cound in cfg/trans/*.cfg
	if( defined($T_DefKeyDesc{$T_DefKey}{hashptr}{Default}) )
	{
		$transval = $T_DefKeyDesc{$T_DefKey}{hashptr}{Default};
	}
}

# Null out T_PROFILE if not profile based
$$p_hash{T_PROFILE} = "" if( defined($$p_hash{T_PROFILE}) && $T_DefIgnoreProfileHash{$trans} );

# Support T_SCHEDULE
if( defined($p_hash->{T_SCHEDULE}) && $p_hash->{T_SCHEDULE} ne "" )
{
	($err, $msg) = &ScheduleTransaction( $p_hash );
	return( $err, $msg );
}

# Kludge to use script value as t_profile for script transaction.
# Another kludge is to copy T_JOBID value into JOBID.
if( $$p_hash{T_TRANS} =~ /^EQScript|Script|EQPlan$/i ) 
{
	if( !defined($$p_hash{T_PROFILE}) || $$p_hash{T_PROFILE} eq "" ) {
		$$p_hash{T_PROFILE} = $$p_hash{SCRIPT};	
		# Remove seconds, third, and so on script names
		$$p_hash{T_PROFILE} =~ s/\|.+$//;
	}
	if	((!$$p_hash{JOBID})&&($$p_hash{T_JOBID}))
	{
		$$p_hash{JOBID} = $$p_hash{T_JOBID};
	}
	elsif	((!$$p_hash{T_JOBID})&&($$p_hash{JOBID}))
	{
		$$p_hash{T_JOBID} = $$p_hash{JOBID};
	}
}

$parameters = "";
if( $$p_hash{RECORD} || $$p_hash{T_RECORD} ) 
{
	# Build parameters string
	$parameters = "T_TRANS=" . $$p_hash{T_TRANS};
	while (($key, $value) = each %$p_hash)
	{
		next	if	($key =~ /^T_TARGET|T_TARGETS|T_TARGETTYPE|T_EQUSER|T_EQGROUP|T_RECDTS|T_TRANS|T_SCHEDULE|RECORD|T_RECORD$/i);
		$value =~ s/'/"/g;
		$value = '"' . $value . '"'		if	($value =~ /;/);
		$parameters .= ";" . $key . "=" . $value;
	}
}

# Assign default transaction values if not in message
&AssignDefTransVals( $p_hash );

# Make sure T_EXEC is a valid file here
$exec_kw = $T_ExecDesc{keyword};
return( 1, "file not found - $exec_kw=$$p_hash{$exec_kw}" ) unless( -f $$p_hash{$exec_kw} );

$l_target_key = $Q_TargetDesc{"keyword"};
$l_targets_key = $l_target_key . "S";
@target_types = ();
$def_ttype = $$p_hash{T_TARGETTYPE} || "\@$xc_DEFTARGETTYPE";
if	((defined ($$p_hash{$l_targets_key}))&&($$p_hash{$l_targets_key} ne ""))
{
	@l_targets = split (/\s*,\s*/, $$p_hash{$l_targets_key});
	delete $$p_hash{$l_targets_key};
}
elsif	((defined ($$p_hash{$l_target_key}))&&($$p_hash{$l_target_key} ne ""))
{
	@l_targets = $$p_hash{$l_target_key};
}
elsif	((defined ($$p_hash{T_TFILE}))&&($$p_hash{T_TFILE} ne ""))
{
	# Get name of the file containing a list of targets
	$file = $$p_hash{T_TFILE};
	$file =~ s#\\#/#g;
	@l_targets = ();
	# Open the list
	return( 1, "Cannot open target file '$file': $!" ) unless( open( TARGETS_FILE, $file ) );

	# Read data from the file line by line
	while (defined ($s = <TARGETS_FILE>))
	{
		# Skip empty lines and comments
		next	if	($s =~ /^#/);
		$s =~ s/\s+$//;
		$s =~ s/^\s+//;
		next	if	($s eq "");
		# Target on the line can be in format "<label>" or "<type>:<label>".
		($ttype, $target) = split (":", $s, 2);
		if	(defined ($target))
		{
			# Make sure valid target type specified
			$ttype = "\@" . $ttype unless( $ttype =~ /^\@/ );
#			return( 1, "Invalid target type '$ttype' in target file '$file'\n" ) 
#				unless( $ttype eq "\@Endpoint" || $ttype eq "\@ManagedNode" || $ttype eq "\@Computer" );

			# Save target's label and type
			push (@l_targets, $target);
			push (@target_types, $ttype);
		}
		else
		{
			# Save target's label and default type.
			push (@l_targets, $ttype);
			push (@target_types, $def_ttype);
		}
	}
	close (TARGETS_FILE);
	delete $$p_hash{T_TFILE};
}
else
{
	# Transaction must have T_TARGET, T_TARGETS or T_TFILE keys
	return( 1, "Add message must have T_TARGET, T_TARGETS or T_TFILE keywords" );
}

$$p_hash{T_SID} = "0";

$chkdup_string = $$p_hash{$T_DefKey} . $$p_hash{$Q_ProfileDesc{keyword}};

# Combine all appl arg into T_APPARGS keyword
$$p_hash{T_APPARGS} = &AssignAppArgs( $p_hash );

# Convert expiration time to absolute value
$value = $$p_hash{T_EXPIRE} || "";
if	($value)
{
	$s = &ConvertExpirationTime (\$value);
	return( 1, "Invalid expiration time '$$p_hash{T_EXPIRE}'" ) if( $s );
}

$$p_hash{T_EXPIRE} = $value;

# Assign unique value
if( defined($$p_hash{T_UNIQUEKEYS}) &&
    length($$p_hash{T_UNIQUEKEYS}) > 0 &&
    ($$p_hash{T_UNIQUEKEYS} !~ /^NONE$/i) ) 
{
		$$p_hash{T_UNIQUEVAL} = &AssignUniqueVal( $p_hash )
}
else 
{ 
	$$p_hash{T_UNIQUEVAL} = ""; 
}

$i = 0;
%l_hash_copy = %$p_hash;
foreach $target (@l_targets)
{
	# 2011SEP26 - DSL - Strip leading/trailing spaces and skip blank targets
	$target =~ s/^\s+|\s+$//g;
	next if( $target eq "" );
	
	$$p_hash{$l_target_key} = $target;
	$ttype = $target_types[$i] || $def_ttype;
	$i++;
	$$p_hash{T_TARGETTYPE} = $ttype;

	# Check for duplicate.  Returns MID if dup found
	$mid = $Q_DupMIDKeyHash{$ttype . $target . $chkdup_string};
#	$mid = &ChkDupMIDKeyRec( \%$p_hash );
	if	($mid)
#	if( $mid ne "0" )
	{
		&LogMsg( "Duplicate $Q_TransHash{$mid} msg recd for $Q_TargetHash{$mid}.  Same as $Q_Key=$mid\n" );
		# Update all keyword settings
		$status = &UpdateMRec( $mid, $p_hash );
		$status =~ s/\s+$//;
		$buf = ($status ||
			"$SUCCESS_MSG: Duplicate of $Q_Key=$mid.  Record updated") . "\n";
		push( @G_ReturnArray, $buf );
#		return ($buf)	if	($status ne "");
	}
	else
	{
		($err, $msg) = &M_AddMRec( $p_hash );
		$buf = $err ? "$FAILURE_MSG: $msg" : "$SUCCESS_MSG: $msg";
		push( @G_ReturnArray, $buf );
		$mid = $err ? 0 : $$p_hash{T_MID};
	}

	if	($mid eq "0")
	{
		$target = "";
	}
	else
	{
		$targets_added{$ttype}{$target} = 1;
	}
	$last_mid = $mid	if	($mid);
	%$p_hash = %l_hash_copy;
}

if( $$p_hash{RECORD} || $$p_hash{T_RECORD} )
{
	# Store command parameters.
	&ParmsFileUpdate( $Q_TransHash{$last_mid}, $Q_ProfileHash{$last_mid},
		$parameters, $Q_JobIdHash{$last_mid} )
			if	($parameters);
}

# For each target type
foreach $ttype (keys %targets_added)
{
	$s = join (",", keys %{$targets_added{$ttype}});
	if( $$p_hash{RECORD} || $$p_hash{T_RECORD} )
	{
		# Update status file for all targets at once. Do it for the last MID -
		# this information is identical for all targets anyway
		&StatusFileUpdate( $s, $ttype, $Q_TransHash{$last_mid},
			$Q_ProfileHash{$last_mid}, "", $Q_ReasonHash{$last_mid},
			$Q_JobIdHash{$last_mid}, $Q_EQUserHash{$last_mid}, $Q_EQGroupHash{$last_mid}, $Q_RecdTSHash{$last_mid} );
	}

	# If we need to dispatch targets
	if	($$p_hash{T_DISPATCH})
	{
		%l_hash_copy =
		(
			"T_TARGETS"		=> $s,
			"T_TARGETTYPE"	=> $ttype
		);
		# Support Dispatching a particular transaction/profile combination 
		#  1 - any/all trans/profile combos
		#  2 - all matching transactions
		#  3 - specific transaction/profile combo
		if( $$p_hash{T_DISPATCH} == 1 )
		{
			delete( $l_hash_copy{T_TRANS} );
			delete( $l_hash_copy{T_PROFILE} );
		}
		elsif( $$p_hash{T_DISPATCH} == 2 )
		{
			delete( $l_hash_copy{T_PROFILE} );
		}
		($err, $msg) = &M_Dispatch (\%l_hash_copy);
		push( @G_ReturnArray, "$FAILURE_MSG: $msg" ) if( $err );
	}
}

return( 0, "" );

}	# end of M Add


#-------------------------------------------------------#
#	Schedule Transaction
#-------------------------------------------------------#
sub ScheduleTransaction
{
my( $p_hash ) = @_;
my( $err, $msg, $eqmsg, $socket, $k, @a, $s, $fh );

# Add scheduler parms
$p_hash->{T_SCHED_OCCURS} = "On";
$p_hash->{T_SCHED_TIME} = $p_hash->{T_SCHEDULE};
delete( $p_hash->{T_SCHEDULE} );

# Create scheduler message
$eqmsg = "T_MSG=Add;";
foreach $k( keys %$p_hash )
{
	$eqmsg .= "$k=$p_hash->{$k};";
}

# Remove trailing semicolons
$eqmsg =~ s/;+$//;

# Get EQScheduler port if not already set
unless( $G_Config{EQSCHEDPORT} )
{
	$G_Config{EQSCHEDPORT} = 2330;	# set default value
	if( open( EQSCHEDCFG, "$xc_EQ_PATH/cfg/EQScheduler.cfg" ) )
	{
		@a = <EQSCHEDCFG>;
		close( EQSCHEDCFG );
		foreach $s( @a )
		{
			$s =~ s/\s+//g;
			next unless( $s =~ /PORT=(\d+)/ );
			$G_Config{EQSCHEDPORT} = $1;
			last;
		}
	}
}

# Send message to EQScheduler
unless( $G_EQSchedSocket )
{
	$G_EQSchedSocket = IO::Socket::INET->new(	PeerAddr => $xc_HOSTNAME,
												PeerPort => $G_Config{EQSCHEDPORT},
												Proto    => 'tcp',
												Type     => SOCK_STREAM );
	return( 1, "Error  opening socket with '$xc_HOSTNAME:$G_Config{EQSCHEDPORT}'" ) unless( $G_EQSchedSocket );
	
	# Add this socket for reading response
	$G_Select->add( $G_EQSchedSocket );
	
	# Set socket to flush data written to it
	$fh = select($G_EQSchedSocket); $|=1; select( $fh );
}

print $G_EQSchedSocket "$eqmsg\n";

return( 0, "Transaction Scheduled" );

}	# end of Schedule Transaction


#-------------------------------------------------------#
#	Assign Def Trans Vals
#-------------------------------------------------------#
sub AssignDefTransVals
{
my( $p_hash ) = @_;
my( $trans, $p_transdesc, $p_transhash, $kw );

$trans = $$p_hash{$T_DefKey};

# Assign default transaction values if not in message
foreach $p_transdesc ( values %T_DefKeyDesc )
{
	# Get keyword (i.e. T_TRANS, T_TIMEOUT, T_CLASS, etc.)
	$kw = $$p_transdesc{keyword};

	# if keyword not in message, add trans default
	if( !exists( $$p_hash{$kw} ) )
	{
		$p_transhash = $$p_transdesc{hashptr};
		$$p_hash{$kw} = $$p_transhash{$trans};
	}
 }

}	# end of Assign Def Trans Vals


#-------------------------------------------------------#
#	Chk Dup MID Key Rec
#-------------------------------------------------------#
sub ChkDupMIDKeyRec
{
my( $p_hash ) = @_;
my( $ProfKey, $SrcKey, $mid, $key );

# Find dup in Q based on having the same values for
# T_Key, T_TARGET, T_PROFILE, and each keyword in @duparray
$ProfKey = $Q_ProfileDesc{keyword};

$key  = join ("", $$p_hash{T_TARGETTYPE}, $$p_hash{T_TARGET},
	$$p_hash{$T_DefKey}, $$p_hash{$ProfKey});

$mid = $Q_DupMIDKeyHash{$key};
if( !defined($mid) ) { return( 0 ); }
&LogMsg( "Duplicate $Q_TransHash{$mid} msg recd for $Q_TargetHash{$mid}.  Same as $Q_Key=$mid\n" );
return( $mid );

}	# end of chk dup mid key rec


#-------------------------------------------------------#
#	Chk Dup SID Key Rec
#-------------------------------------------------------#
sub ChkDupSIDKeyRec
{
my( $p_hash ) = @_;
my( $TransKey, $ProfKey, $SchedKey, $sid );
my( $key );

# Find dup in Q based on having the same values for
# T_TRANS, T_PROFILE, and T_UTS
$TransKey = $S_TransDesc{keyword};
$ProfKey = $S_ProfileDesc{keyword};
$SchedKey = $S_UTSDesc{keyword};

$key  = $$p_hash{$TransKey};
$key .= $$p_hash{$ProfKey};
$key .= $$p_hash{$SchedKey};

return( "0" ) unless( defined($S_DupSIDKeyHash{$key}) );

$sid = $S_DupSIDKeyHash{$key};
&LogMsg( "Duplicate Schedule Record ($S_Key=$sid) found.\n" );
return( "$sid" );

}	# end of chk dup sid key rec


#-------------------------------------------------------#
#	Start Program
#-------------------------------------------------------#
sub StartProgram
{
my( $prog, $args, $trace ) = @_;
my( $cmd, $exec, $dir, $buf );

# If program doesn't end with ".pl", assume it's executable
if( $prog !~ /\.pl$/i )
{
	$exec = $prog;
	$cmd = $prog;
}

# Otherwise, invoke as PERL script using STARTCMD
else
{
	# $exec is used only for Windows
	$exec = "$xc_PERL_BIN_PATH/perl.exe";
	$cmd = "$G_Config{STARTCMD} $prog";
}

if( $trace ) { &LogMsg( "STARTCMD: $cmd \"$args\"\n" ); }

if	($OS eq $NT)
{
	$exec =~ s#/#\\#g;
	$cmd =~ s#/#\\#g;
	$dir = "$xc_EQ_PATH/trans";
	$dir =~ s#/#\\#g;
	unless (Win32::Process::Create ($ProcessObj, $exec, "$cmd \"$args\"", 0,
		NORMAL_PRIORITY_CLASS, $dir))
	{
		$buf = "Error starting new process '$exec': " .
			Win32::FormatMessage (Win32::GetLastError());
		&LogMsg( $buf);
	}
}
else
{
	# Append ampersand to run in background
	system( "$cmd \"$args\" &" );
}

}	# end of Start Program


#-------------------------------------------------------#
#	Invoke Timeout Exec
#-------------------------------------------------------#
sub InvokeTimeoutExec
{
my( $tid ) = @_;
my( $program, $appargs, $buf, $pid, $trans, $prof, $targets, $tmout, $l_kill );

# First, make sure file exists
$program = $T_TimeoutExecHash{$tid};
unless( -e $program ) {
	&LogMsg( "$program does not exist.  Cannot invoke timeout executable.\n" );
	return;
}

$pid = $T_PIDHash{$tid};
$trans = $T_TransHash{$tid};
$prof = $T_ProfileHash{$tid};
$targets = $T_TargetsHash{$tid};
$tmout = $T_TimeoutHash{$tid};
$l_kill = $T_KillHash{$tid};

$appargs = "$T_Key=$tid;T_PID=$pid;T_TRANS=$trans;T_PROFILE=$prof;T_TARGETS=$targets;T_TIMEOUT=$tmout;T_KILL=$l_kill";

&StartProgram( $program, $appargs, $G_Config{TRACESTARTCMD} );

}	# end of Invoke Timeout Exec


#-------------------------------------------------------#
#	Assign App Args
#-------------------------------------------------------#
sub AssignAppArgs
{
my( $p_hash ) = @_;
my( $buf, $kw, $v );

$buf = "";
foreach $kw ( keys( %$p_hash ) )
{
	next if( $kw eq "" );
	# If ! rsrvd Q kw & ! rsrvd T kw & ! rsrvd S kw
	if( !exists($Q_KeyDesc{$kw}) &&
	    !exists($T_DefKeyDesc{$kw}) )
	{
		$v = $$p_hash{$kw};
		$v =~ s/\"/\'/g;
		$buf .= "$kw=$v;";
	}
}

# append any T_APPARGS passed in
if( exists( $$p_hash{T_APPARGS} ) && length($$p_hash{T_APPARGS}) ) {
	$buf .= "$$p_hash{T_APPARGS};";
}

# remove last semi-colon
chop( $buf );

return $buf;

}	# end of Assign App Args


#-------------------------------------------------------#
#	Assign Unique Val
#-------------------------------------------------------#
sub AssignUniqueVal
{
my( $p_hash ) = @_;
my( $UniqueKeys, @UniqueArr, $i );
my( $UniqueVal ) = "";

$UniqueKeys = $$p_hash{T_UNIQUEKEYS};

# return NULL string if no unique keys for this trans type
return( "" ) if( $UniqueKeys eq "" );

# create array for easier processing
@UniqueArr = split( /,/, "$UniqueKeys" );
for( $i=0; $i <= $#UniqueArr; $i++ ) {
	next if( !exists($$p_hash{$UniqueArr[$i]}) );
	$UniqueVal .= $$p_hash{$UniqueArr[$i]};
}

return( $UniqueVal );

}	# end of Assign Unique Val


#-------------------------------------------------------#
#       M Reload Cfg
#-------------------------------------------------------#
sub M_ReloadCfg
{
my( $s, $err, $msg );

# Re-read configuration file
&ReadCfgFile( \$G_Config{"CONFIGFILE"}, \%G_Config, \%G_ConfigMod );

&BuildValidClientIPList ();

&BuildExcludeIPList ();

$s = &ParseClassFile( \$G_Config{"CLASSFILE"}, 0 );
&DisplayCRecs( );

# Reset Class Contention hash, since we may have new class values
%G_ClassContention = ( );

($err, $msg ) = &ParseTransFiles( \$G_Config{"TRANSCFGDIR"} ) if( $s eq "" );
&DisplayDefTransRecs( );

&ParseEQMsg( "$xc_EQ_PATH/cfg/eqmsg.cfg" );

push( @G_ReturnArray, ($s eq "")?
	"$SUCCESS_MSG: Configuration data reloaded\n": "$FAILURE_MSG: $s");

}	# end of M Reload Cfg


#-------------------------------------------------------#
#	M Reset M Q Info
#-------------------------------------------------------#
sub M_ResetMQInfo
{

$G_CurMsgsPerSec = $G_MaxMsgsPerSec = 0;
push( @G_ReturnArray, "$SUCCESS_MSG: Reset Queue Counters\n" );

}	# end of M Reset MQ Info


#-------------------------------------------------------#
#	M Dump Special Arrays
#-------------------------------------------------------#
sub M_DumpSpecialArrays
{

&DumpSpecialArrays( );
push( @G_ReturnArray, "$SUCCESS_MSG: Special Arrays Logged\n" );

}	# end of M Dump Special Arrays


#-------------------------------------------------------#
#	M Reset T Q Info
#-------------------------------------------------------#
sub M_ResetTQInfo
{

$G_CurTransPerSec = $G_MaxTransPerSec = 0;
$G_SuccessTrans = $G_FailureTrans = 0;
push( @G_ReturnArray, "$SUCCESS_MSG: Reset Queue Counters\n" );

}	# end of M Reset T Q Info


#-------------------------------------------------------#
#	M Stop
#-------------------------------------------------------#
sub M_Stop
{

$G_Continue = 0;
push( @G_ReturnArray, "$SUCCESS_MSG: Stopping Process\n" );

}	# end of M Stop


#-------------------------------------------------------#
#	M Cmd
#-------------------------------------------------------#
sub M_Cmd
{
my( $p_hash ) = @_;
my	(@result, $line);

# Make sure command part of hash
if( !defined( $$p_hash{T_CMD} ) ) {
	push( @G_ReturnArray, "$FAILURE_MSG: Message must include T_CMD\n" );
}

@result = `$$p_hash{T_CMD} 2>&1`;
push( @G_ReturnArray, "RESULT: $?\n" );
foreach $line( @result ) {
	chomp($line);
	push( @G_ReturnArray, "$line\n" );
}

}	# end of M Stop


#-------------------------------------------------------#
#	Reset D Q TID
#-------------------------------------------------------#
sub ResetDQTID
{
my( $tid ) = @_;
my( $did, $p_hash, %hash );

$p_hash = $Q_TID2DIDHash{$tid};
foreach $did( keys( %$p_hash ) ) 
{
	%hash = ( );
	$hash{$D_Key} = $did;
	$hash{$D_TIDDesc{keyword}} = 0;
	&M_ModifyDRec( \%hash );
}

}	# end of Reset D Q TID


#-------------------------------------------------------#
#  Reset D Q Rec
#-------------------------------------------------------#
sub ResetDQRec
{
my( $target, $targettype, $mid, $tid ) = @_;
my( %hash, $now, $att, $retries, $did );

# Get did from G_DispatchTargetHash
$did = $G_DispatchTargetHash{$targettype}{$target} ||
	return( 1, "$targettype:$target not in DispatchTargetHash\n" );

# Make sure dispatch record assigned to transaction supplied
return( 1, "$target not assigned to TID ($tid)" ) unless( $D_TIDHash{$did} = $tid );

# Update Q_TID2DIDHash
&DelTID2DIDRec( $tid, $did );

# update dispatch hash tid assignment
%hash = ( );
$hash{$D_Key} = $did;
$hash{$D_TIDDesc{keyword}} = 0;
&M_ModifyDRec( \%hash );

return( 0, "$SUCCESS_MSG: Elements reset for $did\n" );

}	# end of Reset DQ Rec


#-------------------------------------------------------#
#	Reset M Q TID
#-------------------------------------------------------#
sub ResetMQTID
{
my( $tid, $result, $status, $reason ) = @_;
my( $mid, $buf, $p_hash );

return if( !exists($Q_TID2MIDHash{$tid}) );

$p_hash = $Q_TID2MIDHash{$tid};
foreach $mid ( keys( %$p_hash ) ) 
{
	if( $Q_MsgStatusHash{$mid} eq $ASSIGNED ) 
	{
		&ResetMQRec( $mid, $result, $status, $reason ); 
	}
}

}	# end of Reset M Q TID


#-------------------------------------------------------#
#  Reset M Q Rec
#-------------------------------------------------------#
sub ResetMQRec
{
my( $mid, $result, $status, $reason ) = @_;
my( %hash, $now, $att, $retries, $tid, $did );
my( $target, $targettype, @arr );

$tid = $Q_TIDHash{$mid} || "0";
&DelTID2MIDRec( $tid, $mid ) unless( $tid eq "0" );

# Added 10/14/02 by DSL - Keep TargetKeyHash updated
$target = $Q_TargetHash{$mid};
$targettype = $Q_TargetTypeHash{$mid};
&UpdateTargetKeyRec( $targettype, $target, $mid, 0 );

# 11/03/05 - Keep TID2DID and DRec Updated
($err, $msg) = &ResetDQRec( $target, $targettype, $mid, $tid );

# set default values for result, status, and reason
#if( !defined($result) ) {$result = $G_ResultHash{FAILURE}; }
#if( !defined($status) ) {$status = $QUEUED; }
#if( !defined($reason) ) {$reason = ""; }

$now = time;
$att = $Q_AttemptsHash{$mid} + 1;
$retries = $Q_RetryCntHash{$mid} + 1;

# Keep only one PREVIOUS REASON
$reason = $1 if( $reason =~ /^(.+?PREVIOUS REASON:.+?)PREVIOUS REASON:/i );

%hash = ( );
$hash{$Q_Key} = $mid;
$hash{T_TID} = "0" unless( $Q_TIDHash{$mid} eq "0" );
$hash{T_MSGSTATUS} = $status unless( $Q_MsgStatusHash{$mid} eq $status );
$hash{T_RESULT} = $result unless( $Q_ResultHash{$mid} eq $result );
$hash{T_REASON} = $reason;
$hash{T_FAILTS} = $now;
$hash{T_ATTEMPTS} = $att;
$hash{T_RETRYCNT} = $retries;

@arr = &M_ModifyMRec( \%hash );

return( @arr );

}	# end of Reset MQ Rec


#-------------------------------------------------------#
#	M Clear Q
#-------------------------------------------------------#
sub M_ClearQ
{
my( $p_hash ) = @_;

# Set flag to store queue
$G_StoreQ = 1;
&QuickClearQ( );
return( 0, "All queues cleared" );

}	# end of M Clear Q


#-------------------------------------------------------#
#	Quick Clear Q
#-------------------------------------------------------#
sub QuickClearQ
{
my( $buf );

# First, clear all special hashes
%Q_DupMIDKeyHash = ( );
%Q_DupMIDKeyRevHash = ( );
%Q_TargetKeyHash = ( );
%Q_TID2MIDHash = ( );
%Q_TID2DIDHash = ( );
%G_DispatchPriorityHash = ( );
%G_DispatchTargetHash = ( );
@G_CheckDispatchedTarget = ( );
%G_ClassContention = ( );
@G_CheckQueue = ( );

# Reset all hashes to null:
&ClearHashPtr( \%Q_KeyDesc );
$buf = "$SUCCESS_MSG: $G_MsgCnt records removed from message queue\n";
push( @G_ReturnArray, $buf );

&ClearHashPtr( \%T_KeyDesc );
$buf = "$SUCCESS_MSG: $G_TransCnt records removed from running transaction queue\n";
push( @G_ReturnArray, $buf );

&ClearHashPtr( \%D_KeyDesc );
$buf = "$SUCCESS_MSG: $G_DispCnt records removed from dispatch queue\n";
push( @G_ReturnArray, $buf );

# Now, zero counters
$G_MsgCnt = 0;
$G_TransCnt = 0;
$G_DispCnt = 0;

}	# end of Quick Clear Q


#-------------------------------------------------------#
#	Clear Hash Ptr
#-------------------------------------------------------#
sub ClearHashPtr
{
my( $p_masterdesc ) = @_;
my( $k, $p_deschash, $p_hashptr );

foreach $k( keys %$p_masterdesc )
{
	$p_deschash = $$p_masterdesc{$k};
	$p_hashptr = $$p_deschash{hashptr};
	%$p_hashptr = ( );

}

}	# end of Clear Hash Ptr


#-------------------------------------------------------#
# 	M Clear D Q
#-------------------------------------------------------#
sub M_ClearDQ
{
my( $p_hash ) = @_;
my( $buf, $counter );

# Clear dispatch queue
$counter = &ClearXQ( \%D_DIDHash, \&DeleteDRec );
return( 0, "$counter records removed from dispatch queue" );

}	# end of M Clear D Q


#-------------------------------------------------------#
#	M Clear M Q
#-------------------------------------------------------#
sub M_ClearMQ
{
my( $p_hash ) = @_;
my( $buf, $counter );

# Clear schedule queue
&M_ClearSQ( $p_hash );

# Clear message queue
$counter = &ClearXQ( \%Q_MIDHash, \&DeleteMRec );
return( 0, "$counter records removed from message queue" );

}	# end of M Clear MQ


#-------------------------------------------------------#
#	M Clear S Q
#-------------------------------------------------------#
sub M_ClearSQ
{
my( $p_hash ) = @_;
my( $buf, $counter );

# Clear schedule queue
$counter = &ClearXQ( \%S_SIDHash, \&DeleteSRec );
return unless( $counter > 0 );

$buf = "$SUCCESS_MSG: $counter records removed from schedule queue\n";
push( @G_ReturnArray, $buf );

}	# end of M Clear SQ


#-------------------------------------------------------#
#	M Clear T Q
#-------------------------------------------------------#
sub M_ClearTQ
{
my( $p_hash ) = @_;
my( $buf, $counter );

# Clear transaction queue
$counter = &ClearXQ( \%T_TIDHash, \&DeleteTRec );
return( 0, "$counter records removed from transaction queue" );

}	# end of M Clear TQ


#-------------------------------------------------------#
# 	Clear X Q
#-------------------------------------------------------#
sub ClearXQ
{
my( $p_mhash, $p_delsub ) = @_;
my( $key, $status, $counter );

$counter = 0;
foreach $key ( keys( %$p_mhash ) )
{
#ModifyXRec - Actually, create t_msg=clearq;t_queue=all,msg,trans, or disp
	$counter += 1;
	$status = &$p_delsub( $key );
}

return( $counter );

}	# end of Clear X Q


#-------------------------------------------------------#
#	M Delete MRec
#-------------------------------------------------------#
sub M_DeleteMRec
{
my( $p_hash ) = @_;
my( $mid, $user, $err, $msg, $i, $s, @arr );

$mid = $$p_hash{$Q_Key} || "";
$user = defined($$p_hash{"T_EQUSER"}) ? $$p_hash{"T_EQUSER"} : "Unknown";
#return( 1, "Message does not contain $Q_Key keyword" ) unless( defined($mid) );

if( $mid ne "" )
{
	@arr = split (/\s*,\s*/, $mid);
	foreach $mid( @arr )
	{
		&DelMRec( $mid, $user );
	}
}
else
{
	# Find all records that match all key/value pairs using M Filter M Recs routine
	$p_hash->{T_VIEW} = "detail";
	($err, $msg) = &M_FilterMRecs( $p_hash );
	
	# See if no records match criteria
	$i = scalar( @G_ReturnArray ) - 1;
	$msg = $G_ReturnArray[$1];
	return( 0, "" ) if( $msg =~ /No records match/i );
	
	# Must have match(es) so make a copy and start with a clean slate
	push( @arr, @G_ReturnArray );
	@G_ReturnArray = ( );
	foreach $msg( @arr )
	{
		next unless( $msg =~ /T_MID=(\d+)/i );
		$mid = $1;
		&DelMRec( $mid, $user );
	}
}

return( 0, "" );

}	# end of M Delete MRec


#-------------------------------------------------------#
#	Del M Rec
#-------------------------------------------------------#
sub DelMRec
{
my( $mid, $user ) = @_;
my( $err, $msg, @arr, %hash, $reason );

$reason = "Deleted by '$user' PREVIOUS REASON: ";
$reason .= $Q_ReasonHash{$mid};
$reason = $1 if( $reason =~ /^(.+?PREVIOUS REASON:.+?)PREVIOUS REASON:/i );

%hash = ( );
$hash{T_MID} = $mid;
$hash{T_TARGET} = $Q_TargetHash{$mid};
$hash{T_RESULT} = "D";
$hash{T_REASON} = $reason;
($err, $msg) = &M_Status( \%hash );

}	# end of Del M Rec


#-------------------------------------------------------#
#	M Delete S Rec
#-------------------------------------------------------#
sub M_DeleteSRec
{
my( $p_hash ) = @_;
my( $sid, $buf, @l_records );

$sid = $$p_hash{$S_Key};
return( 1, "Message does not contain $S_Key keyword" ) unless( defined($sid) );

@l_records = split (/\s*,\s*/, $sid);
foreach $sid (@l_records)
{
	$buf = &DeleteSRec( $sid );
	push( @G_ReturnArray, $buf );
}

return( 0, "" );

}	# end of M Delete SRec


#-------------------------------------------------------#
#	M Delete TRec
#-------------------------------------------------------#
sub M_DeleteTRec
{
my( $p_hash ) = @_;
my( $tid, $buf, @l_records );

$tid = $$p_hash{$T_Key};
return( 1, "Message does not contain $T_Key keyword" ) unless( defined($tid) );

@l_records = split (/\s*,\s*/, $tid);
foreach $tid (@l_records)
{
	$buf = &DeleteTRec( $tid );
	push( @G_ReturnArray, $buf );
}

return( 0, "" );

}	# end of M Delete TRec


#-------------------------------------------------------#
# 	M Delete DRec
#-------------------------------------------------------#
sub M_DeleteDRec
{
my( $p_hash ) = @_;
my( $did, $buf, @l_records );

$did = $$p_hash{$D_Key};
return( 1, "Message does not contain $D_Key keyword" ) unless( defined($did) );

@l_records = split (/\s*,\s*/, $did);
foreach $did (@l_records)
{
	$buf = &DeleteDRec( $did );
	push( @G_ReturnArray, $buf );
}

return( 0, "" );

}	# end of M Delete DRec


#-------------------------------------------------------#
#	Delete M Rec
#-------------------------------------------------------#
sub DeleteMRec
{
my( $mid ) = @_;
my( $buf, $err, $msg, $target, $targettype, $tid, $did, $count, %hash );

# 20051022 - Bug found where Trans Queue target assignment not updated when a user deletes
# a MID while transaction is running.  Normally, this routine is called after a T_MSG=Status
# message is received, so the TID2MID, TID2DID, TargetKey, etc are already taken care of.
# But when a user deletes the MID from the GUI, TID will be non-zero.  If the last target is
# removed from the running TID, we need to call DeleteTRec to clean house. 

$tid = $Q_TIDHash{$mid} || "0";
$target = $Q_TargetHash{$mid};
$targettype = $Q_TargetTypeHash{$mid};
$did = $G_DispatchTargetHash{$targettype}{$target} || "0";

&LogMsg( "TRACEMQ: Removing $target ($Q_Key=$mid) from Msg Queue\n" ) if( $G_Config{TRACEMQ} );

# Reset everything associated with the MID
&UpdateTargetKeyRec( $targettype, $target, $mid, 0 );
unless( $tid eq "0" )
{
	&DelTID2MIDRec( $tid, $mid );
	unless( $did eq "0" )
	{
		&DelTID2DIDRec( $tid, $did );
		&M_SetDID( { T_DID => "$did", T_TID => "0" } );
	}
}

# Now delete special hash elements associated with this mid
&DelTargetKeyRec( $targettype, $target, $mid);
&DelDupMIDKeyRec( $mid );

# Finally, remove the record entirely
$buf = &DeleteXRec( $mid, $Q_Key, \%Q_KeyDesc, \%Q_MIDHash, "DelMRec", 1 );
$G_MsgCnt -= 1 if( $buf =~ /^$SUCCESS_MSG/ );
return( $buf );

}	# end of Delete M Rec


#-------------------------------------------------------#
#	Delete S Rec
#-------------------------------------------------------#
sub DeleteSRec
{
my( $sid ) = @_;
my( $buf );

$buf = &DeleteXRec( $sid, $S_Key, \%S_KeyDesc, \%S_SIDHash, "DelSRec", 1 );
&DelDupSIDKeyRec( $sid) if( $buf =~ /^$SUCCESS_MSG/ );
return( $buf );

}	# end of Delete S Rec


#-------------------------------------------------------#
#	Delete T Rec
#-------------------------------------------------------#
sub DeleteTRec
{
my( $tid ) = @_;
my( $err, $buf, $class );

$class = $T_ClassHash{$tid};
&LogMsg( "TRACETQ: Removing $T_TransHash{$tid} ($T_Key=$tid) from Trans Queue\n" ) if( $G_Config{TRACETQ} );

# Delete the target file created for this transaction
($err, $buf ) = &DelTargetFile( $tid );
&LogMsg( "DelTargetFile Error: $buf" ) if( $err );

$buf = &DeleteXRec( $tid, $T_Key, \%T_KeyDesc, \%T_TIDHash, "DelTRec", 1 );
&DelTID2MIDRec( $tid );
&DelTID2DIDRec( $tid );
delete( $G_ClassContention{$class} );	# Remove from class contention hash
push( @G_CheckQueue, $class );			# Push class on array to check later

$G_TransCnt -= 1 if( $buf =~ /^$SUCCESS_MSG/ );

return( $buf );

}	# end of Delete T Rec


#-------------------------------------------------------#
#	Delete D Rec
#-------------------------------------------------------#
sub DeleteDRec
{
my( $did) = @_;
my( $buf );

if( $G_Config{TRACEDQ} == 1 ) 
{
	$buf = "TRACEDQ: Removing $D_TargetHash{$did} ($D_Key=$did) from Dispatch Queue";
	&LogMsg( $buf );
#	&Carp::cluck( $buf );
}

# Remove records from Dispatch Priority Hash and Dispatch Target Hash
&DeleteDispatchPriRec( $did );
&DeleteDispatchTargetRec( $did );

$buf = &DeleteXRec( $did, $D_Key, \%D_KeyDesc, \%D_DIDHash, "DelDRec", 1 );
$G_DispCnt -= 1 if( $buf =~ /^$SUCCESS_MSG/ );

return( $buf );

}	# end of Delete D Rec


#-------------------------------------------------------#
#	Delete X Rec
#-------------------------------------------------------#
sub DeleteXRec
{
my( $key, $keyname, $p_keydesc, $p_keyhash, $msgtype, $store ) = @_;
my( $p_tempdesc, $p_temphash, $p_hash, $k, %hash, $msg );

# First, check for existence of key in master hash
if( !exists( $$p_keyhash{$key} ) )
{
	$msg = "Delete error: $keyname=$key not found.";
	&LogMsg( $msg );
	#confess( $msg );
	return( "$FAILURE_MSG: $msg" );
}

#delete key from each hash list
foreach $p_tempdesc ( values( %$p_keydesc ) )
{
	# set pointer to correct hash for this keyword
	$p_temphash = $$p_tempdesc{hashptr};
	delete( $$p_temphash{$key} );

}	# end of for loop

$hash{$M_Key} = "$msgtype";
$hash{$keyname} = "$key";
&StoreMsg( \%hash ) if( $store );

return( "$SUCCESS_MSG: Deleted $keyname=$key\n" );

}	# end of Delete X Rec


#-------------------------------------------------------#
#	Delete X Recs
#-------------------------------------------------------#
sub DeleteXRecs
{
my( $p_KeyDesc ) = @_;
my( $k, $p_deschash, $p_hashptr );

foreach $k ( keys %$p_KeyDesc ) {
	$p_deschash = $$p_KeyDesc{$k};
	$p_hashptr = $$p_deschash{hashptr};
	%$p_hashptr = ( );
}

}	# end of Delete X Recs


#-------------------------------------------------------#
#	Del Target File
#-------------------------------------------------------#
sub DelTargetFile
{
my( $tid ) = @_;
my( $file );

$file = $T_TargetFileHash{$tid};
return( 0, "$file does not exist" ) unless( -f $file );
unlink( $file );
return( 0, "$file removed successfully" );

}	# end of Del Target File


#-------------------------------------------------------#
#	M Store Q
#-------------------------------------------------------#
sub M_StoreQ
{
&StoreQ();
return( 0, "All Queues Stored" );

}	# end of M Store Q


#-------------------------------------------------------#
#	M Store D Q
#-------------------------------------------------------#
sub M_StoreDQ
{

&StoreDQ();
return( 0, "Dispatch queue stored" );

}	# end of M Store D Q


#-------------------------------------------------------#
#	M Store M Q
#-------------------------------------------------------#
sub M_StoreMQ
{

&StoreMQ();
return( 0, "Message queue stored" );

}	# end of M Store M Q


#-------------------------------------------------------#
#	M Store S Q
#-------------------------------------------------------#
sub M_StoreSQ
{

&StoreSQ();
return( 0, "Schedule queue stored" );

}	# end of M Store S Q


#-------------------------------------------------------#
#	M Store T Q
#-------------------------------------------------------#
sub M_StoreTQ
{

&StoreTQ();
return( 0, "Transaction queue stored" );

}	# end of M Store T Q


#-------------------------------------------------------#
#	M Help
#-------------------------------------------------------#
sub M_Help
{
my( $msgkw, $p_deschash, $help, $example );

#while( ($msgkw, $p_deschash) = each( %M_MsgDesc ) )
push( @G_ReturnArray, "*** enterprise-Q EQServer Process ***" );
foreach $msgkw( sort keys ( %M_MsgDesc ) )
{
	$p_deschash = $M_MsgDesc{$msgkw};
	next if( length($$p_deschash{help}) == 0 );
	$help  = "$msgkw:  $$p_deschash{help}";
	$help .= "  Required Keywords: $$p_deschash{reqkeys}." if( $$p_deschash{reqkeys} ne "" );
	$example = "\tExample:  $$p_deschash{example}"; 
	push( @G_ReturnArray, "$help\n" );
	push( @G_ReturnArray, "$example\n" );
}

return( 0, "Help Displayed" );

}	# end of M Help


#-------------------------------------------------------#
# 	M Info
#-------------------------------------------------------#
sub M_Info
{
my( $p_hash ) = @_;

return( 0, "Information Message Received" );

}	# end of M Info


#-------------------------------------------------------#
#	M SockInfo
#-------------------------------------------------------#
sub M_SockInfo
{
my( $buf );

$buf = sprintf( "CurSocks=%d  MaxSocks=%d\n", $G_SockCnt, $G_SockCntMax );
return( 0, $buf );

}	# end of M SockInfo


#-------------------------------------------------------#
#	M QInfo D
#-------------------------------------------------------#
sub M_QInfoD
{
my( $buf );

$buf = sprintf( "InQue: %d  MaxInQ: %d  Stored: %s\n", $G_DispCnt, $G_DispCntMax, &CTime( $G_LastDQStore ) );
return( 0, $buf );

}	# end of M QInfoD


#-------------------------------------------------------#
#	M QInfo M
#-------------------------------------------------------#
sub M_QInfoM
{
my( $buf );

$buf = sprintf( "InQue: %d  Max/Sec: %d  MaxInQ: %d  Stored: %s\n", $G_MsgCnt, $G_MaxMsgsPerSec, $G_MsgCntMax, &CTime( $G_LastMQStore ) );
return( 0, $buf );

}	# end of M QInfoM


#-------------------------------------------------------#
#	M QInfo T
#-------------------------------------------------------#
sub M_QInfoT
{
my( $buf );

$buf = sprintf( "InQue: %d  Success: %d  Failure: %d  MaxInQ: %d  Stored: %s\n", 
	$G_TransCnt, $G_SuccessTrans, $G_FailureTrans, $G_TransCntMax, &CTime( $G_LastTQStore ) );
return( 0, $buf );

}	# end of M QInfoT


#-------------------------------------------------------#
# 	C Time - convert uts to printable date/time
#-------------------------------------------------------#
sub CTime
{
my( $uts ) = @_;
my( $sec, $min, $hr, $day, $mon, $yr );
my( $buf );

($sec,$min,$hr,$day,$mon,$yr) = localtime( $uts );

$buf = sprintf( "%02d-%s-%04d %02d:%02d:%02d",
	$day, $G_mons[$mon], 1900+$yr, $hr, $min, $sec );

return( $buf );

}	# end of C Time


#-------------------------------------------------------#
# 	M Set Parms
#-------------------------------------------------------#
sub M_SetParms
{
my( $p_hash ) = @_;
my( $buf, $newkey, $cfgkey );

foreach $newkey (sort keys( %$p_hash ) )
{
	next if( !exists($G_Config{$newkey}) );

	$G_Config{$newkey} = $$p_hash{$newkey};
	$buf = "\$G_Config{$newkey} = $$p_hash{$newkey}\n";
	push( @G_ReturnArray, $buf );
}

return( 0, "" );

}	# end of M Set Parms


#-------------------------------------------------------#
# 	M Show Parms
#-------------------------------------------------------#
sub M_ShowParms
{
my( $p_hash ) = @_;
my( $buf, $key );

foreach $key ( sort keys( %G_Config ) ) {
	$buf = "$key = $G_Config{$key}\n";
	push( @G_ReturnArray, $buf );
}

return( 0, "" );

}	# end of M Show Parms


#-------------------------------------------------------#
#	M Show Trans
#-------------------------------------------------------#
sub M_ShowTrans
{
my( $p_hash ) = @_;
my( $mkey, $buf, $p_tempdesc, $p_temphash, $reccnt, $p_transhash );

$reccnt = 0;

# Now, for each element in master hash,
$p_transhash = $T_DefKeyDesc{$T_DefKey}{hashptr};

foreach $mkey ( sort keys( %$p_transhash ) )
{
	$reccnt += 1;
	# first, clear buf and append
	$buf = "";
	$buf .= "$T_DefKey=$mkey;";

	# find match for each of the other hashes
	foreach $p_tempdesc ( sort values( %T_DefKeyDesc ) )
	{
		# skip master key description
		next if( $$p_tempdesc{keyword} eq "$T_DefKey" );

		# set pointer to hash for keyword
		$p_temphash = $$p_tempdesc{hashptr};

		# put keyword and value in output buffer
		$buf .= "$$p_tempdesc{keyword}=$$p_temphash{$mkey};";
	}
	# lop off last ';'
	$buf =~ s/\;+$//;
	push( @G_ReturnArray, $buf );
}

if( $reccnt == 0 ){ $buf = "No records in hash\n"; }
else { $buf = "Total Records Displayed = $reccnt\n"; }

return( 0, $buf );

}	# end of Display Def Trans Recs


#-------------------------------------------------------#
#	M Show Classes
#-------------------------------------------------------#
sub M_ShowClasses
{
my( $p_hash ) = @_;
my( $mkey, $buf, $p_tempdesc, $p_temphash, $reccnt );

$reccnt = 0;
# Now, for each element in master hash,
foreach $mkey ( sort keys( %C_ClassHash ) )
{
	$reccnt += 1;
	# first, clear buf and append
	$buf = "";
	$buf .= "$C_Key=$mkey;";

	# find match for each of the other hashes
	foreach $p_tempdesc ( sort values( %C_KeyDesc ) )
	{
		# skip master key description
		next if( $$p_tempdesc{keyword} eq "$C_Key" );

		# set pointer to hash for keyword
		$p_temphash = $$p_tempdesc{hashptr};

		# put keyword and value in output buffer
		$buf .= "$$p_tempdesc{keyword}=$$p_temphash{$mkey};";
	}
	# lop off last ';'
	$buf =~ s/\;+$//;
	push( @G_ReturnArray, $buf );
}

if( $reccnt == 0 ){ $buf = "No records in hash\n"; }
else { $buf = "Total Records Displayed = $reccnt\n"; }

return( 0, $buf );

}	# end of M Show Classes


#-------------------------------------------------------#
# 	M Show Clients
#-------------------------------------------------------#
sub M_ShowClients
{
my( $p_hash ) = @_;
my( $ip, $i );

foreach $ip ( sort keys( %G_ValidClientIP ) ) 
{
	push( @G_ReturnArray, "'$ip'\n" );
}

# Check provided IP address against a list of IP ranges
for ($i = 0; $i < @G_ValidClientIPRange; $i += 2)
{
	push (@G_ReturnArray,
		"'" . &ConvertIntToIP ($G_ValidClientIPRange[$i]) . "-" .
		&ConvertIntToIP ($G_ValidClientIPRange[$i + 1]) . "'\n");
}

return( 0, "" );

}	# end of M Show Clients


#-------------------------------------------------------#
#	Convert Int To IP
#-------------------------------------------------------#
sub	ConvertIntToIP
{
my	($l_int) = @_;
my	($n1, $n2, $n3, $n4);

$n1 = (int ($l_int / 16777216)) % 256;
$n2 = (int ($l_int / 65536)) % 256;
$n3 = (int ($l_int / 256)) % 256;
$n4 = $l_int % 256;

return "$n1.$n2.$n3.$n4";
	
}	# end of Convert Int To IP


#-------------------------------------------------------#
# 	Validate TID
#-------------------------------------------------------#
sub ValidateTID
{
my( $p_hash, $state, $p_tid ) = @_;
my( $tid );

$tid = $$p_hash{$T_Key};
return( 1, "Message does not contain $T_Key keyword" ) unless( defined($tid) );
return( 1, "$T_Key=$tid does not exist" ) unless( exists($T_TIDHash{$tid}) );
return( 1, "Invalid msg for $T_Key=$tid; Not in correct state" ) unless( $state =~ /$T_TranStatusHash{$tid}/ );

$$p_tid = $tid;

return( 0, "TID valid" );

}	# end of Validate TID


#-------------------------------------------------------#
# 	Validate Result
#-------------------------------------------------------#
sub ValidateResult
{
my( $p_hash, $tid ) = @_;
my( $result, $resultkw, $v );

# extract result keyword
$resultkw = $Q_ResultDesc{keyword};
$result = $$p_hash{$resultkw};

return( $result );

#if( !defined($result) ) {
#	$$p_buf = "$FAILURE_MSG: Message missing $resultkw: $T_Key=$tid\n";
#	return( -1 );
#}

#foreach $v ( values %G_ResultHash ) { if( $result == $v ) { return( $result ); } }

#$$p_buf = "$FAILURE_MSG: Unrecognized result code: $resultkw=$result\n";
#return( -1 );

}	# end of Validate Result


#-------------------------------------------------------#
#	 Validate Target
#-------------------------------------------------------#
sub ValidateTarget
{
my( $p_thash, $tid, $p_mid ) = @_;
my( $target, $tgtkw, $mid, $p_hash );

# extract target keyword
$tgtkw = $Q_TargetDesc{keyword};
$target = $$p_thash{$tgtkw};
return( 1, "Message missing $tgtkw: $T_Key=$tid" ) unless( defined($target) );

$p_hash = $Q_TID2MIDHash{$tid} if( exists($Q_TID2MIDHash{$tid}) );
foreach $mid ( keys %$p_hash ) 
{
	if( $$p_hash{$mid} eq $target ) 
	{
		$$p_mid = $mid; 
		return( 0, "" ); 
	}
}

return( 1, "$tgtkw=$target not associated with $T_Key=$tid" );

}	# end of Validate Target


#-------------------------------------------------------#
#	M Started
#-------------------------------------------------------#
sub M_Started
{
my( $p_hash ) = @_;
my( $tid, $buf, $resultkw, $result, %hash, $mid, $p_temp, %finhash );
my( $pid, $pidkw, $err, $msg );

($err, $msg) = &ValidateTID( $p_hash, $STARTED, \$tid );
return( $err, $msg ) if( $err );

$result = defined($$p_hash{T_RESULT}) ? $$p_hash{T_RESULT} : 1;

$pidkw = $T_PIDDesc{keyword};
$pid = $$p_hash{$pidkw};
return( 1, "Missing $pidkw in STARTED msg for $T_Key=$tid" ) unless( defined($pid) );

# if successful, store pid, change status to running, and store trans queue
if( $result == $G_ResultHash{SUCCESS} ) 
{
	%hash = ( );
	$hash{$T_Key} = $tid;
	$hash{$T_PIDDesc{keyword}} = $pid;
	$hash{$T_TranStatusDesc{keyword}} = $RUNNING;
	&M_ModifyTRec( \%hash );
	return( 0, "$T_Key=$tid status set to $RUNNING\n" );
}

# $result must be an error
$msg = defined($$p_hash{T_REASON}) ? $$p_hash{T_REASON} : "Transaction Startup Failure for $T_Key=$tid: $result";
push( @G_ReturnArray, $msg );

$finhash{T_TID} = $tid;
$finhash{T_RESULT} = $result;
$finhash{T_REASON} = $msg; 
($err, $msg) = &M_Finished( \%finhash );
#push( @G_ReturnArray, $msg );

return( 0, "" );

}	# end of M Started


#-------------------------------------------------------#
#	M Finished
#-------------------------------------------------------#
sub M_Finished
{
my( $p_hash ) = @_;
my( $tid, $mid, $reason, $result, @mids, $err, $msg, %hash, $class );

# Could rec FINISHED in either state...
($err, $msg) = &ValidateTID( $p_hash, "$STARTED $RUNNING $MONITORING $TIMEOUT", \$tid );
return( $err, $msg ) if( $err );

$result = defined($$p_hash{T_RESULT}) ? $$p_hash{T_RESULT} : 1;

# Update counter
if( $result == $G_ResultHash{SUCCESS} ) { $G_SuccessTrans += 1; }
else { $G_FailureTrans += 1; }

# Set reason string
$reason = defined($$p_hash{"T_REASON"}) ? $$p_hash{T_REASON} : "Transaction Finished Failure: No Status Msg for Target";

# Create Status file for each mid still assigned to transaction
@mids = ();
@mids = keys %{$Q_TID2MIDHash{$tid}} if( exists($Q_TID2MIDHash{$tid}) );

foreach $mid (@mids) 
{
	%hash = ( );
	$hash{T_RESULT} = 1;
	$hash{T_REASON} = $reason;
	$hash{T_MID} = $mid;
#	$hash{T_TID} = $tid;
	$hash{T_TARGET} = $Q_TargetHash{$mid};
	($err, $msg) = &M_Status( \%hash );
}

# delete trans rec assoc w/TID
$msg = &DeleteTRec( $tid );
push( @G_ReturnArray, $msg );

return( 0, "" );

}	# end of M Finished


#-------------------------------------------------------#
# 	Check Next Trans
#-------------------------------------------------------#
sub CheckNextTrans
{
my( $mid ) = @_;
my( $trans, $msg, $tgt_kw, $target, $buf );
my( $type_kw, $tgt_type, $script, $pri_kw, $pri, $equser_kw, $equser, $eqgroup );

# check if next trans defined
$trans = $Q_NextTransHash{$mid};
return if( $trans eq "" );

$tgt_kw  = $Q_TargetDesc{keyword};
$target  = $Q_TargetHash{$mid};
$type_kw = $Q_TargetTypeDesc{keyword};
$tgt_type = $Q_TargetTypeHash{$mid} || "\@$xc_DEFTARGETTYPE";
$equser_kw = $Q_EQUserDesc{"keyword"};
$equser  = $Q_EQUserHash{$mid} || "";
$eqgroup = $Q_EQGroupHash{$mid} || "";

# build msg
$msg = "$M_Key=ADD;$T_DefKey=$trans;$tgt_kw=$target;$type_kw=$tgt_type;$equser_kw=$equser;T_EQGROUP=$eqgroup;$Q_AppArgsHash{$mid}";

# Kludge for scripts - when the next transaction from a script is submitted
# to the queue the set the RECORD flag to 0
$msg =~ s/(^|;)(RECORD\s*)=\s*1(;|$)/$1$2=0$3/i
	if	( $trans =~ /^EQScript|Script|EQPlan$/i);

$pri = $Q_PriorityHash{$mid};
$pri_kw = $Q_PriorityDesc{keyword};
$msg .= ";$pri_kw=$pri";

$buf = &ProcessMsg( "$msg\n" );

}	# end of Check Next Trans


#-------------------------------------------------------#
#	M New Status File
#-------------------------------------------------------#
sub M_NewStatusFile
{
my( $p_hash ) = @_;
my( $err, $msg, $buf, @arr );

@arr = stat( STATUS_FILE );
return( 0, "Current STATUS file empty" ) if( $arr[7] == 0 );

# Close current status file
($err, $msg) = &StatusFileClose( );
push( @G_ReturnArray, "$FAILURE_MSG: $msg\n" ) if( $err );

# Open new status file
($err, $msg) = &StatusFileOpen( );
return( $err, $msg );

}	# end of M New Status File


#-------------------------------------------------------#
#	Save Status
#-------------------------------------------------------#
sub M_SaveStatus
{
my	($p_hash) = @_;
my	($key, $value, $err, $msg, @a);

@a = ();

# Save information header
push (@a, (defined ($$p_hash{HEADER}))?
	"-----" . $$p_hash{HEADER} . "-----": "-----STATUS-----");

foreach $key (keys %$p_hash)
{
	next	if	($key =~ /^T_/i);
	$value = $$p_hash{$key};
	$key =~ tr/a-z/A-Z/;
	next	if	($key eq "HEADER");
	if	($value =~ /\n/)
	{
		push (@a, "$key " . join ("\n$key ", split ("\n", $value)));
	}
	else
	{
		push (@a, "$key $value");
	}
}

# Write data to file
print STATUS_FILE join ("\n", @a), "\n";

push( @G_ReturnArray, "$SUCCESS_MSG: Status information saved.\n" );

# Maintain status record count
$G_StatusCount += 1;
return( 0, "" ) if( $G_StatusCount < 5000 );

# Create new STATUS file when max reached
($err, $msg) = &StatusFileClose( );
unless( $err )
{
	($err, $msg) = &StatusFileOpen( );
	$G_StatusCount = 0 unless( $err );
}

return( $err, $msg );

}	# end of M Save Status


#-------------------------------------------------------#
#	Status File Open
#-------------------------------------------------------#
sub StatusFileOpen
{
my( $fh, $id, $dir, $filename );

# Get unique ID for filename
$id = &AssignID( );
$dir = "$G_Config{QSTOREDIR}/status";

# Open in append mode
$filename = "$dir/$id.status.new";
return( 1, "Error opening: '$filename': $!" )
	unless( open( STATUS_FILE, ">$filename" ) );

# Set AutoFlush On
$fh = select( STATUS_FILE );
$| = 1;
select( $fh );

# We're done
return( 0, "New Status File Created: '$filename'" );

}	# end of Status File Open


#-------------------------------------------------------#
#	Status File Close
#
#   Parameters:
#       $p_starting:
#           1 - EQ Server is starting, and there
#               is no STATUS file opened yet.
#           <nothing> - STATUS file was already opened.
#    
#-------------------------------------------------------#
sub StatusFileClose
{
my	($p_starting) = @_;
my( $fh, $id, $dir, $filename, $result, @arr );

# First, close current status file
close( STATUS_FILE )	unless	($p_starting);

# Then, rename current status file if exists
$dir = "$G_Config{QSTOREDIR}/status";
return( 1, "Error opening directory '$dir': $!" )
	unless( opendir( DH, $dir ) );

@arr = readdir( DH );
closedir( DH );

$result = -1;
foreach $filename( @arr )
{
	next unless( $filename =~ /(\d+)\.status\.new/ );
	$id = $1;
	if	(-z "$dir/$filename")
	{
		unlink ("$dir/$filename") ||
			return (1, "Error deleting STATUS file '$dir/$filename': $!");
		$result = 0;
	}
	else
	{
		$result = rename( "$dir/$id.status.new", "$dir/$id.status" );
		return( 1, "Error renaming STATUS file '$dir/$id.status.new': $!" ) if( $result == 0 );
	}
}

return( 0, "No STATUS file to close and rename" ) if( $result == -1 );

return( 0, "All new STATUS files closed and renamed" );

}	# end of Status File Close


#-------------------------------------------------------#
#	Status File Update 
#-------------------------------------------------------#
sub StatusFileUpdate
{
my( $target, $type, $trans, $label, $result, $reason, $jobid, $equser, $eqgroup, $qtime ) = @_;
my( $actname, $time, @a, $err, $msg );

# Do not create status file if DB not installed
return if( $xc_DB_VENDOR eq "NONE" );

# Set to camelcase if dispatch...
$trans = "Dispatch" if( $trans =~ /^DISPATCH$/i );

# Strip leading @ and action type from label, if there
#$label =~ s/^\@*.*\://;
$label =~ s/^\@*$trans://;

# Generate action name using trans and label (if exists)
$actname = "$trans";
$actname .= "\:$label" unless( $label eq "" || $label eq "$trans" );

$actname =~ s/[\@\-\/]+/\-/g;		# replace multiple '@' and '-' with one '-'
$actname =~ s/^\-|\-$//g;		# remove leading/trailing dashes

$jobid = ""	if	(!defined ($jobid));
$equser  = ""	unless( defined ($equser) );
$eqgroup  = ""	unless( defined ($eqgroup) );

# Save data to a log file so we can update action status in the RDBMS later.
# Get current time
$time = time ();

# Ignore script transaction if status file already exist
if( $trans =~ /^EQScript|Script|EQPlan$/i )
{
	return	if	($result eq "0");
}

# Write data to file
print STATUS_FILE <<EOF;
-----STATUS-----
NAME $actname
DESC $actname
TIME $time
QTIME $qtime
TARGET $target
TARGET_TYPE $type
JOB_ID $jobid
EQUSER $equser
EQGROUP $eqgroup
RESULT $result
EOF

@a = split ("\n", $reason);
print STATUS_FILE "ERROR ", join ("\nERROR ", @a), "\n";

# Maintain status record count
$G_StatusCount += 1;
return if( $G_StatusCount < 5000 );

# Create new STATUS file when max reached
($err, $msg) = &StatusFileClose( );
($err, $msg) = &StatusFileOpen( ) unless( $err );
$G_StatusCount = 0 unless( $err );

}	# end of Status File Update 


#-------------------------------------------------------#
#	Parms File Update
#-------------------------------------------------------#
sub ParmsFileUpdate
{
my( $trans, $label, $p_parms, $jobid ) = @_;
my( $actname, $time, $err, $msg );

# Set to camelcase if dispatch...
$trans = "Dispatch" if( $trans =~ /^DISPATCH$/i );

# Strip leading @ and action type from label, if there
#$label =~ s/^\@*.*\://;
$label =~ s/^\@*$trans://;

# Generate action name using trans and label (if exists)
$actname = "$trans";
$actname .= "\:$label" unless( $label eq "" || $label eq "$trans" );

$actname =~ s/[\@\-\/]+/\-/g;		# replace multiple '@' and '-' with one '-'
$actname =~ s/^\-|\-$//g;		# remove leading/trailing dashes

$jobid = ""	if	(!defined ($jobid));

# Save data to a log file so we can update action status in the RDBMS later.
# Get current time
$time = time ();

# Write data to file
print STATUS_FILE <<EOF;
-----PARAMETERS-----
NAME $actname
DESC $actname
JOB_ID $jobid
PARAMETERS $p_parms
EOF

# Maintain status record count
$G_StatusCount += 1;
return if( $G_StatusCount < 5000 );

# Create new STATUS file when max reached
($err, $msg) = &StatusFileClose( );
($err, $msg) = &StatusFileOpen( ) unless( $err );
$G_StatusCount = 0 unless( $err );

}	# end of Create Parms File

#-------------------------------------------------------#
#	Create IP File
#-------------------------------------------------------#
sub CreateIPFile
{
my	($p_target, $p_type, $p_ip) = @_;
my	($file, $time);

return	if	($p_ip !~ /^(\d+.\d+\.\d+)\.\d+$/);

$file = "$xc_EQ_PATH/data/ip/IP.$1.dat";

# Get current time
$time = time ();

# Write data to a file. Don't do anythig if the file cannot be opened.
open (IP_FILE, ">>$file") || return;
print IP_FILE "$time $p_ip $p_type:$p_target\n";
close (IP_FILE);

}	# end of Create IP File


#-------------------------------------------------------#
#	M Status
#-------------------------------------------------------#
sub M_Status
{
my( $p_hash ) = @_;
my( $tid, $buf, $result, $reason, $status, $target, $targettype, $msgstatus );
my( $mid, $did, $err, $msg, $max_attempts, $status_update, %hash, @arr, $k, $v );

# See if TID provided
if( defined( $$p_hash{T_TID} ) )
{
	($err, $msg) = &ValidateTID( $p_hash, "$STARTED $RUNNING $MONITORING $TIMEOUT", \$tid );
	return( $err, $msg ) if( $err );

	($err, $msg) = &ValidateTarget( $p_hash, $tid, \$mid );
	return( $err, $msg ) if( $err );
}

# Otherwise, must have MID defined
elsif( defined( $$p_hash{T_MID} ) )
{
	$mid = $$p_hash{T_MID};
	#$tid = defined($Q_TIDHash{$mid}) ? $Q_TIDHash{$mid} : "0";
	if( defined($Q_TIDHash{$mid}) )
	{
		$tid = $Q_TIDHash{$mid};
	}
	else
	{
		return( 1, "T_MID=$mid not assigned to a transaction" );
	}
}

# If no TID or MID provided, return error
else
{
	return( 1, "T_MSG=Status requires either T_TID or T_MID information" );
}

$reason = "";
if( defined( $$p_hash{T_REASON} ) ) 
{
	$reason = $$p_hash{T_REASON};
	chomp( $reason );
	$reason =~ s/\n/ /g;
}

$result = defined($$p_hash{T_RESULT}) ? $$p_hash{T_RESULT} : "";
$target = $Q_TargetHash{$mid};
$targettype = $Q_TargetTypeHash{$mid};
$did = defined($G_DispatchTargetHash{$targettype}{$target}) ? $G_DispatchTargetHash{$targettype}{$target} : "0";

# Make sure result set if trans assigned and changing the msgstatus
$result = 1 if( $tid ne "" && defined($$p_hash{T_MSGSTATUS}) && $result eq "" ); 

# If result was not provided, just update queued record with data passed
if( $result eq "" || $result == -1 )
{
	%hash = ( );
	$hash{$Q_Key} = $mid;
	foreach $k( keys %$p_hash )
	{
		next if( $k =~ /^(T_TID|T_MID|T_EQUSER|T_EQGROUP)$/i );
		$v = $$p_hash{$k};
		$v = "\U$v" if( $k =~ /^(T_MSGSTATUS)$/ );
		$hash{$k} = $v;
	}
	
	$hash{T_REASON} = $reason unless( $reason eq "" );
	@arr = &M_ModifyMRec( \%hash );
	push( @G_ReturnArray, @arr );
	return( 0, "" );
}

# Keep previous reason if transaction being monitored or (mid and reason provided)
$reason .= " PREVIOUS REASON: $Q_ReasonHash{$mid}" 
	if( $T_TranStatusHash{$tid} eq $MONITORING || (defined($$p_hash{T_MID}) && defined($$p_hash{T_REASON})) );
	
$reason = $1 if( $reason =~ /^(.+?PREVIOUS REASON:.+?)PREVIOUS REASON:/i );

$status_update = defined($$p_hash{T_STATUSUPDATE}) ? $$p_hash{T_STATUSUPDATE}: 1;
if( $result == 0 || $result =~ /^[DX]$/ ) 
{
	# check if next trans set for this message
	&CheckNextTrans( $mid ) if( length($Q_NextTransHash{$mid}) > 0 );
	$Q_MsgStatusHash{$mid} = $$p_hash{T_MSGSTATUS} if( defined($$p_hash{T_MSGSTATUS}) );
	$Q_ResultHash{$mid} = $result;
	$Q_ReasonHash{$mid} = $reason;

	&StatusFileUpdate( $Q_TargetHash{$mid}, $Q_TargetTypeHash{$mid}, 
		$Q_TransHash{$mid}, $Q_ProfileHash{$mid}, $Q_ResultHash{$mid},
		$Q_ReasonHash{$mid}, $Q_JobIdHash{$mid}, $Q_EQUserHash{$mid}, $Q_EQGroupHash{$mid}, $Q_RecdTSHash{$mid} )
			if( $status_update );
	
	# invoke status exec only if true status from transaction
	&InvokeStatusExec( $mid ) if( $result == 0 );
	
	# pop it off the message queue if not DELAYED
	if( $Q_MsgStatusHash{$mid} ne $DELAYED ) 
	{ 
		$buf = &DeleteMRec( $mid ); 
		push( @G_ReturnArray, $buf );
	}
	else 
	{ 
		@arr = &ResetMQRec( $mid, $result, $DELAYED, $reason ); 
		push( @G_ReturnArray, @arr );
	}
}

# Must be failed result, so 
else 
{
	$msgstatus = "\U$$p_hash{T_MSGSTATUS}" || $FAILED;
	$reason = $Q_ReasonHash{$mid} if( $reason eq "" );
	&LogMsg( "TRACEMQ: Setting $Q_Key=$mid to $msgstatus\n" ) if( $G_Config{TRACEMQ} == 1 );
	
	# Reset MQRec calls DelTID2MID, UpdateTargetKeyRec, then modifies MRec with status and reason
	@arr = &ResetMQRec( $mid, $result, $msgstatus, $reason );
	push( @G_ReturnArray, @arr );

	&StatusFileUpdate( $Q_TargetHash{$mid}, $Q_TargetTypeHash{$mid}, 
		$Q_TransHash{$mid}, $Q_ProfileHash{$mid}, $Q_ResultHash{$mid},
		$Q_ReasonHash{$mid}, $Q_JobIdHash{$mid}, $Q_EQUserHash{$mid}, $Q_EQGroupHash{$mid}, $Q_RecdTSHash{$mid} )
			if( $status_update );

	&InvokeStatusExec( $mid );

	$max_attempts = $Q_MaxAttemptsHash{$mid};
	# Pop transaction from the queue if it failed too many times
	if	(($max_attempts)&&($Q_AttemptsHash{$mid} >= $max_attempts))
	{
		# Update message record so we can call Invoke Finished Exec
		$Q_MsgStatusHash{$mid} = $EXPIRED;
		$Q_ReasonHash{$mid} =  "FATAL: Maximum number of failures (" .
			$max_attempts . ") reached. " . $Q_ReasonHash{$mid};

		&StatusFileUpdate ($Q_TargetHash{$mid}, $Q_TargetTypeHash{$mid},
			$Q_TransHash{$mid}, $Q_ProfileHash{$mid}, "X",
			$Q_ReasonHash{$mid}, $Q_JobIdHash{$mid}, $Q_EQUserHash{$mid}, $Q_EQGroupHash{$mid}, $Q_RecdTSHash{$mid});

		$buf = &DeleteMRec( $mid );
		push( @G_ReturnArray, $buf );
		&LogMsg( "Maximum number of failures ($max_attempts) reached for transaction $mid\n");
	}
}

push( @G_CheckDispatchedTarget, $did ) unless( $did eq "0" );
return( 0, "" );

}	# end of M Status


#-------------------------------------------------------#
#	M Trans Status
#-------------------------------------------------------#
sub M_TransStatus
{
my( $p_hash ) = @_;
my( $err, $msg, $buf, $tid, $state, %hash, $class, $skip_monitoring );

($err, $msg) = &ValidateTID( $p_hash, "$STARTED $RUNNING $MONITORING $TIMEOUT", \$tid );
return( $err, $msg ) if( $err );

$state = $$p_hash{T_TRANSTATUS}; 
return( 1, "Invalid State Request. Must be set to $MONITORING" ) unless( defined($state) );

%hash = ();
$hash{$T_Key} = $tid;
$hash{T_TRANSTATUS} = $MONITORING;
@G_ReturnArray = &ModifyXRec( \%hash, $T_Key, \%T_KeyDesc, \%T_TIDHash, "ModTRec", 1 );

# If 'monitored' transaction are not counted toward class contention
$skip_monitoring = defined($G_Config{SKIP_MONITORING}) ? $G_Config{SKIP_MONITORING} : 1;
if( $skip_monitoring )
{
	$class = $T_ClassHash{$tid};
	delete( $G_ClassContention{$class} );	# Remove from Class Contention hash
	push( @G_CheckQueue, $class );			# Push class on array to check later

}

return( 0, "" );

#$buf = "Transaction ($T_Key=$tid) state changed to $MONITORING\n";
#push( @G_ReturnArray, $buf );

}	# end of M Trans Status


#-------------------------------------------------------#
#	M Force Success
#-------------------------------------------------------#
sub M_ForceSuccess
{
my( $p_hash ) = @_;
my( $mid, $tid, $err, $msg, $buf, %hash );

$mid = $$p_hash{"T_MID"};
return( 1, "MID was not provided" ) unless( defined($mid) );
return( 1, "Invalid MID ($mid) - must be a number" ) unless( $mid =~ /^\d+$/ );
return( 1, "MID ($mid) does not exist" ) unless( defined($Q_TargetHash{$mid}) );

# Determine TID of queued transaction
$tid = $Q_TIDHash{$mid} || "0";

# Allow non-assigned transactions to be Forced Success
#return( 1, "MID ($mid) not assigned to a transaction" ) if( $tid eq "0" );

%hash = ( );
if( $tid eq "0" )
{
	$hash{T_MID} = $mid;
}
else
{
	$hash{T_TID} = $tid;
}

$hash{T_TARGET} = $Q_TargetHash{$mid};
$hash{T_RESULT} = 0;
$hash{T_REASON} = "Success state was forced" . 
					((defined($$p_hash{T_EQUSER}))? " by $$p_hash{T_EQUSER}" : "") .
					(($$p_hash{"T_REASON"})? ': ' . $$p_hash{"T_REASON"}: '');

($err, $msg) = &M_Status( \%hash );
return( $err, $msg );

#$buf = $err ? "$FAILURE_MSG: $msg" : "$SUCCESS_MSG: $msg";
#push( @G_ReturnArray, $buf ) unless( $msg eq "" );
#return( 0, "" );

}	# end of M Force Success


#-------------------------------------------------------#
#	Check Class
#-------------------------------------------------------#
sub CheckClass
{
my( $mid ) = @_;
my( $tid, $cur, $class, $c, $skip_monitoring );

$class = $Q_ClassHash{$mid};
return( 1, "Class '$class' found in G_ClassContention hash" ) if( defined($G_ClassContention{$class}) );

$cur = 0;
$skip_monitoring = defined($G_Config{SKIP_MONITORING}) ? $G_Config{SKIP_MONITORING} : 1;
	
#foreach $c (values( %T_ClassHash ) ) 
foreach $tid( keys( %T_ClassHash ) )
{
#	if( $c eq $class ) { $cur++; } }

	# skip transactions being monitored
	next if( $T_TranStatusHash{$tid} eq $MONITORING && $skip_monitoring );

	$cur += 1 if( $T_ClassHash{$tid} eq $class ); 
}

return( 0 ) if( $cur == 0 || $cur < $C_LimitHash{$class} );

#&LogMsg( "TRACEDQ: Class Contention ($Q_Key=$mid)\n" ) if( $G_Config{TRACEDQ} == 1 );
$G_ClassContention{$class} = 1;
return( 1, "Class '$class' limit of $C_LimitHash{$class} reached" );

}	# end of Check Class


#-------------------------------------------------------#
#	Check Unique Val - If not null, check against
#	transactions for match.  Return 0 if it's unique
#-------------------------------------------------------#
sub CheckUniqueVal
{
my( $UVal ) = @_;
my( $mid, $tid, $p_hash );

# return if null
if( $UVal eq "" ) { return( 0 ); }

foreach $tid( keys %Q_TID2MIDHash ) {

	$p_hash = $Q_TID2MIDHash{$tid};
	foreach $mid (keys %$p_hash ) {
		next unless( $Q_UniqueValHash{$mid} eq $UVal );
		&LogMsg( "TRACEDQ: Uniqueness Contention ($Q_Key=$mid) (\$UVal=$UVal)\n" ) if( $G_Config{TRACEDQ} );
		return( 1 );  # it ain't unique
	}

}	# end of foreach TID 2 MID

# it's unique!
return( 0 );

}	# end of Check Unique Val


#-------------------------------------------------------#
# Invoke Status Exec
#-------------------------------------------------------#
sub InvokeStatusExec
{
my( $mid ) = @_;
my( $result, $program, $appargs, $p_hashptr, $kw, $val, $statusflag );

# Make sure Status Flag and Status Exec variables are valid
$statusflag = $Q_StatusFlagHash{$mid} || 0;
$program = $Q_StatusExecHash{$mid} || "" ;
return if( $statusflag == 0 || ! -f $program );

if( $statusflag )
{
	# Now check the result against the flag setting: 1 - always, 2 - fail only, 3 - success only
	$result = $Q_ResultHash{$mid};
	return if( $result == 0 && $statusflag == 2 );	
	return if( $result != 0 && $statusflag == 3 );	
}

$appargs = "T_RESULT=$result;";
#foreach $kw ( keys %Q_KeyDesc )
foreach $kw ( @Q_KeyDesc_keys )
{
	$p_hashptr = $Q_KeyDesc{$kw};
	next unless( $$p_hashptr{statusexecvar} );
	$p_hashptr = $$p_hashptr{hashptr};
	$val = $$p_hashptr{$mid};
	next unless( $val );
	if( $kw =~ /T_APPARGS/i ) { $appargs .= "$val;"; }
	else { $appargs .= "$kw=$val;"; }
}

chop( $appargs );		# remove last semi-colon
&StartProgram( $program, $appargs, $G_Config{TRACESTARTCMD} );

}	# end of Invoke Status Exec


#-------------------------------------------------------#
# Check Retry Attempts
#-------------------------------------------------------#
sub CheckRetryAttempts
{
my( $mid ) = @_;
my( $now, $nextattempt, $secs, $ts );

# Return true if first attempt
return( 1 )	if	(($Q_RetryCntHash{$mid} == 0 )&&
				 ($Q_MsgStatusHash{$mid} ne $FAILED)&&
				 ($Q_MsgStatusHash{$mid} ne $ONHOLD));

# Remove retry message from reason...
$Q_ReasonHash{$mid} =~ s/  EQ will retry after .+$//;

# If exceeded retry count or retry interval == 0, don't retry
if( ($Q_RetryCntHash{$mid} > $Q_RetryHash{$mid}) || ($Q_RetryIntHash{$mid} == 0) ) {

	&LogMsg( "TRACEMQ: Max Retries or Retry Int=0 for $Q_Key=$mid\n" ) if( $G_Config{TRACEMQ} );
	return( 0 );
}

$now = time;
$nextattempt = $Q_FailTSHash{$mid} + $Q_RetryIntHash{$mid};
$secs = $nextattempt - $now;

# Return true, but don't reset status to queued if not ready to retry
if( $secs > 0 ) {
	$ts = localtime($nextattempt);
	$Q_ReasonHash{$mid} .= "  EQ will retry after $ts.";
	&LogMsg( "TRACEMQ: Will retry after $secs seconds for $Q_Key=$mid\n" ) if( $G_Config{TRACEMQ} );
	return( 1 );
}

# Set back to queued state
$Q_MsgStatusHash{$mid} = $QUEUED;
return( 1 );

}	# end of Check Retry Attempts


#-------------------------------------------------------#
# 	Batch Match - Cool name for a subroutine, huh?
#-------------------------------------------------------#
sub BatchMatch
{
my( $mid, $tid ) = @_;
my( $kw, $p_tdesc, $p_thash, $p_mdesc, $p_mhash );
my( $user_jobid, $appargs_match );

foreach $p_tdesc( values %T_KeyDesc ) 
{
	# Check if batch field
	if( $$p_tdesc{batchfield} == 1 ) 
	{
		# Get transaction keyword and hashptr
		$kw = $$p_tdesc{keyword};
		$p_thash = $$p_tdesc{hashptr};

		# Skip transaction keywords that don't have corresponding queue keyword
		next unless( exists($Q_KeyDesc{$kw} ) );

		$p_mdesc = $Q_KeyDesc{$kw};
		$p_mhash = $$p_mdesc{hashptr};
		
		if( $kw eq "T_APPARGS" )
		{
			# Handle this separately
			$appargs_match = &AppArgsMatch( $tid, $mid );
			return( 0 ) unless( $appargs_match );
		}
		elsif( $kw eq "T_JOBID" )
		{
			# Don't worry if job ID is just a timestamp
			next unless( $$p_mhash{$mid} =~ /^\d+\s+(.+)$/ );
			$user_jobid = $1;
			# Not a match unless user specified part of jobid matches
			return( 0 ) unless( $$p_thash{$tid} =~ /^\d+\s+$user_jobid/ );
		}
		else
		{		

			if( ($$p_tdesc{keytype} eq "STRING") &&
			    ($$p_thash{$tid} ne $$p_mhash{$mid}) ) { return( 0 ); }

			elsif( ($$p_tdesc{keytype} eq "NUMBER") &&
			    ($$p_thash{$tid} != $$p_mhash{$mid}) ) { return( 0 ); }
		}
	}
}

# all batch fields match...
return( 1 );

}	# end of Batch Match


#-------------------------------------------------------#
#	App Args Match
#-------------------------------------------------------#
sub AppArgsMatch
{
my( $tid, $mid ) = @_;
my( $s, $k, %tidhash, %midhash );

# Get hash of tid appargs
$s = $T_AppArgsHash{$tid};
$s =~ s/^\'|\'$//g;
&HashMsg( \$s, \%tidhash );

# Get hash of mid appargs
$s = $Q_AppArgsHash{$mid};
$s =~ s/^\'|\'$//g;
&HashMsg( \$s, \%midhash );

# Compare value of each
foreach $k( keys %tidhash )
{
	return( 0 ) unless( defined( $midhash{$k} ) && $midhash{$k} eq $tidhash{$k} );
}

return( 1 );

}	# end of App Args Match


#-------------------------------------------------------#
# 	Check Batch Max
#-------------------------------------------------------#
sub CheckBatchMax
{
my( $tid ) = @_;
my( $mid, $cnt, $p_hash );

$p_hash = $Q_TID2MIDHash{$tid};
$cnt = 0;
foreach $mid( keys %$p_hash ) { $cnt += 1; }

if( $cnt < $T_BatchMaxHash{$tid} ) { return( 0 ); }
else { return( 1 ); }

}	# end of Check Batch Max


#-------------------------------------------------------#
#
# 	Check Batch Trans - Check each queued transaction
# 	for matching batch fields.  If found, include target
# 	in targets field.
#
#-------------------------------------------------------#
sub BatchMsg
{
my( $mid ) = @_;
my( $tid, $status );

# Check each transaction still queued
foreach $tid ( keys %T_TranStatusHash ) {
	# only consider queued transactions with a batch delay
	if( ($T_TranStatusHash{$tid} eq $QUEUED) &&
	    ($T_BatchDelayHash{$tid} > 0) ) {
		# skip if batch max reached
		$status = &CheckBatchMax( $tid );
		next if( $status == 1 );
		# Check if batch elements match
		$status = &BatchMatch( $mid, $tid );
		# If so return $tid
		return( $tid ) if( $status == 1 );
	}
}

# Not batched...
return( "0" );

}	# end of Batch Msg


#-------------------------------------------------------#
# 	Assign Message Vals
#-------------------------------------------------------#
sub AssignMessageVals
{
my( $mid, $p_hash ) = @_;
my( $tkey, $q_descptr, $q_hashptr );

#foreach $tkey( sort keys (%T_KeyDesc) )
foreach $tkey( keys (%T_KeyDesc) )
{
	# check for existence of q element with same keyword
	next if( !exists( $Q_KeyDesc{$tkey} ) );

	$q_descptr = $Q_KeyDesc{$tkey};
	$q_hashptr = $$q_descptr{hashptr};

	if( exists( $$q_hashptr{$mid} ) ) {
		$$p_hash{$tkey} = $$q_hashptr{$mid}; }
	else {
		$$p_hash{$tkey} = "";
		&LogMsg( "Missing $tkey from msg queue for $Q_Key=$mid\n" );
	}

}	# end of foreach $tkey

}	# end of Assign Message Vals


#-------------------------------------------------------#
#	Add Trans Hash
#-------------------------------------------------------#
sub AddTransHash
{
my( $mid ) = @_;
my( $tid, %t_hash, $tkey, $q_descptr, $q_hashptr, $kw );
my( $status, $err, $msg );

&AssignMessageVals( $mid, \%t_hash );

# add status and received timestamp
$t_hash{T_TRANSTATUS} = $QUEUED;
$t_hash{T_RECDTS} = time( );

# add transaction record
($err, $msg) = &M_AddTRec( \%t_hash );
$msg = $err ? "$FAILURE_MSG: $msg" : "$SUCCESS_MSG: $msg";
push( @G_ReturnArray, $msg );

$tid = $t_hash{T_TID} || 0;

# Add Trans Hash populates T_TID of t_hash
return( $tid );

}	# end of Add Trans Hash


#-------------------------------------------------------#
#	Get Priority Hash
#-------------------------------------------------------#
sub GetPriorityHash
{
my( $target, $targettype, $p_hash, $p_count ) = @_;
my( $mid, $p_midhash, $pri, $tid, $msg );

$$p_count = 0;
%$p_hash = ( );

$p_midhash = $Q_TargetKeyHash{$targettype . $target};
return( 10, "$target not in Q_TargetKeyHash" ) unless( defined( $p_midhash ) );

#foreach $mid( sort keys %$p_midhash  )
foreach $mid( keys %$p_midhash  ) 
{
	# Return if a target already assigned to a transaction
	$tid = $Q_TIDHash{$mid};
	if( $tid ne "0" ) {
		$msg = "$target ($Q_Key=$mid) assigned to transaction ($T_Key=$tid).";
		&LogMsg( "$msg\n" );
		return( 30, $msg ) if( exists($T_TIDHash{$tid}) );
		&LogMsg( "But transaction does not exist.  Repairing\n" );
		$Q_TIDHash{$mid} = "0";
		$tid = "0";
	}

#	&LogMsg( "TYPE QUEUED: $Q_TargetTypeHash{$mid}   PASSED:$targettype\n" );

	# Consider MID only if same target/target type of dispatch message
	next unless( $Q_TargetHash{$mid} eq $target &&
			 $Q_TargetTypeHash{$mid} eq $targettype );

	# Consider QUEUED, FAILED, ONHOLD, and RESTRICTED transactions only
	next unless( $Q_MsgStatusHash{$mid} eq $QUEUED ||
			 $Q_MsgStatusHash{$mid} eq $FAILED ||
			 $Q_MsgStatusHash{$mid} eq $ONHOLD ||
			 $Q_MsgStatusHash{$mid} eq $RESTRICTED ); 

	# increment counter and build hash
	$$p_count += 1;
	$pri = $Q_PriorityHash{$mid};
	$$p_hash{$pri}{$mid} = $target; 

}	# end of foreach MID

return( 0, "" );

}	# end of Get Priority Hash


#-------------------------------------------------------#
#	Dispatch Transaction Check
#-------------------------------------------------------#
sub DispatchTransCheck
{
my( $mid, $did ) = @_;

# return true if dispatch not limited to a specific transaction
return( 1 ) if( $D_TransHash{$did} eq "" );

# return false if transactions don't match
return( 0 ) if( $D_TransHash{$did} ne $Q_TransHash{$mid} );

# return true if dispatch profile not limited to a specific one
return( 1 ) if( $D_ProfileHash{$did} eq "" );

# return false if profiles don't match
return( 0 ) if( $D_ProfileHash{$did} ne $Q_ProfileHash{$mid} );

# Passed profile match, so return true
return( 1 );

}	# end of Dispatch Transaction Check


#-------------------------------------------------------#
#	Start Queued Trans
#-------------------------------------------------------#
sub StartQueuedTrans
{
my( $target, $targettype, $p_tid, $p_mid, $did, $class ) = @_;
my( %prihash, $count, $err, $msg, $pri, $p_hash, $skip, $contention);
my( $retry, $status, $mid, $thisclass, $buf );

$$p_tid = "0";

# check if there's a msg queue entry for target (should be)
( $err, $msg ) = &GetPriorityHash( $target, $targettype, \%prihash, \$count );
return( $err, "GetPriorityHash ($err): $msg" ) if( $err );

# If no queued transactions, remove from dispatch hash
return( 1, "No transactions for $target available to run: $msg" ) if( $count == 0 );

$count = 0;
my @p = sort {$a <=> $b} (sort keys %prihash);
#foreach $pri( sort keys %prihash ) 
foreach $pri( @p ) 
{
	$buf = "Considering PRIORITY '$pri' for '$target'\n";
	&LogMsg( "TRACEMQ: $buf" ) if( $G_Config{TRACEMQ} );

	$p_hash = $prihash{$pri};
	foreach $mid( sort keys %$p_hash ) 
	{

		$buf = "Considering MID '$mid'  TRANS '$Q_TransHash{$mid}'  PROFILE '$Q_ProfileHash{$mid}  TARGET '$Q_TargetHash{$mid}'  CLASS '$Q_ClassHash{$mid}'\n";
		&LogMsg( "TRACEMQ: $buf" ) if( $G_Config{TRACEMQ} );

		$$p_mid = $mid;
		# Set the skip variable from queued transaction
		$skip = $Q_SkipHash{$mid};
		
		# Check if dispatching a specific transaction
		unless( &DispatchTransCheck( $mid, $did ) )
		{
			&LogMsg( "TRACEMQ: Transaction Dispatch Mismatch" ) if( $G_Config{TRACEMQ} );
			next if( $skip );
			$msg = "Transaction (T_MID=$mid) can not be skipped to execute $D_TransHash{$did}";
			$msg .= ":$D_ProfileHash{$did}" if( $D_ProfileHash{$did} ne "" );
			return( 1, $msg );
		}
		
		# do not proceed if MID is RESTRICTED
		if( $Q_MsgStatusHash{$mid} eq $RESTRICTED ) 
		{
			&LogMsg( "TRACEMQ: Restricted Transaction" ) if( $G_Config{TRACEMQ} );
			next if( $skip );
			return( 1, "Transaction (T_MID=$mid) RESTRICTED by time for $target" );
		}

		# do not proceed if MID is ONHOLD
		if( $Q_MsgStatusHash{$mid} eq $ONHOLD ) 
		{
			&LogMsg( "TRACEMQ: Onhold Transaction" ) if( $G_Config{TRACEMQ} );
			next if( $skip );
			return( 1, "Transaction (T_MID=$mid) ONHOLD for $target" );
		}

		# If target is in excluded IP range
		if( $D_ExcludeIPHash{$did} )
		{
			# If transaction cannot run if target is in excluded IP range
			if	((!defined ($Q_ExcludeIPHash{$mid}))||($Q_ExcludeIPHash{$mid} ne "NO"))
			{
				$Q_MsgStatusHash{$mid} = $EXCLUDED;
				&LogMsg( "TRACEMQ: Excluded IP Transaction" ) if( $G_Config{TRACEMQ} );
				next	if	($skip);
				return ( 1, "Transaction (T_MID=$mid) cannot run: target is in excluded IP range" );
			}
		}

		# Replaced by DSL Jan. 19, 2001 per request from Mead for this capability
		# Skip if recently attempted or if no retries allowed
		$retry = &CheckRetryAttempts( $mid );

		# either 	A) ready to try/retry transaction now; $retry = 1, status = QUEUED
		#		B) not ready to retry transaction yet; $retry = 1, status = FAILED
		#		C) retry attempts exhausted; $retry = 0, status = FAILED
		unless( $retry ) 
		{
			&LogMsg( "TRACEMQ: Retries Exhausted" ) if( $G_Config{TRACEMQ} );
			next if( $skip );
			return( 1, "Transaction (T_MID=$mid) FAILED for $target" ); 
		}

		# Must be queued or to be retried, so increment counter
		$count += 1;
		
		# If transaction FAILED, skip it or return
		if( $Q_MsgStatusHash{$mid} eq $FAILED ) 
		{
			&LogMsg( "TRACEMQ: Failed Transaction" ) if( $G_Config{TRACEMQ} );
			next if( $skip );
			return( 0, "Transaction (T_MID=$mid) must be retried for $target" ) if( $retry ); 
			return( 1, "Transaction (T_MID=$mid) FAILED for $target" );
		}

		# return if batched with queued transaction
		$$p_tid = &BatchMsg( $mid );
		if( $$p_tid ne "0" )
		{
			&LogMsg( "TRACEMQ: Batched with TID '$$p_tid'" ) if( $G_Config{TRACEMQ} );
			return( 0, "$mid batched together with $$p_tid" );
		}
		
		# If class specified, only consider trans of that class
		$thisclass = $Q_ClassHash{$mid};
		if( $class ne "" && $thisclass ne $class )
		{
			&LogMsg( "TRACEMQ: Class Mismatch" ) if( $G_Config{TRACEMQ} );
			next if( $skip );
			return( 0, "Only '$class' class being considered at this time" ); 
		}

		# Skip/return (but don't delete) if the trans class prohibits execution.
		($contention, $msg) = &CheckClass( $mid );
		if( $contention ) 
		{
			&LogMsg( "TRACEMQ: Class Contention: $msg" ) if( $G_Config{TRACEMQ} );
			next if( $skip );
			return( 0, "Transaction Class Contention" ); 
		}

		# Skip/return (but don't delete) if uniqueness prohibits execution.
		$contention = &CheckUniqueVal( $Q_UniqueValHash{$mid} );
		if( $contention ) 
		{
			&LogMsg( "TRACEMQ: Failed Uniqueness Test" ) if( $G_Config{TRACEMQ} );
			next if( $skip );
			return( 0, "Transaction Uniqueness Contention" ); 
		}

		# Otherwise, create a new transaction
		$$p_tid = &AddTransHash( $mid );
		return( 0, "Starting new transactions" );

	}	# end of foreach mid

}	# end of foreach pri

$err = ($count == 0 ? 1 : 0);
return( $err, "No transactions ready at this time for $target" );

}	# end of Start Queued Trans


#-------------------------------------------------------#
#	Check Queue
#-------------------------------------------------------#
sub CheckQueue
{
my( $class ) = @_;
my( $target, $targettype, $did, $mid, $tid, $status, %hash, $pri, $p_hash );
my	($err, $msg);

return if( $G_Config{SUSPEND} );

# For each target in the dispatch hash, check if it's time to assign to trans
foreach $pri( sort keys %G_DispatchPriorityHash ) {

	$p_hash = $G_DispatchPriorityHash{$pri};
	foreach $did( sort keys %$p_hash ) 
	{
		# skip it if already assigned to a transaction
		next if( $D_TIDHash{$did} ne "0" );

		&CheckDispatchedTarget( $did, $class );
		last if( defined($G_ClassContention{$class}) );
		
	}	# end of foreach did
	
	last if( defined($G_ClassContention{$class}) );

}	# end of foreach priority

}	# end of Check Queue


#-------------------------------------------------------#
#	Check Dispatched Target 
#-------------------------------------------------------#
sub CheckDispatchedTarget
{
my( $did, $class ) = @_;
my( $tid, $mid, $err, $msg, %hash, $targettype, $target );

$class = "" unless( defined($class) );
$target = $D_TargetHash{$did};
$targettype = $D_TargetTypeHash{$did};

# delete it if nothing queued for target
unless( defined $Q_TargetKeyHash{$targettype . $target} ) 
{
	&LogMsg( "TRACEDQ: No record of Target in TargetKeyHash" ) if( $G_Config{TRACEDQ} );
	&DeleteDRec( $did );
	return;
}

( $err, $msg ) = &StartQueuedTrans( $target, $targettype, \$tid, \$mid, $did, $class );
if( $err || $tid eq "0" ) 
{
	&LogMsg( "TRACEDQ: $msg" ) if( $G_Config{TRACEDQ} && $err );
	&DeleteDRec( $did ) if( $err );
	return;
}

# Update target key hash
$Q_TargetKeyHash{$targettype . $target}{$mid} = $tid;

# Update TID 2 MID assignment
&AddTID2MIDRec( $tid, $mid, $target );

# Update TID 2 DID assignment
&AddTID2DIDRec( $tid, $did, $target );

# Update message status and tid assignment
%hash = ( );
$hash{$Q_Key} = $mid;
$hash{$Q_TIDDesc{keyword}} = $tid;
$hash{$Q_MsgStatusDesc{keyword}} = $ASSIGNED;
&M_ModifyMRec( \%hash );

# Update dispatch hash tid assignment
%hash = ( );
$hash{$D_Key} = $did;
$hash{$D_TIDDesc{keyword}} = $tid;
&M_ModifyDRec( \%hash );

# Set flag to call CheckTrans
$G_CheckTrans = $tid;

}	# end of Check Dispatched Target


#-------------------------------------------------------#
# 	Invoke Exec
#-------------------------------------------------------#
sub InvokeExec
{
my( $tid ) = @_;
my( $appargs, $buf, $p_desc, $p_hash, %hash, $now );
my( $seq, $type, $target, $filename, @targetarr, $cmdlen, $transprogram );

# Make sure we found matching elements
if( !defined($T_ExecHash{$tid}) ) { return( 0 ); }

# initialize application arguments
$appargs = "";

# See if we need to use EQTransWrapper to start transaction
if( $T_UseEQTransWrapperHash{$tid} )
{
	$transprogram = "$xc_EQ_PATH/trans/EQTransWrapper.pl";
	$appargs = "T_EXEC=$T_ExecHash{$tid};";
}
else
{
	$transprogram = $T_ExecHash{$tid};
}

# Append all standard arguments for this transaction
foreach $p_desc( values %T_KeyDesc ) 
{
	if( $$p_desc{stdarg} == 1 ) 
	{
		$p_hash = $$p_desc{hashptr};
		if( $$p_hash{$tid} ne "" ) { $appargs .= "$$p_desc{keyword}=$$p_hash{$tid};"; }
	}
}

# If args for this tid, append them.
if( length($T_AppArgsHash{$tid}) > 0 ) { $appargs .= "$T_AppArgsHash{$tid}"; }
# Otherwise, chop trailing semi-colon
else { chop( $appargs ); }

%hash = ( );
$hash{$T_Key} = $tid;
$hash{$T_TranStatusDesc{keyword}} = $STARTED;
$hash{$T_InvokedTSDesc{keyword}} = time( );
$hash{$T_AppArgsDesc{keyword}} = $appargs;

# See if we need to shorten command line length by writing targets to file
$cmdlen = length("$G_Config{STARTCMD} $T_ExecHash{$tid} $appargs");
if( $cmdlen > $G_Config{CLIMAXLEN} || $T_TFileFlagHash{$tid} ) 
{
	# Generate unique filename
	$now = time;
	$seq = 1;
	do
	{
		$filename = sprintf( "$xc_EQ_PATH/temp/temp.$now-%03d.tlist", $seq++ );
	}	while( -f $filename );

	# Extract targettype and get target list
	$type = $T_TargetTypeHash{$tid};
	@targetarr = split( /,/, $T_TargetsHash{$tid} );

	# Create target file containing a target on each line
	if	(open( TARGETFILE, ">$filename" ))
	{
		# Update hash with filename
		$hash{$T_TargetFileDesc{keyword}} = $filename;
		#foreach $target( @targetarr ) { print TARGETFILE "$type:$target\n"; }
		foreach $target( @targetarr ) { print TARGETFILE "$target\n"; }		# no need to prefix type as it will be defined in T_TARGETTYPE
		close( TARGETFILE );

		# Append target filename to appargs before starting program
		$appargs .= ";$T_TargetFileDesc{keyword}=$filename";

		# Remove T_TARGETS from $appargs since targets are stored in file
		$appargs =~ s/;*T_TARGETS=[^;]+//;
		$appargs =~ s/^;+//;
	}
}

&M_ModifyTRec( \%hash );
&StartProgram( $transprogram, $appargs, $G_Config{TRACESTARTCMD} );

return( 1 );

}	# end of Invoke Exec


#-------------------------------------------------------#
#  Check For Timeout
#-------------------------------------------------------#
sub CheckForTimeout
{
my( $tid ) = @_;
my( $now, $diff, $buf, $p_hash, $result, $reason, %finhash );

return unless( defined($T_InvokedTSHash{$tid}) );

$now = time;
$diff = $now - $T_InvokedTSHash{$tid};

if( ($T_TranStatusHash{$tid} eq $STARTED) && ($diff > $G_Config{STARTTIMEOUT}) ) 
{
	# Invoke finished routine
	$finhash{T_TID} = $tid;
	$finhash{T_RESULT} = 1;
	$finhash{T_REASON}  = "STARTED Timeout: No startup response from $T_Key=$tid. ";
	$finhash{T_REASON} .= "T_MSG=STARTED not recd within $G_Config{STARTTIMEOUT} seconds.";
	&M_Finished( \%finhash );
	&LogMsg( "$finhash{T_REASON}\n" );

}

elsif( $T_TranStatusHash{$tid} eq $RUNNING && $T_TimeoutHash{$tid} > 0 && $diff > $T_TimeoutHash{$tid} ) 
{
	&LogMsg( "$T_Key=$tid ($T_TransHash{$tid}) exceeded timeout value ($T_TimeoutHash{$tid}) after $diff seconds\n" );
	&InvokeTimeoutExec( $tid );
	$T_TranStatusHash{$tid} = $TIMEOUT;
}

# Check if no more targets assigned to transaction.  I.e. No finished recd
elsif( $T_LastTSHash{$tid} ) 
{
	$diff = $now - $T_LastTSHash{$tid};
	# Use STARTED timeout, for now
	if( $diff > $G_Config{STARTTIMEOUT} ) 
	{
		# Invoke finished routine
		$finhash{T_TID} = $tid;
		$finhash{T_RESULT} = 1;
		$finhash{T_REASON}  = "FINISHED Timeout: No more targets assigned to $T_Key=$tid. ";
		$finhash{T_REASON} .= "T_MSG=FINISHED not recd within $G_Config{STARTTIMEOUT} seconds.";
		&M_Finished( \%finhash );
		&LogMsg( "$finhash{T_REASON}\n" );
	}
}

}	# end of Check For Timeout


#-------------------------------------------------------#
#	Started Trans
#-------------------------------------------------------#
sub StartedTrans
{
my( $tid, $count );

$count = 0;
foreach $tid( keys %T_TIDHash ) 
{
	$count += 1 if( $T_TranStatusHash{$tid} eq $STARTED );
}

return( $count );

}	# end of Started Trans


#-------------------------------------------------------#
# 	Check Trans
#-------------------------------------------------------#
sub CheckTrans
{
my( $tid, $now, $ts, $ReachedBatchMax, $status, $started, @a, $msg );

return if( $G_CheckTrans eq "0" );

$now = time;

# Get the number of trans in STARTED state
$started = &StartedTrans( );

# for each transaction,
foreach $tid( sort keys %T_TIDHash ) 
{
	# Check if trans suffered STARTED timeout, FINISHED timeout, or expired
	if( $T_TranStatusHash{$tid} ne $QUEUED )
	{
		&CheckForTimeout( $tid );
		next;
	}

	# Targets might have been deleted while batching, so
	# delete trans rec assoc w/TID if no targets assigned to it. 
	@a = ();
	@a = keys %{$Q_TID2MIDHash{$tid}};
	if( scalar(@a) == 0 )
	{
		$msg = "TRACETQ: Deleting T_TID=$tid. No targets assigned to queued transaction.";
		&LogMsg( $msg ) if( $G_Config{TRACETQ} );
		$msg = &DeleteTRec( $tid );
		push( @G_ReturnArray, $msg );
		next;
	}

	&LogMsg( "STARTMAX: $G_Config{STARTMAX}  STARTED: $started" ) if( $G_Config{DEBUG} );

	# Skip if reached STARTMAX
	next unless( $started < $G_Config{STARTMAX} );

	# skip transactions not queued or not assigned any targets
	next if( $T_TranStatusHash{$tid} ne $QUEUED );
	next if( $T_TargetsHash{$tid} eq "" );

	# check if it's okay to invoke
	$ts = $T_RecdTSHash{$tid} + $T_BatchDelayHash{$tid};

	# if we haven't reached time to invoke...
	if( $ts > $now ) {
		# check if batch max reached
		$ReachedBatchMax = &CheckBatchMax( $tid );
		next unless $ReachedBatchMax;
	}

	# invoke transaction
	$status = &InvokeExec( $tid );
	if( $status == 0 ) { $status = &DeleteTRec( $tid ); }
	else { $started += 1; }

}	# end of foreach tid loop

$G_CheckTrans = 0;

}	# end of Check Trans



#-------------------------------------------------------#
#	Check Schedule
#-------------------------------------------------------#
sub CheckSchedule
{
my( $sid, $err, $msg, $now );
my( $targets, $max_targets, $target_count, $target_type, $mid );

$max_targets = 100;
$now = time( );
foreach $sid( keys %S_SIDHash ) {

	# skip if not time to dispatch event
	next if( $now < $S_UTSHash{$sid} );

	# initialize some variables
	$targets = "";
	$target_count = 0;
	$target_type = "";

	foreach $mid( keys %Q_MIDHash ) {

		# skip messages not scheduled 
		next if( $Q_SIDHash{$mid} ne "$sid" );

		# handle a single target type at a time
		$target_type = $Q_TargetTypeHash{$mid} if( $target_type eq "" );
		next if( $Q_TargetTypeHash{$mid} ne $target_type );

		# reset to zero, since it's okay to dispatch
		$Q_SIDHash{$mid} = "0";

		# set status to queued
		$Q_MsgStatusHash{$mid} = $QUEUED;

		# create list of targets
		$targets .= "$Q_TargetHash{$mid},";
		$target_count += 1;

		# throttle number if max targets > 0
		next if( $max_targets == 0 );
		last if( $target_count >= $max_targets ); 
	}

	# delete from schedule queue if no targets found
	if( $target_count == 0 ) {
		&DeleteSRec( $sid );
		next;
	}

	# remove last comma from list of targets
	chop( $targets );

	# Create and Process the message
	$msg = "T_MSG=Dispatch;T_TARGETTYPE=$target_type;T_TARGETS=$targets";
	&ProcessMsg( $msg );
}

}	# end of Check Schedule


#-------------------------------------------------------#
#	Get Installed Patches
#-------------------------------------------------------#
sub GetInstalledPatches
{
my( $patches, $dir, $file, @a, $line );

$patches = "";
$dir = "$xc_EQ_PATH/cfg/patches";

# First, get list of patches stored in cfg/patches/InstalledPatch.dat
$file = "$dir/InstalledPatch.dat";
if( open( FH, $file ) )
{
	@a = <FH>;
	close( FH );
	foreach $line( @a )
	{
		$line =~ s/^\s+|\s+$//g;
		next if( $line eq "" || $line =~ /^\#/ );
		$patches .= "$line,";
	}
}

# Now, check each patch logfile in cfg/patches
if( opendir( DH, $dir ) )
{
	while( $file = readdir( DH ) )
	{
		next unless( $file =~ s/\.log$// );
		$patches .= "$file,";
	}
	close( DH );
}

$patches =~ s/,+$//;
return( $patches );	

}	# end of Get Installed Patches


#-------------------------------------------------------#
# 	Log Msg
#-------------------------------------------------------#
sub LogMsg
{
my( $msg, $p_exit ) = @_;
my( $sec, $min, $hr, $mday, $mon, $yr, $wday, $yday, $isdst, $date );
my( $buf ) = "";
my( $time, $prog, $err, $errmsg );


( $sec, $min, $hr, $mday, $mon, $yr, $wday, $yday, $isdst ) =
	localtime( time );

# check if new day since last message written
if( $yday != $G_LastLogfileYDay )
{
	$date = sprintf( "%04d%s%02d", 1900+$yr, $G_mons[$mon], $mday );
	if( $G_LastLogfileYDay != 0 ) 
	{
		$buf = sprintf( "%02d:%02d:%02d  %s - Creating new daily log file.\n", $hr, $min, $sec, $date );
		print "$buf";
	}

	$G_LastLogfileYDay = $yday;
	if((!defined ($p_exit))||($p_exit ne "2"))
	{
		&LogMsg( $buf, 2)       if      ($buf);
	}

	close( STDOUT );
	$G_LogFile = ($G_Config{LOGFILEDIR} ||
		(($OS eq $NT)? "C:/TEMP": "/tmp")) . "/$date.log";
	warn ("Logging data to '$G_LogFile'\n")		if	($G_Debugging);

	open( STDOUT, ">>$G_LogFile" ) || die "Error opening $G_LogFile: $!\n";
	select( STDOUT ); $| = 1;

	print "$date\n";
	&DisplayParms( \%G_Config, \%G_ConfigMod );
	print "Class Definitions:\n";
	&DisplayCRecs( );
	print "Transaction Definitions:\n";
	&DisplayDefTransRecs( );
}

$G_LastLogfileYDay = $yday;
if	(defined ($msg))
{
	$buf = sprintf( "%02d:%02d:%02d  %s\n", $hr, $min, $sec, $msg );
	$buf =~ s/\n+$/\n/;
	print $buf;
	warn ($buf)		if	($G_Debugging);
}

if	((defined ($p_exit))&&(($p_exit eq "1")||($p_exit eq "2")))
{
	die ($msg);
}

}	# end of Log Msg


#-------------------------------------------------------#
# 	Create Config Dirs
#-------------------------------------------------------#
sub CreateConfigDirs
{

# If $G_Config{LOGFILEDIR} !exists, create it
unless( -d $G_Config{LOGFILEDIR} )
{
	mkdir( $G_Config{LOGFILEDIR}, 0777 ) ||
		&LogMsg( "Cannot mkdir $G_Config{LOGFILEDIR}: $!\n", 1);
}

# If $G_Config{QSTOREDIR} !exists, create it
unless( -d $G_Config{QSTOREDIR} )
{
	mkdir( $G_Config{QSTOREDIR}, 0777 ) ||
		&LogMsg( "Cannot mkdir $G_Config{QSTOREDIR}: $!\n", 1);
}

unless( -d "$G_Config{QSTOREDIR}/status" )
{
	mkdir( "$G_Config{QSTOREDIR}/status", 0777 ) || 
		&LogMsg( "Cannot mkdir $G_Config{QSTOREDIR}/status: $!\n", 1);
}

}	# end of Create Config Dirs


#-------------------------------------------------------#
# 	M Filter Recs
#-------------------------------------------------------#
sub M_FilterRecs
{
my( $p_hash ) = @_;
my	($store, $view);

$store = $G_Config{RECDETAILS};
$view = $$p_hash{T_VIEW} || $$p_hash{VIEW} || "";
if	($view ne "")
{
	$G_Config{RECDETAILS} = 1	if	($view =~ /detail/i );
	$G_Config{RECDETAILS} = 2	if	($view =~ /summary/i );
	delete ($$p_hash{T_VIEW});
	delete ($$p_hash{VIEW});
}

push( @G_ReturnArray, "\n" );
push( @G_ReturnArray, "\t***  Dispatch Queue Records  ***\n" );
push( @G_ReturnArray, "\n" );
&M_FilterDRecs ($p_hash);
push( @G_ReturnArray, "\n" );
push( @G_ReturnArray, "\t***  Transaction Queue Records  ***\n" );
push( @G_ReturnArray, "\n" );
&M_FilterTRecs ($p_hash);
push( @G_ReturnArray, "\n" );
push( @G_ReturnArray, "\t***  Message Queue Records  ***\n" );
push( @G_ReturnArray, "\n" );
&M_FilterMRecs ($p_hash);

$G_Config{RECDETAILS} = $store;

return( 0, "" );

}	# end of M Filter Recs


#-------------------------------------------------------#
# 	M Filter M Recs
#-------------------------------------------------------#
sub M_FilterMRecs
{
my( $p_hash ) = @_;
my( $key, $val, %crithash );
my( $store, $view );

$store = $G_Config{RECDETAILS};
$view = $$p_hash{T_VIEW} || $$p_hash{VIEW} || "";
if	($view ne "")
{
	$G_Config{RECDETAILS} = 1	if	($view =~ /detail/i );
	$G_Config{RECDETAILS} = 2	if	($view =~ /summary/i );
	delete ($$p_hash{T_VIEW});
	delete ($$p_hash{VIEW});
}

%crithash = ( );
while( ($key, $val) = each( %$p_hash ) ) { 
	$key =~ s/^\s+|\s+$//g;
	$key =~ tr/[a-z]/[A-Z]/;
	$val =~ s/^\s+|\s+$//g;
	$crithash{$key} = $val;
}

&FilterXRecs( \%crithash, \%Q_MIDHash, \%Q_KeyDesc, \&MRecHeader, \&MRecString );

$G_Config{RECDETAILS} = $store;

return( 0, "" );

}	# end of M Filter M Recs


#-------------------------------------------------------#
#	M Filter T Recs
#-------------------------------------------------------#
sub M_FilterTRecs
{
my( $p_hash ) = @_;
my( $key, $val, %crithash );
my( $store, $view );

$store = $G_Config{RECDETAILS};
$view = $$p_hash{T_VIEW} || $$p_hash{VIEW} || "";
if	($view ne "")
{
	$G_Config{RECDETAILS} = 1	if	($view =~ /detail/i );
	$G_Config{RECDETAILS} = 2	if	($view =~ /summary/i );
	delete ($$p_hash{T_VIEW});
	delete ($$p_hash{VIEW});
}

%crithash = ( );
while( ($key, $val) = each( %$p_hash ) ) { 
	$key =~ s/^\s+|\s+$//g;
	$key =~ tr/[a-z]/[A-Z]/;
	$val =~ s/^\s+|\s+$//g;
	# Special processing for T_TARGET keyword
	if	($key eq "T_TARGET")
	{
		$key = "T_TARGETS";
		$val = "(^|,)$val(,|\$)";
	}
	$crithash{$key} = $val;
}

&FilterXRecs( \%crithash, \%T_TIDHash, \%T_KeyDesc, \&TRecHeader, \&TRecString );

$G_Config{RECDETAILS} = $store;

return( 0, "" );

}	# end of M Filter T Recs


#-------------------------------------------------------#
#	M Filter D Recs
#-------------------------------------------------------#
sub M_FilterDRecs
{
my( $p_hash ) = @_;
my( $key, $val, %crithash );
my( $store, $view );

$store = $G_Config{RECDETAILS};
$view = $$p_hash{T_VIEW} || $$p_hash{VIEW} || "";
if	($view ne "")
{
	$G_Config{RECDETAILS} = 1	if	($view =~ /detail/i );
	$G_Config{RECDETAILS} = 2	if	($view =~ /summary/i );
	delete ($$p_hash{T_VIEW});
	delete ($$p_hash{VIEW});
}

%crithash = ( );
while( ($key, $val) = each( %$p_hash ) ) { 
	$key =~ s/^\s+|\s+$//g;
	$key =~ tr/[a-z]/[A-Z]/;
	$val =~ s/^\s+|\s+$//g;
	$crithash{$key} = $val;
}

&FilterXRecs( \%crithash, \%D_DIDHash, \%D_KeyDesc, \&DRecHeader, \&DRecString );

$G_Config{RECDETAILS} = $store;

return( 0, "" );

}	# end of M Filter D Recs


#-------------------------------------------------------#
#	Filter X Recs
#-------------------------------------------------------#
sub FilterXRecs
{
my( $p_crithash, $p_masterhash, $p_keydesc, $p_headsub, $p_recsub ) = @_;
my( $key, $val, $id, $buf, $p_keyhash, $reccnt, $hashkey, $hashval, $match );
my( $critstr ) = "";

$reccnt = 0;
foreach $key ( keys %$p_crithash ) {
	# make sure the keyword is valid
	if( !defined( $$p_keydesc{$key} ) ) {
		push( @G_ReturnArray, "Invalid keyword ($key) passed to FilterXRecs\n" );
		delete( $$p_crithash{$key} );
	}
	$critstr .= "$key=$$p_crithash{$key}  ";
	$reccnt += 1;
}

unless( $reccnt ) {
	push( @G_ReturnArray, "No valid keywords passed to FilterXRecs\n" );
	return;
}

# initialize a counter
$reccnt = 0;
foreach $id ( sort keys %$p_masterhash ) {

	$match = 1;
	foreach $key ( keys %$p_crithash ) {
		$val = $$p_crithash{$key};
		$p_keyhash = $$p_keydesc{$key}{hashptr};
		if	($val =~ /\|/)
		{
			unless( $$p_keyhash{$id} =~ /$val/ ) {
				$match = 0;
				last;
			}
		}
		else
		{
			unless( $$p_keyhash{$id} eq "$val" ) {
				$match = 0;
				last;
			}
		}
	}

	next unless( $match );

	# found a match.  If not summary...
	if( $G_Config{RECDETAILS} != 2 ) {
		# If not first record, display header
		if( $reccnt == 0 ) {
			$buf = &$p_headsub();
			push( @G_ReturnArray, $buf );
		}
		$buf = &$p_recsub( $id );
		push( @G_ReturnArray, $buf );
	}
	$reccnt += 1;
}

if( $reccnt == 0 ) {
	push( @G_ReturnArray, "No records match $critstr\n" ); }
else {
	push( @G_ReturnArray, "$reccnt records match $critstr\n" ); }

}	# end of Filter X Q Recs


#-------------------------------------------------------#
# 	M Read DQ
#-------------------------------------------------------#
sub M_ReadDQ
{
my( $p_hash ) = @_;
my( $store, $view, $sched, %keyhash, $kw );

$store = $G_Config{RECDETAILS};
$view = $$p_hash{T_VIEW} || $$p_hash{VIEW} || "";
if	($view ne "")
{
	$G_Config{RECDETAILS} = 1	if	($view =~ /detail/i );
}

%keyhash = ( );
$kw = $$p_hash{T_KEYWORDS} || $$p_hash{KEYWORDS} || "";
if	($kw ne "")
{
	foreach $kw (split (/\s*,\s*/, $kw))
	{
		$keyhash{"\U$kw"} = 1; 
	}
}

&ReturnDRecs (\%keyhash);

$G_Config{RECDETAILS} = $store;

return( 0, "" );

}	# end of M Read DQ


#-------------------------------------------------------#
# 	M Read MQ
#-------------------------------------------------------#
sub M_ReadMQ
{
my( $p_hash ) = @_;
my( $store, $view, $sched, %keyhash, $kw );

$store = $G_Config{RECDETAILS};
$view = $$p_hash{T_VIEW} || $$p_hash{VIEW} || "";
if	($view ne "")
{
	$G_Config{RECDETAILS} = 1	if	($view =~ /detail/i );
}

%keyhash = ( );
$kw = $$p_hash{T_KEYWORDS} || $$p_hash{KEYWORDS} || "";
if	($kw ne "")
{
	foreach $kw (split (/\s*,\s*/, $kw))
	{ 
		$keyhash{"\U$kw"} = 1; 
	}
}

$sched = $$p_hash{SCHEDULE} || $S_IncludeRecs;

&ReturnMRecs( $sched, \%keyhash );

$G_Config{RECDETAILS} = $store;

return( 0, "" );

}	# end of M Read MQ


#-------------------------------------------------------#
# 	M Read SQ
#-------------------------------------------------------#
sub M_ReadSQ
{
my( $p_hash ) = @_;
my( $store, $view );

$store = $G_Config{RECDETAILS};
$view = $$p_hash{T_VIEW} || $$p_hash{VIEW} || "";
if	($view ne "")
{
	$G_Config{RECDETAILS} = 1	if	($view =~ /detail/i );
}

&ReturnSRecs();

$G_Config{RECDETAILS} = $store;

return( 0, "" );

}	# end of M ReadSQ


#-------------------------------------------------------#
# 	M Read TQ
#-------------------------------------------------------#
sub M_ReadTQ
{
my( $p_hash ) = @_;
my( $store, $view );

$store = $G_Config{RECDETAILS};
$view = $$p_hash{T_VIEW} || $$p_hash{VIEW} || "";
if	($view ne "")
{
	$G_Config{RECDETAILS} = 1	if	($view =~ /detail/i );
}

&ReturnTRecs();

$G_Config{RECDETAILS} = $store;

return( 0, "" );

}	# end of M ReadTQ


#-------------------------------------------------------#
# 	M Read Q
#-------------------------------------------------------#
sub M_ReadQ
{
my( $p_hash ) = @_;
my( $store, $view, $sched, %keyhash );

$store = $G_Config{RECDETAILS};
$view = $$p_hash{T_VIEW} || $$p_hash{VIEW} || "";
if	($view ne "")
{
	$G_Config{RECDETAILS} = 1	if	($view =~ /detail/i );
}

$sched = $$p_hash{SCHEDULE} || $S_IncludeRecs;

%keyhash = ();
&ReturnDRecs (\%keyhash);
&ReturnTRecs ();
&ReturnMRecs ($sched, \%keyhash);

$G_Config{RECDETAILS} = $store;

return( 0, "" );

}	# end of M ReadQ


#-------------------------------------------------------#
#	Return M Recs
#-------------------------------------------------------#
sub ReturnMRecs
{
my( $sched, $p_keyhash ) = @_;
my( $reccnt, $buf, $mid, $keyhashcnt );

$reccnt = 0;
$buf = "";
$keyhashcnt = scalar %$p_keyhash;

# Header goes first
unless( $keyhashcnt ) {
	push( @G_ReturnArray, "\n" );
	push( @G_ReturnArray, "\t***  Message Queue Records  ***\n" );
	push( @G_ReturnArray, "\n" );
	$buf = &MRecHeader();
	push( @G_ReturnArray, $buf );
}

# Push each element in queue onto G_ReturnArray
foreach $mid ( sort keys( %Q_MIDHash ) )
{
	# Filter Scheduled Records based on $sched setting
	next if( $sched == $S_ExcludeRecs && $Q_SchedHash{$mid} ne "0" );
	next if( $sched == $S_SRecsOnly && $Q_SchedHash{$mid} eq "0" );
	if( $keyhashcnt ) { $buf = &MRecString( $mid, $p_keyhash ); }
	else { $buf = &MRecString( $mid ); }
	push( @G_ReturnArray, $buf );

	$reccnt += 1;
}

# Trailer info goes here
unless( $keyhashcnt ) {
	push( @G_ReturnArray, "\n" );
	if( $reccnt == 0 ) { $buf = "No records in message queue\n"; }
	else { $buf = "$reccnt records in message queue\n"; }
	push( @G_ReturnArray, $buf );
}

}	# end of Return M Recs


#-------------------------------------------------------#
#	Return S Recs
#-------------------------------------------------------#
sub ReturnSRecs
{
my( $reccnt ) = 0;
my( $buf ) = "";
my( $hashkey );

$buf = "";

# Header goes first
push( @G_ReturnArray, "\n" );
push( @G_ReturnArray, "\t***  Schedule Queue Records  ***\n" );
push( @G_ReturnArray, "\n" );
$buf = &SRecHeader();
push( @G_ReturnArray, $buf );

# Push each element in queue onto G_ReturnArray
foreach $hashkey ( sort keys( %S_SIDHash ) )
{
	$buf = &SRecString( $hashkey );
	push( @G_ReturnArray, $buf );
	$reccnt += 1;
}

push( @G_ReturnArray, "\n" );
if( $reccnt == 0 ) { $buf = "No records in schedule queue\n"; }
else { $buf = "$reccnt records in schedule queue\n"; }
push( @G_ReturnArray, $buf );

}	# end of Return S Recs


#-------------------------------------------------------#
#	Return T Recs
#-------------------------------------------------------#
sub ReturnTRecs
{
my( $reccnt ) = 0;
my( $buf ) = "";
my( $hashkey );

$buf = "";

# Header goes first
push( @G_ReturnArray, "\n" );
push( @G_ReturnArray, "\t***  Transaction Queue Records  ***\n" );
push( @G_ReturnArray, "\n" );
$buf = &TRecHeader();
push( @G_ReturnArray, $buf );

# Push each element in queue onto G_ReturnArray
foreach $hashkey ( sort keys( %T_TIDHash ) )
{
	$buf = &TRecString( $hashkey );
	push( @G_ReturnArray, $buf );
	$reccnt += 1;
}

push( @G_ReturnArray, "\n" );
if( $reccnt == 0 ) { $buf = "No records in transaction queue\n"; }
else { $buf = "$reccnt records in transaction queue\n"; }
push( @G_ReturnArray, $buf );

}	# end of Return T Recs


#-------------------------------------------------------#
#	Return D Recs
#-------------------------------------------------------#
sub ReturnDRecs
{
my( $p_keyhash ) = @_;
my( $reccnt, $buf, $did, $keyhashcnt );

$reccnt = 0;
$buf = "";
$keyhashcnt = scalar %$p_keyhash;

unless( $keyhashcnt ) {
	# Header goes first
	push( @G_ReturnArray, "\n" );
	push( @G_ReturnArray, "\t***  Dispatch Queue Records  ***\n" );
	push( @G_ReturnArray, "\n" );
	$buf = &DRecHeader();
	push( @G_ReturnArray, $buf );
}

# Push each element in queue onto G_ReturnArray
foreach $did ( sort keys( %D_DIDHash ) )
{
	$buf = &DRecString( $did, ($keyhashcnt)? $p_keyhash: undef );
	push( @G_ReturnArray, $buf );
	$reccnt += 1;
}

unless( $keyhashcnt ) {
	push( @G_ReturnArray, "\n" );
	push( @G_ReturnArray, ($reccnt == 0)? "No records in dispatch queue\n":
		"$reccnt records in dispatch queue\n");
}

}	# end of Return D Recs


#---------------------------------------------
#	Dump PPID Hash
#---------------------------------------------
sub DumpPPIDHash
{
my( $p_ppidhash, $pid ) = @_;
my( $ppid, $cpid, $p_hash );

# Dump ppidhash
foreach $ppid( sort keys %$p_ppidhash ){
	next if( defined($pid) && $ppid ne $pid );
	&LogMsg( "PARENT: $ppid\n" );
	$p_hash = $$p_ppidhash{$ppid};
	foreach $cpid( sort keys %$p_hash ) { 
		&LogMsg( "\tCHILD PID: $cpid ($$p_hash{$cpid})\n" ); 
	}
}

}	# end of Dump PPID Hash


#---------------------------------------------
#	Get Child PIDs
#---------------------------------------------
sub GetChildPIDs
{
my( $ppid, $p_pidhash, $p_ppidhash ) = @_;
my( $pid, $p_hash );

#&DumpPPIDHash( $p_ppidhash, $ppid );
return unless( defined $$p_ppidhash{$ppid} );

$p_hash = $$p_ppidhash{$ppid};
foreach $pid( sort keys %$p_hash ) {
	$$p_pidhash{$pid} = $$p_hash{$pid};
	&GetChildPIDs( $pid, $p_pidhash, $p_ppidhash );
}

}	# end of Get Child PIDs


#---------------------------------------------
#	Create Proc Hash
#---------------------------------------------
sub CreateProcHash
{
my( $pid, $p_pidhash ) = @_;
my( %ppidhash, %cpidhash, @arr, $line, $p_hash );

%$p_pidhash = ( );

# store output from ps into $buf
@arr = `$G_Config{NTPROCINFO} 2>&1`;
return( 1, "Error calling $G_Config{NTPROCINFO}\n" ) if( $? );

# For each line of output from ps -elo pid,args
foreach $line( @arr ) {
	# Format of line is "PID  PPID PROCESS_NAME  ..."
	next unless( $line =~ /\s*(\d+)\s+(\S+)\s+(.+)/ );
	$ppidhash{$2}{$1} = $3;
	$cpidhash{$1} = $3;
}

return( 0, "$pid does not exist\n" ) unless( defined $cpidhash{$pid} );

# Put PID in hash and assign to name of process
$$p_pidhash{$pid} = $cpidhash{$pid};

# Now check for any child processes
&GetChildPIDs( $pid, $p_pidhash, \%ppidhash );

return( 0, "Child processes of $pid successfully determined\n" );

}	# end of Create Proc Hash


#-------------------------------------------------------#
#	Kill Transaction
#-------------------------------------------------------#
sub KillTransaction
{
my( $ppid ) = @_;
my( %ProcHash, $pid, @arr, $err, $msg );

$err = 0;
$msg = "";
%ProcHash = ( );

($err, $msg) = &CreateProcHash( $ppid, \%ProcHash );
foreach $pid( sort keys %ProcHash ) {
	@arr = `$G_Config{NTPROCINFO} -k $pid 2>&1`;
	if( $? ) {
		$err = $?;
		$msg .= "Error killing PID $ProcHash{$pid} ($pid)\n";
	}
	else {
		$msg .= "Successfully killed PID $ProcHash{$pid} ($pid)\n";
	}
}

return( $err, $msg );

}	# end of Kill Transaction


#-------------------------------------------------------#
#	Check Running Trans
#-------------------------------------------------------#
sub CheckRunningTrans
{
my( $tid, $buf, $err, %ProcHash, $pid, $p_hash );

foreach $tid (sort keys %T_PIDHash )
{
	$pid = $T_PIDHash{$tid};

	# Delete it if set to "0"
#	unless( $pid eq "0" ) {
#		($err, $buf) = &KillTransaction( $pid );
#		&LogMsg( "$buf" );
#	}

	#&ResetDQTID( $tid );
	&ResetMQTID( $tid, $G_ResultHash{Q_RESTORED} );
	$buf = &DeleteTRec( $tid );

}	# end of foreach tid

}	# end of Check Running Trans


#-------------------------------------------------------#
#	Restore Q
#-------------------------------------------------------#
sub RestoreQ
{
# Set flag indicating we're restoring queues
$G_RestoringQ = 2;

# Restore all queues
#&RestoreFile( $G_Config{QSTOREDIR}, "$G_Config{DISPATCHSTORE}.new", "AddDRec" );
&RestoreFile( $G_Config{QSTOREDIR}, "$G_Config{MSGSTORE}.new", "AddMRec" );
&RestoreFile( $G_Config{QSTOREDIR}, "$G_Config{XACTIONSTORE}.new", "AddTRec" );
&RestoreFile( $G_Config{QSTOREDIR}, "$G_Config{SCHEDSTORE}.new", "AddSRec" );

$G_StoreQ = 0;
$G_RestoringQ = 1;

# Process message file for stragglers
&RestoreFile( $G_Config{QSTOREDIR}, "MsgFile.new" )
	if( -f "$G_Config{QSTOREDIR}/MsgFile.new" );

# No longer restoring queues
$G_RestoringQ = 0;

# Check if any transactions are still running
# Commented 06-20-99 by DSL.  Allow timeout policy to handle it...
&CheckRunningTrans( );

# Release messages pushed onto return array
@G_ReturnArray = ( );

# Reset all ASSIGNED messages...
&ResetAssignedMRecs( );

# Let's store what we got...
&StoreQ (($G_StoreQ)? 0: 1);

}	# end of Restore Q


#-------------------------------------------------------#
#	Reset Assigned M Recs
#-------------------------------------------------------#
sub ResetAssignedMRecs
{
my( $mid, $reason );

$reason = "Message assigned to action during EQ Server shutdown";
foreach $mid( keys %Q_MsgStatusHash ) 
{
#	next unless( $Q_MsgStatusHash{$mid} eq $ASSIGNED );
	next if( $Q_TIDHash{$mid} eq "0" );
	&ResetMQRec( $mid, $G_ResultHash{Q_RESTORED}, $FAILED, $reason );
}

}	# end of Reset Assigned M Recs


#-------------------------------------------------------#
#	Restore File
#-------------------------------------------------------#
sub RestoreFile
{
my( $dir, $filename, $msgtype ) = @_;
my( $fn, $msg, %hash, $v, $k);

$fn = "$dir/$filename";
if( -f $fn ) { open( TEMPFH, "$fn" ) || &LogMsg( "Can not open $fn", 1); }
else { open( TEMPFH, "+>$fn" ) || &LogMsg( "Can not open $fn\n", 1); }

open( TEMPFILE, "$fn" ) || &LogMsg( "Error opening $fn", 1);
while (defined($msg = <TEMPFILE>)) {
#	chomp( $msg );
	$msg = "$M_Key=$msgtype;$msg" 	if( $msg !~ /(^|;)$M_Key\s*=/i);
#	&ProcessMsg( "$msg\n" );
	&ProcessMsg( $msg );
}

close( TEMPFILE );

}	# end of Restore File


#-------------------------------------------------------#
#	Store Msg - write message to message file
#-------------------------------------------------------#
sub StoreMsg
{
my( $p_hash, $p_buf ) = @_;
my( $key, $val, $buf );

# Don't store messages while restoring the queue
if( $G_RestoringQ )
{
	$G_StoreQ = 1	if	($G_RestoringQ < 2);
	return;
}

# Put t_msg as first element in buffer
#$buf = "$M_Key=$$p_hash{$M_Key}";
#while( ($key, $val) = each( %$p_hash ) )
#{
#	if( $key ne $M_Key ) { $buf .= ";$key=\'$val\'"; }
#}

if	(defined ($p_buf))
{
	print MSGFILE $$p_buf, "\n";
}
else
{

$buf = "";
while( ($key, $val) = each( %$p_hash ) )
{
	$buf .= "$key=\'$val\';";
}
chop ($buf);

print MSGFILE "$buf\n";

}

$G_StoreQ = 1;

}	# end of Store Msg


#-------------------------------------------------------#
#	Rename Data Files
#-------------------------------------------------------#
sub RenameDataFiles
{
my( $fn, $max ) = @_;
my( $result, $file1, $file2, $oldver );

# First, remove the oldest file
$max -= 1;
$file1 = "${fn}.$max"; 
unlink( $file1 );

# Keep renaming until the 'new'est file is renamed
while( $max > 0 )
{
	$oldver = $max;
	$max -= 1;
	$file1 = "${fn}.$max"; 
	
	# Skip unless the file exists
	next unless( -f $file1 );
	$file2 = "${fn}.$oldver";
	$result = rename( $file1, $file2 );
	return( 1, "Error renaming $file1 to $file2: $!\n" ) if( $result == 0 );

}	# end of while

# Now, rename .new to .0
if	( -f "${fn}.new")
{
	$file2 = $file1;
	$file1 = "${fn}.new";
	$result = rename( $file1, $file2 );
	return( 1, "Error renaming $file1 to $file2: $!\n" ) if( $result == 0 );
}
return( 0, "" );

}	# end of Rename Data Files


#-------------------------------------------------------#
# 	Store Q
#-------------------------------------------------------#
sub StoreQ
{
my	($starting_eq) = @_;
my( $msgfile, $err, $msg, $fh );

&StoreDQ ($starting_eq);
&StoreTQ ($starting_eq);
&StoreMQ ($starting_eq);
&StoreSQ ($starting_eq);

# Close current msg file
close( MSGFILE );

# Rename message files since we synch queues
$msgfile = "$G_Config{QSTOREDIR}/MsgFile";
($err, $msg) = &RenameDataFiles( $msgfile, 10 );

# Open new msg file
open( MSGFILE, ">>${msgfile}.new" ) || &LogMsg( "Error opening '$msgfile.new': $!", 1);

# Enable AutoFlush
$fh = select( MSGFILE );
$| = 1;
select( $fh );

# No need to store queue at this time
$G_StoreQ = 0;

}	# end of Store Q


#-------------------------------------------------------#
# Store each hash that defines queue
#-------------------------------------------------------#
sub StoreDQ
{
my	($starting_eq) = @_;
my( $fn, $result );

# Rename storage file
$fn = "$G_Config{QSTOREDIR}/$G_Config{DISPATCHSTORE}";
return	if	(($starting_eq)&&(-f "$fn.new"));
$result = &StoreXQ( $fn, \%D_KeyDesc, \%D_DIDHash, "AddDRec" );
if( $result == 1 ) {
	$G_LastDQStore = time;
#	&LogMsg( "Dispatch Queue Successfully Stored: $G_LastDQStore\n" );
}
else {
	&LogMsg( "Error Storing Message Queue: $G_LastDQStore\n" );
}

}	# end of Store D Q


#-------------------------------------------------------#
# Store each hash that defines queue
#-------------------------------------------------------#
sub StoreMQ
{
my	($starting_eq) = @_;
my( $fn, $result );

# Rename storage file
$fn = "$G_Config{QSTOREDIR}/$G_Config{MSGSTORE}";
return	if	(($starting_eq)&&(-f "$fn.new"));
$result = &StoreXQ( $fn, \%Q_KeyDesc, \%Q_MIDHash, "AddMRec" );
if( $result == 1 ) {
	$G_LastMQStore = time;
#	&LogMsg( "Message Queue Successfully Stored: $G_LastMQStore\n" );
}
else {
	&LogMsg( "Error Storing Message Queue: $G_LastMQStore\n" );
}

}	# end of Store M Q


#-------------------------------------------------------#
# Store each hash that defines queue
#-------------------------------------------------------#
sub StoreSQ
{
my	($starting_eq) = @_;
my( $fn, $result );

# Rename storage file
$fn = "$G_Config{QSTOREDIR}/$G_Config{SCHEDSTORE}";
return	if	(($starting_eq)&&(-f "$fn.new"));
$result = &StoreXQ( $fn, \%S_KeyDesc, \%S_SIDHash, "AddSRec" );
if( $result == 1 ) {
	$G_LastSQStore = time;
#	&LogMsg( "Schedule Queue Successfully Stored: $G_LastSQStore\n" );
}
else {
	&LogMsg( "Error Storing Schedule Queue: $G_LastSQStore\n" );
}

}	# end of Store S Q


#-------------------------------------------------------#
# Store each hash that defines queue
#-------------------------------------------------------#
sub StoreTQ
{
my	($starting_eq) = @_;
my( $fn, $result );

# Rename storage file
$fn = "$G_Config{QSTOREDIR}/$G_Config{XACTIONSTORE}";
return	if	(($starting_eq)&&(-f "$fn.new"));
$result = &StoreXQ( $fn, \%T_KeyDesc, \%T_TIDHash, "AddTRec" );
if( $result == 1 ) {
	$G_LastTQStore = time;
#	&LogMsg( "Trans Queue Successfully Stored: $G_LastTQStore\n" );
}
else {
	&LogMsg( "Error Storing Trans Queue: $G_LastTQStore\n" );
}

}	# end of Store T Q


#-------------------------------------------------------#
# Store each hash that defines queue
#-------------------------------------------------------#
sub StoreXQ
{
my( $fn, $p_deschash, $p_mhash, $msgtype ) = @_;
my( $buf, $result, $mkey, $p_desc, $p_hash, $hash, $k, @p_deschash_values );
my( $maxver, $err, $msg );

# Open file for write.  Destroy if already exists
unless( open( TEMPFH, ">$fn.temp" ) ) {
	&LogMsg( "Can not open $fn.temp: $!\n" );
	return( 0 );
}

@p_deschash_values = values %$p_deschash;
# For each key in master hash, find matches and concatenate
#foreach $mkey ( sort keys( %$p_mhash ) ) {
foreach $mkey ( keys( %$p_mhash ) ) {
	$buf = "$M_Key=$msgtype";
	foreach $p_desc( @p_deschash_values )
	{
		$p_hash = $$p_desc{hashptr};
		# log error message if keyword not present, then set to defval

		if( !exists( $$p_hash{$mkey} ) )
		{
			&LogMsg( "Missing $$p_desc{keyword} for $mkey in StoreXQ\n" );
			&LogMsg( "Setting to default value ($$p_desc{defval})\n" );
			$$p_hash{$mkey} = $$p_desc{defval};
			$buf .= ";$$p_desc{keyword}=\'$$p_desc{defval}\'";
		}
		# otherwise, add keyword=value to string
		else {
			$buf .= ";$$p_desc{keyword}=\'$$p_hash{$mkey}\'";
		}
	}

	# write record to disk
	print TEMPFH "$buf\n";

}	# end of foreach mkey

# no more messages to store
close( TEMPFH );


# maintain file versions
$maxver = 10;
($err, $msg) = &RenameDataFiles( $fn, $maxver );
if( $err ) {
	&LogMsg( $msg );
	return( 0 );
}

# Now, rename .temp to .new
$result = rename( "${fn}.temp", "${fn}.new" );
if( $result == 0 )
{
	&LogMsg( "Error renaming '${fn}.temp' to '${fn}.new': $!" );
	return( 0 ); 
}

return( 1 );

}	# end of Store X Q


#-------------------------------------------------------#
# 	Sig Handler
#-------------------------------------------------------#
sub SigHandler
{
my( $sig ) = @_; #first argument is signal name

&LogMsg( "Caught SIG${sig}\n" );

if( ($sig eq "INT") || ($sig eq "TERM") )
{
	$G_Continue = 0;
}

# On NT, must re-establish signal handler
if( $OS eq $NT ) {
	$SIG{$sig} = 'SigHandler'; }

}	# end of Sig Handler


#-------------------------------------------------------#
# 	D Rec Header
#-------------------------------------------------------#
sub DRecHeader
{
my( $buf, $format );

$format = "%-12s\t%-25s\t%-12s\t%-s\t%-s\n";
$buf = sprintf( "$format", "DID", "Target", "TID", "PRIORITY", "ACTION" );
return( $buf );

}	# end of D Rec Header


#-------------------------------------------------------#
# 	D Rec String
#-------------------------------------------------------#
sub DRecString
{
my( $did, $p_keyhash ) = @_;
my( $buf, $format, $trans, $label, $action, $tid, $pri );
my( $p_desc, $p_hash, $kw );

if( defined($p_keyhash) ) {
	foreach $kw ( keys %$p_keyhash ) {
		next unless( $D_KeyDesc{$kw} );
		$p_desc = $D_KeyDesc{$kw};
		$p_hash = $$p_desc{hashptr};
		if( !defined($$p_hash{$did}) ) { $buf .= "$kw=;"; }
		else { $buf .= "$kw=$$p_hash{$did};"; }
	}
	chop($buf);
	$buf .= "\n";
}
elsif( $G_Config{RECDETAILS} == 0 )
{
	$action = "None";
	$tid = $D_TIDHash{$did};
	if( $tid ne "0" ) {
		$trans = $T_TransHash{$tid};
		$label = $T_ProfileHash{$tid};

		# Kludge to display script name for Script transaction
		if( $trans =~ /^EQScript|Script|EQPlan$/i ) {
			$label = $1 if( $T_AppArgsHash{$tid} =~ /script=([^;]*)/i );
		}

		$action  = "$trans";
		$action .= "\:$label" if( $label ne "" );
	}

	$format = "%-12s\t%-25s\t%-12s\t%-5s\t%-s\n";
	$buf = sprintf( "$format", $did, $D_TargetHash{$did}, $tid,
		$D_PriorityHash{$did}, $action );
}
else {
	foreach $p_desc (sort values %D_KeyDesc) {
		$kw = $$p_desc{keyword};
		$p_hash = $$p_desc{hashptr};
		if( !defined($$p_hash{$did}) ) { $buf .= "$kw=;"; }
		else { $buf .= "$kw=$$p_hash{$did};"; }
	}
	chop($buf);
	$buf .= "\n";
}

return( $buf );

}	# end of D Rec String


#-------------------------------------------------------#
# 	M Rec Header
#-------------------------------------------------------#
sub MRecHeader
{
my( $buf ) = "";

if( $G_Config{RECDETAILS} == 0 ) {
	$buf = sprintf( "%-12s  %-10s  %-10s  %-12s  %-10s  %-30s\n",
				"MID", "TRANS", "TARGET", "TID", "STATUS", "APPARGS" );
}

return( $buf );

}	# end of M Rec Header


#-------------------------------------------------------#
# 	M Rec String
#-------------------------------------------------------#
sub MRecString
{
my( $mid, $p_keyhash ) = @_;
my( $buf ) = "";
my( $p_desc, $p_hash, $kw );

if( defined($p_keyhash) ) {
	foreach $kw ( keys %$p_keyhash ) {
		next unless( $Q_KeyDesc{$kw} );
		$p_desc = $Q_KeyDesc{$kw};
		$p_hash = $$p_desc{hashptr};
		if( $kw eq $Q_AppArgsDesc{keyword} ) { $buf .= "$kw=\'$$p_hash{$mid}\';"; }
		elsif( !defined($$p_hash{$mid}) ) { $buf .= "$kw=;"; }
		elsif( !length($$p_hash{$mid}) ) { $buf .= "$kw=;"; }
		else { $buf .= "$kw=$$p_hash{$mid};"; }
	}
	chop($buf);
	$buf .= "\n";
}

elsif( $G_Config{RECDETAILS} == 0 ) {
	$buf = sprintf( "%-12s  %-10s  %-10s  %-12s  %-10s  %-s", $mid,
	$Q_TransHash{$mid}, $Q_TargetHash{$mid}, $Q_TIDHash{$mid},
	$Q_MsgStatusHash{$mid}, $Q_AppArgsHash{$mid} );
	if( length($Q_ProfileHash{$mid}) ) {
		$buf .= ";T_PROFILE=$Q_ProfileHash{$mid}"; }
	if( length($Q_TargetTypeHash{$mid}) ) {
		$buf .= ";T_TARGETTYPE=$Q_TargetTypeHash{$mid}"; }
	if( length($Q_ReasonHash{$mid}) ) {
		$buf .= ";T_REASON=$Q_ReasonHash{$mid}"; }
	$buf .= "\n";
}

else {
	foreach $p_desc (sort values %Q_KeyDesc) {
		$kw = $$p_desc{keyword};
		$p_hash = $$p_desc{hashptr};
		if( $kw eq $Q_AppArgsDesc{keyword} ) { $buf .= "$kw=\'$$p_hash{$mid}\';"; }
		elsif( !defined($$p_hash{$mid}) ) { $buf .= "$kw=;"; }
		elsif( !length($$p_hash{$mid}) ) { $buf .= "$kw=;"; }
		else { $buf .= "$kw=$$p_hash{$mid};"; }
	}
	chop($buf);
	$buf .= "\n";
}

return( $buf );

}	# end of M Rec String


#-------------------------------------------------------#
# 	S Rec Header
#-------------------------------------------------------#
sub SRecHeader
{
my( $buf, $format );

$format = "%-12s  %-20s  %-30s  %-s\n";
$buf = sprintf( "$format", "SID", "Trans", "Profile", "Scheduled Time" );
return( $buf );

}	# end of S Rec Header


#-------------------------------------------------------#
# 	S Rec String
#-------------------------------------------------------#
sub SRecString
{
my( $sid ) = @_;
my( $buf, $datetime, $format );
my( $sec, $min, $hr, $day, $mon, $yr );

($sec,$min,$hr,$day,$mon,$yr) = localtime( $S_UTSHash{$sid} );
$datetime = sprintf( "%04d/%02d/%02d  %02d:%02d:%02d", $yr+1900,$mon+1,$day,$hr,$min,$sec );

$format = "%-12s  %-20s  %-30s  %-s\n";
$buf = sprintf( "$format", $sid, $S_TransHash{$sid}, $S_ProfileHash{$sid}, $datetime );

return( $buf );

}	# end of S Rec String


#-------------------------------------------------------#
# 	T Rec Header
#-------------------------------------------------------#
sub TRecHeader
{
my( $buf ) = "";

if( $G_Config{RECDETAILS} == 0 ) {
	$buf = sprintf( "%-12s  %-10s  %-10s  %-5s  %-8s  %-30s\n",
	            "TID", "TRANS", "STATUS", "PID", "INVOKED", "APPARGS" );
}

return( $buf );

}	# end of T Rec Header


#-------------------------------------------------------#
# 	T Rec String
#-------------------------------------------------------#
sub TRecString
{
my( $tid, $sum ) = @_;
my( $buf ) = "";
my( $sec, $min, $hrs, $timebuf );
my( $p_desc, $p_hash, $kw, @a );

if( defined($sum) && $sum == 1 ) {
	$buf = sprintf( "%-12s  %-10s  %-10s\n", $tid,
      		  $T_TransHash{$tid}, $T_TranStatusHash{$tid} );
}

elsif( $G_Config{RECDETAILS} == 0 ) {
	(@a) = localtime( $T_InvokedTSHash{$tid} );
	$timebuf = sprintf( "%02d:%02d:%02d", $a[2], $a[1], $a[0] );

	$buf = sprintf( "%-12s  %-10s  %-10s  %-5s  %-8s  %-60s\n", $tid,
      		  $T_TransHash{$tid}, $T_TranStatusHash{$tid}, $T_PIDHash{$tid},
      		  $timebuf, $T_AppArgsHash{$tid} );
}
else {
	foreach $p_desc (sort values %T_KeyDesc) {
		$kw = $$p_desc{keyword};
		$p_hash = $$p_desc{hashptr};
		if( $kw eq $T_AppArgsDesc{keyword} ) { $buf .= "$kw=\'$$p_hash{$tid}\';"; }
		elsif( !defined($$p_hash{$tid}) ) { $buf .= "$kw=;"; }
		elsif( !length($$p_hash{$tid}) ) { $buf .= "$kw=;"; }
		else { $buf .= "$kw=$$p_hash{$tid};"; }
	}
	chop($buf);
	$buf .= "\n";
}

return( $buf );

}	# end of T Rec String


#-------------------------------------------------------#
#	Build Dup Excl List
#-------------------------------------------------------#
sub BuildDupExclList
{
my( $list, $item, @arr );

if( length($G_Config{DUPAPPARGSEXCL}) ) {
	$list = $G_Config{DUPAPPARGSEXCL};
	$list =~ s/ //g;
	@arr = split( /,/, $list );
}

foreach $item ( @arr ) {
	$G_DupAppArgsExcl{$item} = 1;
	#&LogMsg( "EXCLUDE KEY $item IN DUP CHECK\n" );
}

}	# end of Build Dup Excl List

#
# Build list of excluded IPs
#
sub	BuildExcludeIPList
{
	my	($s, @a, $l_ip1, $l_ip2);

	@G_ExcludeIPs = ();
	$s = $G_Config{"EXCLUDEIPS"} || return;
	# Get srray of IP ranges
	@a = split (",", $s);
	foreach $s (@a)
	{
		# If IP range is in format #.#.#.# - #.#.#.#
		if	($s =~ /^\s*(\d+)\.(\d+)\.(\d+)\.(\d+)\s*\-\s*(\d+)\.(\d+)\.(\d+)\.(\d+)\s*$/)
		{
			$l_ip1 = (($1 * 256 + $2) * 256 + $3) * 256 + $4;
			$l_ip2 = (($5 * 256 + $6) * 256 + $7) * 256 + $8;
		}
		# If range consist of one IP only
		elsif	($s =~ /^\s*(\d+)\.(\d+)\.(\d+)\.(\d+)\s*$/)
		{
			$l_ip1 = (($1 * 256 + $2) * 256 + $3) * 256 + $4;
			$l_ip2 = l_ip1;
		}
		elsif	($s !~ /^\s*$/)
		{
			&LogMsg( ("Invalid range '$s' was provided in 'EXCLUDEIPS' parameter " .
				 "in configuration file '" . $G_Config{"CONFIGFILE"} . "'\n"), 1);
		}
		else
		{
			next;
		}
		# Save beginning end end of range values.
		push (@G_ExcludeIPs, $l_ip1);
		push (@G_ExcludeIPs, $l_ip2);
	}
}


#-------------------------------------------------------#
#	Build Valid Client IP List
#-------------------------------------------------------#
sub BuildValidClientIPList
{
my( $s, @arr, $ip );

%G_ValidClientIP = ();
@G_ValidClientIPRange = ();
$G_ValidClientIP{$G_ServerIP} = 1	if	($G_ServerIP);
# Get IPs of all Managed Nodes
$s = "$xc_EQ_PATH/data/odlist.dat";
@arr = ( );
if	(-f $s)
{
	if	(open (ODLIST_FILE, "$s"))
	{
		@arr = <ODLIST_FILE>;
		close (ODLIST_FILE);
	}
	else
	{
		&LogMsg( "ERROR: Error reading file '$s': $!");
		@arr = ();
	}
}
elsif( $xc_TIVOLI_FWRK )
{
	@arr = `odadmin odlist`;
	if	($? != 0)
	{
		&LogMsg( ("ERROR: Error executing 'odadmin odlist' command: " . join ("", @arr)));
		@arr = ();
	}
}

foreach $ip( @arr ) {
	next if( $ip !~ /\s+(\d+\.\d+\.\d+\.\d+)\s+/ );
	$G_ValidClientIP{$1} = 1;
}

# Get IPs from configuration file
@arr = split (",", $G_Config{"VALIDCLIENTIPS"} );
foreach $s( @arr ) {

	$s =~ s/^\s+|\s+$//g;

	# If range consist of one IP only
	if	($s =~ /^\d+\.\d+\.\d+\.\d+$/)
	{
		$G_ValidClientIP{$s} = 2;
	}
	# If IP range is in format #.#.#.# - #.#.#.#
	elsif	($s =~ /^\s*(\d+)\.(\d+)\.(\d+)\.(\d+)\s*\-\s*(\d+)\.(\d+)\.(\d+)\.(\d+)\s*$/)
	{
		# Save beginning end end of range values.
		push (@G_ValidClientIPRange, (($1 * 256 + $2) * 256 + $3) * 256 + $4);
		push (@G_ValidClientIPRange, (($5 * 256 + $6) * 256 + $7) * 256 + $8);
	}
	else
	{
		&LogMsg( ("Invalid IP '$s' provided in 'VALIDCLIENTIPS' parameter " .
			 "in configuration file '" . $G_Config{"CONFIGFILE"} . "'\n"), 1);
	}
}
#
#&LogMsg( "Valid Clients include:\n" );
#foreach $ip( sort keys %G_ValidClientIP ) { &LogMsg( "\t$ip\n" ); }

}	# end of Build Valid Client IP List


#--------------------------------------------
#	Build Dispatch Var Hash
#--------------------------------------------
sub BuildDispatchVarHash
{
my( @arr, $line, %hash, $trans, $k, @keylist );

%G_DispatchVarHash = ( );
return unless( open( DVC, $G_Config{DISPATCHVARCFG} ) );
@arr = <DVC>;
close( DVC );

# Each line should contain T_TRANS=<trans>;T_KEYWORDS=<comma-seperated list of keywords>
while( $line = shift(@arr) ) {
	$line =~ s/^\s+|\s+$//g;
	next if( $line =~ /^\#/ );
	%hash = &HashMsg( \$line );
	next unless( $hash{T_TRANS} && $hash{T_KEYWORDS} );
	$trans = $hash{T_TRANS};
	@keylist = split( ",", $hash{T_KEYWORDS} );
	while( $k = shift(@keylist) ) {
		$k =~ s/^\s+|\s+$//g;
		$G_DispatchVarHash{$trans}{"\U$k"} = 1;
		$G_DispatchVarCount += 1;
	}

}

}	# end of Build Dispatch Var Hash


#--------------------------------------------
#	Set Env
#--------------------------------------------
sub SetEnv
{
my( $infile ) = @_;
my( $line, $var, $val );

open( IH, "$infile" ) || &LogMsg( "Error opening '$infile': $!\n", 1);

while (defined($line = <IH>)) {

	# skip blank lines and comments
	next if( $line =~ /^\s*$/ );
	next if( $line =~ /^\s*#/ );

	# remove leading and trailing blanks, and newline
	$line =~ s/^\s+|\s+$//g;
	chomp( $line );

	# split into variable and value, then store it
	if( $line =~ /(.*)=(.*)/ ) { $ENV{$1} = $2; }

}

close( IH );

}	# end of Set Env


#---------------------------------------------
#	Sched 2 UTS
#---------------------------------------------
sub Sched2UTS
{
my( $sched ) = @_;
my( $sec, $min, $hr, $day, $mon, $yr, $dow );
my( $uts, @arr, $isdst );

# Replace spaces in schedule string
$sched =~ s/\s+//g;

# sched format should be "yr:mon:day:hr:min:sec"
return( 0, "Invalid Schedule format: $sched" ) 
	# 04JUL99 9:30 AM -> 1999   :   07    :   04    :    9    :   30  :  00
	unless( $sched =~ /(\d{2,4}):(\d{1,2}):(\d{1,2}):(\d{1,2}):(\d{2}):(\d{2})/ );

$yr  = $1;
$mon = $2;
$day = $3;
$hr  = $4;
$min = $5;
$sec = $6 || 0;

$yr -= 1900 if( $yr > 1900 );
$yr += 100 if( $yr < 50 );
$mon -= 1;

# Get local time and set Daylight Saving Time flag (isdst)
# Logic flaw if scheduled time after change in dst, but with minimal affect
@arr = localtime( time );
$isdst = $arr[8];

use POSIX;
$uts = &POSIX::mktime( $sec, $min, $hr, $day, $mon, $yr, "", "", $isdst );

return ($uts, "");

}	# end of sched 2 uts


#---------------------------------------------
#	Check Time Limit Hash
#---------------------------------------------
sub CheckTimeLimitHash
{
my( $sched, $cur_status, $okay, $new_status );
my( $mid, $count, $msg_status, $err );

foreach $k( sort keys %G_TimeLimitHash ) {
	
	$cur_status = $G_TimeLimitHash{$k};
	
	# skip if no change in status
	($err, $okay) = &CheckTimeLimit( $k );
	next	if	($err);
	$new_status = ($okay ? $QUEUED : $RESTRICTED);
	next if( $new_status eq $cur_status );

	# set status of messages accordingly...
	$count = 0;
	foreach $mid( keys %Q_TimeLimitHash ) 
	{
		# Skip message not having this restriction
		next unless( $Q_TimeLimitHash{$mid} eq $k );
		$count += 1;
		$msg_status = $Q_MsgStatusHash{$mid};
		# Skip messages assigned or onhold
		next if( $msg_status eq $ASSIGNED || $msg_status eq $ONHOLD || $msg_status eq $SCHEDULED);
		$Q_MsgStatusHash{$mid} = $new_status;
		# Save the status into MgFile.new
		print MSGFILE "T_MSG='ModMRec';T_MID='$mid';T_MSGSTATUS='$new_status'\n"
			if	(!$G_RestoringQ);
		$G_StoreQ = 1	if	($G_RestoringQ < 2);
	}	

	# remove time limit record if no matching messages
	if( $count == 0 ) { delete( $G_TimeLimitHash{$k} ); }

	# otherwise, update the record accordingly
	else { $G_TimeLimitHash{$k} = $new_status; }

}

}	# end of Check Time Limit Hash


#---------------------------------------------
#	Add Time Limit Rec
#---------------------------------------------
sub AddTimeLimitRec
{
my( $sched ) = @_;
my( $k, $v, $okay, $status, $err );

foreach $k (keys %G_TimeLimitHash)
{
	return( 0, $G_TimeLimitHash{$k} ) if( $k eq $sched );
}

# see if within time restriction
($err, $okay) = &CheckTimeLimit( $sched );
return ($err, $okay)	if	($err);

# set status accordingly
$status = ($okay ? $QUEUED : $RESTRICTED);

# set and return status for setting message status
$G_TimeLimitHash{$sched} = $status;
return( 0, $status );

}	# end of Add Time Limit Rec


#---------------------------------------------
#	Check Time Limit
#---------------------------------------------
sub CheckTimeLimit
{
my( $restr ) = @_;
my( $now, @tm_now, $range, $start, $end, $startuts, $enduts, $err );

# get current time and create time array for it
$now = time( );
@tm_now = localtime( $now );
$tm_now[4]++;			# adjust month variable
$tm_now[5] += 1900;		# adjust year variable

# Process time restrictions string
while( $restr ne "" ) {

	# For each comma seperated range
	if( $restr =~ s/(.+?),// ) {
		$range = $1;
	}
	else {
		$range = $restr;
		$restr = "";
	}

	# parse range into start and end strings
	if( $range =~ s/(.+)-(.+)// ) {
		$start = $1;
		$end = $2;
	}
	else {
		$start = $range;
		$end = "";
	}

	($err, $startuts) = &Limit2UTS( $start, \@tm_now );
	return (1, $startuts)	if	($err);
	($err, $enduts) = &Limit2UTS( $end, \@tm_now );
	return (1, $enduts)		if	($err);

	return (0, 1)		if	($now >= $startuts && $now <= $enduts);

}

return( 0, 0 );

}	# end of Check Time Limit


#---------------------------------------------
#	Limit 2 UTS
#---------------------------------------------
sub Limit2UTS
{
my( $sched, $p_tmdef ) = @_;
my( $time, $sec, $min, $hr, $day, $mon, $yr );
my( $uts, @tmarr, $i );

$time = ":" . $sched;
# $sched format: '[YYYY:MM:DD:]hh:mm'
# Replace spaces in schedule string
$time =~ s/\s+//g;

$i = 0;
# build start time array, reversing the order
while( $time =~ s/^:(\*|\d+)// ) {
	unshift( @tmarr, $1 );
	$i++;
}

return (1, "Invalid time format '$sched'\n")
	if	(($i > 6)||($time !~ /^:?\s*$/));

# Make assumptions determining if secs not provided, then default to zero
if( $i == 2 || $i == 5 ) { unshift( @tmarr, 0 ); }

# set default values
for ($i = 0; $i < 6; $i++) {
	next if( defined($tmarr[$i]) && $tmarr[$i] ne "*" );
	$tmarr[$i] = $$p_tmdef[$i];
}

$yr  = $tmarr[5];
$mon = $tmarr[4];
$day = $tmarr[3];
$hr  = $tmarr[2];
$min = $tmarr[1];
$sec = $tmarr[0];

$yr -= 1900 if( $yr > 1900 );
$yr += 100 if( $yr < 50 );
$mon -= 1;

use POSIX;
$uts = &POSIX::mktime( $sec, $min, $hr, $day, $mon, $yr, "", "", -1 );

return( 0, $uts );

}	# end of Limit 2 uts


#---------------------------------------------
#	Check Expired Records
#---------------------------------------------
sub CheckExpiredRecords
{
my( $now );

$now = time( );

&CheckExpiredMIDs( ) if( $G_NextExpireMRec && $now > $G_NextExpireMRec );

&CheckExpiredDIDs( ) if( $G_NextExpireDRec && $now > $G_NextExpireDRec );

}	# end of Check Expired Records


#---------------------------------------------
#	Check Expired MIDs
#---------------------------------------------
sub CheckExpiredMIDs
{
my( @mids, $mid, $expire, $l_time, $err, $msg, @a );

# Get current time
$l_time = time ();

# Check for expired transactions in message queue
foreach $expire( sort keys %G_ExpireMHash )
{
	# Make sure it after expire time
	last unless( $l_time >= $expire );

	$mid = $G_ExpireMHash{$expire};
	
	# Get a list of MIDs associated with current timestamp
	@mids = split (/\s*,\s*/, $mid);
	foreach $mid( @mids )
	{
		# Make sure MID still exists
		next unless( exists($Q_TargetHash{$mid}) );
		
		$reason = "FATAL: Transaction expired. $Q_ReasonHash{$mid}";
		
		%hash = ( );
		$hash{T_MID} = $mid;
		$hash{T_TARGET} = $Q_TargetHash{$mid};
		$hash{T_RESULT} = "X";
		$hash{T_REASON} = $reason;
		($err, $msg) = &M_Status( \%hash );
	}
	
	delete $G_ExpireMHash{$expire};
}

@a = sort keys %G_ExpireMHash;
if( scalar(@a) == 0 ) { $G_NextExpireMRec = 0; }
else { $G_NextExpireMRec = $a[0]; }

}	# end of Check Expired MIDs


#---------------------------------------------
#	Check Expired DIDs
#---------------------------------------------
sub CheckExpiredDIDs
{
my( $expire, $l_time, @dids, $did, @new_dids, $err, $msg, @a );

# Get current time
$l_time = time ();

# Check for expired dispatch messages
foreach $expire( sort keys %G_ExpireDHash )
{
	# Make sure it's after expire time
	last unless( $l_time >= $expire );

	$did = $G_ExpireDHash{$expire};
	
	# Get a list of DIDs associated with current timestamp
	@dids = split (/\s*,\s*/, $did);
	@new_dids = ();
	foreach $did( @dids )
	{
		# Make sure DID is still in the queue
		next unless( $D_DIDHash{$did} );
		
		# Make sure there is no transaction running for this dispatch message
		if( $D_TIDHash{$did} eq "0" )
		{
			&DeleteDRec( $did );
			&LogMsg( "Dispatch message $did expired\n");
		}
		else
		{
			# Save it
			push( @new_dids, $mid );
		}
	}

	if( scalar(@new_dids) == 0 )
	{
		delete $G_ExpireDHash{$expire};
	}
	else
	{
		$G_ExpireDHash{$expire} = join (",", @new_mids);
	}
}

@a = sort keys %G_ExpireDHash;
if( scalar(@a) == 0 ) { $G_NextExpireDRec = 0; }
else { $G_NextExpireDRec = $a[0]; }

}	# end of Check Expired DIDs


#---------------------------------------------
#	Update Expiration Time Rec
#---------------------------------------------
sub UpdateExpirationTimeRec
{
my	($p_expire, $p_mid, $p_hash, $p_add, $p_nexttime ) = @_;
my	($l_time, @time_now, $err);

$l_time = $p_expire;
if	($p_expire !~ /^(\d+)$/)
{
	$err = &ConvertExpirationTime (\$l_time);
	return $err		if	($err);
}

if	($$p_hash{$l_time})
{
	# Add new message id?
	if	($p_add)
	{
		$$p_hash{$l_time} .= "," . $p_mid;
	}
	# Remove message id from the list
	else
	{
		$$p_hash{$l_time} =~ s/(^|,)$p_mid(,|$)/,/;
		$$p_hash{$l_time} =~ s/(^,|,$)//;
	}
}
# If we need to add new message id
elsif	($p_add)
{
	$$p_hash{$l_time} = $p_mid;
}

#$G_NextExpireMRec = $l_time if( $G_NextExpireMRec == 0 || $l_time < $G_NextExpireMRec ); 
$$p_nexttime = $l_time if( $$p_nexttime == 0 || $l_time < $$p_nexttime ); 

return "";

}	# end of Update Expiration Time Rec


#---------------------------------------------
#	Convert Expiration Time
#---------------------------------------------
sub	ConvertExpirationTime
{
my	($p_expire) = @_;
my	($l_time, $expire, @time_now, $err);

return ""	if	($$p_expire =~ /^\d+$/);
$l_time = time ();
# Time can be in relative format (+<seconds>) or absolute
# format (yyyy/mm/dd hh:mm:ss).
if	($$p_expire =~ /^\+(\d+)$/)
{
	$$p_expire = $1 + $l_time;
	return "";
}

$expire = $$p_expire;
$expire =~ s/^\s+//;
$expire =~ s/\s+$//;
$expire =~ s/\s+/:/g;
$expire =~ s#/+#:#g;
$expire =~ s/::+/:/g;

@time_now = localtime ($l_time);
$time_now[4]++;				# adjust month variable
$time_now[5] += 1900;		# adjust year variable

($err, $l_time) = &Limit2UTS ($expire, \@time_now);
return $l_time	if	($err);
$$p_expire = $l_time;

return "";
	
}	# end of Convert Expiration Time


###########################################
#
# Q_*Function functions.
# These functions are used to perform special
# processing of some transaction keywords.
# These functions should be specified in the
# ${$Q_KeyDesc{keyword}}=>function variable.
#
###########################################

#---------------------------------------------
#	Q Schedule Function
#---------------------------------------------
sub	Q_ScheduleFunction
{
my	($p_mid, $p_newvalue, $p_oldvalue, $p_hash) = @_;

# Check if a scheduled transaction
if	($Q_SIDHash{$p_mid} ne "0")
{
	$Q_MsgStatusHash{$p_mid} = $SCHEDULED;
	$Q_ReasonHash{$p_mid} = "Scheduled by " . $Q_EQUserHash{$p_mid} .
		" for $p_newvalue";
	if	($p_hash)
	{
		$$p_hash{T_MSGSTATUS} = $SCHEDULED;
		$$p_hash{T_REASON} = $Q_ReasonHash{$p_mid};
	}
}
elsif	($Q_MsgStatusHash{$p_mid} eq $SCHEDULED)
{
	# If transaction is restricted by time
	$Q_MsgStatusHash{$p_mid} = ($Q_TimeLimitHash{$p_mid})?
		($G_TimeLimitHash{$Q_TimeLimitHash{$p_mid}} || $QUEUED): $QUEUED;
	$Q_ReasonHash{$p_mid} = "Queued by " . $Q_EQUserHash{$p_mid}
		if	($Q_ReasonHash{$p_mid} =~ /^Scheduled by /i);
	if	($p_hash)
	{
		$$p_hash{T_MSGSTATUS} = $Q_MsgStatusHash{$p_mid};
		$$p_hash{T_REASON} = $Q_ReasonHash{$p_mid};
	}
}

return "";
	
}	# end of Q Schedule Function


#---------------------------------------------
#	Q Time Limit Function
#---------------------------------------------
sub Q_TimeLimitFunction
{
my	($p_mid, $p_newvalue, $p_oldvalue, $p_hash) = @_;
my	($err, $status);

# We don't care about old value - it will be removed by
# CheckTimeLimitHash routine when it finds out
# that old time restriction is not linked with any
# transaction.

# Check if time restricted transaction
if( $p_newvalue !~ /^\s*$/ )
{
	$p_newvalue =~ s/\s+//g;		# remove spaces
	# Check/Add TimeLimit record and set msg status accordingly
	($err, $status) = &AddTimeLimitRec( $p_newvalue );
	return	$status	if	($err);
	if	($Q_MsgStatusHash{$p_mid} ne $SCHEDULED)
	{
		$Q_MsgStatusHash{$p_mid} = $status;
		$$p_hash{T_MSGSTATUS} = $status		if	($p_hash);
	}
	$Q_TimeLimitHash{$p_mid} = $p_newvalue;
}
else
{
	if	($Q_MsgStatusHash{$p_mid} eq $RESTRICTED)
	{
		$Q_MsgStatusHash{$p_mid} = $QUEUED;
		$$p_hash{T_MSGSTATUS} = $QUEUED		if	($p_hash);
	}
}

return "";
	
}	# end of Q Time Limit Function


#---------------------------------------------
#	Q Job ID Function
#---------------------------------------------
sub Q_JobIDFunction
{
my( $mid, $newvalue, $oldvalue, $p_hash ) = @_;
my( $err, $status );

# Assume jobid okay if it starts with 10-digit UTS
return "" if( $newvalue =~ /^\d{10/ );

$$p_hash{T_JOBID}  = $G_Now;
$$p_hash{T_JOBID} .= " $newvalue" unless( $newvalue eq "" );

return "";
	
}	# end of Q JobID Function


#---------------------------------------------
#	Q Recd TS Function
#---------------------------------------------
sub Q_RecdTSFunction
{
my( $mid, $newvalue, $oldvalue, $p_hash ) = @_;
my( $err, $status );

# Assume rec'd ts okay if it starts with 10-digit UTS
return "" if( $newvalue =~ /^\d{10/ );

$$p_hash{T_RECDTS}  = time();

return "";
	
}	# end of Q JobID Function


#---------------------------------------------
#	Q Expire Function
#---------------------------------------------
sub Q_ExpireFunction
{
	my	($p_mid, $p_newvalue, $p_oldvalue) = @_;
	my	($s);

	if	($p_oldvalue ne "")
	{
		&UpdateExpirationTimeRec( $p_oldvalue, $p_mid, \%G_ExpireMHash, 0, \$G_NextExpireMRec );
	}

	if	($p_newvalue !~ /^\s*$/)
	{
		$s = &UpdateExpirationTimeRec( $p_newvalue, $p_mid, \%G_ExpireMHash, 1, \$G_NextExpireMRec );
		return $s	if	($s);
	}

	return "";
	
}	# end of Q Expire Function


#---------------------------------------------
#	Dump Special Arrays
#---------------------------------------------
sub DumpSpecialArrays
{
my( $mid, $tid, $did, $p_hash, $type, $target, $pri );

&LogMsg( "Q_TargetKeyHash\n" );
foreach $k( sort keys %Q_TargetKeyHash )
{
	&LogMsg( "\tKEY = $k\n" );
	$p_hash = $Q_TargetKeyHash{$k};
	foreach $mid( sort keys %$p_hash )
	{
		&LogMsg( "\t\tMID: $mid   TID: $$p_hash{$mid}\n" );
	}
	&LogMsg( "\n" );
}

&LogMsg( "Q_TID2MIDHash\n" );
foreach $tid( sort keys %Q_TID2MIDHash )
{
	&LogMsg( "\tTID = $tid\n" );
	$p_hash = $Q_TID2MIDHash{$tid};
	foreach $mid( sort keys %$p_hash )
	{
		&LogMsg( "\t\tMID: $mid   TID: $$p_hash{$mid}\n" );
	}
	&LogMsg( "\n" );
}

&LogMsg( "Q_TID2DIDHash\n" );
foreach $tid( sort keys %Q_TID2DIDHash )
{
	&LogMsg( "\tTID = $tid\n" );
	$p_hash = $Q_TID2DIDHash{$tid};
	foreach $did( sort keys %$p_hash )
	{
		&LogMsg( "\t\tDID: $did   TARGET: $$p_hash{$did}\n" );
	}
	&LogMsg( "\n" );
}

&LogMsg( "G_DispatchTargetHash\n" );
foreach $type( sort keys %G_DispatchTargetHash )
{
	&LogMsg( "\tType = $type\n" );
	$p_hash = $G_DispatchTargetHash{$type};
	foreach $target( sort keys %$p_hash )
	{
		&LogMsg( "\t\tTARGET: $target   DID: $$p_hash{$target}\n" );
	}
}

&LogMsg( "G_DispatchPriorityHash\n" );
foreach $pri( sort keys %G_DispatchPriorityHash )
{
	&LogMsg( "\tPRIORITY = $pri\n" );
	$p_hash = $G_DispatchPriorityHash{$pri};
	foreach $did( sort keys %$p_hash )
	{
		&LogMsg( "\t\tDID: $did   TARGET: $$p_hash{$did}\n" );
	}
	&LogMsg( "\n" );
}

&LogMsg( "Q_DupMIDKeyHash\n" );
foreach $k( sort keys %Q_DupMIDKeyHash )
{
	&LogMsg( "\tKEY: $k  T_MID: $Q_DupMIDKeyHash{$k}\n" );
}

&LogMsg( "Q_DupMIDKeyRevHash\n" );
foreach $k( sort keys %Q_DupMIDKeyRevHash )
{
	&LogMsg( "\tKEY: $k  T_MID: $Q_DupMIDKeyRevHash{$k}\n" );
}

&LogMsg( "G_CheckQueue" );
foreach $class( @G_CheckQueue )
{
	&LogMsg( "\tClass: $class" );
}

&LogMsg( "G_ClassContention" );
foreach $class( keys %G_ClassContention )
{
	&LogMsg( "\tCLASS: $class" );
}

$count = scalar(@G_CheckDispatchedTarget);
&LogMsg( "G_CheckDispatchedTarget Count: $count" );

}	# end of Dump Special Arrays
