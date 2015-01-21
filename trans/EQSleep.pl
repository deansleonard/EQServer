#!C:/dean/EQ-Working/EQServer/perl5/bin/perl

#
#	Sleep.pl
#
#	Copyright Capital Software Corporation - All Rights Reserved
#

if	((@ARGV == 1)&&($ARGV[0] eq "-v"))
{
	print '$Id: Sleep.pl,v 1.4 2008/05/08 14:47:28 csdev Exp $', "\n";
	exit (0);
}


# Get EQ configuration data
$s = $ENV{EQHOME} . "/cfg/setup_env.pl";
open (IN_FILE, "$s") || &LogMsg( "Cannot open file '$s': $!\n", 1);
$s = join ("", <IN_FILE>);
close (IN_FILE);
eval "$s";

require ( "$xc_EQ_PATH/lib/eqclientlib.pl" );

( $buf ) = @ARGV;

%G_MsgHash = &HashMsg( \$buf );

my( $rc, $targets, $t, $tid, $sec, @arr );

$tid = $G_MsgHash{T_TID};
$targets = $G_MsgHash{T_TARGETS} || undef;
$targetfile = $G_MsgHash{T_TARGETFILE} || undef;
$sec = $G_MsgHash{SECONDS} || 30;
$rc = 0;

$trans = $G_MsgHash{T_TRANS};
$G_Debug = $G_MsgHash{EQDEBUG} || 0;
if( $G_Debug )
{
	delete( $G_MsgHash{EQDEBUG} );				# Remove hash element
	$G_logfile = "$xc_EQ_PATH/logs/$trans.log";	# Set logfile name
	open( EQLOG, ">$G_logfile" );				# Open logfile and set autoflush on

	$fh = select(EQLOG);
	$| = 1;
	select($fh);
}

unless( defined($tid) && (defined($targets) || defined($targetfile)) ) 
{
	$buf =	"T_MSG=STARTED;T_RESULT=1;T_PID=$$;T_TID=$tid;T_REASON=" .
			"Invalid Startup Command: $buf. " .
			"$trans requires T_TID, And T_TARGETS or T_TARGETFILE, as arguments\n";
	&EQLogMsg( $buf ) if( $G_Debug );
	&SendMsg( \$buf ); 
	exit( 1 );
}

# Send startup ok status message to EQ Server
$msg = "T_MSG=STARTED;T_RESULT=0;T_PID=$$;T_TID=$tid";
&EQLogMsg( $msg ) if( $G_Debug );
&SendMsg( \$msg ); 

@arr = split( /,/, "$targets" ) if( defined($targets) );
if( defined($targetfile) && open( TFILE, "$targetfile" ) )
{
	while( $t = <TFILE> )
	{
		$t =~ s/^\@*[^:]+://;
		$t =~ s/^\s+|\s+$//g;
		push( @arr, $t );
	}
	close( TFILE );
}

print EQLOG "Sleeping for '$sec' seconds.\n" if( $G_Debug );
sleep( $sec );

$S = &EQSockConn( );
&EQLogMsg( "EQSockConn Error: $trans", 1 ) if( !$S );

foreach $t ( @arr ) 
{
	$msg = "T_MSG=STATUS;T_TID=$tid;T_RESULT=0;T_TARGET=$t;T_REASON=Slept for $sec seconds";
	$Error = &EQSockRequest( $S, $msg ); 
	&EQLogMsg( "Sent to EQServer: '$msg'" ) if( $G_Debug );
	
	$Error = &EQSockResponse( $S, \@Response );
	
	$G_MsgHash{T_TARGETS} = $t;
	($err, $msg) = &SchedTrans( \%G_MsgHash ) if( $G_MsgHash{DURATION} );
	&EQLogMsg( "SchedMaintMode: $msg" ) if( $err );
	
	next unless( $G_Debug );
	
	&EQLogMsg( "Recd from EQServer: '" . join( "\n", @Response ) . "'" );
}

# Send finished message, and we're done...
$msg = "T_MSG=FINISHED;T_TID=$tid;T_PID=$$;T_RESULT=0";
$Error = &EQSockRequest( $S, $msg ); 
&EQLogMsg( "Sent to EQServer: '$msg'" ) if( $G_Debug );

$Error = &EQSockResponse( $S, \@Response );
&EQLogMsg( "Recd from EQServer: '" . join( "\n", @Response ) . "'" ) if( $G_Debug );

&EQSockClose( $S );

# Determine sched_day and sched_time
if( $G_MsgHash{DURATION} )
{
}

exit( 0 );


#----------------------------------------------
#	Sched Trans
#----------------------------------------------
sub SchedTrans
{
my( $p_hash ) = @_;
my( $ep, $sched_occurs, $sched_days, $sched_time, $eqmsg, $err, @a );
my( %new_keys, %skip_keys, $k );

$ep = $$p_hash{T_TARGETS};
&GetSched( $p_hash{DURATION} * 3600, \$sched_occurs, \$sched_days, \$sched_time );

%new_keys = 
(
	DURATION 	=> 0,
	T_REASON 	=> "Server maintenance duration elapsed",
	T_SCHED_DAYS 	=> $sched_days,
	T_SCHED_OCCURS	=> $sched_occurs,
	T_SCHED_SUBS	=> "DYNAMIC",
	T_SCHED_TIME	=> $sched_time,
);

%skip_keys = 
(
	T_MSG 		=> 1,
	T_TRANS 	=> 1,
	T_PROFILE	=> 1,
	T_TARGETS	=> 1,
);

$eqmsg  = "T_MSG=Add;T_TRANS=$$p_hash{T_TRANS};T_PROFILE=;T_TARGETS=$ep;";
foreach $k( keys %new_keys )
{
	$eqmsg .= "$k=$new_keys{$k};";
}

foreach $k( sort keys %$p_hash )
{
	next if( exists( $skip_keys{$k} ) || exists( $new_keys{$k} ) );
	$eqmsg .= "$k=$$p_hash{$k};";
}

$eqmsg =~ s/;+$//;
&EQLogMsg( "Scheduling '$$p_hash{T_TRANS}' for '$ep' using '$eqmsg'" ) if( $G_Debug );

($err, @a ) = &SendEQMsg( \$eqmsg, $xc_HOSTNAME, 2330 );
return( $err, join( "", @a ) );

}	# end of Sched Trans 


#----------------------------------------------
#	Get Sched
#----------------------------------------------
sub GetSched
{
my( $dur_secs, $p_sched_occurs, $p_sched_days, $p_sched_time ) = @_;
my( $now, $then, @a );

$now = time();
$then = $now + $dur_secs;
@a = localtime( $then );

if( int($now/86400) == int($then/86400) )
{
	$$p_sched_occurs = "TODAY";
	$$p_sched_days = "";
}
else
{
	$$p_sched_occurs = "NEXT";
	$$p_sched_days = $a[3];
}

$$p_sched_time = sprintf( "%02d:%02d:00", $a[2], $a[1] );

}	# end of Get Sched

