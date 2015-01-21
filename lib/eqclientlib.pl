#!C:/dean/EQ-Working/EQServer/perl5/bin/perl
#
#	print '$Id: eqclientlib.pl,v 1.12 2014/11/07 00:13:19 eqadmin Exp $'

no utf8;
use Socket;
use IO::Socket;

sub	SendMsg;
sub	HashMsg;
sub	SendEQMsg;
sub	AlarmSigHandler;

sub	EQSockConn;
sub	EQSockClose;
sub	EQSockRequest;
sub	EQSockResponse;
sub	EQProcessResults;
sub	EQProcessTargetData;
sub	EQProcessLogFile;
sub	EQDumpTargetData;
sub	EQCheckMDistState;
sub	EQProcessMDistData;
sub	EQCheckTimeout;

sub	EQStartup;
sub	EQStatus;
sub	EQFinished;
sub	EQInfo;
sub	EQSendMsg;
sub	EQGenerateOptions;
sub	EQSterilizeMsg;
sub	EQStdResponse;
sub	EQLogArgs;
sub	EQLogMsg;
sub	EQCacheCmd;
sub	EQReadCacheFile;
sub	EQWriteCacheFile;
sub	EQDateOption;
sub	EQReadTargetFile;

sub	GWGetHash;
sub	GWMsgCheck;

sub	TFileLog;
sub	TFileRemoveTarget;
sub	TFileAppend;
sub	TFileReplace;

sub	EQGetMNOID;
sub	EQGetMNInterp;
sub	EQGetFileOffset;

sub	EQInitEnv;

$G_DefPort = 2345;

#---------------------------------------------------------------
# Send Msg
#---------------------------------------------------------------
sub SendMsg
{
my( $p_msg ) = @_;
my( $rc, @arr );

( $rc, @arr ) = &SendEQMsg( $p_msg );
if( $rc != 0 ) { 
	foreach( @arr ) { print "$0 $_"; } 
	exit( 1 );
}

}	# end of Send Msg


