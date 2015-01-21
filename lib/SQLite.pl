#!C:/dean/EQ-Working/EQServer/perl5/bin/perl
#
# Function used by enterprise-Q to create SQLite DB and perform SQLite I/O.
# enterprise-Q $xc_* variables should be set prior to calling these functions.
# Furthermore, this library will only work with enterprise-Q built with Perl5.6.1
# or higher, unless you've installed Perl5.6.1 separately and have the path set 
# to find DBD::SQLite
#
#	print '$Id: SQLite.pl,v 1.5 2014/11/06 23:35:57 eqadmin Exp $'
#

#use lib "~EQ_PATH~/lib";
use lib "C:/dean/EQ-Working/EQServer/lib";
#use lib "~EQ_PATH~/perl5/lib";
use lib "C:/dean/EQ-Working/EQServer/perl5/lib";
#use lib "~EQ_PATH~/perl5/site/lib";
use lib "C:/dean/EQ-Working/EQServer/perl5/site/lib";
#use lib "~EQ_PATH~/perl5/lib/site_perl";
use lib "C:/dean/EQ-Working/EQServer/perl5/lib/site_perl";

sub CreateSQLiteDB;
sub LoadSQLCmds;

use DBD::SQLite;


#--------------------------------------------
#	Create SQLite DB
#--------------------------------------------
sub CreateSQLiteDB
{
my( $dbfile, $sqlfile, $silent, $new ) = @_;
my( $err, $msg, $dbh, @a );

# Set defaults if any args are undef
$dbfile = "$xc_EQ_PATH/EQ_DB" unless( defined($dbfile) );
$sqlfile = "$xc_EQ_PATH/install/inst_sqlite.sql" unless( defined($sqlfile) );
$silent = 0 unless( defined($silent) );

# Remove old database file if there
unlink( $dbfile ) if( -f $dbfile && $new );

# Load the SQL statements to create the enterprise-Q tables
@a = ( );
($err, $msg) = &LoadSQLCmds( $sqlfile, \@a );
return( 1, $msg ) if( $err );

($err, $msg) = &RunSQLiteCmds( $dbfile, \@a, $silent );
return( $err, $msg );

}	# end of Create SQLite DB
	   

#-----------------------------------------
#	Run SQLite Cmds
#-----------------------------------------
sub RunSQLiteCmds
{
my( $dbfile, $p_cmds, $silent ) = @_;
my( $dbh, $cmd, $drop_notice );

# Connect to the database, PrintError => 0 prevents errors to standard output
$dbh = DBI->connect( "dbi:SQLite:dbname=$dbfile", "", "", { PrintError => 0 } ) || 
	return( 1, "Failed to connect to database" );

# Run each command to create tables/keys/indices
$drop_notice = 	"*** Please ignore 'no such table' messages, which may be  ***\n" .
				"*** generated from attempts to DROP a non-existent table. ***\n";

foreach $cmd( @$p_cmds )
{
	print "$cmd\n" unless( $silent );
	next if( $dbh->do( $cmd ) );
	return( 1, "Error running '$cmd': " . $dbh->errstr ) unless( $cmd =~ /^DROP/i );
}

# Disconnect from database
$dbh->disconnect( );

return( 0, "Commands successfully executed" );

}	# end of Run SQLite Cmds
	   

#-----------------------------------------
#	SQLite Select
#-----------------------------------------
sub SQLiteSelect
{
my( $p_cmds, $p_results, $dbfile ) = @_;
my( $dbfile, $dbh, $h, @a, $cmd );

$dbfile = "$xc_EQ_PATH/EQ_DB" unless( defined($dbfile) );

# Connect to the database
$dbh = DBI->connect( "dbi:SQLite:dbname=$dbfile", "", "" ) || return( 1, "Failed to connect to database" );

# Run each command to create tables/keys/indices
foreach $cmd( @$p_cmds )
{
	$h = $dbh->prepare ($cmd) ||
	return (1, "Error parsing SQL command '$cmd': " . $dbh->errstr);

	($s = $h->execute ()) ||
	return (1, "Error executing SQL command '$cmd': " . $dbh->errstr);

	push( @$p_results, "CMD: $cmd" );
	while(	(@a = $h->fetchrow) )
	{
		push( @$p_results, join( ",", @a ) );
	}

	$h->finish ();
}

# Disconnect from database
$dbh->disconnect( );

return( 0, "Commands successfully executed" );

}	# end of SQLite Select


#-----------------------------------------
#	Load SQL Cmds
#-----------------------------------------
sub LoadSQLCmds
{
my( $file, $p_cmds ) = @_;
my( $s, $line, @a );

open( FH, "$file" ) || return( 1, "Error opening '$file': $!" );
@a = <FH>;
close( FH );

$s = "";
foreach $line( @a )
{
	$line =~ s/^\s+|[\;\s]+$//g;
	next if( $line eq "" || $line =~ /^\#/ );
	$line =~ s/\t+/ /g;
	
	if( $line =~ /^(CREATE|DROP|INSERT|DELETE|UPDATE) /i )
	{
		push( @$p_cmds, $s ) unless( $s eq "" );
		$s = "";
	}
	
	$s .= "$line ";
}

# Add last statement to array
push( @$p_cmds, $s ) unless( $s eq "" );

return( 0, "" );

}	# end of Load SQL Cmds

1;

