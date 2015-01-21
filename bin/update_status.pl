#!C:/dean/EQ-Working/EQServer/perl5/bin/perl
#
# update_status.pl
#

use Getopt::Std;

&getopts('avm:');

if( $opt_v )
{
	print '$Id: update_status.pl,v 1.7 2014/11/06 23:31:38 eqadmin Exp $', "\n";
	exit (0);
}

use DBI;

# This hash will be dyna,ically populated from a list of available target types
%ConvertTypeCode = (
#	"I"	=> "ManagedSystem",
#	"C"	=> "Computer",
#	"E"	=> "Endpoint",
#	"M"	=> "ManagedNode",
#	"P"	=> "PcManagedNode"
);

%ValidTargetTypes = ();

$x_field_len = 255;

# Get EQ configuration data
$s = $ENV{EQHOME} . "/cfg/setup_env.pl";
open (IN_FILE, "$s") || &LogMsg( "Cannot open file '$s': $!\n", 1);
$s = join ("", <IN_FILE>);
close (IN_FILE);
eval "$s";

# No need to proceed if database was not configured
exit( 0 ) if( $xc_DB_VENDOR eq "NONE" );

require ("$xc_EQ_PATH/lib/eqclientlib.pl");
require ("$xc_EQ_PATH/lib/www_gui.pl");
require ("$xc_EQ_PATH/lib/EQAction.pl");
require "$xc_EQ_PATH/lib/EQTTypes.pl";

# Location of log file
$x_logfile = $xc_EQ_PATH . "/logs/update_status.log";

$xc_ERROR_LENGTH = 255		unless ($xc_ERROR_LENGTH);

# Initialize global variables
%x_nodes   = ();
%x_actions = ();
%x_status  = ();
%x_action_parms = ();

# These variables will keep the next available node id and action id.
$x_node_id = 0;
$x_action_id = 0;

# This array is used to keep track of inserted (index 0) and
# updated (index 1) records
@x_updated = ();


&EQ_UpdateEnv ();
# Check if lock file exist
$x_lock = "$xc_EQ_PATH/temp/update_status.lock";
if	(-f $x_lock)
{
	# Ignore the lock file if it was created more than 4 hours ago
	@a = stat ($x_lock);
	$i = time ();
	if	($i - $a[9] < 14400)
	{
		# Make sure we don't delete lock file
		$x_lock = "";
		&LogError (1, "Cannot execute - update_status process already running");
	}
	unlink ($x_lock);
}

# Create lock file
open (LOCK_FILE, ">$x_lock") ||
	&LogError (1, "Cannot create lock file '$x_lock': $!");
close (LOCK_FILE);

($i, $s) = &EQ_InitSQL ();
&LogError (1, $s)	if	($i != 0);

# Populate ConvertTypeCode and ValidTargetTypes hashes.
# Get a list of available types
my	$types = &GetAllTargetTypes ('TYPE_DEVICE', 'TYPE_AGENT');

&LogError (1, $types)	if	(!ref ($types));
# Populate the hashes
foreach (@$types)
{
	$s = $_->type;
	$ConvertTypeCode{$_->type_abbrev} = $s;
	$ValidTargetTypes{$s} = 1;
}

# Tell EQ Server to close the status file and open a new one.
# We don't care if this operation fails - we'll just process what status
# files are there.
($err, $msg) = &SendEQMsg( \"T_MSG=NEWSTATUSFILE" );
&LogError( 0, "EQServer connection attempt failed: $msg " ) if( $err );

# Get a list of all currently defined Nodes and Actions in RDBMS
($err, $msg) = &EQ_GetDBIdHashes (\%x_nodes, \%x_actions);
&LogError (1, $msg)		if	($err);

# Get list of all status records in RDBMS
&GetDBActStatus (\%x_status);

# Get list of all records with distribution parameters in RDBMS
&GetDBActParms (\%x_action_parms);

# Determine maximum Node ID
while (($s, $i) = each %x_nodes)
{
	$x_node_id = $i		if	($x_node_id < $i);
}

