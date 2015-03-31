#!c:/eq/perl5/bin/perl
#

use DBI;

if	($xc_DB_VENDOR =~ /^DB2/i)
{
	require "DBD/DB2.pm";
}
elsif	($xc_DB_VENDOR =~ /^ORACLE/i)
{
	require "DBD/Oracle.pm";
}
elsif	($xc_DB_VENDOR =~ /^SQLite/i)
{
	require "DBD/SQLite.pm";
}
elsif	($xc_DB_VENDOR =~ /^MySQL/i)
{
# Net::MySQL Module
#	require "Net/MySQL.pm";
# DBD::MySQL Module
#	require "DBD/MySQL.pm";
}

my ($x_db_handle) = "";

#-------------------------------------------------
#	EQ Init SQL
#-------------------------------------------------
sub EQ_InitSQL
{
my( $user, $pass, $db_host, $rdbms );

return( 1, "enterprise-Q database schema not configured (DB_VENDOR='$xc_DB_VENDOR') in site cfg" ) if( $xc_DB_VENDOR eq "NONE" );

# Get username/password for account in the database
$user = $xc_DB_USERNAME || "";
$pass = $xc_DB_PASSWORD || "";
$db_host = $xc_DB_HOST || "";
$rdbms = $xc_DB_VENDOR || "SQLite";

if	($rdbms =~ /DB2/i)
{
	$x_db_handle = DBI->connect("dbi:DB2:$db_host", $user, $pass) ||
		return (1, "Failed to connect to database: $DBI::errstr");
}
elsif	($rdbms =~ /ORACLE/i)
{
	$x_db_handle = DBI->connect("dbi:Oracle:$db_host", $user, $pass) ||
		return (1, "Failed to connect to database: $DBI::errstr");
}
elsif	($rdbms =~ /SQLite/i)
{
	$x_db_handle = DBI->connect("dbi:SQLite:dbname=$xc_EQ_PATH/EQ_DB", $user, $pass) ||
		return (1, "Failed to connect to database: $DBI::errstr");
}
elsif	($rdbms =~ /MySQL/i)
{
# Net::MySql Method
#	$x_db_handle = Net::MySQL->new( hostname => $host, database => $db, user => $user, password => $pass ) ||
#		return (1, "Failed to connect to database: $DBI::errstr");
# DBD::MySQL Method
#	$x_db_handle = DBI->connect("dbi:mysql:EQ_DB", $user, $pass) ||
#		return (1, "Failed to connect to database: $DBI::errstr");
}

return( 0, "" );

}	# end of EQ Init SQL

#-------------------------------------------------
#	EQ Exit SQL
#-------------------------------------------------
sub EQ_ExitSQL
{

#$x_db_handle->commit ();
$x_db_handle->disconnect ()		if	($x_db_handle ne "");
$x_db_handle = "";

}	# end of EQ Exit SQL


#------------------------------------------
#	EQ Exe SQL
#------------------------------------------
sub EQ_ExeSQL
{
my( $command, $p_result, $exit ) = @_;
my( $err, $msg );

unless( $x_db_handle )
{
	($err, $msg) = &EQ_InitSQL ();
	return ($err, $msg)	if	($err);
}

($err, $msg) = &EQ_ExeSQLCmd ($command, $p_result);
return ($err, $msg)	if	($err);

&EQ_ExitSQL () if( $exit );

return (0, "");

}	# end of EQ Exe SQL


