#!C:/dean/EQ-Working/EQServer/perl5/bin/perl
#
#----------------------------------------------------------------#
# Installation script for Enterprise-Q                           #
#                                                                #
# (C) Copyright Capital Software Corporation, 2000               # 
#----------------------------------------------------------------#                                        

if	((@ARGV == 1)&&($ARGV[0] eq "-v"))
{
	print '$Id: SQLiteSelect.pl,v 1.3 2014/11/06 23:35:19 eqadmin Exp $', "\n";
	exit (0);
}

use DBI;
use Getopt::Std;

&getopts('c:');

&EQInitEnv( );

require "$xc_EQ_PATH/lib/SQLite.pl";
require "$xc_EQ_PATH/lib/eqclientlib.pl";

&Usage( ) unless( defined( $opt_c ) );

@cmds = split( /;/, $opt_c );
($err, $msg) = SQLiteSelect( \@cmds, \@arr );

if( $err )
{
	print "$msg\n";
}
else
{
	foreach $line( @arr )
	{
		print "$line\n";
	}
}

exit( $err );



#--------------------------------------------------
#	Usage
#--------------------------------------------------
sub Usage
{
print <<EOT;
Usage: SQLiteSelect.pl -c <select-command>

EOT

exit( 0 );

}	# end of Usage


#--------------------------------------------------
#	EQ Init Env
#--------------------------------------------------
sub EQInitEnv
{
my( $s );

$s = $ENV{EQHOME} . "/cfg/setup_env.pl";
open (IN_FILE, "$s") || &LogMsg( "Cannot open file '$s': $!\n", 1);
$s = join ("", <IN_FILE>);
close (IN_FILE);
eval "$s";

}	# end of EQ Init Env

