#!C:/dean/EQ-Working/EQServer/perl5/bin/perl

#
#	Timeout.pl
#
#	Copyright Capital Software Corporation - All Rights Reserved
#

if	((@ARGV == 1)&&($ARGV[0] eq "-v"))
{
	print '$Id: Timeout.pl,v 1.3 2014/11/06 23:36:55 eqadmin Exp $', "\n";
	exit (0);
}

# Get EQ configuration data
$s = $ENV{EQHOME} . "/cfg/setup_env.pl";
open (IN_FILE, "$s") || &LogMsg( "Cannot open file '$s': $!\n", 1);
$s = join ("", <IN_FILE>);
close (IN_FILE);
eval "$s";

require( "$xc_EQ_PATH/lib/eqclientlib.pl" );
require( "$xc_EQ_PATH/lib/tivclientlib.pl" );
$logfile = "$xc_EQ_PATH/temp/timeout.out";

sub	DistFPTimeout;
sub	KillTrans;

( $buf ) = @ARGV;

%G_MsgHash = &HashMsg( \"$buf" );

$tid = $G_MsgHash{T_TID};
#$targets = $G_MsgHash{T_TARGETS};
$pid = $G_MsgHash{T_PID};
$trans = $G_MsgHash{T_TRANS};
$profile = $G_MsgHash{T_PROFILE};
#$tmout = $G_MsgHash{T_TIMEOUT};
$x_kill = $G_MsgHash{T_KILL};

if	((!defined($tid))||(!defined($pid)))
{
	&SendEQMsg
		(\"T_MSG=STARTED;T_RESULT=1;T_PID=$$;T_TID=$tid;T_REASON=Invalid Startup Args");
	exit (1);
}

if	((!defined ($xc_OS))||($xc_OS =~ /^Windows/i))
{
	$list_cmd = "$xc_EQ_PATH/bin/eqps";
	$kill_cmd = "$xc_EQ_PATH/bin/eqps -k";
}
else
{
	$list_cmd = "ps -e -o pid,ppid,comm";
	$kill_cmd = "kill -9";
}

# Take specific action if Inventory MCollect timeout
if( $trans =~ /InventoryConfig/ )
{
	# Determine logfile
	($err, $logfile) = &InventoryConfigCheck( $profile );
	unless( $err ) {
		`echo Timeout: T_TID=$tid >> $logfile 2>&1`;
		exit( 0 );
	}
	($err, $msg) = &SendEQMsg( \"T_MSG=INFO;MSG=$logfile" );
}

elsif( $trans =~ /InventoryProfile/i )
{
	# Check if MCollect being used for this distro
	($enabled, $logfile) = &MCollectCheck( $profile );
	if( $enabled ) {
		`echo Timeout: T_TID=$tid >> $logfile 2>&1`;
		exit( 0 );
	}
}

elsif( $trans =~ /^SP(Install|Remove|Undo|Accept|Commit|Verify)/i ) 
{
	# Determine logfile
	($err, $logfile) = &SoftwarePackageCheck( $profile );
	unless( $err ) {
		$msg = `echo Timeout: T_TID=$tid >> \"$logfile\" 2>&1`;
		$err = $?;
		exit( $err );
	}
	($err, $msg) = &SendEQMsg( \"T_MSG=INFO;MSG=$logfile" );
}

( $err, $msg ) = &KillTrans( $pid, $trans, $x_kill );
($err, $msg) = &SendEQMsg( \"T_MSG=FINISHED;T_TID=$tid;T_RESULT=$err;T_REASON=Timeout - $msg" );
if( $err ) {
	if( open( FH, ">>$logfile" ) ) {
		print FH "ERR: $err  TID: $tid  MSG: $msg\n";
		close( FH );
	}
}

exit( 1 );


#-------------------------------------------------
#	MCollect Check
#-------------------------------------------------
sub MCollectCheck
{
my( $profile ) = @_;
my( $line, @arr, $logfile, $enabled );

$logfile = "";
$enabled = 0;

@arr = `wgetipcoll -a \@InventoryProfile:\"$profile\" 2>&1`;
return( $enabled, $logfile ) if( $? );

foreach $line( @arr ) {
	if( $line =~ /Use MCollect:(.+)$/i ) {
		$enabled = ($1 =~ /YES/i) ? 1 : 0;
	}
	elsif( $line =~ /Log file name:(.+)$/i ) {
		$logfile = $1;
	}
}

$logfile =~ s/^\s+|\s+$//g;
return( $enabled, $logfile );

}	 # end of MCollect Check


