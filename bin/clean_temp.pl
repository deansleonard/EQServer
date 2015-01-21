#!C:/dean/EQ-Working/EQServer/perl5/bin/perl
#
# clean_temp.pl
#
# (C) Copyright 1998, Capital Software Corporation

if	((@ARGV == 1)&&($ARGV[0] eq "-v"))
{
	print '$Id: clean_temp.pl,v 1.5 2014/11/06 23:31:37 eqadmin Exp $', "\n";
	exit (0);
}

use DBI;

# Get EQ configuration data
$s = $ENV{EQHOME} . "/cfg/setup_env.pl";
open (IN_FILE, "$s") || &LogMsg( "Cannot open file '$s': $!\n", 1);
$s = join ("", <IN_FILE>);
close (IN_FILE);
eval "$s";

require ("$xc_EQ_PATH/lib/www_gui.pl");
require ("$xc_EQ_PATH/lib/EQAction.pl");

# Location of the log file
$x_logfile = $xc_EQ_PATH . "/logs/clean_temp.log";

%x_config = ();

%x_dirs = ();

# Name of configuration file
$x_config_file = "$xc_EQ_PATH/cfg/clean_temp.cfg";


	&EQ_UpdateEnv ();
	$s = &EQ_LoadIniFile ($x_config_file, \%x_config);
	&LogError (1, "Cannot load file '$x_config_file': $!")
		if	($s);

	@x_files = keys %x_config;
	$x_time = time ();
	foreach $x_dir (@x_files)
	{
		next	if	($x_dir !~ m#^(.+)/([^/]+)$#);
		$l_dir = $1;
		$l_mask = $2;
		$i = $x_config{$x_dir}{DISABLE} || 0;
		next	if	($i);
		$days = $x_config{$x_dir}{EXPIRE} || 0;
		if	(($days !~ /^\d+$/)||($days eq "0"))
		{
			&LogError (0, "Invalid data '$x_dir' in file '$x_config_file'");
			next;
		}
		&CleanDir ($l_dir, $l_mask, $x_time - $days * 86400);
	}


	($err, $msg) = &EQ_InitSQL ();
	&LogError (1, $msg)	if	($err != 0);

######################################################
#
#		Remove old data from the database
#
######################################################

	foreach $x_table (@x_files)
	{
		next	if	($x_table =~ m#/#);
		$i = $x_config{$x_table}{DISABLE} || 0;
		next	if	($i);
		$days = $x_config{$x_table}{EXPIRE} || 0;
		$l_field = $x_config{$x_table}{COLUMN} || "";
		if	(($days !~ /^\d+$/)||($days eq "0"))
		{
			&LogError (0, "Invalid data '$x_table' in file '$x_config_file'");
			$x_table = "";
			next;
		}
		if	($l_field =~ /^\s*$/)
		{
			&LogError (0, "Invalid data '$x_table' in file '$x_config_file'");
			$x_table = "";
			next;
		}

		$days = $x_time - $days * 86400;
		$l_recs = "";
		$cmd    = "DELETE FROM $x_table WHERE $l_field < $days";
		($err, $msg) = &EQ_ExeSQLCmd ($cmd, \$l_recs);
		&LogError (0, $msg) if	($err);
	}

######################################################
#
#		Remove orhaned records in the database
#
######################################################

	%x_nodes = ();
	# Get a list of all currently defined Node IDs in RDBMS
	$cmd = "SELECT NODE_ID FROM EQ_NODES";
	@l_status = ();
	($err, $msg) = &EQ_ExeSQLCmd ($cmd, \@l_status);
	&LogError (1, $msg) if	($err);

	# For each node id in the list
	foreach $s (@l_status)
	{
		($node_id) = @{$s};
		$x_nodes{$node_id} = 1	if	($node_id);
	}

	%x_actions = ();
	# Get a list of all currently defined Node IDs in RDBMS
	$cmd = "SELECT ACTION_ID FROM EQ_ACTIONS";
	@l_status = ();
	($err, $msg) = &EQ_ExeSQLCmd ($cmd, \@l_status);
	&LogError (1, $msg) if	($err);

	# For each action id in the list
	foreach $s (@l_status)
	{
		($action_id) = @{$s};
		$x_actions{$action_id} = 1	if	($action_id);
	}

	# Get list of all actions and their ids from the database
	$cmd = "SELECT NODE_ID, ACTION_ID, SUBACTION_ID FROM EQ_ACTION_STATUS";
	@l_status = ();
	($err, $msg) = &EQ_ExeSQLCmd ($cmd, \@l_status);
	&LogError (1, $msg) if	($err);

	# For each action status in the list
	foreach $s (@l_status)
	{
		($node_id, $action_id, $subaction_id) = @{$s};
		delete $x_nodes  {$node_id}
			if	(($node_id)&&(defined ($x_nodes{$node_id})));
		delete $x_actions{$action_id}
			if	(($action_id)&&(defined ($x_actions{$action_id})));
		delete $x_actions{$subaction_id}
			if	(($subaction_id)&&(defined ($x_actions{$subaction_id})));
	}

	# Delete all node ids that don't have child records
	@a = keys %x_nodes;
	foreach $s (@a)
	{
		next	if	($s !~ /^\d+$/);

		$l_recs = "";
		$cmd = "DELETE FROM EQ_NODES WHERE NODE_ID = $s";
		($err, $msg) = &EQ_ExeSQLCmd ($cmd, \$l_recs);
		&LogError (0, $msg) if	($err);
	}

	# Delete all action ids that don't have child records
	@a = keys %x_actions;
	foreach $s (@a)
	{
		next	if	($s !~ /^\d+$/);

		$l_recs = "";
		$cmd = "DELETE FROM EQ_ACTIONS WHERE ACTION_ID = $s";
		($err, $msg) = &EQ_ExeSQLCmd ($cmd, \$l_recs);
		&LogError (0, $msg) if	($err);
	}

	# All done!
	&EQ_ExitSQL ();
	print "Completed Successfully\n";
	exit (0);


sub	CleanDir
{
	local	($p_dir, $p_mask, $p_time) = @_;
	local	(@a, $l_file, $l_dir, @files);

	$p_mask =~ s/(^|[^\\])([\*\+\?\.\~\!\@\$\(\)\|])([^\{]|$)/$1\\$2$3/g;
	$p_mask =~ s/(^|[^\\])([\*\+\?\.\~\!\@\$\(\)\|])([^\{]|$)/$1\\$2$3/g;
	$p_mask =~ s/(^|[^\\])([\*\+\?\.\~\!\@\$\(\)\|])([^\{]|$)/$1\\$2$3/g;

	$l_dir = $xc_EQ_PATH . "/" . $p_dir;
	if	(!exists ($x_dirs{$l_dir}))
	{
		# Get all temp.* files from TEMP directory
		unless	(opendir (TEMP_DIR, $l_dir))
		{
			&LogError (0, "Cannot open directory '$l_dir': $!");
			return;
		}
		@{$x_dirs{$l_dir}} = readdir (TEMP_DIR);
		closedir (TEMP_DIR);
	}
	@files = @{$x_dirs{$l_dir}};

	# For each file in the directory
	foreach $l_file (@files)
	{
		# If this file matches a mask
		if	($l_file =~ /^$p_mask$/i)
		{
			$l_file = $l_dir . "/" . $l_file;
			# Get last modification time of the file
			@a = stat ($l_file);
			if	((defined (@a))&&(@a != 0))
			{
				# If file is too old
				if	($a[9] <= $p_time)
				{
					# ... delete it
					unlink ($l_file) ||
						&LogError (0, "Cannot delete file '$l_file': $!");
				}
			}
			else
			{
				&LogError (0,
					"Cannot stat the file '$l_file': $!");
			}
		}
	}
}


sub		LogError
{
	local	($p_exit, $p_message) = @_;
	my		(@a, @tmarr, $tm);

	@tmarr = localtime (time());
	$tm = sprintf ("%d/%02d/%02d %02d:%02d:%02d", $tmarr[5]+1900, $tmarr[4]+1, $tmarr[3], $tmarr[2], $tmarr[1], $tmarr[0]);
	if	(open (LOG_FILE, ">>$x_logfile"))
	{
		@a = split ("\n", $p_message);
		print LOG_FILE "***  $tm  ", join ("\n    ", @a), "\n";
		close (LOG_FILE);
	}
	else
	{
		warn ("Cannot open file '$x_logfile' for writing: $!\n");
	}

	if ($p_exit)
	{
		&EQ_ExitSQL ();
		print "$p_message\n";
		exit ($p_exit);
	}

}