#-------------------------------------------------
#	EQ Exe SQL Cmd
#-------------------------------------------------
sub EQ_ExeSQLCmd
{
my( $command, $p_result, @p_bind ) = @_;
my( $s, @a, $i, $j, $l_handle );

if	($x_db_handle eq "")
{
#warn ("INIT SQL\n");
	my	($err, $msg) = &EQ_InitSQL ();
	return (1, $msg)	if	($err);
}

#warn ("PREPARE $command\n");
$l_handle = $x_db_handle->prepare ($command) ||
	return (1, "Error parsing SQL command '$command': " . $x_db_handle->errstr);

#warn ("EXECUTE: " . join ("|", @p_bind) . "\n");
($s = $l_handle->execute (@p_bind)) ||
	return (1, "Error executing SQL command '$command': " . $x_db_handle->errstr);

if	($command =~ /^SELECT\s+/i )
{
#	for ($i = 0; @a = $l_handle->fetchrow; $i++)
#	{
#		for ($j = 0; $j < @a; $j++)
#		{
#			$$p_result[$i][$j] = $a[$j];
#		}
#	}

	if	(ref($p_result) eq "")
	{
		&$p_result ($l_handle);
	}
	else
	{
		$i = 0;
		while (1)
		{
			my (@a);
#warn ("FETCH\n");
			last	unless	(@a = $l_handle->fetchrow);
			$$p_result[$i] = \@a;
			$i++;
		}
	}

	$l_handle->finish ();
}
else
{
	$s = 0	if	($s eq "0E0");
	if( ref($p_result) =~ /Array/i )
	{
		$$p_result[0] = $s;
	}
	else
	{
		$$p_result = $s;
	}
}

return (0, "");

}	# end of EQ Exe SQL Cmd


#-------------------------------------------------
#	EQ Exe SQL Cmd 2
#-------------------------------------------------
sub EQ_ExeSQLCmd2
{
my( $command, $p_result ) = @_;
my( $s, @a, $l_handle );

@$p_result = ( );

return (1, "Internal error: database connection is not established")
	if	($x_db_handle eq "");

$l_handle = $x_db_handle->prepare ($command) ||
	return (1, "Error parsing SQL command '$command': " . $x_db_handle->errstr);

($s = $l_handle->execute ()) ||
	return (1, "Error executing SQL command '$command': " . $x_db_handle->errstr);

while (1)
{
	last	unless	(@a = $l_handle->fetchrow);
	$s = join( ",", @a );
	push( @$p_result, $s );
}

$l_handle->finish ();

return (0, "");

}	# end of EQ Exe SQL Cmd 2

sub	EQ_SQLQuote
{
	my	($p_value) = @_;

	return "''"		if	(!defined ($p_value));

	if	($x_db_handle eq "")
	{
		my	($err, $msg) = &EQ_InitSQL ();
		return $p_value		if	($err);
	}

	return $x_db_handle->quote($p_value);
}

sub	EQ_SQLCommit
{
	$x_db_handle->commit()	if	($x_db_handle);
}

#
# This subroutine checks if connection is still open. If the database
# closed previously open connection then the subroutine will reset
# x_db_handle variable so that EQ_ExeSQL... subroutines will automatically
# connect to the database next time they are called.
#
sub EQ_SQLCheckConnection
{

	if	(($x_db_handle)&&(!$x_db_handle->ping ()))
	{
		$x_db_handle->disconnect();
		undef($x_db_handle);
	}
	return '';
}

sub	EQ_SQLTableInfo
{
	my	($p_filter) = @_;

	if	($x_db_handle eq "")
	{
		my	($err, $msg) = &EQ_InitSQL ();
		return (1, $msg)	if	($err);
	}

	my $sth = $x_db_handle->table_info (undef, undef, $p_filter || undef, 'TABLE') ||
		return (1, "Error executing table_info: " . $x_db_handle->errstr);

	my	$arr = $sth->fetchall_arrayref ();
	my	@data = ();
	foreach (@$arr)
	{
		# Return only schema and table_name
		push (@data, $_->[1] . '.' . $_->[2]);
	}
	$sth->finish ();
	return (0, \@data);
}

sub	EQ_SQLColumnInfo
{
	my	($p_table) = @_;

	if	($x_db_handle eq "")
	{
		my	($err, $msg) = &EQ_InitSQL ();
		return (1, $msg)	if	($err);
	}

	my	($schema, $table) = ($p_table =~ /^([^\.]+)\.(.+)$/)?
		($1, $2): (undef, $p_table);
	my $sth = $x_db_handle->column_info (undef, $schema, $table, undef) ||
		return (1, "Error executing column_info: " . $x_db_handle->errstr);

	my	$arr = $sth->fetchall_arrayref ();
	my	@data = ();
	foreach (@$arr)
	{
		# Return only schema and table_name
		push (@data, [ $_->[3], $_->[5], $_->[6], $_->[10] ]);
	}
	$sth->finish ();
	return (0, \@data);
}

1;