#-------------------------------------------------
#	Inventory Config Check
#-------------------------------------------------
sub InventoryConfigCheck
{
my( $profile ) = @_;
my( $err, $msg, $cmd, $line, @arr, $logfile );

$cmd = "wgetinvglobal \@InventoryConfig:\"$profile\"";
@arr = `$cmd 2>&1`;
$err = $?;
if( $err ) {
	$msg = join( "", @arr );
	return( 1, "Error calling '$cmd': $msg" );
}

foreach $line( @arr ) 
{
	next unless( $line =~ /Log file pathname:(.+)$/i );
	$logfile = $1;
	$logfile =~ s/^\s+|\s+$//g;
	return( 0, $logfile );
}

return( 1, "Could not determine InventoryConfig logfile" );

}	 # end of Inventory Config Check


#-------------------------------------------------
#	Software Package Check
#-------------------------------------------------
sub SoftwarePackageCheck
{
my( $profile ) = @_;
my( $err, $msg, $cmd, $line, @arr, $logfile );

# wgetspop requires $ENV{HOME}
$ENV{HOME} = "$xc_EQ_PATH/temp" unless( defined($ENV{HOME}) );

$cmd = "wgetspop -L \"\@$profile\"";
@arr = `$cmd 2>&1`;
$err = $?;
if( $err ) {
	$msg = join( "", @arr );
	return( 1, "Error calling '$cmd': $msg" );
}

$logfile = $arr[0];
$logfile =~ s/^\s+|\s+$//g;
return( 0, $logfile );

}	 # end of Software Package Check


#-------------------------------------------------
#	Kill Trans
#-------------------------------------------------
sub KillTrans
{
my( $perlpid, $trans, $p_kill ) = @_;
my( @tlist, $line, $err, @arr, $killpid, %l_parent, $i, $j, @kill_list );

@tlist = `$list_cmd 2>&1`;
return( 1, "Error getting list of processes: " . join ("", @tlist))
	if( $? );

if	((defined ($p_kill))&&($p_kill ne ""))
{
	# There maybe more than one transaction in the list
	@kill_list = split (/\s*,\s*/, $p_kill);
	
	%l_parent = ();
	# Go through list of processes and save information about their parents
	foreach $line (@tlist)
	{
		$line =~ s/\s+$//;
		# We are not interested in lines where PPID is not provided
		if	($line =~ /^\s*(\d+)\s+(\d+)/)
		{
			$l_parent{$1} = $2;
		}
	}

	foreach $kill_proc (@kill_list)
	{
		foreach $line (@tlist)
		{
			if	(($line =~ /^\s*(\d+)\s+\d+\s+$kill_proc$/i)||
				 ($line =~ m#^\s*(\d+)\s+\d+\s+/(.+)/$kill_proc$#i))
			{
				$killpid = $1;
				# Make sure it's a child of our original process
				$i = $killpid;
				$j = 10000;
				while (defined ($l_parent{$i}))
				{
					last	if	($i == $perlpid);
					$i = $l_parent{$i};
					# $j is used to avoid infinite loop situation
					$j--;
					last	if	($j <= 0);
				}
				next	if	($i != $perlpid);
				@arr = `$kill_cmd $killpid 2>&1`;
				return( 1, "Error killing PID ($killpid) of $kill_proc" ) if( $? );
				return( 0, "Successfully terminated transaction ($kill_proc)" );
			}
		}
	}
}

foreach $line (@tlist)
{
	$line =~ s/\s+$//;
	if	(($line =~ /^\s*$perlpid\s+\d+\s+$trans$/i)||
		 ($line =~ m#^\s*$perlpid\s+\d+\s+$xc_EQ_PATH/trans/$trans$#i))
	{
		@arr = `$kill_cmd $perlpid 2>&1`;
		return( 1, "Error killing PID ($perlpid) of $trans" ) if( $? );
		return( 0, "Successfully terminated transaction ($trans)" );
	}
	elsif	(($line =~ /^\s*$perlpid\s+\d+\s+perl$/i)||
			 ($line =~ m#^\s*$perlpid\s+\d+\s+$xc_PERL_BIN_PATH/perl$#i))
	{
		@arr = `$kill_cmd $perlpid 2>&1`;
		return( 1, "Error killing perl PID ($perlpid) of $trans" ) if( $? );
		return( 0, "Successfully terminated perl parent process for ($trans)" );
	}
}

return( 1, "PID for $trans not found" );

}	# end of Kill Trans

#-------------------------------------------------
#	Dist FP Timeout
#-------------------------------------------------
sub DistFPTimeout
{
my( @result, $line, $killpid );

@result = `odstat -cv 2>&1`;
for( $i=0; $i <= $#result; $i++ ) {
	$line = $result[$i];
	chomp( $line );
	if( $line =~ /fps_install/ ) {
		$line = $result[$i+1];
		chomp( $line );
		return if( $line !~ /pid=(\d+)/ );
		$killpid = $1;
		`$kill_cmd $killpid 2>&1`;
		return;
	}
}

}	# end of Dist FP Timeout

