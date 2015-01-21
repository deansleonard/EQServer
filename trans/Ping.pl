#!C:/dean/EQ-Working/EQServer/perl5/bin/perl
#
#	$Id$
#
# Queue this transaction script using:
#
#	<eq>/bin/EQMsg "t_msg=Add;t_trans=Ping;t_target=<target>;device=google.com
#
# Keywords passed via environment variables prefixing each with 'EQ_'.
# EQServer reserved keywords will be all caps. 
# Application keywords case sensitive.
#

my $host = defined( $ENV{EQ_device} ) ? $ENV{EQ_device} : "yahoo.com";
my( $err, $msg ) = &Ping( $host );
$err = $err ? 1 : 0;
$msg =~ s/\n*$/\n/;
print $msg;
exit( $err );


#-------------------------------------------
#	Ping
#-------------------------------------------
sub Ping
{
my( $host ) = @_;
my( $err, $msg, $cmd, $os, @ping_data, $ip, $p, @a );

$os = $^O;

# Try to resolve ip using label
if( $host !~ /^\d+\.\d+\.\d+\.\d+$/ )
{
	$ip = gethostbyname ($host);
	if( $ip )
	{
		@a = unpack ('C4', $ip);
		$ip = $a[0] . "." . $a[1] . "." . $a[2] . "." . $a[3];
	}
	else
	{
		return( 1, $ip );
	}
}

@ping_data = ();
# Ping the node
if( $os =~ /^mswin/i )
{
	use Net::Ping;
	$p = Net::Ping->new( "icmp" );
	$err = $p->ping( $ip, 5 );
	$p->close();
	return( 1, "Cannot ping node $host ($ip): Request timed out" ) if( $err == 0 );
	return( 1, "Cannot ping node $host ($ip): Unknown error" ) if( !defined($err) || $err eq "" );
	return( 0, $err );
}

# We cannot use Net::Ping for Solaris as sending ping messages may require root
elsif( $os =~ /^Solaris/i )
{
	$cmd = "/usr/sbin/ping -s $ip 64 1";
	@ping_data = `$cmd 2>&1`;
	$err = $?;
	$msg = join ("", @ping_data);
	return( 1, "Error pinging $ip: $msg" ) if( $err || $msg !~ /1 packets received, 0\% packet loss/ );
	return( 0, $msg );
}

elsif( $os =~ /^Aix/i )
{
	$cmd = "/usr/sbin/ping -c 1 $ip 64 1";
	@ping_data = `$cmd 2>&1`;
	$err = $?;
	$msg = join ("", @ping_data);
	return( 1, "Error pinging $ip: $msg" ) if( $err || $msg !~ /1 packets received, 0\% packet loss/ );
	return( 0, $msg );
}

elsif( $os =~ /^Linux/i )
{
	$cmd = "/bin/ping -c 1 $ip";
	@ping_data = `$cmd 2>&1`;
	$err = $?;
	$msg = join ("", @ping_data);
	return( 1, "Error pinging $ip: $msg" ) if( $err || $msg !~ /1 packets transmitted, 1 received, 0\% packet loss/ );
	return( 0, $msg );
}

return( 1, "Internal error: OS contains invalid value '$os'");

}	# end of Ping
