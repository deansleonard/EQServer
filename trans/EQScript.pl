#!C:/dean/EQ-Working/EQServer/perl5/bin/perl
#
# script.pl
#
# Read script alias file to correspond script alias with file
#	scr1=script1.txt
#	scr2=script2.txt
#	scr3=script3.txt
#
# Parse message for elements including:
#	t_tid
#	t_target
#	script (alias)
#	step
#
# Parse script keyword to determine script file to read. Format
# should be alias name(s) seperated by vertical bar (|):
#	script=scr3|scr2|scr1
#
# Consider "first" script alias (scr3 in above example). Compare
# to elements read from script alias file to find alias's script
# filename:
#	scr3=script3.txt
#
# Now parse step keyword to determine step within file. Format
# should be step(s) seperated by vertical bar (|):
#	step=start|step3|step2
#
# For example, if there are three script, there should be three
# steps; one for each script.
#
# "special" step(s);
#	START - read first step
#	EXIT - exit current script
#
# If no step exists, step=START is assumed
#
# If not a special step, find step in script, then read file for
# next step.  Process this step for special instructions (TBD):
#	if blah then stepA else stepB
# or	script scr2 (implies step=START)
# or	step stepN (read stepN in current script)
#
# If next step found, append msg with (following example above):
#	t_target=target;
#	script=scr3|scr2|scr1;
#	step=thisstep|step3|step2
#
# If end of file, strip first step and first script from key
# values and attempt to process it as stated above:
#	script=scr2
#	step=step3
#
#

