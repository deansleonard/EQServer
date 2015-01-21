#!C:/dean/EQ-Working/EQServer/perl5/bin/perl
#
#----------------------------------------------------------------#
# Installation script for Enterprise-Q                           #
#                                                                #
# (C) Copyright Capital Software Corporation, 2000               # 
#----------------------------------------------------------------#                                        

if	((@ARGV == 1)&&($ARGV[0] eq "-v"))
{
	print '$Id: SQLiteUpdate.pl,v 1.3 2014/11/06 23:35:19 eqadmin Exp $', "\n";
	exit (0);
}

use DBI;
use Getopt::Std;

&getopts('nf:c:s');

&EQInitEnv( );

require "$xc_EQ_PATH/lib/SQLite.pl";
require "$xc_EQ_PATH/lib/eqclientlib.pl";

&Usage( ) unless( defined( $opt_f ) );

($err, $msg) = &CreateSQLiteDB( "$xc_EQ_PATH/EQ_DB", $opt_f, $opt_s, $opt_n );
print( $msg ) if( $err );
exit( $err );



#--------------------------------------------------
#	Usage
#--------------------------------------------------
sub Usage
{
print <<EOT;
Usage: SQLiteUpdate.pl -f <sql-file> [-s] [-n]

This program reads in the contents of 'sql-file' and executes the statements
against the enterprise-Q SQLite database file named EQ_DB stored in '\$xc_EQ_PATH',
which is currently set to '$xc_EQ_PATH'.

Use -s to run silently.  That is, do not display the commands being executed.
Use -n to create new SQLite database file.

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