#-------------------------------------------------------#
#	Hash Msg
#-------------------------------------------------------#
sub HashMsg
{
my( $p_orig_buf, $p_hash ) = @_;
my( $buf, $key, $val, $k, %hash, $l_hash );

$buf = $$p_orig_buf;

# Strip leading spaces from input string
$buf =~ s/^\s+//g;

$l_hash = (defined ($p_hash))? $p_hash: \%hash;
%$l_hash = ();

# If the value is enclosed in quotes
if	($buf !~ s/^(['"])(.*)\1$/$2/)
{
	if	($buf =~ /^['"]/)
	{
		&EQLogMsg( "Unmatched quote passed to HashMsg\n");
		&EQLogMsg( "$$p_orig_buf\n" );
		return ((defined ($p_hash))? undef: %hash);
	}
}

#$buf =~ s/(?:^|;)\s*([^=;\s]+)\s*=\s*(?:(['"])(.*?)\2|(.*?))\s*(?=;|$)/$$l_hash{"\U$1"}=(defined ($2))? $3: $4; ";"/eg;
$buf =~ s/(?:^|;)\s*([^=;\s]+)\s*=\s*(?:(['"])(.*?)\2|(.*?))\s*(?=;|$)/$$l_hash{$1}=(defined ($2))? $3: $4; ";"/eg;

unless( $buf =~ /^;*$/ )
{
	$buf =~ s/^;+//;
	&EQLogMsg( "Invalid data passed to HashMsg: $buf\n")
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
#	Hash Msg Old
#-------------------------------------------------------#
sub HashMsgOld
{
my( $p_orig_buf, $p_hash ) = @_;
my( $buf, $key, $val );
my( %hash, $l_hash );

$buf = $$p_orig_buf;
chomp( $buf );

# Strip leading spaces only. Hash algorithm doesn't care about trailing spaces
$buf =~ s/^\s+//g;

# If the value is enclosed in quotes
if	($buf !~ s/^(['"])(.*)\1$/$2/)
{
	# Strip the first quote if there is no matching quote
	$buf =~ s/^['"]//;
}
$l_hash = (defined ($p_hash))? $p_hash: \%hash;
%$l_hash = ();

while ($buf =~ /(?:^|;)\s*([^=;\s]+)\s*=\s*(?:(['"])(.*?)\2|(.*?))\s*(?=;|$)/g)
{
#	$$l_hash{"\U$1"} = (defined ($2))? $3: $4;
	$$l_hash{$1} = (defined ($2))? $3: $4;
}
#$buf =~ s/(?:^|;)\s*([^=]+)\s*=\s*(?:(['"])(.*?)\2|(.*?))\s*(?=;|$)/$hash{$1}=(defined ($3))? $3: $4; ";"/eg;

return ((defined ($p_hash))? undef: %hash);

}	# end of Hash Msg Old


#----------------------------------------------------------------------
# Send response msg to EQServer
#----------------------------------------------------------------------
sub SendEQMsg
{
my( $p_msg, $host, $port, $maxattempts, $p_response ) = @_;
my( $OS, $NT, @ret_arr, $data, $s );
my( $SocketMaxAttempts ) = 15;
my( $SocketReadTimeout ) = 300;
my( $LAST_MSG ) = "THE END";

local( $RecdAlarm ) = 0;

$OS = $^O;
$NT = "MSWin32";

$SocketMaxAttempts = $maxattempts
	if	((defined ($maxattempts))&&($maxattempts =~ /^\d+$/));

if( !defined($host) || (length($host) == 0) ) {
	# First, try hostname command
	$host = `hostname 2>&1`; chomp($host);
	# Then, try environment variable set in env.cfg
	$host = $ENV{HOSTNAME} if( (length($host)==0 ) && (length($ENV{HOSTNAME})>0) );
	# Finally, try netbios name (NT only)
	$host = $ENV{COMPUTERNAME} if( (length($host)==0 ) && (length($ENV{COMPUTERNAME})>0) );
}

if( !defined($port) || (length($port) == 0) ) { $port = $G_DefPort; }

$p_response = 1	if	(!defined ($p_response));

while( 1 ) {
	$socket = IO::Socket::INET->new( PeerAddr => $host,   PeerPort => $port,
						   Proto    => 'tcp',   Type     => SOCK_STREAM );
	last if( $socket );
	$SocketMaxAttempts -= 1;
	if( $SocketMaxAttempts == 0 )
	{
		$s = $!;
		$s = "$^E"	if	($s =~ /^Unknown error$/i);
		return( 1, "Error creating new socket: $s" );
	}
	sleep( 1 );		# pause for a second
}

select($socket); $|=1; select( STDOUT );
print $socket "$$p_msg\n";

@ret_arr = ();
if	($p_response)
{
	# if not NT, set signal handler for SIG$ALARM
	if( $OS ne $NT ) { $SIG{ALRM}  = 'AlarmSigHandler'; }

	$data = "";
	while( 1 ) {
		if( $OS ne $NT ) { alarm( $SocketReadTimeout ); }	# set alarm
		$data = <$socket>;
		if( $RecdAlarm ) {
			push( @ret_arr, "Socket read timeout\n" );
			return( 1, @ret_arr );
		}
		if( $OS ne $NT ) { alarm( 0 ); }			# cancel alarm
		if( !defined( $data ) ) {
			push( @ret_arr, "Error reading socket" );
			return( 1, @ret_arr );
		}
		last if( $data =~ /${LAST_MSG}$/ );

		push( @ret_arr, $data );
	}
}

close( $socket );

# restore disposition of alarm signal
if( $OS ne $NT ) { $SIG{ALRM}  = "DEFAULT"; }

return( 0, @ret_arr );

}	#sub SendEQMsg


#----------------------------------------------------------------------
#	EQ Sock Conn
#----------------------------------------------------------------------
sub EQSockConn
{
my( $Host, $Port ) = @_;
my( $SocketMaxAttempts ) = 15;
my( $Socket, $OS, $NT );

$OS = $^O;
$NT = "MSWin32";

if( !defined($Host) || (length($Host) == 0) ) {
	# First, try hostname command
	$Host = `hostname 2>&1`; chomp($Host);
	# Then, try environment variable set in env.cfg
	$Host = $ENV{HOSTNAME} if( (length($Host)==0 ) && (length($ENV{HOSTNAME})>0) );
	# Finally, try netbios name (NT only)
	$Host = $ENV{COMPUTERNAME} if( (length($Host)==0 ) && ($OS eq $NT) );
}

if( !defined($Port) || (length($Port) == 0) ) { $Port = $G_DefPort; }

while( 1 ) {
	$Socket = IO::Socket::INET->new( PeerAddr => $Host,   PeerPort => $Port,
						   Proto    => 'tcp',   Type     => SOCK_STREAM );
	last if( $Socket );
	$SocketMaxAttempts -= 1;
	return( 0 ) if( $SocketMaxAttempts == 0 );
	sleep( 1 );		# pause for a second
}

select($Socket); $|=1; select( STDOUT );

return( $Socket );

}	#sub EQSockConn


#----------------------------------------------------------------------
#	EQ Sock Request
#----------------------------------------------------------------------
sub EQSockRequest
{
my( $Socket, $Msg ) = @_;

$Msg .= "\n" if( $Msg !~ /\n$/ );
print $Socket "$Msg\n"; 

return( "Sent $Msg to Socket\n" );

}	#sub EQSockRequest


#----------------------------------------------------------------------
#	EQ Sock Response
#----------------------------------------------------------------------
sub EQSockResponse
{
my( $Socket, $p_Arr ) = @_;
my( $OS, $NT, $data );
my( $SocketReadTimeout ) = 300;
my( $LAST_MSG ) = "THE END";
local( $RecdAlarm ) = 0;

$OS = $^O;
$NT = "MSWin32";

$data = "";
@$p_Arr = ( );
while( 1 ) {

	alarm( $SocketReadTimeout ) if( $OS ne "$NT" );	# set alarm
	$data = <$Socket>;
	if( $RecdAlarm ) {
		push( @$p_Arr , "Socket read timeout\n" );
		return( 1 );
	}
	alarm( 0 ) if( $OS ne "$NT" );				# cancel alarm
	if( !defined( $data ) ) {
		push( @$p_Arr , "Error reading socket" );
		return( 1 );
	}
	last if( $data =~ /${LAST_MSG}$/ );
	push( @$p_Arr, $data );
}

return( 0 );

}	#sub EQSockResponse


#----------------------------------------------------------------------
#	EQ Sock Close
#----------------------------------------------------------------------
sub EQSockClose
{
my( $Socket ) = @_;
my( $OS, $NT );

$OS = $^O;
$NT = "MSWin32";

close( $Socket );

# restore disposition of alarm signal
$SIG{ALRM}  = "DEFAULT" if( $OS ne $NT );

}	#sub EQSockClose


#----------------------------------------------------------------------
# Alarm Sig Handler
#----------------------------------------------------------------------
sub AlarmSigHandler
{
my( $signal ) = @_;

close( S );
$RecdAlarm = 1;
return;

}	# end of Alarm Sig Handler



##########  Added for SoftwarePackage and InventoryConfig Support  ##########



#------------------------------
#	EQ Process Results
#------------------------------
sub EQProcessResults
{
my( $p_prochash, $p_socket ) = @_;
my( $tid, $tfile, $logfile, $tailsecs, $mdistid, $mdistcheck, $logfunc, $debug );
my( $err, $msg, $i, $target, %tardatahash, @tararr, %gwhash, %masterhash, %masterstate );
my( $curtime, $lastmdistcheck );

$tfile = $$p_prochash{TFILE};
return( 1, "Error opening TFILE: '$tfile'" ) unless( open( TFILE, "$tfile" ) );
@tararr = <TFILE>;
close( TFILE );

# Remove target type from each target...
%masterhash = ( );
%masterstate = ( );
foreach $target( @tararr ) 
{ 
	$target =~ s/^\s+|\s+$//; 
	$target =~ s/^\@\S+:(.+)$/$1/; 
	next if( $target eq "" );
	$masterhash{$target} = "UNKNOWN";
	$masterstate{$target} = "";
}

# Return if no targets in hash
$i = (keys %masterhash); 
return( 0, "" ) if( $i == 0 );

# Get list of gateways for expired distributions
%gwhash = ( );
($err, $msg) = &GWGetHash( \%gwhash );
return( $err, "GWGetHash: $msg" ) if( $err );

# Keep processing logfile until all targets are resolved
$lastmdistcheck = 0;
%tardatahash = ( );

$tid = $$p_prochash{TID};
$mdistid = $$p_prochash{MDISTID};
$logfunc = $$p_prochash{LOGFUNC};
$logfile = $$p_prochash{LOGFILE};
$tailsecs = $$p_prochash{TAILSECS};
$mdistcheck = $$p_prochash{MDISTCHECK};
$debug = $$p_prochash{DEBUG};

while( 1 ) 
{
	&EQLogMsg( "TARGETS LEFT: $i  LOGFILE = '$logfile', OFFSET = $$p_prochash{OFFSET}" ) 
		if( $debug );

	# Store current time to compare with last mdist check
	$curtime = time();

	($err, $msg) = &EQProcessLogFile( $p_prochash, \%tardatahash );
	return( $err, "EQ Process Log File Error: $msg" ) if( $err );

	# Check for EQ Timeout 
	($err, $msg) = &EQCheckTimeout( $tid, $mdistid, \%masterhash, \%tardatahash, $p_socket );
	return( $err, "EQ Check Timeout: $msg" ) if( $err );
	&EQLogMsg( "$msg" ) if( $msg ne "" );

	# Dump the parsed data
	&EQDumpTargetData( \%tardatahash ) if( $debug );

	# First, process each gateway for timeout message, etc
	($err, $msg) = &GWMsgCheck( $mdistid, \%gwhash, \%tardatahash );
	return( $err, "GWMsgCheck: $msg" ) if( $err );

	# Next, process results for each target in array
	($err, $msg) = &EQProcessTargetData( $tid, $mdistid, \%masterhash, \%tardatahash, $p_socket );
	return( $err, "EQ Process Target Data: $msg" ) if( $err );

	# Now, get updated information from Tivoli using 'wmdist' command
	if( $mdistcheck > 0 && $lastmdistcheck <= ($curtime - $mdistcheck) ) 
	{
		$lastmdistcheck = time();
		($err, $msg) = &EQCheckMDistState( $p_prochash, \%masterstate, $p_socket );
		return( $err, "EQ Check MDist State: $msg" ) if( $err );
	}

	# Let's close the socket before continuing
	&EQSockClose( $$p_socket );
	$$p_socket = 0;

	# We're done, unless we're supposed to 'tail' the logfile
	last unless( $tailsecs );

	# We're done if no more targets to process
	$i = (keys %masterhash);
	last if( $i == 0 );

	sleep( $tailsecs );
}

return( 0, "" );

}	#sub EQProcessResults


#------------------------------
#	EQ Process Log File
#------------------------------
sub EQProcessLogFile
{
my( $p_prochash, $p_targethash ) = @_;
my( $logfunc, $logfile, $offset, $filesize, @data );
my( $err, $msg );

$logfunc = $$p_prochash{LOGFUNC};
$logfile = $$p_prochash{LOGFILE};
$offset = $$p_prochash{OFFSET};

# Make sure file exists.  Loop until it does.
return( 0, "$logfile does not exist" ) unless( -f $logfile );

$filesize = (-s $logfile);
return( 0, "Filesize equals Offset.  Nothing new to process." ) 
	if( $filesize == $offset );

# Open logfile, skip to offset, and read everything
return( 1, "Error opening $logfile" ) unless( open( FH, "$logfile" ) );
binmode( FH );
seek( FH, $offset, 0 );
@data = <FH>;
close( FH );

($err, $msg) = &$logfunc( $p_prochash, $p_targethash, \@data );
return( $err, "Logfile Process Results: $msg" );

}	#sub EQProcessLogFile


#------------------------------
#	EQ Process Target Data
#------------------------------
sub EQProcessTargetData
{
my( $tid, $mdistid, $p_masterhash, $p_tarhash, $p_socket ) = @_;
my( $err, $msg, $target, $result, $reason, $i );

foreach $target( keys %$p_tarhash ) 
{
	# Remove it unless its in the master target hash
	unless( exists($$p_masterhash{$target}) )
	{
		delete( $$p_tarhash{$target} );
		next;
	}

	# Found a matching target - skip if result not yet determined
	$result = $$p_tarhash{$target}{RESULT};
	$reason = $$p_tarhash{$target}{MSG};
	$reason =~ s/\s+$//;

	# if result and reason are blank or not defined, delete it
	if( (!defined($result) || $result eq "") &&
	    (!defined($reason) || $reason eq "") ) 
	{
		delete( $$p_tarhash{$target} );
		next;
	}

	# Got results, so let's send status message to EQ Server
	($err, $msg) = &EQStatus( $p_socket, $tid, $target, $result, $reason );
	return( $err, "EQStatus Error: $msg" ) if( $err );

	# Remove target from master hash and dynamic hash
	delete( $$p_masterhash{$target} );
	delete( $$p_tarhash{$target} );
}

return( 0, "" );

}	#sub EQProcessTargetData


#------------------------------
#	EQ Check MDist State
#------------------------------
sub EQCheckMDistState
{
my( $p_prochash, $p_masterstatehash, $p_socket ) = @_;
my( $tid, $mdistid, $interval );
my( $cmd, @arr, $err, $msg, $gw, @gwarr, %tarstatehash, $target, $state, $reason );

$tid = $$p_prochash{TID};
$mdistid = $$p_prochash{MDISTID};
$interval = $$p_prochash{MDISTCHECK};

# First, get a list of gateways and their corresponding MNs
$cmd = "wlookup -ar Gateway -L"; 
$err = &EQCacheCmd( $cmd, \@gwarr, 1 );
if( $err ) 
{
	$msg = join( "", @gwarr );
	&EQSterilizeMsg( \$msg );
	return( $err, $msg );
}

%tarstatehash = ( );
foreach $gw( @gwarr ) 
{
	$gw =~ s/^\s+|\s+$//g;
	next if( $gw eq "" );
	$cmd = "wmdist -I \"$gw\"";
	$err = &EQCacheCmd( $cmd, \@arr, 1, $interval );
	if( $err ) 
	{
		$msg = join( "", @arr );
		&EQSterilizeMsg( \$msg );
		return( $err, $msg );
	}
	&EQProcessMDistData( $p_prochash, $gw, \%tarstatehash, \@arr );
}

foreach $target( keys %tarstatehash )
{
	# Skip if not one of our targets
	next unless( exists($$p_masterstatehash{$target}) );

	# Extract the state
	$state = $tarstatehash{$target};

	# Skip it if the state hasn't changed
	next if( defined($$p_masterstatehash{$target}) &&
			$$p_masterstatehash{$target} eq "$state" );

	# Parse the state to separate out the gateway
	next unless( $state =~ /^([^:]+):(.+)$/ );

	# Let's update the reason
	$reason = "MDist ID: $mdistid   State: $2   Via GW: $1";
	($err, $msg) = &EQStatus( $p_socket, $tid, $target, "", $reason );
	return( $err, "EQStatus Error: $msg" ) if( $err );

	# Store the state for next time
	$$p_masterstatehash{$target} = $state;
}

return( 0, "" );

}	#sub EQCheckMDistState


#------------------------------
#	EQ Process MDist Data
#------------------------------
sub EQProcessMDistData
{
my( $p_prochash, $gw, $p_tarhash, $p_datarr) = @_;
my( $line, $curmdistid, $mdistid );

$mdistid = $$p_prochash{MDISTID};

$curmdistid = -1;
foreach $line( @$p_datarr ) 
{
	$line =~ s/^\s+|\s+$//g;
	next if( $line eq "" );

	# See if line contains our distribution ID
	if( $line =~ /$mdistid/ ) 
	{
		$curmdistid = $mdistid;
		next;
	}

	# We're done if data for new dist and we've already processed ours
	elsif( $line =~ /=== Distribution Information ===/i ) 
	{
		last if( $curmdistid eq $mdistid );
	}

	# Skip every line not pertaining to our distribution
	next unless( $curmdistid eq $mdistid );

	# Must be our distribution.  Only process lines with target status
	next unless( $line =~ /^Target:\s+(.+)\s+State:\s+(.*)$/i );
	$$p_tarhash{$1} = "$gw:$2";
}

}	#sub EQProcessMDistData


#------------------------------
#	EQ Check Timeout
#------------------------------
sub EQCheckTimeout
{
my( $tid, $mdistid, $p_masterhash, $p_tardatahash, $p_socket ) = @_;
my( $target, $result, $msg );

return( 0, "" ) unless( defined($$p_tardatahash{EQTIMEOUT}) );

$result = $$p_tardatahash{EQTIMEOUT}{RESULT};
return( 0, "EQ Timeout Error: T_TID not provided" ) unless( defined($result) );
return( 0, "Received EQ Timeout for another T_TID: $result" ) unless( $result eq $tid );

$msg = $$p_tardatahash{EQTIMEOUT}{MSG} || "EQ Timeout Expired";
foreach $target( keys %$p_masterhash ) 
{
	# Skip target if something else found...
	next if( defined( $$p_tardatahash{$target} ) && 
				$$p_tardatahash{$target}{RESULT} ne "" &&
				$$p_tardatahash{$target}{RESULT} ne $mdistid );
	$$p_tardatahash{$target}{RESULT} = 1;
	$$p_tardatahash{$target}{MSG} = $msg;
}

return( 0, "EQ Timeout Received" );

}	#sub EQCheckTimeout


#------------------------------
#	EQ Update Target Status
#------------------------------
sub EQUpdateTargetStatus
{
my( $tid, $tfile, $reason, $p_socket ) = @_;
my( @tararr, $target, $err, $msg );

return( 1, "Error opening TFILE: '$tfile'" ) unless( open( TFILE, "$tfile" ) );
@tararr = <TFILE>;
close( TFILE );

# Remove target type from each target...
foreach $target( @tararr ) 
{ 
	$target =~ s/^\s+|\s+$//; 
	next unless( $target =~ s/^\@\S+:(.+)$/$1/ ); 

	# Now, update target status
	($err, $msg) = &EQStatus( $p_socket, $tid, $target, "", $reason );
	return( $err, $msg ) if( $err );
}

return( 0, "" );

}	#sub EQUpdateTargetStatus


#------------------------------
#	EQ Dump Target Data
#------------------------------
sub EQDumpTargetData
{
my( $p_tarhash ) = @_;
my( $target, $result, $reason );

$count = scalar (keys %$p_tarhash) ;

&EQLogMsg( "Dump Target Data Count: $count" ) if( $count > 0 );
foreach $target( keys %$p_tarhash ) 
{
	$result = $$p_tarhash{$target}{RESULT};	
	$reason = $$p_tarhash{$target}{MSG};	
	&EQLogMsg( "TARGET: '$target'  RESULT: '$result'" );
	&EQLogMsg( "MSG: \n$reason" );
}

}	#sub EQDumpTargetData


#-----------------------------------------
#	EQ Startup
#-----------------------------------------
sub EQStartup
{
my( $arguments, $p_ArgDefinitions ) = @_;
my( %MsgHash, $msg, $result, $k, $p_deschash );
my( $p_value, $defval, $reqdflag, $tid );

$msg = "";
$result = 0;

# Parse arguments and set tid
%MsgHash = &HashMsg( \$arguments );
$tid = $MsgHash{T_TID};

# Send startup message to EQ Server
unless( defined( $tid ) ) 
{
	&SendMsg( \"T_MSG=STARTED;T_RESULT=1;T_PID=$$;T_TID=UNKNOWN;T_REASON=Missing T_TID argument" );
	return( 1, "T_TID is not provided in argument list." );
}


foreach $k( keys %$p_ArgDefinitions ) 
{
	# initialize some vars
	$p_deschash = $$p_ArgDefinitions{$k};
	$p_var = $$p_deschash{varptr};
	$defval = $$p_deschash{default};
	$$p_var = $defval;

	# Get passed value
	if( defined($MsgHash{$k}) ) 
	{
		$$p_var = $MsgHash{$k};
		next;
	}

	# Not passed in, so check if required
	$reqdflag = $$p_deschash{required};
	if( $reqdflag ) 
	{
 		$result = 1;
		$msg = "Invalid Startup Arguments.  Missing " if( $msg eq "" );
		$msg .= "'$k' ";
	}

}

# Send startup message to EQ Server
&SendMsg( \"T_MSG=STARTED;T_RESULT=$result;T_PID=$$;T_TID=$tid;T_REASON=$msg" );

return( $result, $msg );

}	#sub EQStartup


#-----------------------------------------
#	EQ Status
#-----------------------------------------
sub EQStatus
{
my( $p_S, $tid, $target, $result, $reason, $state ) = @_;
my( $msg, $err, @arr );

# Establish socket connection if need be
unless( $$p_S ) 
{
	$$p_S = &EQSockConn( );
	return( 1, "Error opening socket to EQServer. ABORTING", 0 ) if( !$$p_S );
}

# Ensure $reason is suitable for EQ Server
&EQSterilizeMsg( \$reason );
$msg =  "T_MSG=STATUS;T_TID=$tid;T_TARGET=$target;T_REASON=\"$reason\"";
$msg .= ";T_RESULT=$result" if( $result =~ /\d+/ );
$msg .= ";T_MSGSTATUS=$state" if( $state );

$err = &EQSockRequest( $$p_S, $msg ); 
$err = &EQSockResponse( $$p_S, \@arr );
return( $err, @arr );

}	#sub EQStatus


#-----------------------------------------
#	EQ SendMsg
#-----------------------------------------
sub EQSendMsg
{
my( $p_S, $eqmsg ) = @_;
my( $msg, $err, @arr );

# Establish socket connection if need be
unless( $$p_S ) 
{
	$$p_S = &EQSockConn( );
	return( 1, "Error opening socket to EQServer. ABORTING", 0 ) if( !$$p_S );
}

$err = &EQSockRequest( $$p_S, $eqmsg ); 
$err = &EQSockResponse( $$p_S, \@arr );
return( $err, @arr );

}	#sub EQSendMsg


#-----------------------------------------
#	EQ Info
#-----------------------------------------
sub EQInfo
{
my( $p_S, $tid, $target, $result, $reason ) = @_;
my( $msg, $err, @arr );

# Establish socket connection if need be
unless( $$p_S ) 
{
	$$p_S = &EQSockConn( );
	return( 1, "Error opening socket to EQServer. ABORTING", 0 ) if( !$$p_S );
}

$msg = "T_MSG=INFO;T_TID=$tid;T_TARGET=$target;T_RESULT=$result;T_REASON=$reason";

$err = &EQSockRequest( $$p_S, $msg ); 
$err = &EQSockResponse( $$p_S, \@arr );
return( $err, @arr );

}	#sub EQInfo


#-----------------------------------------
#	EQ Finished
#-----------------------------------------
sub EQFinished
{
my( $p_S, $tid, $profile ) = @_;
my( $msg, $err, @arr );

# Establish socket connection if need be
unless( $$p_S ) 
{
	$$p_S = &EQSockConn( );
	return( 1, "Error opening socket to EQServer. ABORTING", 0 ) if( !$$p_S );
}

$msg = "T_MSG=Finished;T_TID=$tid;T_PID=$$;T_RESULT=0";

$err = &EQSockRequest( $$p_S, $msg ); 
$err = &EQSockResponse( $$p_S, \@arr );

&EQSockClose( $$p_S );
return( $err, @arr );

}	#sub EQFinished


#------------------------------
#	EQ Generate Options
#------------------------------
sub EQGenerateOptions
{
my( $p_argdesc, $p_order ) = @_;
my( $k, $p_desc, $options, $var, $code );

$options = "";
foreach $k( @$p_order ) 
{
	next unless( exists($$p_argdesc{$k}) );
	$p_desc = $$p_argdesc{$k};
	$var = ${$$p_desc{varptr}};
	$code = $$p_desc{optcode};
	next unless( defined($code) );
	eval($code);
}

return( $options );

}	#sub EQGenerateOptions


#------------------------------
#	EQ Sterilize Msg
#------------------------------
sub EQSterilizeMsg
{
my( $p_msg ) = @_;

# Truncate Canned Error messages...
$$p_msg =~ s/\n/ /g;
$$p_msg =~ s/Summary of possible error conditions:.*$//s;
$$p_msg =~ s/Please refer.*$//g;

$$p_msg =~ s/[\x01-\x1F\x7F-\xFF]//g;
$$p_msg =~ s/"/'/g;
$$p_msg =~ s/;/:/g;

}	#sub EQSterilizeMsg


#------------------------------
#	EQ Std Response
#------------------------------
sub EQStdResponse
{
my( $p_socket, $tfile, $rc, $errmsg, $profile, $tid ) = @_;
my( $target, $msg, $len, $MSGMAXLEN, @arr, $err, $s );

$errmsg =~ s/\r//g;
$errmsg =~ s/\n/  /g;

#&EQLogMsg( "EQStdResponse: $errmsg" );

$MSGMAXLEN = $xc_ERROR_LENGTH || 1024;
$len = (length($errmsg) > $MSGMAXLEN)? $MSGMAXLEN: length($errmsg);

$msg = substr( $errmsg, 0, $len );

# Read targets from file
open( TFILE, "$tfile" );
@arr = <TFILE>;
close( TFILE );

# Send status message for each target
foreach $target( @arr ) 
{
	# remove target type information
	$target =~ s/\s+$//;
	$target =~ s/^\@\S+:(.+)$/$1/;
#	&EQLogMsg( "Sending Status Message for '$target'\n" );
	($e, $s) = &EQStatus( $p_socket, $tid, $target, $rc, $msg );
	&EQLogMsg( "Error Sending EQ Status Msg for '$target': $s" ) if( $e );
}

# Send transaction finished message to EQ Server
&EQFinished( $p_socket, $tid, $profile );

# Remove tfile before exiting
unlink( $tfile ) unless( $G_Debug );
exit (0);

}	#sub EQStdResponse


#-----------------------------------------
#	EQ Log Args
#-----------------------------------------
sub EQLogArgs
{
my( $p_ArgDefinitions ) = @_;
my( $k, $p_deschash, $p_var );

foreach $k( sort keys %$p_ArgDefinitions ) 
{
	# initialize some vars
	$p_deschash = $$p_ArgDefinitions{$k};
	$p_var = $$p_deschash{varptr};
	&EQLogMsg( "$k = '$$p_var'" );
}

}	#sub EQLogArgs


#-----------------------------------------
#	EQ Log Msg
#-----------------------------------------
sub EQLogMsg
{
my( $msg, $err ) = @_;
my( @arr, $ts );

@arr = localtime( time );
$ts = sprintf( "%04d-%02d-%02d  %02d:%02d:%02d", 
		    $arr[5]+1900, $arr[4]+1, $arr[3], $arr[2], $arr[1], $arr[0] );

$msg =~ s/\n+$/\n/;
print EQLOG "$ts ($$) $msg\n";
print "$msg\n";

exit( $err ) if( defined($err) && $err > 0 );

}	# end of EQ Log Msg


#-----------------------------------------------------------
#	EQ Cache Cmd
#-----------------------------------------------------------
sub EQCacheCmd
{
my( $cmd, $p_arr, $cache, $expiration ) = @_;
my( $err, $s, $i, $file);

$cache = 0 if( !defined($cache) );
$file = $cmd;
@$p_arr = ();

&EQLogMsg( "TRACECMD (cache flag=$cache): $cmd" ) if( $G_Config{TRACECMD} );

# If it's OK to read data from cache
if( $cache ) 
{
	# Get data from cache if possible
	$err = &EQReadCacheFile( $file, $p_arr, $expiration );
	unless( $err )
	{
		if( $G_Config{TRACECMD} == 2 )
		{
			foreach $s( @$p_arr ) { &EQLogMsg( $s ); }
		}
		return( 0 );
	}
}

# Execute command locally
@$p_arr = `$cmd 2>&1`;
$err = $?;
if( $err ) 
{
	unshift( @$p_arr, "Error executing $cmd: $err\n" );
	return 1;
}

if( $G_Config{TRACECMD} == 2 )
{
	foreach $s( @$p_arr ) { &EQLogMsg( $s ); }
}

# Write cache file
&EQWriteCacheFile( $file, $p_arr, "" );

return 0;

}	# end of EQ Cache Cmd


#-----------------------------------------------------------
#	EQ Read Cache File
#-----------------------------------------------------------
sub EQReadCacheFile
{
my( $file, $p_arr, $expire ) = @_;
my( $s, @l_rcf_data, %l_config, $err );

# After how many seconds data in cache file will expire
my( $X_CACHE_EXPIRATION ) = 1800;

# Generate valid file name from user's string (usually it's a command).
$s = "$xc_EQ_PATH/temp/temp." . unpack ("H*", $file) . ".cache";

# return if file doesn't exist 
return( 1 ) unless( -f $s );

$expire = $X_CACHE_EXPIRATION 
	unless( defined($expire) && $expire =~ /^\d+$/ );

# return if file older than expiration
@l_rcf_data = stat( $s );
return( 1 ) if( (time() - $l_rcf_data[9]) > $expire );

# return if error opening cache file
return( 1 ) unless( open( CACHE_FILE, $s ) );

@$p_arr = ();
# Read contents of file
while( $s = <CACHE_FILE> ) 
{
	$s =~ s/\s+$//;
	push (@$p_arr, $s);
}

close (CACHE_FILE);
return 0;

}	#sub EQReadCacheFile


#-----------------------------------------------------------
#	EQ Write Cache File
#-----------------------------------------------------------
sub EQWriteCacheFile
{
my( $file, $p_arr, $sep) = @_;
my( $s );

# Generate valid file name from user's string (usually it's a command).
$s = "$xc_EQ_PATH/temp/temp." . unpack ("H*", $file) . ".cache";
if	(open (CACHE_FILE, ">$s")) 
{
	print CACHE_FILE join ($sep, @$p_arr);
	close (CACHE_FILE);
}

}	#sub EQWriteCacheFile


#------------------------------
#	EQ Date Option
#------------------------------
sub EQDateOption
{
my( $date, $p_options, $optstr, $p_quotes ) = @_;
my( $secs, @arr, %x_coeff );

# Strip leading/trailing spaces and return if blank
$date =~ s/^\s+|\s+$//g;
return if( $date eq "" );

if( $date =~ /\d\d\/\d\d\/\d\d\d\d \d\d:\d\d/ )
{
	$$p_options .= " $optstr" . (($p_quotes)? "\"$date\"": $date);
	return;
}

%x_coeff = ( s => 1, m => 60, h => 3600, d => 86400 );

$date =~ s/^\+*\s*//;
# Check for relative times
$secs = 0;
my $v;
while( $date =~ s/^(\d+)\s*([smhd])\s*//i ) 
{
	$v = $2;
	$v =~ tr/A-Z/a-z/;
	$secs += ($1 * $x_coeff{$v}); 
}

# See if any left over digits.  Default to seconds
$secs += $1 if( $date =~ s/^(\d+)$// );

# Convert to date format
@arr = localtime( (time() + $secs) );
$date = sprintf( "%02d/%02d/%04d %02d:%02d", $arr[4] + 1, $arr[3], $arr[5] + 1900, $arr[2], $arr[1] );

# Update option
$$p_options .= " $optstr" . (($p_quotes)? "\"$date\"": $date);

}	#sub EQDateOption


#-----------------------------------------
#	EQ Read Target File
#-----------------------------------------
sub EQReadTargetFile
{
my( $file, $targettype, $p_targets ) = @_;
my( @arr, $t, $rc );

return( 1, "Error opening '$file'" ) unless( open(TH,$file) );

@arr = <TH>;
close( TH );

$$p_targets = "";
foreach $t( @arr )
{
	$t =~ s/^\s+|\s+$//g;
	next if( $t eq "" );
	$t =~ s/^$targettype://;
	$$p_targets .= "$t,";
}

# Remove trailing comma
$$p_targets =~ s/,+$//;

$rc = length($$p_targets) > 0 ? 0 : 1;

return( $rc, "No Targets Left in Target File" );

}	#sub EQReadTargetFile


#------------------------------
#	TFile Log 
#------------------------------
sub TFileLog
{
my( $file, $s ) = @_;
my( @arr, $line );

open( TFILE, $file );
@arr = <TFILE>;
close( TFILE );

&EQLogMsg( $s );
foreach $line( @arr ) 
{
	$line =~ s/^\s+|\s+$//g;
	&EQLogMsg( "TFileLog: '$line'" );
}

}	#sub TFileLog 


#------------------------------
#	TFile Remove Target
#------------------------------
sub TFileRemoveTarget
{
my( $tfile, $tartype, $bad_target, $p_count ) = @_;
my( @tararr, $target, $err, $msg, $changed );

$changed = "";
@tararr = ();
# Search for this target in our tfile
open( TFILE, "$tfile" ) ||
	return (1, "Cannot open file '$tfile': $!");
while (defined ($target = <TFILE>))
{
	$target =~ s/\s+$//;
	next	if	($target eq "");
	# Skip ones that don't match bad target
	if	($target =~ /$tartype:$bad_target$/)
	{
		$changed = 1;
		next;
	}
	push (@tararr, $target);
}
close( TFILE );

# Set count variable
$$p_count = @tararr;

return (2, "Cannot remove target '$bad_target' from the list - operation aborted to avoid potential infinite loop")
	if	($changed == 0);

# Re-Write target file without "bad" target
($err, $msg) = &TFileReplace( $tfile, "", \@tararr );
return( $err, $msg );

}	#sub TFile Remove Target


#------------------------------
#	TFile Append 
#------------------------------
sub TFileAppend
{
my( $tfile, $targettype, $targets ) = @_;
my( $target, @arr, %hash );

%hash = ( );

open( TFILE, "$tfile" );
@arr = <TFILE>;
close( TFILE );

foreach $target( @arr ) 
{ 
	$target =~ s/^\s+|\s+$//g;
	$target =~ s/$targettype:(.+)$/$1/;
	# Use hash to ensure no dups
	$hash{$target} = 1;
}

@arr = split( /,/, $targets );
foreach $target( @arr ) 
{ 
	$target =~ s/^\s+|\s+$//g;
	$target =~ s/$targettype:(.+)$/$1/;
	$hash{$target} = 1;
}

open( TFILE, ">$tfile" );
foreach $target( sort keys %hash ) 
{ 
	next if( $target eq "" );
	print TFILE "$targettype:$target\n"; 
}

close( TFILE );

}	#sub TFileAppend 


#------------------------------
#	TFile Replace 
#------------------------------
sub TFileReplace
{
my( $tfile, $targettype, $p_targetarr ) = @_;
my( $target );

# Delete file
unlink ($tfile);

# Open new file
open (TFILE, ">$tfile") || return( 1, "Error creating file '$tfile': $!" );

# Write each target to file
foreach $target (@$p_targetarr) 
{ 
	next if( $target eq "" || $target eq "$targettype:" );
	# Include targettype if provided
	if( $targettype eq "" ) { print TFILE "$target\n"; }
	else { print TFILE "$targettype:$target\n"; }
}

# Close file and return
close (TFILE);
return( 0, "" );

}	#sub TFileReplace


#------------------------------
#	GW Msg Check
#------------------------------
sub GWMsgCheck
{
my( $mdistid, $p_gwhash, $p_tarhash ) = @_;
my( $err, $msg, $cmd, $result, $reason, $gw, @gwarr, $target );

foreach $gw( keys %$p_gwhash ) 
{
	next unless( $$p_tarhash{$gw} );
	# Found a matching gateway!
	$result = $$p_tarhash{$gw}{RESULT};
	$reason = $$p_tarhash{$gw}{MSG};
	# Skip unless reason contains distribution ID...
	next unless( $reason =~ /$mdistid/ );
	# Skip unless reason contains GW OID...
	next unless( $reason =~ /$$p_gwhash{$gw}/ );
	# Something reporting regarding this distro on this gateway...
	# So, add entry to tarhash for each EP on reporting GW
	$cmd = "wep ls -g \"$gw\" -i label";
	$err = &EQCacheCmd( $cmd, \@gwarr, 1 );
	if( $err ) 
	{
		$msg = join( "", @gwarr );
		&EQSterilizeMsg( \$msg );
		return( $err, $msg );
	}
	foreach $target( @gwarr ) 
	{
		$target =~ s/^\s+|\s+$//g;	# strip leading/trailing spaces
		# Skip target that already have an entry in the target hash
		next if( exists($$p_tarhash{$target}) );
		# Otherwise, add an entry using result and reason from gw entry
		$$p_tarhash{$target}{RESULT} = $result;
		$$p_tarhash{$target}{MSG} = $reason;
	}
}

return( 0, "" );

}	#sub GWMsgCheck 


#------------------------------
#	GW Get Hash
#------------------------------
sub GWGetHash
{
my( $p_gwhash ) = @_;
my( $err, $msg, $cmd, @gwarr, $gw );

$cmd = "wlookup -ar Gateway";
$err = &EQCacheCmd( $cmd, \@gwarr, 1 );
if( $err ) 
{
	$msg = join( "", @gwarr );
	&EQSterilizeMsg( \$msg );
	return( $err, $msg );
}

# Strip leading/trailing whitespace from reach element
foreach $gw( @gwarr ) 
{ 
	$gw =~ s/^\s+|\s+$//g; 
	next unless( $gw =~ /(.+)\s+(\d+\.\d+\.\d+)\#TMF_Gateway::Gateway\#/ );
	$$p_gwhash{$1} = $2;
}

return( 0, "" );

}	#sub GWGetHash


#-----------------------------------------
#	EQ Get MN OID
#-----------------------------------------
sub EQGetMNOID
{
my( $mn, $p_oid ) = @_;
my( $err, $msg, $cmd );

# Get oid of loghost
$cmd = "wlookup -or ManagedNode \"$mn\"";
$err = &EQCacheCmd( $cmd, \@arr, 1 );
$msg = join( "", @arr );
if( $err ) 
{
	&EQSterilizeMsg( \$msg );
	return( $err, "GetMNOID: $msg" );
}

return( 1, "Error determining OID for $mn: $msg" ) unless( $msg =~ /(\d+\.\d+\.\d+)/ );

$$p_oid = $1;
return( 0, "" );

}	#sub EQGetMNOID


#-----------------------------------------
#	EQ Get MN Interp
#-----------------------------------------
sub EQGetMNInterp
{
my( $mn, $p_interp ) = @_;
my( $err, $msg, $cmd, @arr, $interp );

$cmd = "winterp \"$mn\"";
$err = &EQCacheCmd( $cmd, \@arr, 1 );
$msg = join( "", @arr );
if( $err ) 
{
	&EQSterilizeMsg( \$msg );
	return( $err, "GetMNInterp: $msg" );
}

$msg =~ s/^\s+|\s+$//g;
$$p_interp = $msg;
return( 0, "" );

}	#sub EQGetMNInterp


#-----------------------------------------
#	EQ Get File Offset
#-----------------------------------------
sub EQGetFileOffset
{
my( $host, $file, $p_offset ) = @_;
my( $err, $msg, $cmd, @arr, $quote, $line, $oid );

# Change backslashes to slashes
$file =~ s#\\+#/#g;

# See if file is local
if( $host eq "$xc_EQ_MN" )
{
	# if file exists, get size. otherwise, set offset to zero
	if( -f $file ) { $$p_offset = (-s $file); }
	else { $$p_offset = 0; }
	return( 0, "" );
}

# File must be remote, so use Tivoli stat_file method

# Get the oid and interp of the loghost
($err, $msg) = &EQGetMNOID( $host, \$oid );
return( $err, $msg ) if( $err );

$quote = ((!$xc_OS)||($xc_OS =~ /^Windows/i))? "": "'";
$cmd = "echo ${quote}\"$file\" TRUE$quote \| idlcall -v $oid stat_file";
&EQLogMsg( "Executing: '$cmd'" ) if( $G_Debug );

$err = &EQCacheCmd( $cmd, \@arr, 0 );
if( $err ) 
{
	$msg = join( "", @arr );
	&EQSterilizeMsg( \$msg );
	return( $err, "EQGetFileOffset: $msg" );
}

$line = $arr[0];
$line =~ s/^\d+\s+\{\s+\"[^\"]+\"\s+//;
@arr = split( " ", $line );
$$p_offset = $arr[8];

return( 0, "" );

}	#sub EQGetFileOffset

sub	EQLogFatalError
{
	my	($p_msg) = @_;
	my	(@a, $time, $file);

	@a = localtime (time ());
	$file = "$xc_EQ_PATH/logs/fatal/" .
		sprintf ("%04d%02d%02d", $a[5] + 1900, $a[4] + 1, $a[3]) . ".log";
	$file =~ s#\\#/#g;

	$time = sprintf ("%02d:%02d:%02d", $a[2], $a[1], $a[0]);
	# Writing data to this log file is our last resort. If we cannot do
	# that there is nothing else we can do.
	if	(open (FLOG_FILE, ">>$file"))
	{
		$p_msg =~ s/\s+$//;
		print FLOG_FILE "$time $p_msg\n";
		close (FLOG_FILE);
	}
}

#-----------------------------------------
#	EQ Init Env
#-----------------------------------------
sub EQInitEnv2
{

my $s = $ENV{EQHOME} . "/cfg/setup_env.pl";
open (IN_FILE, "$s") || &LogMsg( "Cannot open file '$s': $!\n", 1);
$s = join ("", <IN_FILE>);
close (IN_FILE);
eval "$s";

}	# end of EQ Init Env

#--------------------------------------------------
#	Stop Processing
#--------------------------------------------------
sub StopProcessing2
{
	my( $err, $msg ) = @_;
	my( $s, $e );

	# Log the msg and exit if just testing
	if	($G_Testing)
	{
		$s = ($err)? "ERROR": "SUCCESS";
		print "Program execution completed.\n$s: $msg";
		exit( $err );
	}

	&EQLogMsg( "\nTID: $tid  TARGET: $G_Target  ERR: $err  MSG: $msg" ) if( $G_Config{EQDEBUG} );

	# Send status for target
	($e, $s) = &EQStatus( \$G_Socket, $tid, $G_Target, $err, $msg );
	&EQLogMsg( "Error Sending EQ Status Msg for '$G_Target': $s" ) if( $e );

	# Send transaction finished message to EQ Server
	&EQFinished( \$G_Socket, $tid, "" );
	exit( 0 );

} # end of Stop Processing

1;