# Determine maximum Action ID
while (($s, $i) = each %x_actions)
{
	$x_action_id = $i		if	($x_action_id < $i);
}

@x_files = ();
@x_custom = ();
# Get list of all status files.
opendir( LOG_DIR, "$xc_EQ_PATH/qstore/status" ) ||
	&LogError (1, "Cannot open directory '$xc_EQ_PATH/qstore/status': $!");

$upd_time = time ();
$upd_time -= 31 unless( $opt_a );

my $file_mask = $opt_m || undef;
#&LogError( 0, "File Mask: $file_mask" );

# For each file in the directory
while( defined ($s = readdir(LOG_DIR)) ) 
{
#	&LogError( 0, "File: $s" );

	# Only process specified files if file_mask defined
	next if( defined($file_mask) && $s !~ /$file_mask/i );

	if	($s =~ /\.status$/i)
	{
		push (@x_files, $xc_EQ_PATH . "/qstore/status/" . $s);
	}
	elsif	($s =~ /^.*?(\d+)\.update$/i)
	{
		push (@x_custom, $xc_EQ_PATH . "/qstore/status/" . $s)
			if	($1 < $upd_time);
	}
}
closedir (LOG_DIR);

@x_updated = ( 0, 0 );
# For each status file in the directory
foreach $x_file (sort @x_files) {
	# Open log file
	unless( open (STATUS_FILE, $x_file) ) 
	{
		&LogError (0, "Cannot open file '$x_file': $!");
		next;
	}

	@failed_recs = ();
	$next_record = "STATUS";

	while ($next_record ne "")
	{
		%x_data = ();
		$current_record = $next_record;
		$next_record = "";
		@current_recs = ( "-----${current_record}-----" );
		# Read data from status file and put it into assoc array
		while( defined ($s = <STATUS_FILE>) )
		{
			next	if	($s =~ /^#/);
			$s =~ s/\s+$//;
			next	if	($s eq "");

			# If line contains data
			if	($s =~ /^(\w+)\s*(.*)$/)
			{
				if( !defined( $x_data{$1} )) { $x_data{$1} = $2; }
				else { $x_data{$1} .= " " . $2; }
				push (@current_recs, $s);
			}
			elsif	($s =~ /^\-\-\-\-\-(\w+)\-\-\-\-\-/)
			{
				$next_record = "\U$1";
				last;
			}
		}
		# Go to next record if there is no data for current record
		next	unless	(scalar (%x_data));

		if	($current_record eq "STATUS")
		{
			$err = &ProcessStatusRecord (\%x_data, $x_file);
		}
		elsif	($current_record eq "PARAMETERS")
		{
			$err = &ProcessParametersRecord (\%x_data, $x_file);
		}
		else
		{
			&LogError (0, "Found invalid data header '$current_record'");
			$err = 1;
		}

		push (@failed_recs, @current_recs)	if	($err);
	}

	close (STATUS_FILE);

	# If we couldn't update EQ database for some targets
	if	(@failed_recs > 0)
	{
		# Write only failed records back to the status file
		if	(open (STATUS_FILE, ">$x_file"))
		{
			print STATUS_FILE join ("\n", @failed_recs), "\n";
			close (STATUS_FILE);
		}
		else
		{
			&LogError (0, "Cannot create file '$x_file': $!");
		}
	}
	else
	{
		# Delete successfully processed status files
		unlink ($x_file) || &LogError (0, "Error removing '$x_file': $!");
	}
}	# end of foreach status file

%x_tdefs = ();
# For each custom file in the directory
foreach $x_file (sort @x_custom) 
{
	# Open log file
	unless( open (CUSTOM_FILE, $x_file) ) {
		&LogError (0, "Cannot open file '$x_file': $!");
		next;
	}

	@failed_recs = ();
	$next_record = "STATUS";

	while ($next_record ne "")
	{
		$err = 0;
		%x_data = ();
		$current_record = $next_record;
		$next_record = "";
		@current_recs = ( "-----${current_record}-----" );
		# Read data from status file and put it into assoc array
		while( defined ($s = <CUSTOM_FILE>) )
		{
			next	if	($s =~ /^#/);
			$s =~ s/\s+$//;
			next	if	($s eq "");

			# If line contains data
			if	($s =~ /^(\w+)\s*=\s*(.*)$/)
			{
				if( !defined( $x_data{$1} )) { $x_data{$1} = $2; }
				else { $x_data{$1} .= " " . $2; }
				push (@current_recs, $s);
			}
			elsif	($s =~ /^\-\-\-\-\-(\w+)\-\-\-\-\-/)
			{
				$next_record = "\U$1";
				last;
			}
		}
		# Go to next record if there is no data for current record
		next	unless	(scalar (%x_data));

		$current_record =~ tr/A-Z/a-z/;
		# See if we have definition for this table. This value will be
		# undefined if we haven't loaded the definition yet, or empty string
		# if there was an error loading the definition
		if	(!defined ($x_tdefs{$current_record}))
		{
			$s = &LoadTableDefFile ($current_record, \%x_tdefs);
			if	($s)
			{
				&EQLogFatalError ($s);
				&LogError (0, $s);
				$x_tdefs{$current_record} = "";
				$err = 1;
			}
		}

		if	($x_tdefs{$current_record})
		{
			$err = &ProcessCustomRecord ($current_record, \%x_data,
				$x_file, $x_tdefs{$current_record});
		}

		push (@failed_recs, @current_recs)	if	($err);
	}

	close (CUSTOM_FILE);

	# If we couldn't update EQ database for some targets
	if	(@failed_recs > 0)
	{
		# Write only failed records back to the status file
		if	(open (CUSTOM_FILE, ">$x_file"))
		{
			print CUSTOM_FILE join ("\n", @failed_recs), "\n";
			close (CUSTOM_FILE);
		}
		else
		{
			&LogError (0, "Cannot create file '$x_file': $!");
		}
	}
	else
	{
		# Delete successfully processed status files
		unlink ($x_file) || &LogError (0, "Error removing '$x_file': $!");
	}
}

&EQ_ExitSQL ();
# Don't forget to remove lock file
unlink ($x_lock);
$s = (($x_updated[0])?
	(($x_updated[0] == 1)? "1 record was": "$x_updated[0] records were"):
		"No records were") .
	" inserted, " . (($x_updated[1])?
	(($x_updated[1] == 1)? "1 record was": "$x_updated[1] records were"):
		"No records were") . " updated";
print $s, "\n";
exit (0);



#-----------------------------------------------
#	Process Status Record
#-----------------------------------------------
sub	ProcessStatusRecord
{
	my	($p_data, $p_file) = @_;
	my	($target, $target_type, $action, $actdesc, $err);
	my	($action_id, $node_id, $job_id, $eq_user, @targets);

	# All data should be provided
	if	( !defined ($$p_data{TIME})  || !defined ($$p_data{TARGET} ) ||
		  !defined ($$p_data{TARGET_TYPE}) || !defined ($$p_data{QTIME}) ||
		  !defined ($$p_data{RESULT}) || !defined ($$p_data{ERROR}) ||
		  !defined ($$p_data{NAME})   || !defined ($$p_data{DESC}) )
	{
		&LogError (0, "Error in file '$p_file': data is missing");
		return 1;
	}

	# Make sure that data is valid
	if( $$p_data{TIME} !~ /^\d+$/) {
		&LogError (0, "Error in '$p_file': found invalid value '$$p_data{TIME}' for TIME");
		return 1;
	}
	
	if( $$p_data{QTIME} !~ /^\d+$/) {
		&LogError (0, "Error in '$p_file': found invalid value '$$p_data{QTIME}' for QTIME");
		return 1;
	}

	if( $$p_data{RESULT} !~ /^(\d*|D|X)$/i) {
		&LogError (0, "Error in '$p_file': found invalid value '$$p_data{RESULT}' for RESULT");
		return 1;
	}

	# TARGET should be provided
	$target = $$p_data{TARGET};
	if( $target eq "") {
		&LogError (0, "Error in '$p_file': found invalid value '$$p_data{TARGET}' for TARGET");
		return 1;
	}

	# Check target type
	$target_type = $$p_data{TARGET_TYPE};
	$target_type =~ s/^\@//;
	if	(!$ValidTargetTypes{$target_type}) 
	{
		&LogError (0, "Error in '$p_file': unsupported target type '$target_type'");
		return 1;
	}

	# Generate action name
	$action = $$p_data{NAME};
	$actdesc = $$p_data{DESC};
	$err = &VerifyAct (\$action, $actdesc, \%x_actions);
	return 1	if	($err);

	# Set job_id variable
	$job_id = $$p_data{JOB_ID} || "NONE";
	$job_id = substr ($job_id, 0, 64);

	# Set eq_user and qgroup variables
	$eq_user = $$p_data{"EQUSER"} || "";
	$eq_user= substr ($eq_user, 0, 32);

	$qgroup = $$p_data{"EQGROUP"} || "";
	$qgroup = substr ($qgroup, 0, 32);
	
	$action_id = $x_actions{$action};
	return 1	if	($action_id == 0);

	@targets = split (/\s*,\s*/, $target);
	foreach $target (@targets)
	{
		# If node is not defined in the database
		unless( defined ($x_nodes{"$target_type:$target:$xc_REGION"})) 
		{
			$err = &AddNewNode ($target_type, $target);
			return 1	if	($err);
			$x_nodes{"$target_type:$target:$xc_REGION"} = $x_node_id;
		}

		$node_id   = $x_nodes{"$target_type:$target:$xc_REGION"};
		# If node is not in the database
		return 1	if	($node_id == 0);

		# Update action status.
		$err = &UpdateActStatus ($node_id, $action_id, $job_id,
				$$p_data{TIME}, 0, $$p_data{RESULT}, $$p_data{ERROR}, $eq_user, $qgroup, $$p_data{QTIME});
		return 1	if	($err);
	}

	return 0;
	
}	# end of Process Status Record


#-----------------------------------------------
#	Process Parameters Record
#-----------------------------------------------
sub	ProcessParametersRecord
{
	my	($p_data, $p_file) = @_;
	my	($action, $actdesc, $err, $action_id, $job_id);

	# All data should be provided
	if	((!defined ($$p_data{PARAMETERS}))||(!defined ($$p_data{NAME}))||
		 (!defined ($$p_data{DESC})))
	{
		&LogError (0, "Error in file '$p_file': data is missing");
		return 1;
	}

	if( $$p_data{PARAMETERS} =~ /^\s*$/) {
		&LogError (0, "Error in '$p_file': found invalid value '$$p_data{PARAMETERS}' for PARAMETERS");
		return 1;
	}

	# Generate action name
	$action = $$p_data{NAME};
	$actdesc = $$p_data{DESC};
	$err = &VerifyAct (\$action, $actdesc, \%x_actions);
	return 1	if( $err );

	$action_id = $x_actions{$action};
	# If action is not in the database
	return 1	if( $action_id == 0 );

	# Set job_id variable
	$job_id = $$p_data{JOB_ID} || "NONE";
	$job_id = substr ($job_id, 0, 64);

	# Update action status.
	$err = &UpdateActParms ($action_id, $job_id, $$p_data{PARAMETERS});
	return ($err)? 1: 0;
}

#-----------------------------------------------
#	Verify Act
#-----------------------------------------------
sub VerifyAct
{
my( $p_action, $desc, $p_acthash ) = @_;
my( $cmd, $s, $err, $l_result );

$$p_action =~ s/[\-\@'\/]+/\-/g;
$$p_action =~ s/^\-+|\-+$//g;

# Truncate action if necessary
$$p_action = substr( $$p_action, -$x_field_len) if( length($$p_action) > $x_field_len);

# return if action is defined in the database
return( 0 ) if( defined($$p_acthash{$$p_action}) );

$x_action_id++;
# Insert new record into the EQ_ACTIONS table
$cmd = "INSERT INTO EQ_ACTIONS (ACTION_NAME, ACTION_DESC, ACTION_ID, STATUS)\n" .
"VALUES ('$$p_action', '$desc', $x_action_id, 'A')";
($err, $s) = &EQ_ExeSQLCmd ($cmd, \$l_result);
if	($err != 0)
{
	&LogError (0, $s);
	$x_action_id--;
	return 1;
}

$x_updated[0]++;
$$p_acthash{$$p_action} = $x_action_id;

return( 0 );

}	# end of Verify Act


#-----------------------------------------------
#	Get DB Action Status information
#-----------------------------------------------
sub GetDBActStatus
{
my( $p_statushash ) = @_;
my( $cmd, $err, $msg, @status, $s, $node_id, $action_id, $job_id);

# Get list of all actions and their ids from the database
$cmd = "SELECT NODE_ID, ACTION_ID, JOB_ID FROM EQ_ACTION_STATUS";
($err, $msg) = &EQ_ExeSQLCmd ($cmd, \@status);
&LogError( 1, $msg ) if( $err );

# For each action status in the list
foreach $s (@status)
{
	($node_id, $action_id, $job_id) = @{$s};
	# Get action name and action id
	if ((defined($job_id))&&($job_id ne ""))
	{
		# Save action name and id
		$$p_statushash{"$node_id $action_id $job_id"} = 1;
	}
	elsif	($s !~ /^\s*$/) {
		&LogError (0, "Cannot get action status info from DB:\n$s");
	}
}

# Free some memory
@status = ();

}	# end of Get DB Acts


#-----------------------------------------------
#	Get DB Action Parameters information
#-----------------------------------------------
sub GetDBActParms
{
my( $p_statushash ) = @_;
my( $cmd, $err, $msg, @status, $s, $action_id, $job_id);

# Get list of all action and job ids from the database
$cmd = "SELECT ACTION_ID, JOB_ID FROM EQ_ACTION_PARMS";
($err, $msg) = &EQ_ExeSQLCmd ($cmd, \@status);
&LogError( 1, $msg ) if( $err );

# For each action status in the list
foreach $s (@status)
{
	# Get action name and action id
	($action_id, $job_id) = @{$s};
	if ((defined($job_id))&&($job_id ne ""))
	{
		# Save action id and job id
		$$p_statushash{"$action_id $job_id"} = 1;
	}
	elsif	($s !~ /^\s*$/) {
		&LogError (0, "Cannot get action parms info from DB:\n$s");
	}
}

# Free some memory
@status = ();

}	# end of Get DB Act Parms

#-----------------------------------------------
#	Add New Node
#-----------------------------------------------
sub AddNewNode
{
my( $type, $node ) = @_;
my( $cmd, $err, $s, $computer, $code, $k, $v, $ts, $l_result );

$code = "U";
foreach $k( %ConvertTypeCode )
{
	$code = $k
		if ((defined ($ConvertTypeCode{$k}))&&($ConvertTypeCode{$k} eq $type));
}

if( $type eq "C" ) { $computer = $node; }
else { $computer = "*"; }
#else { $computer = &EQ_GetComputerName( $type, $node ); }

# Truncate computer name if necessary
if( length($computer) > 64) { substr ($computer, 64) = ""; }

# Generate timestamp
$ts = time( );

$x_node_id++;
# Insert new record into the EQ_NODES table
$cmd = "INSERT INTO EQ_NODES (NODE_NAME, NODE_TYPE, REGION, COMPUTER_NAME, NODE_ID, STATUS, MAC, CREATED_TS)\n" .
"VALUES ('$node', '$code', $xc_REGION, '$computer', $x_node_id, 'A', '', $ts)";
($err, $s) = &EQ_ExeSQLCmd ($cmd, \$l_result);
if	($err != 0)
{
	$x_node_id--;
	&LogError (0, $s);
	return 1;
}

$x_updated[0]++;

return 0;

}	# end of Add New Node


#--------------------------------------------
#	Update Act Status
#--------------------------------------------
sub UpdateActStatus
{
my( $node_id, $action_id, $job_id, $time, $subaction_id, $status, $error, $p_equser, $qgroup, $qtime ) = @_;
my( $cmd, $err, $msg, $s, @a, $i );

# Change status from number to letter
if	($status eq "")
{
	$status = "*";
}
elsif	($status eq "0")
{
	$status = "S";
	# Ignore error message if status is OK and error message
	# just says "Reason unknown";
	$error = ""	if( $error =~ /^Reason unknown/i);
}
elsif	($status eq "2") { $status = "F"; }
elsif	($status eq "3") { $status = "W"; }
elsif	(($status ne "D")&&($status ne "X")) { $status = "E"; }

# Make sure error message does not contain single quotes and unprinted characters
# (single quotes will be converted to double quotes)
$error =~ tr/\t\n/ /;
$error =~ tr/\x00-\x1F\x7F-\xFF//d;
$error =~ s/'/"/g;
$job_id =~ s/'/"/g;

# Truncate error message if it's longer than 256 characaters
substr ($error, $xc_ERROR_LENGTH) = ""
	if	(length ($error) > $xc_ERROR_LENGTH);
$error =~ s/\\/\\\\/g
	if	((defined ($xc_DB_VENDOR))&&($xc_DB_VENDOR =~ /MySQL/i));

$subaction_id = "NULL" if( $subaction_id == 0 );

my	$index = 0;
# check if we need to insert the record or update it
if	(defined ($x_status{"$node_id $action_id $job_id"}))
{
	$cmd = "UPDATE EQ_ACTION_STATUS SET TIME = $time, QTIME=$qtime, " .
		 "SUBACTION_ID = $subaction_id, STATUS = '$status', " .
		 "ERROR = '$error', EQUSER = '$p_equser', EQGROUP = '$qgroup' " .
		 "WHERE NODE_ID = $node_id AND ACTION_ID = $action_id AND JOB_ID='$job_id'";
	$index = 1;
}
else
{
	$cmd = "INSERT INTO EQ_ACTION_STATUS" .
		"( TIME, QTIME, NODE_ID, ACTION_ID, JOB_ID, SUBACTION_ID, EQUSER, EQGROUP, STATUS, ERROR ) " .
		"VALUES ( $time, $qtime, $node_id, $action_id, '$job_id', $subaction_id, '$p_equser', '$qgroup', '$status', '$error' )";
}
($err, $msg) = &EQ_ExeSQLCmd ($cmd, \$i);
if	($err != 0)
{
	&LogError (0, $msg);
	return 1;
}

$x_updated[$index]++;
$x_status{"$node_id $action_id $job_id"} = 1;

return 0;
}	# end of Update Act Status

#--------------------------------------------
#	Update Action Parameters
#--------------------------------------------
sub UpdateActParms
{
my( $action_id, $job_id, $p_parms) = @_;
my( $cmd, $err, $msg, $s, @a, $i );

# Make sure error message does not contain single quotes and unprinted characters
# (single quotes will be converted to double quotes)
$p_parms =~ tr/\t\n/ /;
$p_parms =~ tr/\x00-\x1F\x7F-\xFF//d;
$p_parms =~ s/'/"/g;
$job_id  =~ s/'/"/g;
if	(length ($p_parms) > 1024)
{
	&LogError (0, "PARAMETERS value is too long");
	return 1;
}

$p_parms =~ s/\\/\\\\/g
	if	((defined ($xc_DB_VENDOR))&&($xc_DB_VENDOR =~ /MySQL/i));

my	$index = 0;
# check if we need to insert the record or update it
if	(defined ($x_action_parms{"$action_id $job_id"}))
{
	$cmd = "UPDATE EQ_ACTION_PARMS SET PARAMETERS = '$p_parms' " .
		   "WHERE ACTION_ID = $action_id AND JOB_ID='$job_id'";
	$index = 1;
}
else
{
	$cmd = "INSERT INTO EQ_ACTION_PARMS ( ACTION_ID, JOB_ID, PARAMETERS ) " .
		"VALUES ( $action_id, '$job_id', '$p_parms' )";
}
($err, $msg) = &EQ_ExeSQLCmd ($cmd, \$i);
if	($err != 0)
{
	&LogError (0, $msg);
	return 1;
}

$x_updated[$index]++;
$x_action_parms{"$action_id $job_id"} = 1;

return 0;
}	# end of Update Act Parms

#--------------------------------------------
#	Log Error
#--------------------------------------------
sub LogError
{
my( $err, $message ) = @_;
my( @a, @tmarr, $tm );

print "LogError: $message\n";

@tmarr = localtime( time );
$tm = sprintf( "%d/%02d/%02d %02d:%02d:%02d", $tmarr[5]+1900, $tmarr[4]+1, $tmarr[3], $tmarr[2], $tmarr[1], $tmarr[0] );
if	(open (LOG_FILE, ">>$x_logfile"))
{
	@a = split ("\n", $message);
	print LOG_FILE "***  $tm  ", join ("\n    ", @a), "\n";
	close (LOG_FILE);
}
else
{
	warn ("Cannot open file '$x_logfile' for writing: $!\n");
}

if( $err )
{
	unlink ($x_lock)	if	($x_lock ne "");
	&EQ_ExitSQL ();
	print "$message\n";
	exit( $err );
}

}	# end of Log Error


#--------------------------------------------
#	Load Table Def File
#--------------------------------------------
sub	LoadTableDefFile
{
	my	($p_table, $p_tdef) = @_;
	my	(@a, $s, $file, %hash, $field, $type, $min, $max, $flag, $def);

	%hash = ();
	$file = "$xc_EQ_PATH/cfg/$p_table.tdef";
	# Read file into memory
	open (DEF_FILE, $file) ||
		return "Error opening table definition file '$file': $!";
	while (defined ($s = <DEF_FILE>))
	{
		$s =~ s/\s+$//;
		next	if	(($s eq "")||($s =~ /^#/));
		($field, $type, $min, $max, $flag, $def) = split (/\s*,\s*/, $s, 6);
		# Do simple validation
		return "EQF0200 Non-alphanumeric field name '$field' in line '$s' in table definition '$p_table'"
			if	($field !~ /^\w+$/);
		return "EQF0201 Unsupported data type '$type' in line '$s' in table definition '$p_table'"
			if	($type !~ /^(INT|STR)$/i);
		return "EQF0202 Invalid minimum value '$min' in line '$s' in table definition '$p_table'"
			if	($min !~ /^\d*$/i);
		return "EQF0203 Invalid maximum value '$max' in line '$s' in table definition '$p_table'"
			if	($max !~ /^\d*$/i);
		return "EQF0204 Invalid FLAG '$flag' in line '$s' in table definition '$p_table'"
			if	($flag !~ /^[RI]*$/i);
		$def = ""	if	(!defined ($def));

		return "EQF0205 Duplicate definition of field '$field' in table definition '$p_table'"
			if	($hash{$field});

		# Store data into hash
		$hash{$field}{TYPE} = $type;
		$hash{$field}{MIN}  = $min;
		$hash{$field}{MAX}  = $max;
		$hash{$field}{FLAG} = $flag;
		$hash{$field}{DEF}  = $def;
	}
	close (DEF_FILE);

	$$p_tdef{$p_table} = \%hash;
	return "";
}

#-----------------------------------------------
#	Process Custom Record
#-----------------------------------------------
sub	ProcessCustomRecord
{
	my	($p_table, $p_data, $p_file, $p_tdef) = @_;
	my	($err, $msg, $field, $tdef, $value, @where, @keyvals, @columns, @values);
	my	($cmd, $s, @a, $i);

	@where = ();
	@keyvals = ();
	@columns = ();
	@values = ();
	# Verify all required data was provided and get default values if
	# necessary
	foreach $field (keys %$p_tdef)
	{
		$tdef = $$p_tdef{$field};
		$value = $$p_data{$field};
		if	(!defined ($value))
		{
			# Return error if this is a required field
			if	($$tdef{FLAG} =~ /R/)
			{
				&LogError (0, "EQF0206 Error in file '$p_file': required field '$field' is not provided");
				return 1;
			}
			# Set default value otherwise
			$value = $$tdef{DEF};
		}
		# Make sure value does not contain single quotes and unprinted characters
		# (single quotes will be converted to double quotes)
		$value =~ tr/\t\n/ /;
		$value =~ tr/\x00-\x1F\x7F-\xFF//d;
		$value =~ s/'/"/g;
		$value =~ s/\\/\\\\/g
			if	((defined ($xc_DB_VENDOR))&&($xc_DB_VENDOR =~ /MySQL/i));

		# Use default value if provided and value is blank (nothing but spaces)
		$value = $$tdef{DEF} if( $value =~ /^\s*$/ && defined($$tdef{DEF}) );
		
		# Make sure data is within limits
		if	($$tdef{TYPE} eq "INT")
		{
			&LogError (0, "EQF0207 Error in file '$p_file': field '$field' should be numeric")
				if	($value !~ /^\d+$/);
			&LogError (0, "EQF0208 Error in file '$p_file': field '$field' should be greater or equal to '$$tdef{MIN}'")
				if	(($$tdef{MIN} ne "")&&($value < $$tdef{MIN}));
			&LogError (0, "EQF0209 Error in file '$p_file': field '$field' should be less or equal to '$$tdef{MIN}'")
				if	(($$tdef{MAX} ne "")&&($value > $$tdef{MAX}));
			push (@keyvals, "$field = $value");
			push (@columns, $field);
			push (@values, $value);
			push (@where, "$field = $value")	if	($$tdef{FLAG} =~ /I/);
		}
		else
		{
			&LogError (0, "EQF0210 Error in file '$p_file': length of field '$field' should be greater or equal to '$$tdef{MIN}'")
				if	(($$tdef{MIN} ne "")&&(length ($value) < $$tdef{MIN}));
			$value = substr ($value, 0, $$tdef{MAX})
				if	(($$tdef{MAX} ne "")&&(length ($value) > $$tdef{MAX}));
			push (@keyvals, "$field = '$value'");
			push (@columns, $field);
			push (@values, "'$value'");
			push (@where, "$field = '$value'")	if	($$tdef{FLAG} =~ /I/);
		}
		$$p_data{$field} = $value;
	}

	$p_table =~ tr/a-z/A-Z/;
	# We will update data only if "Where" data was provided
	if	(@where > 0)
	{
		$cmd = "UPDATE $p_table SET " . join (", ", @keyvals) .
			" WHERE " . join (" AND ", @where);
		($err, $msg) = &EQ_ExeSQLCmd ($cmd, \$i);
		#&LogError( 0, "ERR: $err  MSG: $msg  CMD: $cmd" );
		# If update fails then we will try to insert data 
		if	(($err == 0)&&($i > 0))
		{
			$x_updated[1]++;
			return 0;
		}
	}

	# If update failed try to insert data
	$cmd = "INSERT INTO $p_table ( ". join (", ", @columns ) .
		" ) VALUES ( " . join (", ", @values) . " )";
	($err, $msg) = &EQ_ExeSQLCmd ($cmd, \$i);
	#&LogError( 0, "ERR: $err  MSG: $msg  CMD: $cmd" );
	if	($err != 0)
	{
		&LogError (0, $msg);
		return 1;
	}
	$x_updated[0]++;

	return 0;
}