if	((@ARGV == 1)&&($ARGV[0] eq "-v"))
{
	print '$Id: Script.pl,v 1.3 2014/11/06 23:36:55 eqadmin Exp $', "\n";
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
require( "$xc_EQ_PATH/lib/EQConfig.pl" );
require( "$xc_EQ_PATH/lib/EQNode.pl" );

$DEF_PORT 		= 2345;
$DEF_SCRIPTALIAS 	= "$xc_EQ_PATH/cfg/scriptalias.cfg";
$DEF_CFG		= "$xc_EQ_PATH/cfg/script.cfg";

$G_Debug = 0;

# %G_ConfigMod = ();

%G_Config =
(
	"CONFIGFILE"	=> $DEF_CFG,
	"INTERACTIVE"	=> 1,	# controls logging to STDOUT
	"LOGFILEDIR"	=> "./logs",
	"PORT"		=> $DEF_PORT,
	"SCRIPTALIAS"	=> $DEF_SCRIPTALIAS,
	"*" 			=>  0
);


sub	GetScriptElements;
sub	CheckNextVars;
sub	DetermineNextStep;
sub	PreProcessStep;
sub	GetEQMsg;
sub	GetNextStep;
sub	GetStepMsg;
sub	GetItem;
sub	GetFName;
sub	ProcessIf;
sub	LogMsg;
sub	DisplayParms;
sub	InitConfigMod;
sub	ReadCfgFile;

my( %hash, $tid, $target, $ttype, $scripts, $steps, $nextstep, $appargs );
my( $autobatch, $batchid, $jobid, $G_test ) = 0;

( $buf ) = @ARGV;

%hash = &HashMsg( \$buf );

if	($G_Debug)
{
	foreach $key( sort keys %hash ) { &LogMsg( \"$key = $hash{$key}" ); }
}

$pri = "";
$jobid = "";
$autobatch = "";
$batchid = "";
$nextscript = "";
$nextstep = "";
$steps = "START";
$x_equser = "";

&GetScriptElements( \%hash, \$tid, \$target, \$ttype, \$scripts,
	\$steps, \$nextscript, \$nextstep, \$appargs, \$autobatch, \$batchid,
	\$pri, \$jobid, \$x_equser, \$G_test );

if( !defined($tid) || !defined($target) || !defined($scripts) ) {
	$msg = "$0 must get T_TID, T_TARGETS, and SCRIPT arguments\n";
	if( !$G_test )
	{
		&SendMsg( \"T_MSG=STARTED;T_TID=$tid;T_PID=$$;T_RESULT=1;T_REASON=$msg");
	}
	exit( 1 );
}

# Read configuration file
# &ReadCfgFile( \$G_Config{"CONFIGFILE"}, \%G_Config, \%G_ConfigMod );

# Send startup status
&SendMsg( \"T_MSG=STARTED;T_TID=$tid;T_PID=$$;T_RESULT=0" ) if( !$G_test );

# First, follow nextstep and/or nextscript keywords
if( $nextscript ne "" || $nextstep ne "" ) {
	&CheckNextVars( \$scripts, \$steps, $nextscript, $nextstep ); }
# Otherwise, find next step in script processing
else { 
	&DetermineNextStep( \$scripts, \$steps ); }

# Process directives in script (IF's, GOTO's, etc)
if( $scripts ne "" && $steps ne "" ) {
	&PreProcessStep( \$scripts, \$steps, $target ); }

if( $scripts eq "" && $steps eq "" ) {
	&LogMsg( \"No more scripts\\steps left to process for $target\n" )
		if	($G_Debug);
}
else
{
	# Get EQ msg from file
	($status, $msg) = &GetEQMsg($scripts, $steps);
	if( $status )
	{
		# If transaction is a script
		if	($msg =~ /(^|;|')SCRIPT=([^\';]+)('|;|$)/i)
		{
			$scripts = $2 . "|" . $scripts;
			$steps   = "START|" . $steps;
			$msg =~ s/(^|;|')(SCRIPT=)[^\s\';]+('|;|$)/$1$2$scripts$3/i;
			$msg .= ";T_TARGET=$target;T_TARGETTYPE=$ttype;STEP=$steps;T_EQUSER=$x_equser";
			# Remove reference to next transaction
			$msg =~ s/(^|;|')T_NEXTTRANS=[^\';]+('|;|$)/$1$2/i;
		}
		else
		{
			$msg .= ";T_TARGET=$target;T_TARGETTYPE=$ttype;SCRIPT=$scripts;STEP=$steps;T_EQUSER=$x_equser;RECORD=1";
		}

		if( length($appargs) > 0 )
		{
			%l_new_hash = &HashMsg (\$msg);
			%l_old_hash = &HashMsg (\$appargs);

			# For each key an application arguments
			foreach $s( keys %l_old_hash )
			{
				# Add this key/value to resulting message only
				# if the same key was not specified in the script file
				$msg .= ";$s=$l_old_hash{$s}" if( !defined ($l_new_hash{$s}));
			}
		}

		# propagate batch id; 'T_AUTOBATCH' for EQServer processing, 
		# 'AUTOBATCH' as apparg to be passed for subsequent step processing
		if	($autobatch ne "")
		{
			# Remove existing AUTOBATCH/T_AUTOBATCH keywords
			$msg =~ s/(^|;|')(AUTOBATCH|T_AUTOBATCH)=[^\';]*('|;|$)/$1$3/i;
			$msg .= ";T_AUTOBATCH=$autobatch;AUTOBATCH=$autobatch";
		}

		# propagate batch id; 'T_BATCHID' for EQServer processing, 
		# 'BATCHID' as apparg to be passed for subsequent step processing
		if	($batchid ne "")
		{
			# Remove existing BATCHID/T_BATCHID keywords
			$msg =~ s/(^|;|')(BATCHID|T_BATCHID)=[^\';]*('|;|$)/$1$3/i;
			$msg .= ";T_BATCHID=$batchid;BATCHID=$batchid";
		}

		# propagate priority; 'T_PRIORITY' for EQServer processing, 
		# 'PRIORITY' as apparg to be passed for subsequent step processing
		if	($pri ne "")
		{
			# Remove existing PRIORITY/T_PRIORITY keywords
			$msg =~ s/(^|;|')(PRIORITY|T_PRIORITY)=[^\';]*('|;|$)/$1$3/i;
			$msg .= ";T_PRIORITY=$pri;PRIORITY=$pri";
		}

		# propagate job id; 'T_JOBID' for EQServer processing, 
		# 'JOBID' as apparg to be passed for subsequent step processing
		if	($jobid ne "")
		{
			# Remove existing JOBID/T_JOBID keywords
			$msg =~ s/(^|;|')(JOBID|T_JOBID)=[^\';]*('|;|$)/$1$3/i;
			$msg .= ";T_JOBID=$jobid;JOBID=$jobid";
		}
	}
	# Remove duplicate semicolumns - these could be created by eliminating
	# some of the keywords
	$msg =~ s/;{2,}/;/g;

	if( $status == 0 || $G_test == 1 ) { 
		&LogMsg (\"$msg\n");
	}
	else {
		&SendMsg (\"$msg");
	}
}

# Send status and finished messages
&StopProcessing (0, "") if( !$G_test );

exit( 0 );



#-------------------------------------------------------#
#	Stop Processing
#-------------------------------------------------------#
sub		StopProcessing
{
local	($p_result, $p_error) = @_;

$p_error = ";T_REASON=" . $p_error		if	($p_error ne "");
&SendMsg (\"T_MSG=STATUS;T_TID=$tid;T_TARGET=$target;T_RESULT=$p_result$p_error");
&SendMsg (\"T_MSG=FINISHED;T_TID=$tid;T_PID=$$;T_RESULT=0");
exit ($p_result);

}	# end of Stop Processing



#-------------------------------------------------------#
# Get Script Elements
#-------------------------------------------------------#
sub GetScriptElements
{
my( $p_hash, $p_tid, $p_target, $p_ttype, $p_scripts, $p_steps,
    $p_nextscript, $p_nextstep, $p_appargs, $p_autobatch, $p_batchid, $p_pri,
	$p_jobid, $p_equser, $p_test ) = @_;
my( $key );

$$p_appargs = "";
foreach $key ( keys %$p_hash ) {
	if( $key eq "T_TID" ) { $$p_tid = $$p_hash{$key}; }
	elsif( $key eq "T_TARGETS" ) { $$p_target = $$p_hash{$key}; }
	elsif( $key eq "T_TARGETTYPE" ) { $$p_ttype = $$p_hash{$key}; }
	elsif( $key eq "PRIORITY" )  { $$p_pri = $$p_hash{$key}; }
	elsif( $key =~ /^SCRIPT$/i ) { $$p_scripts = $$p_hash{$key}; }
	elsif( $key eq "STEP" ) { $$p_steps = $$p_hash{$key}; }
	elsif( $key eq "NEXTSCRIPT" ) { $$p_nextscript = $$p_hash{$key}; }
	elsif( $key eq "NEXTSTEP" ) { $$p_nextstep = $$p_hash{$key}; }
	elsif( $key eq "AUTOBATCH" ) { $$p_autobatch = $$p_hash{$key}; }
	elsif( $key eq "BATCHID" ) { $$p_batchid = $$p_hash{$key}; }
	elsif( $key eq "JOBID" ) { $$p_jobid = $$p_hash{$key}; }
	elsif( $key eq "T_EQUSER" ) { $$p_equser = $$p_hash{$key}; }
	elsif( $key eq "TEST" ) { $$p_test = $$p_hash{$key}; }
	# otherwise, append to appargs with semi-colon
	elsif	($key ne "T_PROFILE")
	{ $$p_appargs .= "$key=$$p_hash{$key};"; }
}
# remove ending semi-colon on appargs
chop( $$p_appargs );

}	# end of Get Script Elements


#-------------------------------------------------------#
# Check Next Vars
#-------------------------------------------------------#
sub CheckNextVars
{
my( $p_scripts, $p_steps, $nextscript, $nextstep ) = @_;
my( $temp, $step );

if( length($nextstep) > 0 ) { $step = $nextstep; }
else { $step = "START"; }

if( length($nextscript) > 0 ) {
	if( $$p_scripts eq "" ) { $$p_scripts = $nextscript; }
	else { $$p_scripts = "$nextscript\|$$p_scripts"; }
}
else {
	# pop current step, before pushing new step
	$temp = &GetItem( $p_steps );
}

if( $$p_steps eq "" ) { $$p_steps = $step; }
else { $$p_steps = "$step\|$$p_steps"; }

if( $step =~ /^START$/i ) { &DetermineNextStep( $p_scripts, $p_steps ); }

}	# end of Check Next Vars


#-------------------------------------------------------#
# Determine Next Step
#-------------------------------------------------------#
sub DetermineNextStep
{
my( $p_scripts, $p_steps ) = @_;
my( $script, $step );

$script = &GetItem( $p_scripts );
if( length($script) == 0 ) { return; }

$step = &GetItem( $p_steps );
if( length($step) == 0 ) { return; }

( $step ) = GetNextStep( $script, $step );
if( length($step) == 0 ) {
	# end of script, so try next script
	&LogMsg( \"No more steps in $script.\n" )	if	($G_Debug);
	&UpdateStatusFile ($target, $ttype, $script, 0, "", $jobid, $x_equser);
	# call routine again until no more scripts to process
	&DetermineNextStep( $p_scripts, $p_steps );
}

else {
	if( $$p_steps eq "" ) { $$p_steps = $step; }
	else { $$p_steps = "$step\|$$p_steps"; }
	if( $$p_scripts eq "" ) { $$p_scripts = $script; }
	else { $$p_scripts = "$script\|$$p_scripts"; }
}

}	# end of Determine Next Step


#-------------------------------------------------------#
#  Get Next Step
#-------------------------------------------------------#
sub GetNextStep
{
my( $script, $step ) = @_;
my( $fname, $foundstep, $newstep );

$fname = &GetFName ($script, $G_Config{SCRIPTALIAS});
if	(length($fname) == 0)
{
	&StopProcessing (1, "Alias '$script' not found in file '$G_Config{SCRIPTALIAS}'");
}

unless	(open (FH, $fname))
{
	&StopProcessing (1, "Error opening file, '$fname': $!");
}

if( $G_test ) { &LogMsg( \"Searching $fname for step: $step\n" ); }

$foundstep = 0;
while( <FH> ) {

	# Skip comments and empty lines
	next	if( $_ =~ /^\s*$/ );
	next	if( $_ =~ /^\s*#/ );

	# parse out "step"
	$_ =~ s/^\s*([^=\s]+)\s*=\s*//;
	$newstep = $1;

	# return first step if "START"
	if( $step =~ /^START$/i ) {
		close( FH );
		return($newstep);
	}

	# return if step was found
	if( $foundstep == 1 ) {
		close( FH );
		return($newstep);
	}

	if( $newstep =~ /^${step}$/i ) { $foundstep = 1; }
	$newstep = "";

}

close( FH );

if( $foundstep == 0 ) { $newstep = ""; }
return( $newstep );

}	# end of Get Next Step


#-------------------------------------------------------#
# Get EQ Msg
#-------------------------------------------------------#
sub GetEQMsg
{
my( $scripts, $steps ) = @_;
my( $msg, $script, $step );

$script = &GetItem( \$scripts );
if( length($script) == 0 ) {
	return( 0, "No more scripts to process\n" ); }

$step = &GetItem( \$steps );
if( length($step) == 0 ) {
	return( 0, "No more steps to process\n" ); }

if	($G_Debug)
{
	&LogMsg( \"Get EQ Msg: SCRIPTS: $scripts       SCRIPT: $script" );
	&LogMsg( \"            STEPS: $steps       STEP: $step" );
}

( $msg ) = &GetStepMsg( $script, $step );

return( 1, $msg );

}	# end of Get EQ Msg


#-------------------------------------------------------#
# Pre Process Step
#-------------------------------------------------------#
sub PreProcessStep
{
my( $p_scripts, $p_steps, $target ) = @_;
my( $msg, $scripts, $steps, $script, $step, $temp, $err );

# work on copy unless/until cmd found
$scripts = $$p_scripts;
$steps = $$p_steps;

$script = &GetItem( \$scripts );
$step = &GetItem( \$steps );

if	($G_Debug)
{
	&LogMsg( \"Pre Process Step: SCRIPTS: $scripts       SCRIPT: $script\n" );
	&LogMsg( \"                  STEPS: $steps       STEP: $step\n" );
}

return	if	(($script eq "")&($step eq ""));

( $msg ) = &GetStepMsg( $script, $step );

if( $msg =~ /^\s*EXIT\s*$/i ) {
	&UpdateStatusFile ($target, $ttype, $script, 0, "", $jobid, $x_equser);
	# pop script and step off orig stacks and try again
	$script = &GetItem( $p_scripts );
	$step = &GetItem( $p_steps );
	&DetermineNextStep( $p_scripts, $p_steps );
	&PreProcessStep( $p_scripts, $p_steps, $target );
	return;
}

$script = "";
$step = "";

# For IF statement, extract step and replace, then call
if( $msg =~ /^\s*IF\s+/i ) {
	($err, $step) = &ProcessIf( $target, $msg );
	if	($err ne "")
	{
		&StopProcessing (1, "IF statement error in script: $err");
	}
	elsif	($step ne "")
	{
		$temp = &GetItem( $p_steps );
		if( $$p_steps eq "" ) { $$p_steps = $step; }
		else { $$p_steps = "$step\|$$p_steps"; }
	}
	else
	{
		&DetermineNextStep( $p_scripts, $p_steps );
	}
	&PreProcessStep( $p_scripts, $p_steps, $target );
	return;
}

if	($msg =~ /\s*GOTO\s+([^:]*):(.*)$/i)
{
	$script = $1;
	$step = $2;
	$step =~ s/\s+$//;
}
elsif	($msg =~ /\s*GOTO\s+([^:]+)$/i)
{
	$step = $1;
	$step =~ s/\s+$//;
}

if( $msg =~ /\s*GOTOSCRIPT\s*=\s*(\S+)/i ) { $script = $1; }
if( $msg =~ /\s*GOTOSTEP\s*=\s*(\S+)/i ) { $step = $1; }

# if neither set, must be a regular step, so return
if( ($script eq "") && ($step eq "") ) { return; }

# If both exist, add to lists, and call Pre Processor again
if( ($script ne "") && ($step ne "") ) {
	if( $$p_steps eq "" ) { $$p_steps = $step; }
	else { $$p_steps = "$step\|$$p_steps"; }
	if( $$p_scripts eq "" ) { $$p_scripts = $script; }
	else { $$p_scripts = "$script\|$$p_scripts"; }
	&PreProcessStep( $p_scripts, $p_steps, $target );
	return;
}

# If just $script set, add to lists assuming START as step
elsif( ($script ne "") && ($step eq "") ) {
	if( $$p_steps eq "" ) { $$p_steps = "START"; }
	else { $$p_steps = "START\|$$p_steps"; }
	if( $$p_scripts eq "" ) { $$p_scripts = $script; }
	else { $$p_scripts = "$script\|$$p_scripts"; }
	&DetermineNextStep( $p_scripts, $p_steps );
	&PreProcessStep( $p_scripts, $p_steps, $target );
	return;
}

# Must only have $step, so just replace step and call Pre Processor
else {
	$temp = &GetItem( $p_steps );
	if( $$p_steps eq "" ) { $$p_steps = $step; }
	else { $$p_steps = "$step\|$$p_steps"; }
	&PreProcessStep( $p_scripts, $p_steps, $target );
	return;
}

}	# end of Pre Process Step


#-------------------------------------------------------#
#  Get Step Msg
#-------------------------------------------------------#
sub GetStepMsg
{
my( $script, $step ) = @_;
my( $fname, $newstep, $msg );

$msg = "";
$fname = &GetFName( $script, $G_Config{SCRIPTALIAS} );

&StopProcessing (1,
	"Alias '$script' not found in file - '$G_Config{SCRIPTALIAS}'")
		if	(length($fname) == 0);
&StopProcessing (1, "Error opening file - '$fname': $!")
	unless	(open(FH, $fname));

if( $G_test ) { &LogMsg( \"Searching $fname for message: $step\n" ); }

while( <FH> ) {

	# Skip comments and empty lines
	next	if( $_ =~ /^\s*$/ );
	next	if( $_ =~ /^\s*#/ );

	# parse into "step" and "msg"
	$_ =~ s/^\s*([^=\s]+)\s*=\s*//;
	$newstep = $1;

	# if step matches or START, extract msg and exit loop
	if( ($newstep =~ /^${step}$/i) || ($step =~ /^START$/i) ) {
		# msg can be enclosed in double quotes ...
		if( $_ =~ s/^"(.*)"\s*$// ) { $msg = $1; }
		# ... or single quotes ...
		elsif( $_ =~ s/^'(.*)'\s*$// ) { $msg = $1; }
		# ... or value can be provided without quotes.
		else { $_ =~ s/^(.*)\s*$//; $msg = $1; }
		last;
	}
}

close( FH );

&StopProcessing (1, "Step '$step' not found in script '$script'")
	if	($msg eq "");

return ($msg);
}	# end of Get Step Msg


#-------------------------------------------------------#
#  Get Item
#-------------------------------------------------------#
sub GetItem
{
my( $p_str ) = @_;
my( $item );

# if vertical bar in string, parse it out
if( $$p_str =~ s/\s*(.+?)\s*\|// ) { $item = $1; }

# otherwise, parse out element from string
elsif( $$p_str =~ s/\s*(.+)\s*$// ) { $item = $1; }

else { $item = ""; }

return( $item );

}	# end of Get Item

sub	GetField
{
my( $p_str ) = @_;

return	$2	if	($$p_str =~ s/^\s*(['"])(.*?)\1\s*//);
return	$1	if	($$p_str =~ s/^\s*(\S+)\s*//);

return "";
}	# end of Get Field

#-------------------------------------------------------#
#  Get FName
#-------------------------------------------------------#
sub GetFName
{
my( $alias, $aliasfile ) = @_;
my( $line, $fname ) = "";

# first, check if alias is really a filename and return it
# if it is.  This maintains compatibility with script.pl
if( -f $alias ) { return( $alias ); }

&StopProcessing (1, "Error opening file '$aliasfile': $!")
	unless	(open( AF, $aliasfile));

while( $line = <AF> ) {
	$line =~ s/^\s+|\s+$//g;
	next if( $line =~ /^\#/ );
	next unless( $line =~ /\b${alias}\s*=\s*(.+)$/ );
	$fname = $1;
	last;
}

close( AF );

return( $fname );

}	# end of Get FName


#-------------------------------------------------------#
#
#	Process if statement
#
#-------------------------------------------------------#
sub ProcessIf
{
my( $target, $ifstatement ) = @_;
my( $sysname, $version, $os, $l_targettype, $l_value, $s );
my( $ifos, $TrueStep, $FalseStep, $cond1, $cond2, $cond3, $l_range, $l_ip );

$ifstatement =~ s/^\s+//;
if	($ifstatement =~ /^if\s+(\S+)\s+then\s+(\S+)\s+else\s+(\S+)/i)
{
	$ifos = $1;
	$TrueStep = $2;
	$FalseStep = $3;

	( $sysname, $version, $os ) = &TivWPcmngnode( $target );

	if( $ifos =~ /$os/i ) { return( $TrueStep ); }
	else { return( $FalseStep ); }
}
elsif	($ifstatement =~ /^if\s+\(\s*(\S+)\s+(\S+)\s+(.*)$/i)
{
	$cond1 = uc($1);
	$cond2 = lc($2);
	$s = $3;

	# Get the rest of parameters. Some of them may be eclosed into quotes.
	$cond3 = &GetField (\$s);
	if	($s !~ s/^\s*\)\s*//)
	{
		return "Invalid IF statement: $ifstatement"
			if	($cond3 !~ s/\)$//);
	}
	$TrueStep    = "";
	$FalseStep   = "";
	$TrueStep  = &GetField (\$s)	if	($s =~ s/^then\s+//i);
	$FalseStep = &GetField (\$s)	if	($s =~ s/^else\s+//i);

	$l_targettype = $ttype;
	$l_targettype =~ s/^\@//;
	# If it's an IP address
	if	($cond1 eq "IP")
	{
		if	(defined ($hash{"IP"}))
		{
			$l_value = $hash{"IP"};
		}
		else
		{
			# Get IP address from Tivoli
			($s, $l_value) = &EQ_GetIP ($l_targettype, $target, 1);
			return ("Cannot determine IP address: $l_value")
				if	($s != 0);
		}
	}
	# If it's an OS type
	elsif	($cond1 eq "OS")
	{
		if	(defined ($hash{"OS"}))
		{
			$l_value = $hash{"OS"};
		}
		else
		{
			# Get OS type from Tivoli
			($s, $l_value) = &EQ_GetOS ($l_targettype, $target, 1);
			return ("Cannot determine OS: $l_value")
				if	($s != 0);
		}
	}
	elsif	($cond1 eq "HOSTNAME")
	{
		if	(defined ($hash{"HOSTNAME"}))
		{
			$l_value = $hash{"HOSTNAME"};
		}
		else
		{
			# Get computer name from Tivoli
			$l_value = &EQ_GetComputerName ($l_targettype, $target);
			return ("Cannot determine hostname")
				if	($l_value eq "*");
		}
	}
	# If it's a target name
	elsif	($cond1 eq "TARGET")
	{
		$l_value = $target;
	}
	# If it's a target type
	elsif	($cond1 eq "TYPE")
	{
		$l_value = $l_targettype;
	}
	else
	{
		return ("IF command contains unsupported target's parameter: $cond1");
	}

	# Check operator
	if	($cond2 eq "==")
	{
		return ("", ($l_value eq $cond3)? $TrueStep: $FalseStep);
	}
	elsif	(($cond2 eq "!=")||($cond2 eq "<>")||($cond2 eq "><"))
	{
		return ("", ($l_value ne $cond3)? $TrueStep: $FalseStep);
	}
	elsif	($cond2 eq "matches")
	{
		$cond3 =~ s/(^|[^\\])([\*\+\?\.\~\!\@\$\(\)\|])([^\{]|$)/$1\\$2$3/g;
		$cond3 =~ s/(^|[^\\])([\*\+\?\.\~\!\@\$\(\)\|])([^\{]|$)/$1\\$2$3/g;
		$cond3 =~ s/(^|[^\\])([\*\+\?\.\~\!\@\$\(\)\|])([^\{]|$)/$1\\$2$3/g;
		return ("", ($l_value =~ /^$cond3$/i)? $TrueStep: $FalseStep);
	}
	elsif	($cond2 =~ "inrange")
	{
		if	($l_value =~ /^\s*(\d+)\.(\d+)\.(\d+)\.(\d+)\s*$/)
		{
			$l_ip = (($1 * 256 + $2) * 256 + $3) * 256 + $4;
		}
		else
		{
			return ("INRANGE operator requires valid IP address: $l_value");
		}
		@a = split (/\s*,\s*/, $cond3);
		foreach $l_range (@a)
		{
			if	($l_range =~ /^\s*(\d+\.\d+\.\d+\.\d+)\s*$/)
			{
				return ("", $TrueStep)	if	($l_value eq $1);
			}
			elsif	($l_range =~ /^\s*(\d+)\.(\d+)\.(\d+)\.(\d+)\s*\-\s*(\d+)\.(\d+)\.(\d+)\.(\d+)\s*$/)
			{
				return ("", $TrueStep)
					if	(($l_ip >= ((($1 * 256 + $2) * 256 + $3) * 256 + $4))&&
						 ($l_ip <= ((($5 * 256 + $6) * 256 + $7) * 256 + $8)));
			}
			elsif	($l_range !~ /^\s*$/)
			{
				return ("Invalid IP range on IF statement: $l_range");
			}
		}
		return ("", $FalseStep);
	}
	else
	{
		return ("Invalid operator in IF statement: $cond2");
	}
}

return ("Invalid IF statement: $ifstatement");
}	# end of Process If


#-------------------------------------------------------#
#                                                       #
# Prints config parms
#                                                       #
#-------------------------------------------------------#
sub DisplayParms
{
my( $p_config, $p_config_mod ) = @_;
my( $s );

foreach $s ( sort keys( %$p_config ) )
{
	&LogMsg( \"$s - $$p_config{$s} $$p_config_mod{$s}\n" );
}

&LogMsg( \"\n" );

}	# end of Display Parms


#-------------------------------------------------------#
#                                                       #
# Initialize configuration parameteres.
#                                                       #
#-------------------------------------------------------#
sub InitConfigMod
{
my( $p_config, $p_config_mod ) = @_;
my( $s );

# Initialize data
# G_ConfigMod array is used to keep a name of function/module
# that did the last modification to the parameter's value

foreach $s ( keys( %$p_config ) )
{
	$$p_config_mod{$s} = "by default";
}

}  # end of Init Config Mod


#-------------------------------------------------------#
#                                                       #
# Read configuration file and process data.
#                                                       #
#-------------------------------------------------------#
sub ReadCfgFile
{
my( $p_filename, $p_config, $p_config_mod ) = @_;
my( $s, $l_cmd, $l_val, $c, $c1, $i );

# If configuration file does not exist
unless (-f $$p_filename)
{
	&StopProcessing (1,
		"Configuration file '$$p_filename' does not exist");
}

# Open configuration file and process it line by line
open (IN_FILE, $$p_filename) ||
	&StopProcessing (1,
		"Cannot open configuration file '$$p_filename': $!");

for	($i = 1; defined ($s = <IN_FILE>); $i++)
{
	# Skip comments and empty lines
	next	if	($s =~ /^\s*$/);
	next	if	($s =~ /^\s*#/);

	# Get name and value
	if	($s =~ /^\s*(\S+)\s*=(.*)$/)
	{
		$l_cmd = "\U$1";	#uppercase parm
		$l_val = $2;

		# Do we expect this parameter?
		if( !defined( $$p_config{$l_cmd} ) )
		{	next if( defined ( $$p_config{"*"} ) );
			&StopProcessing (1,
				"Error in file '$p_filename' on line $i: Invalid parameter name");
		}

		# Remove any heading/trailing spaces in value
		$l_val =~ s/^\s+//;
		$l_val =~ s/\s+$//;

		# If the value is enclosed into quotes
		if	($l_val =~ /^['"]/)
		{
			# Remove quotes
			$c = substr ($l_val, 0, 1);
			substr ($l_val, 0, 1) = "";
			$c1 = chop ($l_val);
			&StopProcessing (1,
				"Error in file '$$p_filename' on line $i: Unterminated quote")
					if	($c ne $c1);
		}

		# Save parameter's value
		$$p_config{$l_cmd} = $l_val;
		$$p_config_mod{$l_cmd} = "in cfg file";
	}
	else
	{
		&StopProcessing (1,
			"Error in file '$$p_filename' on line $i: Invalid data");
	}
}
close (IN_FILE);
}	# end of Read Cfg File


#-------------------------------------------------------#
#
# Central routine to Log message to ???
#
#-------------------------------------------------------#
sub LogMsg
{
my( $p_msg ) = @_;
my( $l_sec, $l_min, $l_hr, $l_mday, $l_mon, $l_yr, $l_wday, $l_yday, $l_isdst );
my( $buf ) = "";

( $l_sec, $l_min, $l_hr, $l_mday, $l_mon, $l_yr, $l_wday, $l_yday, $l_isdst ) =
	localtime( time );

$buf = sprintf( "%02d:%02d:%02d  %s", $l_hr, $l_min, $l_sec, $$p_msg );

if( $G_Config{"INTERACTIVE"} == 1 ) { print "$buf\n"; }
open( FH, ">>$xc_EQ_PATH/temp/Script.out" );
print FH "$buf\n";
close( FH );

}	# end of Log Msg

#-------------------------------------------------------#
#	Create Status File
#-------------------------------------------------------#
sub UpdateStatusFile
{
my( $target, $type, $label, $result, $reason, $p_jobid, $p_equser ) = @_;
my( $actname, $file, $time, $trans );

$trans = "Script";
# Strip leading @ and action type from label, if there
$label =~ s/^\@*.*\://;

# Generate action name using trans and label (if exists)
$actname = "$trans";
$actname .= "\:$label" unless( $label eq "" || $label eq "$trans" );

$actname =~ s/[\@\-\/]+/\-/g;		# replace multiple '@' and '-' with one '-'
$actname =~ s/^\-|\-$//g;		# remove leading/trailing dashes

$p_jobid = ""	if	(!defined ($p_jobid));
$p_equser = ""	if	(!defined ($p_equser));

# Save data to a log file so we can update action status in the RDBMS later.
# Get current time
$time = time ();

$reason =~ s/\n/ /g;

# Send a message to EQ Server
&SendMsg (\"T_MSG=savestatus;NAME='$actname';DESC='$actname';TIME='$time';TARGET='$target';TARGET_TYPE='$type';JOB_ID='$p_jobid';EQUSER='$p_equser';RESULT='$result';ERROR='$reason'");

}	# end of Create Status File
