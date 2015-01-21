#!C:/dean/EQ-Working/EQServer/perl5/bin/perl
#	EQMsgPerl.pl
#
#	Copyright Capital Software Corporation - All Rights Reserved
#

$x_version = '$Id: EQMsg2.pl,v 1.2 2009/05/08 18:53:44 eqadmin Exp $';

use Socket;
use IO::Socket;

sub	SendEQMsg;
sub	AlarmSigHandler;

( $buf ) = @ARGV;

&Usage unless( defined $ARGV[0] );

$Unix = $^O =~ /win/i ? 0 : 1;
$RecdAlarm = 0;

while ( @ARGV ) 
{
	$arg = shift( @ARGV );
	if( $arg eq "-h" )		{ $host = shift( @ARGV ); }
	elsif( $arg eq "-p" )	{ $port = shift( @ARGV ); }
	elsif( $arg eq "-m" )	{ $eqmsg = shift( @ARGV ); }
	else 
	{ 
		# insert space between msg args if more than one
		if( length($eqmsg) ){ $eqmsg .= " "; }
		$eqmsg .= "$arg"; 
	}
}

$eqmsg = $buf if( length( $eqmsg ) == 0 );

unless( defined($host) && length($host) > 0 ) 
{
	# First, try hostname command
	$host = `hostname 2>&1`; chomp($host);
	# Then, try environment variable set in env.cfg
	$host = $ENV{HOSTNAME} if( (length($host)==0 ) && (length($ENV{HOSTNAME})>0) );
	# Finally, try netbios name (NT only)
	$host = $ENV{COMPUTERNAME} if( (length($host)==0 ) && (!$Unix) );
}

$port = 2345 unless( defined($port) );

$file = &GetFilename( $host, $port );

# Get list of messages
($err, $msg) = &GetMsgs( $file, $eqmsg, \@eqmsgs );
if( $err )
{
	print "$msg\n";
	exit( $err );
}

# Establish socket
($err, $msg) = &EQSockConn( \$socket, $host, $port );
if( $err )
{
	print "$msg\n";
	exit( $err );
}

# Send each message in array
while( $eqmsg = shift( @eqmsgs ) )
{
	($err, $msg) = &SendMsg( $socket, $eqmsg );
	print $msg;
	last if( $err );
}

# Place back into array if eqmsg defined
unshift( @eqmsgs, $eqmsg ) if( $eqmsg );

# Close socket
&EQSockClose( $socket );

# Remove the file
unlink( $file );

# Write unsent messages to file
if( scalar(@eqmsgs) > 0 )
{
	open( MSGS, ">$file" ) || die "Error opening '$file' for writing: $!";
	print MSGS join( "", @eqmsgs );
	close( MSGS );
}

exit( 0 );


#--------------------------------
#	Get Filename
#--------------------------------
sub GetFilename
{
my( $host, $port ) = @_;
my( $file, $homevar, $tempvar, $home );

# Unix and Windows use different environment variables for storing home and temp dirs
if( $Unix )
{
	$homevar = "HOME";
	$tempvar = "TMP";
}
else
{
	$homevar = "USERPROFILE";
	$tempvar = "TEMP";
}

# Initialize $home to current working directory
$home = "./";

# Use HOME if set and exists
if( defined($ENV{$homevar}) && -d $ENV{$homevar} )
{
	$home = $ENV{$homevar};
}
# Else use $TMP if set and exists
elsif( defined($ENV{$tempvar}) && -d $ENV{$tempvar} )
{
	$home = $ENV{$tempvar};
}

$home =~ s#\\+#/#g;
$file = sprintf( "%s/%s.%d.txt", $home, $host, $port );

return( $file );

}	# end of Create Filename


#--------------------------------
#	Get Msgs
#--------------------------------
sub GetMsgs
{
my( $file, $eqmsg, $p_arr ) = @_;

$eqmsg =~ s/\n*$/\n/;

open( MSGS, ">>$file" ) || return( 1, "Error opening '$file' for appending: $!" );
print MSGS $eqmsg;
close( MSGS );

open( MSGS, "$file" ) || return( 1, "Error opening '$file' for reading: $!" );
@$p_arr = <MSGS>;
close( MSGS );

return( 0, "" );

}	# end of Get Msgs


#--------------------------------
#	Send Msg
#--------------------------------
sub SendMsg 
{
my( $socket, $eqmsg ) = @_;
my( $ret_data, $data, $SocketReadTimeout, $LAST_MSG );

my( $SocketReadTimeout ) = 30;
my( $LAST_MSG ) = "THE END";

# Add
$eqmsg =~ s/\n*$/\n/;
print $socket "$eqmsg";

$data = $ret_data = "";
while( 1 ) 
{
	alarm( $SocketReadTimeout ) if( $Unix );	# set alarm
	
	$data = <$socket>;
	
	if( $RecdAlarm ) 
	{
		$ret_data .= "Socket read timeout\n";
		return( 1, $ret_data );
	}
	
	alarm( 0 ) if( $Unix );						# cancel alarm
	
	unless( defined( $data ) ) 
	{
		$ret_data .= "Socket read timeout\n";
		return( 1, $ret_data );
	}
	
	last if( $data =~ /^${LAST_MSG}$/ );

	$ret_data .= $data;
}

return( 0, $ret_data );

}	# end of Send EQ Msg


#--------------------------------
#	EQ Sock Conn
#--------------------------------
sub EQSockConn
{
my( $p_socket, $host, $port ) = @_;
my( $SocketMaxAttempts ) = 5;
my( $Socket );

while( 1 ) 
{
	$$p_socket = IO::Socket::INET->new( PeerAddr => $host,
										PeerPort => $port,
										Proto    => 'tcp',
										Type     => SOCK_STREAM );
	last if( $$p_socket );
	$SocketMaxAttempts -= 1;
	return( 1, "Cannot establish socket with '$host:$port'" ) if( $SocketMaxAttempts == 0 );
	sleep( 1 );		# pause for a second
}

select( $$p_socket ); $|=1; select( STDOUT );

# if not NT, set signal handler for SIG$ALARM
$SIG{ALRM}  = 'AlarmSigHandler' if( $Unix );

return( 0, "" );

}	#sub EQ Sock Conn


#--------------------------------
#	EQ Sock Close
#--------------------------------
sub EQSockClose
{
my( $Socket ) = @_;

close( $Socket );

# restore disposition of alarm signal
$SIG{ALRM}  = "DEFAULT" if( $Unix );

}	#sub EQ Sock Close


#--------------------------------
#	Alarm Sig Handler
#--------------------------------
sub AlarmSigHandler
{
my( $signal ) = @_;

close( S );
$RecdAlarm = 1;
return;

}	# end of Alarm Sig Handler


#--------------------------------
#	Usage
#--------------------------------
sub Usage
{
my( $msg ) = @_;

print <<EOT;
$msg
Usage: EQMsg [-h <hostname>] [-p <port>] [-m] <message>

	hostname	- EQ Server hostname.  Default = localhost
	port		- TCP port number.  Default = 2345
	message		- EQ message (\"-m\" optional)

EOT
	
exit( 0 );
	
	
}	# end of Usage

