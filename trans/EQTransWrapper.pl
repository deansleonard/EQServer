#!C:/scratch/EQServer/perl5/bin/perl

#
#	EQ Trans Wrapper.pl
#
#	Copyright Capital Software Corporation - All Rights Reserved
#

if	((@ARGV == 1)&&($ARGV[0] eq "-v"))
{
	print '$Id: EQTransWrapper.pl,v 1.2 2014/11/06 23:37:03 eqadmin Exp $', "\n";
	exit (0);
}


# Get EQ configuration data
$s = $ENV{EQHOME} . "/cfg/setup_env.pl";
open (IN_FILE, "$s") || &LogMsg( "Cannot open file '$s': $!\n", 1);
$s = join ("", <IN_FILE>);
close (IN_FILE);
eval "$s";

require ( "$xc_EQ_PATH/lib/eqclientlib.pl" );

my( $buf ) = @ARGV;

%G_MsgHash = &HashMsg( \$buf );

my $tid = $G_MsgHash{T_TID};
my $targets = $G_MsgHash{T_TARGETS};
my $targettype = $G_MsgHash{T_TARGETTYPE};
my $trans = $G_MsgHash{T_TRANS};
my $exec = $G_MsgHash{T_EXEC};
my $tfile = $G_MsgHash{T_TARGETFILE}; # This is set if command line too long for CLI and must be written to a fiel

if( !defined($tid) || !defined($trans) || !defined($exec) || (!defined($targets) && !defined($tfile)) ) 
{
	$msg = "Invalid Startup Command: ($tid)($targets)($trans) $buf. $0 requires T_TID, T_TARGETS, T_TRANS, and T_EXEC as arguments\n";
	&SendMsg( \"T_MSG=STARTED;T_RESULT=1;T_PID=$$;T_TID=$tid;T_REASON=$msg" ); 
	exit( 1 );
}

# Send startup ok status message to EQ Server
&SendMsg( \"T_MSG=STARTED;T_RESULT=0;T_PID=$$;T_TID=$tid" ); 

my @x_targets = ( );

if( $tfile && -f $tfile )
{
	unless( open( TF, "$tfile" ) )
	{
		&SendMsg( \"T_MSG=FINISHED;T_TID=$tid;T_PID=$$;T_RESULT=1;T_REASON=\"Error opening $tfile: $!\"" ); 
		exit( 1 );
	}
	@x_targets = <TF>;
	close( TF );
}
else
{
	@x_targets = split( /\s*,\s*/, $targets );
}

# Build a command that is used to run the user script
my $cmd = ($exec =~ /\.pl$/i)? "$xc_PERL_BIN_PATH/perl -I$xc_PERL_LIB_PATH $exec": $exec;
if	((!$xc_OS)||($xc_OS =~ /^Windows/i))
{
	$cmd =~ s#/#\\#g;
}
else
{
	$cmd =~ s#\\#/#g;
}

# Set environment before invoking transaction script/executable
foreach my $s (sort keys %G_MsgHash)
{
	next if( $s =~ /^T_TARGET/i || $s =~ /T_TID/i  || $s =~ /T_DISPATCH/i || $s =~ /T_EXEC/i );
	$ENV{"EQ_$s"} = $G_MsgHash{$s};
}

my %err_hash = ();
my %msg_hash = ();

undef($ENV{EQ_T_TARGETS});
foreach $target (@x_targets)
{
	$target =~ s/^\s+|\s+$//g;	# remove leading/trailing spaces
	$ENV{EQ_T_TARGET} = $target;
	
	# set default err/msg values for each target
	$err_hash{$target} = 1;
	$msg_hash{$target} = "Results Unknown";
	
	# invoke the script/executable
	$s = `$cmd 2>&1`;
	
	# set the error code to program's return value
	$err_hash{$target} = ($?) ? 1 : 0;
	
	# use stdout/stderr as the msg text
	$s =~ s/\s+$//;		# strip trailing spaces
	$s =~ s/\n/ /g;		# replace newline with a space
	$msg_hash{$target} = $s;
}

# contact EQServer
my $S = &EQSockConn( );
exit( 1 ) if( !$S );

# Send status for each target
foreach $target( @x_targets ) 
{
	# Get error code and message to send to current target
	$err = $err_hash{$target};
	$msg = $msg_hash{$target};
	
	# Send status for this target
	$Error = &EQSockRequest( $S, "T_MSG=STATUS;T_TID=$tid;T_RESULT=$err;T_TARGET=$target;T_REASON=\"$msg\"" ); 
	$Error = &EQSockResponse( $S, \@Response );
}

# Send finished message, ignoring the response
my @arr;
$err = &EQSockRequest( $S, "T_MSG=FINISHED;T_TID=$tid;T_PID=$$;T_RESULT=0" ); 
$err = &EQSockResponse( $S, \@arr );

# close socket and exit
&EQSockClose( $S );
exit( 0 );

