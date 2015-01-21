#!C:/dean/EQ-Working/EQServer/perl5/bin/perl
#
# Function used by EQ installation and upgrade scripts.
# $xc_* variables should be set prior to calling these functions.
#
#	print '$Id: EQInstallLib.pl,v 1.2 2014/11/06 23:36:12 eqadmin Exp $'

use File::Copy;
use File::Path;
use Cwd;

sub	ArchiveFiles;
sub	ArchiveTivoliFramework;
sub	AskTivTasks;
sub	Check4ITM6;
sub	Check4TivoliFramework;
sub	CheckInvVersion;
sub	CheckRCVersion;
sub	DetermineMN;
sub	DisplayTivoliFrameworkVars;
sub	EQ_getppid;
sub	GetApacheVersion;
sub	GetCandleHome;
sub	GetEQHome;
sub	GetTivoliFrwkEQVars;
sub	Install_Apache;
sub	Install_Ask;
sub	Install_CreateTivoliResources;
sub	Install_Die;
sub	Install_GetApacheDir;
sub	Install_LoadStatus;
sub	Install_MkDir;
sub	Install_RemoveCustomMethods;
sub	Install_RemoveTivoliResources;
sub	Install_SaveStatus;
sub	Install_UpdateFiles;
sub	Install_UpdateOneFile;
sub	InstallU_Apache;
sub	InstallU_CheckService;
sub	InstallU_GetApacheDir;
sub	InstallW_Apache;
sub	InstallW_CfgService;
sub	InstallW_CheckService;
sub	InstallW_EQService;
sub	InstallW_GetAccountInfo;
sub	InstallW_GetApacheDir;
sub	InstallW_UpdateServiceRegistry;
sub	ITMCheckTEPSLogin;
sub	ITMGetVersion;
sub	LogMsg;
sub	SetupTivoliFwrkEnv;
sub	SubdirCheck;
sub	UnixCheckDB2;
sub	UnixCheckOracle;
sub	UnixGetDB2Dir;
sub	UnixGetOracleDir;
sub	UntarApache;
sub	UntarAwstats;
sub	UntarPerl5;
sub	VerifyPath;
sub	WinCheckDB2;
sub	WinCheckOracle;
sub	WinGetDB2Dir;
sub	WinGetOracleDir;
sub	WinValidateDB2Info;
sub	WinValidateMySQLInfo;
sub	WinValidateOracleInfo;

# Task names
%G_TaskHash =
(
	"EQRenameNodeTask" => 
						{	SCRIPT	=> "trans/tasks/RenameNode\.pl",
							COMMENT	=> "Rename node task",
							USER 	=> "*",
							ROLE 	=> "super:senior",
							INTERP	=> "default",
						},
	"EQRemoveNodeTask" =>
						{	SCRIPT	=> "trans/tasks/RemoveNode\.pl",
							COMMENT => "Remove node task",
							USER 	=> "*",
							ROLE 	=> "super:senior",
							INTERP 	=> "default",
						},
	"EQGetCompNameUnix" =>
						{	SCRIPT	=> "trans/tasks/GetCompName\.sh",
							COMMENT => "Get Computer Name - Unix",
							USER 	=> "*",
							ROLE 	=> "super:senior:admin:user",
							INTERP 	=> "default",
						},
	"EQGetCompNameWin" =>
						{	SCRIPT	=> "trans/tasks/GetCompName\.bat",
							COMMENT => "Get Computer Name - Win",
							USER 	=> "*",
							ROLE 	=> "super:senior:admin:user",
							INTERP 	=> "default",
						},
);


########################################################
#
#	ITM 6 Routines
#
########################################################


#--------------------------------
#	Check 4 ITM 6
#--------------------------------
sub Check4ITM6
{
my( $err, $msg, $key, $default );

$key = $^O =~ /MSWin32/i ? "CANDLE_HOME" : "CANDLEHOME";

if( defined( $ENV{$key} ) )
{
	$xc_ITM6_SUPPORT = 1;
	$xc_CANDLEHOME = $ENV{$key};
	$xc_CANDLEHOME =~ s#\\+#/#g;
}

elsif( defined($xc_CANDLEHOME) && $xc_CANDLEHOME ne "" )
{
	$xc_ITM6_SUPPORT = 1;
	$ENV{$key} = $xc_CANDLEHOME;
}

else
{
	$xc_ITM6_SUPPORT = 0;
	$xc_CANDLEHOME = "";
}

if( $xc_ITM6_SUPPORT )
{
	&GetCandleHome( ) if( $xc_CANDLEHOME eq "" );

	($err, $msg) = &ITMGetVersion( $xc_CANDLEHOME, "MS", \$xc_ITM6_VERSION );
	&LogMsg( $msg ) if( $err );

	&ITMCheckTEPSLogin( $xc_CANDLEHOME, \$xc_ITM6_TEPSLOGIN );
}
else
{
	$xc_ITM6_SUPPORT = 0;
	$xc_CANDLEHOME = "";

	($err, $msg) = &ArchiveFiles( "$xc_EQ_PATH/cfg/trans", [ "itm.cfg" ] );
	&LogMsg( $msg ) if( $err );
	
	($err, $msg) = &ArchiveFiles( "$xc_EQ_PATH/cfg/screens", [ "itm.cfg" ] );
	&LogMsg( $msg ) if( $err );
	
	($err, $msg) = &ArchiveFiles( "$xc_EQ_PATH/lib/target_types", [ "ITMSystemList.pm", "ManagedSystem.pm" ] );
	&LogMsg( $msg ) if( $err );
}

return( 0, "" );

}	# end of Check 4 ITM 6


#---------------------------------------------
#	ITM Get Version
#---------------------------------------------
sub ITMGetVersion
{
my( $chome, $prodcode, $p_version ) = @_;
my( $err, $msg, $cmd, @arr, @data, $state, $line, $header, $i, $pc_index, $ver_index );

$cmd = $chome;
$cmd .= $^O =~ /win/i ? "/InstallITM/KinCInfo.exe" : "/bin/cinfo";
$cmd .= " -d";

@data = `$cmd 2>&1`;
$err = $?;
return( 1, "Error running '$cmd': " . join( "", @data ) ) if( $err );

$state = "";
foreach $line( @data )
{
	if( $line =~ /Dump Product Inventory/i )
	{
		$state = "GETHEADER";
		next;
	}
	
	next if( $state eq "" );
	
	if( $state eq "GETHEADER" )
	{
		$line =~ s/\"//g;
		@arr = split( /,/, $line );
		$i = 0;
		foreach $header( @arr )
		{
			$pc_index  = $i if( $header eq "ProdCode" );
			$ver_index = $i if( $header eq "Version" );
			$i += 1;
		}
		
		$state = "GETVERSION";
		next;
	}
	
	if( $state eq "GETVERSION" )
	{
		$line =~ s/\"//g;
		@arr = split( /,/, $line );
		next unless( $arr[$pc_index] =~ /^$prodcode$/i );
		$$p_version = $arr[$ver_index];
		return( 0, "" );
	}
}

return( 1, "Could not determine ITM version for Product Code '$prodcode'" );

}	# end of ITM Get Version


#--------------------------------
#	Get Candle Home
#--------------------------------
sub GetCandleHome
{
my $maxtries = 3;

while( $maxtries )
{
	$xc_CANDLEHOME = "";
	$xc_CANDLEHOME = &Install_Ask ("Please Enter CANDLEHOME Path", "PATH DIR", $xc_CANDLEHOME );
	return if( -d $xc_CANDLEHOME );
	&LogMsg( "CANDLEHOME directory not found '$xc_CANDLEHOME'.  Please try again." );
	$maxtries =- 1;
}

&LogMsg( "Exceeded max attempts." );
return;

}	# end of GetCandleHome


#---------------------------------------------
#	ITM Check TEPS Login
#---------------------------------------------
sub ITMCheckTEPSLogin
{
my( $chome, $p_tepslogin ) = @_;
my( $err, $msg, $cmd );

$cmd = "$chome/bin/tacmd tepslogin";
$msg = `$cmd 2>&1`;
$err = $?;

$$p_tepslogin = $msg =~ /KUIC02005E/ ? 1 : 0;

}	# end of ITM Check TEPS Login


########################################################
#
#	Framework Routines
#
########################################################


#--------------------------------
#	Check 4 Tivoli Framework
#--------------------------------
sub Check4TivoliFramework
{
my( $err, $msg, $cmd, $file );

($err, $msg) = &SetupTivoliFwrkEnv( );
if( $err )
{
	&ArchiveTivoliFramework( );
	return( 0, "" );
}

$default = $xc_TIVOLI_FRWK ? "Y" : "N";
$msg = &Install_Ask( "Do you want to include support for Tivoli Framework (TME10)?", "CHAR YN", $default );

if( $msg =~ /N/i )
{
	&ArchiveTivoliFramework( );
	return( 0, "" );
}

($err, $msg) = &GetTivoliFrwkEQVars( $cmd );
return( $err, $msg );

}	# end of Check 4 Tivoli Framework


#--------------------------------
#	Archive Tivoli Framework
#--------------------------------
sub ArchiveTivoliFramework
{
my( $err, $msg );

$xc_TIVOLI_FRWK = 0;
$xc_DEFTARGETTYPE = "EQAgent";
$xc_REGION = 0;
$xc_EQ_ID = time();
$xc_TMR_MN = $xc_HOSTNAME;
$xc_TMRNAME = $xc_HOSTNAME;
	
($err, $msg) = &ArchiveFiles( "$xc_EQ_PATH/cfg/trans", [ "framework.cfg" ] );
&LogMsg( $msg ) if( $err );
	
($err, $msg) = &ArchiveFiles( "$xc_EQ_PATH/cfg/screens", [ "framework.cfg" ] );
&LogMsg( $msg ) if( $err );
	
($err, $msg) = &ArchiveFiles( "$xc_EQ_PATH/lib/target_types", [ "Endpoint.pm", "ManagedNode.pm", "PcManagedNode.pm", "PolicyRegion.pm", "ProfileManager.pm" ] );
&LogMsg( $msg ) if( $err );

return;

}	# end of Archive Tivoli Framework


#--------------------------------
#	Get Tivoli Frwk EQ Vars
#--------------------------------
sub GetTivoliFrwkEQVars
{
my( $cmd ) = @_;
my( $err, $msg, $region, @arr, $s );

# Tivoli Framework Support
$xc_TIVOLI_FRWK = 1;

# Make sure that Tivoli environment variables are set
&LogMsg( "Validating Tivoli directories..." );

unless( defined( $ENV{BINDIR} ) )
{
	# Run the command, returning on error
	@arr = `$cmd 2>&1`;
	$err = $?;
	return( 1, "Error running '$cmd': " . join( "", @arr ) ) if( $err );
	
	# populate ENV with results
	foreach $s( @arr )
	{
		$s =~ s/^\s+|\s+$//g;					# string leading/trailing spaces
		next unless( $s =~ /^([^=]+)=(.+)/ );	# parse key/value on first equal sign
		$ENV{$1} = $2;							# set ENV key to value
	}
}

&LogMsg( "Determining Managed Node name..." );
($err, $msg) = &DetermineMN( \$xc_EQ_MN );
return( $err, $msg ) if( $err );

$xc_DEFTARGETTYPE = "Endpoint";
	
# Get tivoli region and use as EQ_ID for web pages
$region = `objcall 0.0.0 self 2>&1`;
if( $? )
{
	$region = 0;
}
else
{
	$region =~ s/^\s+|\s+$//g;
	$region =~ s/^(\d+)\.\d+\.\d+$/$1/;
}

$xc_REGION = $region;
if( $region )
{
	$msg = &Install_Ask ("Manage targets in local TMR only (L) or in all interconnected TMRs (I) ?",
		"CHOICE I,L,i,l", "I");
	$xc_REGION = 0 if( $msg =~ /i/i );
}

$xc_EQ_ID = $region ? $region : time();

# Get the TMR Name
&LogMsg( "Getting TMR name..." );
$xc_TMRNAME = `wtmrname 2>&1`;
$err = $?;
$xc_TMRNAME =~ s/^\s+|\s+$//g;

if( $err || $xc_TMRNAME eq "" )
{
	&LogMsg( "Error determining TMR name - user supplied" ); 
	$xc_TMRNAME = &Install_Ask ("Please enter TMR name", "STRING 1,1000 [\\w \\-\\.]+", $xc_TMRNAME);
}

$xc_TMRNAME =~ s/\-region\s*$//i;

# Get TMR managed node name
$xc_TMR_MN = "";
@a = `wlookup -ar ManagedNode 2>&1`;
unless( $? )
{
	foreach $s (@a)
	{
		# If we found the first managed node (i.e. TMR)
		next unless( $s =~ /^(\S+)\s+$region\.1\.\d+/ );
		$xc_TMR_MN = $1;
		last;
	}
}

if( $xc_TMR_MN eq "" )
{
	&LogMsg( "Cannot determine TMR Managed Node. Using hostname '$xc_HOSTNAME'" );
	$xc_TMR_MN = $xc_HOSTNAME;
}

&LogMsg( "Checking version of Tivoli Inventory" );
($err, $msg) = &CheckInvVersion( );
&LogMsg( $msg ) if( $err );

&LogMsg( "Checking version of Tivoli Remote Control" );
($err, $msg) = &CheckRCVersion( );
&LogMsg( $msg ) if( $err );

# Create EQ resources
while( $xc_TIVOLI_FRWK )
{
	&LogMsg( "Asking user's permission to create EQ resources..." );
	$i = &AskTivTasks( );
	last	if ($i == 0);
	&LogMsg( "Creating EQ resources in Tivoli" );
	($e, $s) = &Install_CreateTivoliResources ();
	last	unless( $e );
	$s =~ s/Summary of possible error conditions:.*$//s;
	&LogMsg( "Error creating EQ resource: $s" );
}

return( 0, "" );

}	# end of Get Tivoli Frwk EQ Vars


#------------------------------------#
#	Ask Tiv Tasks
#------------------------------------#
sub AskTivTasks
{
my	($l_pr, $s);

$xc_EQ_PR = "EQRegion" if( !defined ($xc_EQ_PR) || $xc_EQ_PR eq "" );
$xc_EQ_TASKLIB = "EQTaskLib" if( !defined($xc_EQ_TASKLIB) || $xc_EQ_TASKLIB eq "" );

$s = &Install_Ask ("Create EQ resources (Y/N)?", "CHAR YN", "Y" );
if	($s =~ /y/i)
{
	$xc_EQ_PR = &Install_Ask ("EQ Policy Region name", "STRING 1,1000 [\\w \\^\\-\\.]+", $xc_EQ_PR );
	$xc_EQ_TASKLIB = &Install_Ask ("EQ Task Library name", "STRING 1,1000 [\\w \\^\\-\\.]+", $xc_EQ_TASKLIB );
	$s = 1;
}
else
{
	$s = 0;
}

return $s;

}	# end of Ask Tiv Tasks


#--------------------------------
#	Setup Tivoli Fwrk Env
#--------------------------------
sub SetupTivoliFwrkEnv
{
my( $err, $msg, $cmd, $file, @arr, $s );

if( $^O =~ /MSWin32/i )
{
	$file = "$ENV{WINDIR}\\system32\\drivers\\etc\\Tivoli\\setup_env.cmd";
	$file =~ s#\\#\\\\#g;
	$cmd = "cmd /c \"$file && set\"";
}
else
{
	$file = "/etc/Tivoli/setup_env.sh";
	$cmd = ". $file; env;";
}

return( 1, "'$file' does not exist" ) unless( -f "$file" );

# Run the command, returning on error
@arr = `$cmd 2>&1`;
$err = $?;
return( 1, "Error running '$cmd': " . join( "", @arr ) ) if( $err );
                
# populate ENV with results
foreach $s( @arr )
{
	$s =~ s/^\s+|\s+$//g;					# string leading/trailing spaces
	next unless( $s =~ /^([^=]+)=(.+)/ );	# parse key/value on first equal sign
	$ENV{$1} = $2;							# set ENV key to value
}

$xc_TIVOLI_FRWK = 1;
return( 0, "Executed '$cmd'" );

}	# end of Setup Tivoli Fwrk Env


#----------------------------------------
#	Display Tivoli Framework Vars
#----------------------------------------
sub DisplayTivoliFrameworkVars
{

&LogMsg( "Tivoli Framework Related Variables:" );
&LogMsg( "\tTIVOLI_FRWK = $xc_TIVOLI_FRWK" );
&LogMsg( "\tREGION = $xc_REGION" );
&LogMsg( "\tTMRNAME = $xc_TMRNAME" );
&LogMsg( "\tTMR MANAGED NODE = $xc_TMR_MN" );
&LogMsg( "\tEQ MANAGED NODE = $xc_EQ_MN" );
&LogMsg( "\tEQ POLICY REGION = $xc_EQ_PR" );
&LogMsg( "\tEQ TASK LIB = $xc_EQ_TASKLIB" );

}	# end of Display Tivoli Framework Vars


#----------------------------------------
#	Determine MN
#----------------------------------------
sub DetermineMN
{
my( $p_mn ) = @_;
my( $s );

unless( $$p_mn eq "" )
{
	$s = &Install_Ask ("Is the ManagedNode name '$$p_mn'?", "CHAR YN", "Y");
	return( 0, "" ) if( $s =~ /Y/i );
}

# Get managed node object ID
$s = `objcall 0.0.0 get_host_location 2>&1`;
return( 1, "Cannot get a managed node object id: $s" )
	if	(($? != 0)||($s !~ /^(\d+)\.\d+\.\d+#/));

$s =~ s/\s+$//;
# Get managed node label
$xc_EQ_MN = `idlcall $s _get_label 2>&1`;
return( 1, "Cannot get a managed node name: $xc_EQ_MN" )
	if	(($? != 0)||($xc_EQ_MN !~ /^".+"\s*$/));
$xc_EQ_MN =~ s/^"(.+)"\s*$/$1/;

return( 0, "" );

}	# end of Determine MN


#-----------------------------------------
#	Check Inv Version
#-----------------------------------------
sub CheckInvVersion
{
my( $cmd, @arr, $err, $line, $file, $ver, $msg );

$cmd = "wlsinst -a";
@arr = `$cmd 2>&1`;
$err = $?;
return( 1, join( " ", @arr) ) if( $err );

$file = "$xc_EQ_PATH/cfg/parser/HWareQuery";
if( $xc_OS =~ /Windows/i )
{
	$file =~ s#/#\\#g;
	$cmd = "copy ${file}_VER_.cfg ${file}.cfg";
}
else
{
	$file =~ s#\\#/#g;
	$cmd = "cp ${file}_VER_.cfg ${file}.cfg";
}

$ver = "41";
foreach $line( @arr )
{
	next unless( $line =~ /Inventory/ && $line =~ /4\.2/ );
	# Use HWareQuery42.cfg
	$ver = "42";
	last;
}

$cmd =~ s/_VER_/$ver/;	
@arr = `$cmd 2>&1`;
$err = $?;
$msg = "Error running '$cmd': " . join( " ", @arr);
return( 1, $msg ) if( $err );
return( 0, "" );
	
}	# end of Check Inv Version


#-----------------------------------------
#	Check RC Version
#-----------------------------------------
sub CheckRCVersion
{
my( $cmd, @arr, $err, $line, $file, $ver, $msg );

$cmd = "wlsinst -a";
@arr = `$cmd 2>&1`;
$err = $?;
return( 1, join( " ", @arr) ) if( $err );

$file = "$xc_EQ_PATH/cfg/xactions/rc_run";
if( $xc_OS =~ /Windows/i )
{
	$file =~ s#/#\\#g;
	$cmd = "copy ${file}_VER_.label ${file}.label";
}
else
{
	$file =~ s#\\#/#g;
	$cmd = "cp ${file}_VER_.label ${file}.label";
}

$ver = "37";
foreach $line( @arr )
{
	next unless( $line =~ /Remote Control/ && $line =~ /3\.8/ );
	$ver = "38";
	last;
}

$cmd =~ s/_VER_/$ver/;	
@arr = `$cmd 2>&1`;
$err = $?;
$msg = "Error running '$cmd': " . join( " ", @arr);
return( 1, $msg ) if( $err );
return( 0, "" );
	
}	# end of Check RC Version


#-----------------------------------------
#	Create Tivoli resources used by EQ
#-----------------------------------------
sub Install_CreateTivoliResources
{
	my	($s, $e, $eq);

	# Check if EQ policy region exist
	$s = `wlookup -r PolicyRegion \"$xc_EQ_PR\" 2>&1`;
	$e = $?;
	if	( $e )
	{
		# Create EQ policy region
		$s = `wcrtpr -m TaskLibrary -m QueryLibrary \"$xc_EQ_PR\" 2>&1`;
		$e = $?;
		return( 1, "ERROR: Cannot create policy region '$xc_EQ_PR': $s" ) if( $e );
	}

	# Check if task library exist
	$s = `wlookup -r TaskLibrary \"$xc_EQ_TASKLIB\" 2>&1`;
	$e = $?;
	if	( $e )
	{
		$s = `wcrttlib \"$xc_EQ_TASKLIB\" \"$xc_EQ_PR\" 2>&1`;
		$e = $?;
		return( 1, "ERROR: Cannot create task library '$xc_EQ_TASKLIB': $s" ) if( $e );
	}

	$eq = $xc_EQ_PATH;
	$eq =~ s#\\#/#g;
	
	foreach $task( keys %G_TaskHash )
	{
		$cmd = "wcrttask -t $task -l $xc_EQ_TASKLIB ";
		$cmd .= "-u \"$G_TaskHash{$task}{USER}\" " unless( $G_TaskHash{$task}{USER} eq "" );
		$cmd .= "-r $G_TaskHash{$task}{ROLE} ";
		$cmd .= "-c \"$G_TaskHash{$task}{COMMENT}\" ";
		$cmd .= "-i $G_TaskHash{$task}{INTERP} ";
		$cmd .= "$xc_EQ_MN $eq/$G_TaskHash{$task}{SCRIPT}";
		$s = `$cmd 2>&1`;
		$e = $?;
		return( 1, "ERROR: Cannot create task '$task' using command '$cmd': $s" )
			if	(($e != 0)&&($s !~ /:\s+resource `$task' exists/i));
	}
	
	return( 0, "" );
	
}	# end of Install Create Tivoli Resources


#-----------------------------------------
#	Remove Tivoli resources used by EQ
#-----------------------------------------
sub Install_RemoveTivoliResources
{
my( $err, $msg, $cmd, @arr, %tasks, %files, $dir, $file, $task, $s );

return	if	(($xc_EQ_PR eq "")||($xc_EQ_TASKLIB eq ""));

# Get list of all tasks currently defined
$cmd = "wlstlib \"$xc_EQ_TASKLIB\"";
@arr = `$cmd 2>&1`;
$err = $?;
return( 1, join( "", @arr ) ) if( $err );

%tasks = ( );
foreach $s( @arr )
{
	$s =~ s/^\s+|\s+$//g;
	next unless( $s =~ /^\(task\)\s+(.+)$/ );
	$task = $1;
	$tasks{$task} = $task;
}

# Get list of all task file in trans/tasks dir
%files = ( );
$dir = "$xc_EQ_PATH/trans/tasks";
if( opendir( TASKDIR, "$dir" ) )
{
	@arr = join( "", readdir( TASKDIR ) );
	closedir( TASKDIR );
	foreach $file( @arr )
	{
		# lop off extension and the word 'Task' if exists 
		$file = $1 if( $file =~ /(.+)\..+$/ );
		$file = $1 if( $file =~ /(.+)Task$/ );
		$files{$file} = $file;
	}
}		

# Remove each task matching eq task files or G_TaskHash entry
foreach $task( keys %tasks )
{
	next unless( exists($files{$task}) || exists($G_TaskHash{$task}) );
	$cmd = "wdeltask \"$task\" \"$xc_EQ_TASKLIB\"";
	$msg = `$cmd 2>&1`;
	$err = $?;
	delete( $tasks{$task} ) unless( $err );
}

# Remove tasklib if all tasks removed, ignoring any errors
@arr = keys %tasks;
if( scalar(@arr) == 0 )
{
	$cmd = "wdel \@TaskLibrary:\"$xc_EQ_TASKLIB\"";
	$msg = `$cmd 2>&1`;
	$err = $?;
}	
else
{
	print "'$xc_EQ_TASKLIB' not deleted.  Still includes the following tasks\n\t";
	print join( "\n\t", @arr ) . "\n";
}

# now try to delete policy region, ignoring any errors
$cmd = "wdelpr \@PolicyRegion:\"$xc_EQ_PR\"";
$msg = `$cmd 2>&1`;
$err = $?;
	
}	 # end of Install Remove Tivoli Resources


#-----------------------------------------
#	Install Remove Custom Methods
#-----------------------------------------
sub Install_RemoveCustomMethods
{
my( $err, $msg, $cmd, @a );

$cmd = "$xc_EQ_PATH/bin/EQCreateMethod -R";
@a = `$cmd 2>&1`;
$err = $?;

$msg = $err ? join( "", @a ) : "";
return( $err, $msg );

}	# end of Install Remove Custom Methods



#-----------------------------------------
#	Untar Perl5   
#-----------------------------------------
sub UntarPerl5
{
my( $save_dir, $err, $results, $file, $cmd );
my( $msg, $untar, $tarcmd, $tarfile );

($err, $msg) = &SubdirCheck( "perl5", \$untar );
return( $err, $msg ) if( $err || !$untar );

if( -f "$xc_EQ_PATH/install/perl5.tar" )
{
	$tarfile = "$xc_EQ_PATH/install/perl5.tar";
}
elsif( $^O =~ /win/i && -f "$xc_EQ_PATH/install/perl5-win.tar" )
{
	$tarfile = "$xc_EQ_PATH/install/perl5-win.tar";
}
elsif( $^O =~ /linux/ && -f "$xc_EQ_PATH/install/perl5-linux.tar" )
{
	$tarfile = "$xc_EQ_PATH/install/perl5-linux.tar";
}
elsif( $^O =~ /aix/ && -f "$xc_EQ_PATH/install/perl5-aix.tar" )
{
	$tarfile = "$xc_EQ_PATH/install/perl5-aix.tar";
}
elsif( $^O =~ /sol/ && -f "$xc_EQ_PATH/install/perl5-sol.tar" )
{
	$tarfile = "$xc_EQ_PATH/install/perl5-sol.tar";
}
else
{
	return( 1, "Perl5 tar file not found in '$xc_EQ_PATH/install" );
}

$save_dir = &getcwd( );

return( 1, "Error changing to '$xc_EQ_PATH': $!" ) unless( chdir($xc_EQ_PATH) );

&LogMsg( "Extracting '$tarfile' to '$xc_EQ_PATH'" );

$tarcmd = $xc_OS =~ /win/i ? "$xc_EQ_PATH/bin/tar.exe" : "tar";
$cmd = "$tarcmd xvf \"$tarfile\"";

$results = `$cmd 2>&1`;
$err = $?;
if( $err )
{
	chdir( $save_dir );
	return( 1, "Error ($err) extracting perl5 archive using '$cmd':\n$result\n" );
}

# Don't delete this file in case user wants to uninstall/reinstall enterprise-Q
#unlink( "$xc_EQ_PATH/install/perl5.tar" );
chdir( $save_dir );

# Create empty file that will instruct EQ update routines not to update
# files in perl5 directory
$file = "$xc_EQ_PATH/perl5/.skip_update";
if	(open (SKIP_FILE, ">$file"))
{
	print SKIP_FILE "\n";
	close (SKIP_FILE);
}

return( 0, "" );
	
}	# end of Untar Perl5


########################################################
#
#	AWStats Routines
#
########################################################


#-----------------------------------------
# Untar Awstats   #
#-----------------------------------------
sub UntarAwstats
{
my( $err, $tarfile, $save_dir, $results, $srcdir, $dstdir );
my( $msg, $untar, $tarcmd, $cmd );

($err, $msg) = &SubdirCheck( "awstats", \$untar );
return( $err, $msg ) if( $err || !$untar );

$tarfile = "$xc_EQ_PATH/install/awstats.tar";
return( 0, "'$tarfile' does not exist" ) unless( -f $tarfile );

$save_dir = &getcwd( );

return( 1, "Error changing to '$xc_EQ_PATH': $!" ) unless( chdir($xc_EQ_PATH) );

&LogMsg( "Extracting '$tarfile' to '$xc_EQ_PATH'" );

$tarcmd = $xc_OS =~ /win/i ? "$xc_EQ_PATH/bin/tar.exe" : "tar";
$cmd = "$tarcmd xvf \"$tarfile\"";

$results = `$cmd 2>&1`;
$err = $?;
if( $err )
{
	chdir( $save_dir );
	return( 1, "Error ($err) extracting awstats archive using '$cmd':\n$results\n" );
}

# Copy configuration file to awstats directory
$srcdir = "$xc_EQ_PATH/install/data";
$dstdir = "$xc_EQ_PATH/awstats/wwwroot/cgi-bin";
return( 1, "Error copying 'awstats.conf' from '$srcdir' to '$dstdir': $!" ) 
	unless( copy( "$srcdir/awstats.conf", "$dstdir/awstats.conf" ) );

&LogMsg( "Run '$xc_EQ_PATH/awstats/tools/awstats_updateall.pl now' nightly" );

chdir( $save_dir );

return( 0, "" );
	
}	#sub Untar Awstats


########################################################
#
#	Apache Routines
#
########################################################


#-----------------------------------------
#	Untar Apache    
#-----------------------------------------
sub UntarApache
{
my( $p_version ) = @_;
my( $save_dir, $err, $results, $s, $apache );
my( $msg, $untar, $cmd, $tarcmd, $tarfile );

($err, $msg) = &SubdirCheck( "apache", \$untar );
return( $err, $msg ) if( $err );

# Get apache version if user wants to use existing installation
unless( $untar )
{
	($err, $msg) = &GetApacheVersion( $p_version );
	return( $err, $msg );
}

my $os;
if( $^O =~ /sol/i ) 
{
	$tarfile = "$xc_EQ_PATH/apache-sol.tar";
}
elsif( $^O =~  /aix/i )
{
	$tarfile = "$xc_EQ_PATH/apache-aix.tar";
}
elsif( $^O =~ /lin/i )
{
	$tarfile = "$xc_EQ_PATH/apache-linux.tar";
}
elsif( $^O =~ /win/i )
{
	$tarfile = "$xc_EQ_PATH/apache-win.tar";
}
else 
{ 
	&LogMsg( "OS Not Supported: $^O" );
	return;
};

$tarfile = "$xc_EQ_PATH/install/apache.tar" if( ! -f "$tarfile" && -f "$xc_EQ_PATH/install/apache.tar" );
return( 0, "Tarfile '$tarfile' does not exist: $tarfile" ) unless( -f "$tarfile" );

$save_dir = &getcwd( );

return( 1, "Error changing to '$xc_EQ_PATH': $!" ) unless( chdir($xc_EQ_PATH) );

&LogMsg( "Extracting '$tarfile' to '$xc_EQ_PATH'" );

$tarcmd = $xc_OS =~ /win/i ? "$xc_EQ_PATH/bin/tar.exe" : "tar";
$cmd = "$tarcmd xvf \"$tarfile\"";

$results = `$cmd 2>&1`;
$err = $?;
if( $err )
{
	chdir( $save_dir );
	return( 1, "Error ($err) extracting apache archive using '$cmd':\n$result\n" );
}

# Don't delete this file in case user wants to uninstall/reinstall enterprise-Q
#unlink( "$xc_EQ_PATH/install/apache.tar" );
chdir( $save_dir );

$xc_APACHE_PATH = "$xc_EQ_PATH/apache";

# Create empty file that will instruct EQ update routines not to update
# files in apache directory
$file = "$xc_APACHE_PATH/.skip_update";
if	(open (SKIP_FILE, ">$file"))
{
	print SKIP_FILE "\n";
	close (SKIP_FILE);
}

# Get apache version
($err, $msg) = &GetApacheVersion( $p_version );
return( $err, $msg );
	
}	#sub Untar Apache


#######################################
#	Install Apache
#######################################
sub Install_Apache
{
my( $err, $msg );

if( $xc_OS =~ /win/i )
{
	&LogMsg( "Installing EQApache (version $xc_APACHE_VERSION)..." );
	($err, $msg) = &InstallW_Apache( "EQApache", $xc_APACHE_VERSION );
}

else
{
	# Let's update httpd.conf and start apache
	&LogMsg( "Configuring Apache..." );
	($err, $msg) = &InstallU_Apache( );
	return( $err, $msg) if( $err );
}

return( $err, $msg );

}	# end of Install Apache


#######################################
#	Install Get Apache Dir
#######################################
sub Install_GetApacheDir
{
my( $p_path, $p_ver ) = @_;
my( $err, $msg );

if( $xc_OS =~ /win/i )
{
	($err, $msg ) = &InstallW_GetApacheDir( $p_path, $p_ver );
	$xc_APACHE_SERVICE = $$p_ver =~ /^1/ ? "Apache" : "Apache2";
}

else
{
	($err, $msg) = &InstallU_GetApacheDir( $p_path, $p_ver );
}

return( $err, $msg );

}	# end of Install Get Apache Dir


#-----------------------------------------
#	Get Apache Version
#-----------------------------------------
sub GetApacheVersion
{
my( $p_version, $ap_path ) = @_;
my( $err, $msg, $cmd );

# Determine apache executable name
$ap_path = "$xc_EQ_PATH/apache" unless( defined($ap_path) );

if( -f "$ap_path/bin/httpd" )
{
	$cmd = "$ap_path/bin/httpd -v";
}
elsif( -f "$ap_path/bin/httpd.exe" )
{
	$cmd = "$ap_path/bin/httpd.exe -v";
}
elsif( -f "$ap_path/bin/apache.exe" )
{
	$cmd = "$ap_path/bin/apache.exe -v";
}
else
{
	return( 0, "Apache executable file not found" );
}

# Add apache lib dir to lib path the get apache version
&VerifyPath( "$ap_path/lib", "LD_LIBRARY_PATH" );
$msg = `$cmd 2>&1`;
$err = $?;
$msg =~ s/\n+//g;
return( 1, "Error running '$cmd': $msg" ) if( $err );
return( 1, "Error determining apache version: $msg" ) 
	unless( $msg =~ /Server version: Apache\/([\d\.]+)/i );

$$p_version = $1;

return( 0, "" );

}	# end of Get Apache Version


#-----------------------------------------
#	Install U Get Apache Dir
#-----------------------------------------
sub InstallU_GetApacheDir
{
my( $p_path, $p_ver ) = @_;
my	(@a, $s, $success, $path);

$success = 0;

# See if variable already properly defined
if( $xc_APACHE_PATH && -f "$xc_APACHE_PATH/bin/apachectl" )
{
	$$p_path = $xc_APACHE_PATH;
	$success = 1;
}

# See if any of the dirs in the path have 'apachectl'
if	($success == 0)
{
	$s = $ENV{"PATH"};
	@a = split (":", $s);
	# For each directory in the PATH statement
	foreach $s (@a)
	{
		# If this directory contains SQL*Plus program
		if	(-f "$s/apachectl")
		{
			$$p_path = $s;
			$$p_path =~ s#/bin$##i;
			$success = 1;
			last;
		}
	}
}

# Now, check if the process is running to determine the path
if	($success == 0)
{
	# See if apache server already running
	@a = `ps -ef 2>&1`;
	foreach $s (@a)
	{
		if	($s =~ m#\s+(/\S+)/httpd(\s+|$)#)
		{
			$$p_path = $1;
			$$p_path =~ s#/bin$##i;
			$success = 1;
			last;
		}
	}
}

# If we still can't find where Apache installed
while ($success == 0)
{
	# Just in case, check if bin directory exists. Do not check for
	# files in bin directory as we may not have permission to see them!
	$$p_path = &Install_Ask ("Please enter path to Apache directory", "PATH DIR", $path);
	last	if	(-d "$path/bin");
	&LogMsg( "*** Subdirectory 'bin' not found in specified directory ***" );
}

return( 1, "Unable to determine Apache installation directory" ) unless( $success );

# Now, let's get the Apache version
($err, $msg) = &GetApacheVersion( $p_ver, $$p_path );
return( $err, $msg );

}	# end of InstallU Get Apache Dir


#-----------------------------------------
#	InstallU Apache
#-----------------------------------------
sub InstallU_Apache
{
my( $err, $msg, $srcdir, $dstdir, $s, $httpd_conf );

if( $^O =~ /aix/ )
{
	$httpd_conf = "eq-httpd-aix.conf";
}
elsif( $^O =~ /linux/ )
{
	$httpd_conf = "eq-httpd-linux.conf";
}
else
{
	$httpd_conf = "eq-httpd-unix.conf";
}

# Copy configuration file to Apache directory
$srcdir = "$xc_EQ_PATH/install/data";
$dstdir = "$xc_APACHE_PATH/conf";

# Use httpd.conf unless specific OS version exists
$httpd_conf = "httpd.conf" unless( -f "$srcdir/$httpd_conf");
copy( "$srcdir/$httpd_conf", "$dstdir/httpd.conf" ) || return( 1, "Error copying $srcdir/$httpd_conf to $dstdir/httpd.conf: $!" );
	
# Copy apache startup file to Apache directory
$dstdir = "$xc_APACHE_PATH/bin";
copy( "$srcdir/apachectl.sh", "$dstdir/apachectl" ) || return( 1, "Error copying $srcdir/apachectl.sh to $dstdir/apachectl: $!" );

return( 0, "" );

}	# end of Install U Apache


#---------------------------------------------
#	Install W Get Apache Dir
#---------------------------------------------
sub InstallW_GetApacheDir
{
my( $p_dir, $p_ver ) = @_;
my( $key, $p_hash, $ver, $path, $i, $high );

$key = "HKEY_LOCAL_MACHINE/Software";
$p_hash = $Registry->{ $key };

return( 1, "Error reading '$key' from registry" ) 
	unless( ref( $p_hash ) eq "Win32::TieRegistry" );

return( 1, "Apache Not Installed" ) 
	unless( exists( $p_hash->{"Apache Group"}->{"Apache"} ) );
		
$$p_dir = "";
$$p_ver = 0;
$high = 0;

$p_hash = $p_hash->{"Apache Group"}->{"Apache"};
foreach $ver( keys %$p_hash )
{
	$path = $p_hash->{$ver}->{"ServerRoot"};
	$ver =~ s#/+##g;
	$path =~ s#\\+#/#g;
	
	next unless( $ver =~ /^(\d+)\.(\d+)\.(\d+)/ );
	
	$i = (1000000 * $1) + (1000 * $2) + $3;
	next if( $high > $i );
	
	$high = $i;
	$$p_dir = $path;
	$$p_ver = $ver;
}

return( 0, "Apache Installed" );

}	# end of Install W Get Apache Dir


#-----------------------------------------
#	InstallW Apache
#-----------------------------------------
sub InstallW_Apache
{
my( $service_name, $version ) = @_;
my( $s, @a, $i, $admin, $pwd, $service );
my( $apache_bin, $install_opts, $httpd, $httpd_conf );

# 0 - service does not exist
# 1 - service exists and not running
# 2 - apache service running
$service = 0;

# See if Apache service is already installed and running
$s = &InstallW_CheckService ($service_name, 0);
if	($s eq "")
{
	$service = 2;
}
else
{
	my $ImagePath;
	($i, $s) = &GetReg( "SYSTEM\\CurrentControlSet\\Services\\$service_name\\ImagePath", \$ImagePath );
	$service = 1	if	($i == 0);
}

# If service already installed...
if	($service > 0)
{
	$s = ($service == 1)? "$service_name service already installed.\n": "$service_name server is running.\n";
	&LogMsg( $s );

	$s .= &Install_Ask( $s .
		"Do you want to re-configure Apache web server?\n\n" .
		"If you answer 'Yes' then Apache configuration\n" .
		"will be replaced, Apache service will be reinstalled\n" .
		"and Apache web server will be started\n\n" .
		"If you answer 'No' then no changes will be made\n" .
		"to Apache web server. In this case you may need\n" .
		"to change Apache configuration and Apache service\n" .
		"manually. See Enterprise-Q installation guide for\n" .
		"more information on manual setup of Apache web server.", "CHAR YN", "Y" );
	if	($s =~ /Y/i)
	{
		&LogMsg( "Stopping and removing the $service_name service..." );
		# Stop Apache service if it's running
		if	($service == 2)
		{
			# Stop the service
			$s = `$xc_EQ_PATH/bin/eqsrv.exe stop $service_name 2>&1`;
			# Just in case
			sleep (2);
		}
		# Remove Apache service
		$s = `$xc_EQ_PATH/bin/eqsrv.exe remove $service_name 2>&1`;
	}
	else
	{
		&LogMsg( "$service_name service was not changed." );
		return( 0, "" );
	}
}

# Apache service is not installed
$apache_bin = "$xc_APACHE_PATH/bin";
if( -f "$apache_bin/httpd.exe" )
{
	$httpd = "$apache_bin/httpd.exe";
}
elsif( -f "$apache_bin/apache.exe" )
{
	$httpd = "$apache_bin/apache.exe";
}
else
{
	return( 1, "Cannot find 'httpd.exe' nor 'apache.exe' in '$xc_APACHE_PATH/bin'" );
}

# Save original Apache configuration file
return( 1, $! ) unless( copy( "$xc_APACHE_PATH/conf/httpd.conf", "$xc_EQ_PATH/install/data/httpd.conf.saved" ) );

# Use httpd.conf unless OS specific version exists
if( -f "$xc_EQ_PATH/install/data/eq-httpd-win.conf" )
{
	$httpd_conf = "$xc_EQ_PATH/install/data/eq-httpd-win.conf";
}
else
{
	$httpd_conf = "$xc_EQ_PATH/install/data/httpd.conf";
}

return( 1, $! ) unless( copy( $httpd_conf, "$xc_APACHE_PATH/conf/httpd.conf" ) );

# Install Apache as a service
$version = 2 unless( $version );
if( $version =~ /^1/ ) { $install_opts = "-i"; }
else { $install_opts = "-n $service_name -k install"; }
$cmd = "\"$httpd\" $install_opts";
$s = `$cmd 2>&1`;
return( 1, "Cannot install '$service_name' as a service using '$cmd': $s" ) if( $? );

# Configure service 'Run As' account
($err, $msg) = &InstallW_CfgService( $service_name );
return( $err, $msg );

}	# end of InstallW Apache


#-----------------------------------------
#	Install W EQ Service
#-----------------------------------------
sub InstallW_EQService
{
my( $name, $port ) = @_;
my( $err, $msg, $cmd, $eqpath );

$eqpath = $xc_EQ_PATH;
$eqpath =~ s#/#\\#g;

# Try to create service first. Do not use <user> and <password> options
# for service install - some of the registry keys may be deleted if account
# name is incorrect
$cmd = "$xc_EQ_PATH/bin/eqsrv.exe install $name \"$eqpath\\bin\\EQSrvAny.exe $name\"";
$msg = `$cmd 2>&1`;
$err = $?;
return( 1, "Error ($err) running '$cmd': $msg" ) if( $err );

# Add service Parameters registry key
($err, $msg) = &InstallW_UpdateServiceRegistry( $eqpath, $name, $port );
return( $err, $msg ) if( $err );

($err, $msg) = &InstallW_CfgService( $name );
return( $err, $msg );

}	# end of Install W EQService


#-----------------------------------------
#	InstallW Update Service Registry
#-----------------------------------------
sub InstallW_UpdateServiceRegistry
{
my( $eqpath, $name, $port ) = @_;
my( $err, $msg, $cmd, $value, $regkeybase, $regparmkey, %regnamem, $cfgfile );

$regkeybase = "HKEY_LOCAL_MACHINE\\SYSTEM\\CurrentControlSet\\Services\\" . $name;
$regparmkey = $regkeybase . "\\Parameters";

%regname =
(
	Description		=>	{
							REGKEY	=> $regkeybase,
							TYPE	=> "REG_SZ",
							DATA	=> "enterprise-Q $name using port $port",
						},
		
	Application		=>	{
							REGKEY	=> $regparmkey,
							TYPE	=> "REG_SZ",
							DATA	=> "$eqpath\\perl5\\bin\\perl.exe",
						},
	AppDirectory	=>	{
							REGKEY	=> $regparmkey,
							TYPE	=> "REG_SZ",
							DATA	=> "$eqpath\\bin",
						},
	AppParameters	=>	{
							REGKEY	=> $regparmkey,
							TYPE	=> "REG_SZ",
							DATA	=> "-I $eqpath\\perl5\\lib $eqpath\\bin\\" . $name . ".pl",
						},
	AppPort			=>	{
							REGKEY	=> $regparmkey,
							TYPE	=> "REG_SZ",
							DATA	=> $port,
						}
);

# Create Parameters key
$cmd = "$xc_EQ_PATH/bin/EQReg -Ck $regparmkey";
$msg = `$cmd 2>&1`;
$err = $?;
return( 1, "Error running '$cmd': $msg" ) if( $err );

# See if compiled version of service is installed
if( -f "$xc_EQ_PATH/bin/${name}.exe" )
{
	$cfgfile = "$eqpath\\cfg\\$name.cfg";
	$regname{Application}->{DATA} = "$eqpath\\bin\\${name}.exe";
	$regname{AppParameters}->{DATA} = "-c $cfgfile";
}

# Create each named value
&LogMsg( "Add Registry Parameter Keys" );
foreach $value( keys %regname )
{
	my $regkey = $regname{$value}->{REGKEY};
	$cmd = "$xc_EQ_PATH/bin/EQReg -Cv $regkey\\$value \"$regname{$value}->{DATA}\"";
	&LogMsg( "\t$cmd" );
	$msg = `$cmd 2>&1`;
	$err = $?;
	return( 1, "Error running '$cmd': $msg" ) if( $err );
}

return( 0, "" );

}	# end of InstallW Update Service Registry


#-----------------------------------------
#	EQ getppid
#-----------------------------------------
sub EQ_getppid
{
my( $pid, $p_ppid, $p_pprocess ) = @_;
my( $err, $msg, $cmd, @a, $s, %pidhash );

$cmd = "$xc_EQ_PATH/bin/eqps.exe";
@a = `$cmd 2>&1`;
$err = $?;
return( 1, join( "", @a ) ) if( $err );

foreach $s( @a )
{
	next unless( $s =~ /^(\d+)\s+(\d+)\s+(\S+)$/ );
	$pidhash{$1}{PPID} = $2;
	$pidhash{$1}{PROCESS} = $3;
}

$$p_ppid = $pidhash{$pid}{PPID};
$$p_pprocess = $pidhash{$$p_ppid}{PROCESS};
return( 0, "" );

}	# end of EQ getppid


#-----------------------------------------
#	Install W Cfg Service
#-----------------------------------------
sub InstallW_CfgService
{
my( $service ) = @_;
my( $s, $i, $maxtries, $admin, $pwd );

$i = 0;
$maxtries = 3;
my $prompt = "~~~PRODUCT~~~" eq "EQServer" ? "Enter account used to run EQServer service.  Account must have User Right to 'Log on as a Service'" : undef;

# Get username/password
while ($i < $maxtries)
{
	($admin, $pwd) = &InstallW_GetAccountInfo( $i, $prompt );
	return( 1, "No Username/Password provided" ) if( $admin eq "" && $pwd eq "" );
	$s = `$xc_EQ_PATH/bin/eqsrv.exe account \"$service\" \"$admin\" \"$pwd\" 2>&1`;
	if( $? != 0 )
	{
		&LogMsg( "Cannot set account name for service '$service': $s" )
			if	($s !~ /The account name is invalid or does not exist/i);
	}
	else
	{
		# Try to start service
		$s = &InstallW_CheckService( $service, 1 );
		return(0, "$admin\n$s" ) unless(	$s =~ /The account name is invalid or does not exist/i ||
				 				$s =~ /The service did not start due to a logon failure/i );
	}
	
	&LogMsg( "ERROR: Invalid name and/or password for account '$admin': $s" );
	$i = 1;
}

return( 1, "Exceeded $maxtries attempts trying to configure Service '$service'" );

}	# enf of Install W Cfg Service


########################################################
#
#	EQ Services/Daemons Routines
#
########################################################


#-----------------------------------------
#	Install U Check Service
#-----------------------------------------
sub InstallU_CheckService
{
my( $service, $start, $port ) = @_;
my( $s, @a, $msg, $attempts, $err);

if( defined($start) && length($start) )
{
	$start .= " 2>&1"		if	($start !~ /\s+\&\s*$/);
	# Start the service
	$msg = `$start`;
	$err = $?;
	return( 1, "ERROR ($err): Cannot start '$service' using '$start': $msg" ) if( $err );
}

# Give it time to start
sleep( 3 );

$attempts = ($start)? 5: 1;
while ($attempts > 0)
{
	# Check if service is running
	@a = `ps -ef 2>&1`;
	$err = $?;
	return( 1, "ERROR ($err): Cannot execute 'ps -ef' command: ", join ("", @a) ) if( $err );
	foreach $s (@a)
	{
		if	($s =~ m#\s+/\S+/$service(\s+|$)#i)
		{
			return( 0, "" ) unless( $port );
			$err = `$xc_EQ_PATH/bin/EQMsg -p $port t_msg=help 2>&1`;
			return( 0, "'$service' is properly running" ) if( $? == 0 );
			last;
		}
	}
	$attempts--;
	sleep( 3 );
}

$msg = defined($start) && length($start) ? 
	"WARNING: '$service' not responding. May not have started: $msg" : 
	"ERROR: '$service' is not running";

return( 1, $msg );

}	# end of Install U Check Service


#-----------------------------------------
#	Install W Check Service
#-----------------------------------------
sub InstallW_CheckService
{
my( $service, $start) = @_;
my( $err, $msg, $cmd, $s, @a, $result, $err );

if( $start )
{
	# Start the service
	$cmd = "$xc_EQ_PATH/bin/eqsrv.exe start \"$service\"";
	$msg = `$cmd 2>&1`;
	$err = $?;
	if( $err )
	{
		$msg =~ s/^ERROR:\s*//i;
		return( "Error starting '$service' using '$cmd': $msg" );
	}
	$msg =~ s/^SUCCESS:\s*//i;
}

# Check if service is running
$msg = `net start 2>&1`;
$err = $?;
return( "ERROR: Cannot execute 'net start' command: $msg" ) if( $err );

return "" if( $msg =~ /$service/i);

$msg = $start ? "ERROR: Cannot start $service service: $msg" : "ERROR: '$service' service is not running";
return( $msg );

}	# end of Install W Check Service


#---------------------------------------------------
#	Install Get Account Info
#---------------------------------------------------
sub InstallW_GetAccountInfo
{
my( $ask, $prompt ) = @_;
my( $s, @a );

# If this function is called for the first time
return ($x_admin_user, $x_admin_pwd) 
	if( $ask == 0 && defined ($x_admin_user) && $x_admin_user ne "" && defined ($x_admin_pwd ) );

# Set default account name
$x_admin_user = "$xc_HOSTNAME\\Administrator" unless( defined ($x_admin_user) );

$prompt = "Enter an NT Account to run EQ services.\\nNT Account must:\\n   1) be linked to a Tivoli Admin with at least Senior Role\\n   2) have User Right to 'Log on as a Service'" unless( defined( $prompt ) );

# Until we get a valid username/password
while (1)
{
	$s = (!defined ($x_admin_pwd))? "": "********";
	@a = `$xc_EQ_PATH/bin/eqaccount.exe \"$prompt\" \"$x_admin_user\" \"$s\" 2>&1`;
	if	($a[0] =~ /^The name specified is not recognized as an/i)
	{
		&LogMsg( "ERROR: Cannot execute file \"$xc_EQ_PATH/bin/eqaccount.exe\": ",
			join ("", @a) );
			return ("", "");
	}
	foreach $s (@a)
	{
		if	($s =~ /^USERNAME=(\S+)\s*$/i)
		{
			$x_admin_user = $1;
		}
		elsif	($s =~ /^PASSWORD=(\S*)\s*$/i)
		{
			$x_admin_pwd = $1	if	($1 ne "********");
		}
	}
	last	if	($x_admin_user ne "");
}

return ($x_admin_user, $x_admin_pwd);

}	# end of Install W Get Account Info


########################################################
#
#	Windows DB-related routines
#
########################################################


#------------------------------------------------
#	Win Check Oracle
#------------------------------------------------
sub WinCheckOracle
{
my( $err, $msg, $dir, $cmd );

# Check for Oracle in registry
($err, $msg) = &WinGetOracleDir( \$dir, \$cmd );

if	($err)
{
	$dir = &Install_Ask ("Oracle home directory", "PATH DIR", "");
	$dir =~ s#\\+#/#g;

	return( 1, "Cannot file Oracle binaries in '$dir'" )
		if( !-f "$s/bin/sqlplus.exe" && !-f "$s/bin/plus33.exe" && !-f "$s/bin/plus80.exe" );
		
	if	(-f "$dir/bin/plus33.exe")
	{
		$cmd = "plus33";
	}
	elsif	(-f "$dir/bin/plus80.exe")
	{
		$cmd = "plus80";
	}
	else
	{
		$cmd = "sqlplus";
	}
}

$xc_DB_VENDOR	= "ORACLE";
$xc_DB_BINDIR	= "$dir/bin";
$xc_DB_USERNAME	= "";
$xc_DB_PASSWORD	= "";
$xc_DB_HOST 	= "";
$xc_DB_COMMAND	= "$cmd";

return( 0, "" );

}	# end of Win Check Oracle


#---------------------------------------
#	Win Validate MySQL Info
#---------------------------------------
sub WinValidateMySQLInfo
{
my( $c, $u, $p ) = @_;
my( @a, $cmd, $err, $msg );

$c =~ s#/#\\#g;
$cmd = "$c -u $u --password=\"$p\"";
@a = `echo quit | $cmd 2>&1`;
$err = $?;
return( "" ) if( !$err );

$msg = "Error connecting to MySQL Server using $cmd: $a[0]\n";
return( $msg );

}	# end of W Validate MySQL Info


#---------------------------------------
#	Win Validate Oracle Info
#---------------------------------------
sub WinValidateOracleInfo
{
my( $c, $u, $p, $h ) = @_;
my( $s, @a, $success );

$c =~ s#/#\\#g;
# Verify connection to Oracle database
$s = $p;
$s .= "\@$h" if( defined($h) && $h ne "" );

@a = `echo quit | \"$c\" $u/$s \@conn_ora.sql 2>&1`;
$success = 0;
foreach $s (@a) { $success = 1 if( $s =~ /^EQ: database connection OK/i ); }

# If we didn't receive what we expected
return( "" ) if( $success );

$msg = "Error connecting to Oracle DB using supplied elements:\n" .
	join ("   ", @a) . "\n"; 

return( $msg );

}	# end of Win Validate Oracle Info


#---------------------------------------
#	Win Get Oracle Dir
#---------------------------------------
sub WinGetOracleDir
{
my( $p_path, $p_cmd ) = @_;
my( $s, $msg, $regkey, $result, $file, $success, @a );

$success = 0;
$regkey = "SOFTWARE\\ORACLE\\ORACLE_HOME";
($s, $msg) = &GetReg( $regkey, \$result );
if	($s == 0)
{
	$$p_path = $result;

	$regkey = "SOFTWARE\\ORACLE\\EXECUTE_SQL";
	($s, $msg) = &GetReg( $regkey, \$result );
	if	($s == 0)
	{
		$s = $result;
		if	(-f $s)
		{
			$$p_cmd = $s;
			$success = 1;
		}
	}
}

# Use another method if necessary
unless( $success )
{
	$s = defined($ENV{ORACLE_HOME}) ? $ENV{ORACLE_HOME} . "/bin;" : "";
	$s .= $ENV{"PATH"};
	$s =~ s#\\+#/#g;
	@a = split (";", $s);
	# For each directory in the PATH statement
	foreach $s (@a)
	{
		# If this directory contains SQL*Plus program
		if	(-f "$s/sqlplus.exe")
		{
			if	(-f "$s/plus33.exe")
			{
				$$p_cmd = "plus33";
			}
			elsif	(-f "$s/plus80.exe")
			{
				$$p_cmd = "plus80";
			}
			else
			{
				$$p_cmd = "sqlplus";
			}

			$$p_path = $s;
			$$p_path =~ s#/bin$##i;
			$success = 1;
			last;
		}
	}
}

return (1, "Cannot determine Oracle database home directory") unless( $success );

$$p_path =~ s#\\#/#g;
$$p_path =~ s#/$##;
$$p_cmd .= ".exe" if( $$p_cmd !~ /\.exe$/i );

$file = "$$p_path/bin/$$p_cmd";

if( -f "$file" )
{
	return( 0, "Found file: $file" );
}
else
{
	return( 2, "File not found: $file" );
}

}	# end of Win Get Oracle Dir


#---------------------------------------
#	  Win Validate DB2 Info
#---------------------------------------
sub WinValidateDB2Info
{
my( $p_cmd, $p_user, $p_pwd, $p_host ) = @_;
my( $s, @a, $success, $error );

# Verify connection to DB2 database
$s = &Install_RunDB2Script
		("conn_db2.sql", $p_cmd, $p_user, $p_pwd, $p_host, \@a);

# Check for error messages and for expected program output
$error = 0;
$success = 0;
foreach $s (@a)
{
	$error = 1		if	($s =~ /^SQL\d\w+\s+/);
	$success = 1	if	($s =~ /^EQ: database connection OK/i);
	$s =~ s/\s+$/\n/;
}

# If we didn't receive what we expected
return ""	if	(($success)&&(!$error));

$msg = "Error connecting to DB2 database using supplied elements:\n" .
	join ("   ", @a) . "\n"; 

return $msg;

}	# end of Win Validate DB2 Info


#------------------------------------------------
#	Win Check DB2
#------------------------------------------------
sub WinCheckDB2
{
my( $err, $msg, $file, $dir, $cmd );

# Check for DB2 in registry
($err, $msg) = &WinGetDB2Dir( \$dir, \$cmd );

if	($err)
{
	$dir = &Install_Ask( "DB2 home directory", "PATH DIR", undef );
	$dir =~ s#\\#/#g;
	$file = "$dir/bin/db2cmd.exe";
	return( 1, "File not found: $file" ) unless( -f "$file" );
	$cmd = "db2cmd";
}

$xc_DB_VENDOR	= "DB2";
$xc_DB_BINDIR	= "$dir/bin";
$xc_DB_USERNAME	= "";
$xc_DB_PASSWORD	= "";
$xc_DB_HOST		= $ENV{DB2INSTANCE} || "";
$xc_DB_COMMAND	= $cmd;

return( "" );

}	# end of Win Check DB2


#---------------------------------------
#	Win Get DB2 Dir
#---------------------------------------
sub WinGetDB2Dir
{
my( $p_path, $p_cmd ) = @_;
my( $s, $msg, $regkey, $result, $success, @a );

$success = 0;
$regkey = "SOFTWARE\\IBM\\DB2\\DB2 Path Name";
($s, $msg) = &GetReg( $regkey, \$result );
if( $s == 0 )
{
	$$p_path = $result;
	$result .= "/bin/db2cmd.exe";
	$result =~ s#\\#/#g;
	if	(-f $result)
	{
		$$p_cmd = "db2cmd";
		$success = 1;
	}
}

if	(!$success)
{
	$regkey = "SOFTWARE\\IBM\\DB2\\GLOBAL_PROFILE\\DB2PATH";
	($s, $msg) = &GetReg( $regkey, \$result );
	if( $s == 0 )
	{
		$$p_path = $result;
		$result .= "/bin/db2cmd.exe";
		$result =~ s#\\#/#g;
		if	(-f $result)
		{
			$$p_cmd = "db2cmd";
			$success = 1;
		}
	}
}

# Use another method if necessary
if	(!$success)
{
	# add DB2DIR to beginning of path if defined
	$s  = defined($ENV{DB2DIR}) ? $ENV{DB2DiR} . "/bin;" : "";
	$s .= $ENV{"PATH"};
	$s =~ s#\\#/#g;
	@a = split (";", $s);
	# For each directory in the PATH statement
	foreach $s (@a)
	{
		# If this directory contains SQL*Plus program
		if	(-f "$s/db2cmd.exe")
		{
			$$p_cmd = "db2cmd";
			$$p_path = $s;
			$$p_path =~ s#/bin$##i;
			$success = 1;
			last;
		}
	}
}

return (1, "Cannot determine DB2 database home directory")
	if	($success == 0);

$$p_path =~ s#\\#/#g;
$$p_path =~ s#/$##;
$$p_cmd .= ".exe" if( $$p_cmd !~ /\.exe$/i );

return( 0, "" );

}	# end of Win Get DB2 Dir


########################################################
#
#	Unix DB-related routines
#
########################################################


#------------------------------------------------
#	Unix Check Oracle 
#------------------------------------------------
sub UnixCheckOracle
{
my( $err, $msg, $dir, $cmd );

# Check for Oracle in registry
($err, $msg) = &UnixGetOracleDir( \$dir, \$cmd );

if	($err)
{
	$dir = &Install_Ask ("Oracle home directory", "PATH DIR", "");
	return( 1, "Cannot find 'sqlplus' in '$dir/bin'" ) unless(-f "$dir/bin/sqlplus");
	$cmd = "sqlplus";
}

$xc_DB_VENDOR   = "ORACLE";
$xc_DB_BINDIR   = "$dir/bin";
$xc_DB_USERNAME ||= "";
$xc_DB_PASSWORD ||= "";
$xc_DB_HOST     ||= "";
$xc_DB_COMMAND  = "$cmd";

return( 0, "" );

}	# end of Unix Check Oracle


#---------------------------------------
#	Unix Get Oracle Dir
#---------------------------------------
sub UnixGetOracleDir
{
my( $p_path, $p_cmd ) = @_;
my( $s, $exe, $cmd, $result, $file, $success, @a );

# add ORACLE_HOME to beginning of path	
$s = defined($ENV{ORACLE_HOME}) ? $ENV{ORACLE_HOME}	. "/bin:" : "";

$s .= $ENV{"PATH"};
@a = split (":", $s);

# For each directory in the PATH statement
$success = 0;
foreach $s (@a)
{
	# If this directory contains SQL*Plus program
	if	(-f "$s/sqlplus")
	{
		$$p_cmd = "sqlplus";
		$$p_path = $s;
		$$p_path =~ s#/bin$##i;
		$success = 1;
		last;
	}
}

return (1, "Cannot determine Oracle database home directory") unless( $success );

$$p_path =~ s#/$##;
$file = "$$p_path/bin/$$p_cmd";

if( -f "$file" ) 
{
	return( 0, "Found file: '$file'" );
}
else
{
	return( 2, "File not found: '$file" );
}

}	# end of Unix Get Oracle Dir


#------------------------------------------------
#	Unix Check DB2
#------------------------------------------------
sub UnixCheckDB2
{
my( $err, $msg, $dir, $cmd );

($err, $msg) = &UnixGetDB2Dir( \$dir, \$cmd );

if	($err)
{
	$dir = &Install_Ask( "DB2 home directory", "PATH DIR", undef );
	return( 1, "'$dir/bin/db2' not found" ) unless( -f "$dir/bin/db2" );
	$cmd = "db2";
}

$xc_DB_VENDOR   = "DB2";
$xc_DB_BINDIR   = "$dir/bin";
$xc_DB_USERNAME ||= "";
$xc_DB_PASSWORD ||= "";
$xc_DB_HOST     ||= "";
$xc_DB_COMMAND  = "$cmd";

return( "" );

}	# end of Unix Check DB2


#---------------------------------------
#	Unix Get DB2 Dir
#---------------------------------------
sub UnixGetDB2Dir
{
my( $p_path, $p_cmd ) = @_;
my( $s, $dir, $success, @a );

# add DB2DIR to beginning of path if defined
$s  = defined($ENV{DB2DIR}) ? $ENV{DB2DiR} . "/bin:" : "";

$s .= $ENV{"PATH"};
@a  = split (":", $s);

# For each directory in the PATH statement
$success = 0;
foreach $s (@a)
{
	# If this directory contains db2 program
	if	(-f "$s/db2")
	{
		$$p_cmd = "db2";
		$$p_path = $s;
		$$p_path =~ s#/bin$##i;
		$success = 1;
		last;
	}
}

return (1, "Cannot determine DB2 database home directory") unless( $success );

$$p_path =~ s#/$##;

return( 0, "" );

}	# end of Unix Get DB2 Dir


########################################################
#
#	Prompt Routines
#
########################################################


#---------------------------------------
#	Get EQ Home
#---------------------------------------
sub GetEQHome
{

if	($xc_EQ_PATH eq "")
{
	$xc_EQ_PATH = &Install_Ask( "Where to install Enterprise-Q", "PATH DIR", "C:/EQ");
	print "\n";
}

}	# end of Install Ask All


#---------------------------------------
#	Install Ask
#---------------------------------------
sub Install_Ask
{
my( $prompt, $type, $default ) = @_;
my( $err, $msg, $chars, $choice, $extra, $response );

while (1)
{
	print $prompt;
	print " [$default] "	if	(defined ($default));
	$response = <STDIN>;
	$response =~ s/\s+$//;
	
	# Assign default value
	if( defined( $default) && $response eq "" )
	{
		$response = $default;
	}
		
	$response =~ s/^"(.*)"$/$1/;	# remove double-quotes

	# Check data type
	if( $type eq "NUMBER" )
	{
		return $response if( $response =~ /^\d+$/ );
		&LogMsg( "*** Please, provide numeric data ***" );
	}
	
	elsif( $type =~ /^PATH/ )
	{
		$response =~ s#\\#/#g;
		if	($response !~ /^([A-Z]:)?\//i)
		{
			&LogMsg( "*** Please, provide absolute path ***" );
		}
		elsif( $type =~ /^PATH\s+FILE/ )
		{
			return $response	if( -f $response );
			&LogMsg( "*** File '$response' does not exist! ***" );
		}
		elsif( $type =~ /^PATH\s+DIR/ )
		{
#			$response =~ s/\/$//;	# commented this out so user can enter "/" or "c:/" without issue
			return $response	if	(-d $response);
			&LogMsg( "*** Directory '$response' does not exist! ***" );
		}
		else
		{
			if( $^O =~ /win/i )
			{
				return $response if( $response =~ /^[A-Z]:/i );
			}
			else
			{
				return $response if( $response !~ /^[A-Z]:/i );
			}
			&LogMsg( "*** Invalid directory for OS: $response ***" );
		}
	}
	
	elsif	($type =~ /^CHAR\s+(.+)$/i)
	{
		$chars = $1;
		return $response	if( length($response) == 1 && $chars =~ /$response/i );
		&LogMsg( "*** Please, enter one of the characters '$chars' ***" );
	}
	
	elsif	($type =~ /^CHOICE\s+(.+)$/i)
	{
		$choice = $1;
		return $response	if( $choice =~ /(^|,)$response(,|$)/i );
		&LogMsg( "*** Invalid response '$response'. Please, enter one of required choices '$choice' ***" );
	}
	
	elsif	($type =~ /^STRING\s+(.*)$/)
	{
		$error = "";
		$extra = $1 . " ";
		if	($extra =~ s/^(\d+),(\d+)\s+//)
		{
			if	((length ($response) < $1)||(length ($response) > $2))
			{
				if	($1 eq $2)
				{
					$error = "Invalid length: the string should $1 characters long";
				}
				elsif	(length ($response) < $1)
				{
					$error = "Invalid length: the string should be at least $1 characters long";
				}
				else
				{
					$error = "Invalid length: the string should be no more than $2 characters long";
				}
			}
		}
		$extra =~ s/\s+$//;
		if	($extra ne "")
		{
			$error = "The string contains invalid characters ($extra)" if( $response !~ /^$extra$/ );
		}
		
		return $response	if	($error eq "");
		&LogMsg( "*** $error ***" );
	}
}
	
}	# end of Install Ask


########################################################
#
#	Miscellaneous Routines
#
########################################################


#--------------------------------
#	Archive Files
#--------------------------------
sub ArchiveFiles
{
my( $srcdir, $p_files ) = @_;
my( $err, $msg, $dstdir, $file );

$srcdir =~ s#\\#/#g;
$dstdir = "$srcdir/archive";

# &LogMsg( "Archiving files from '$srcdir' to '$dstdir': " . join( ", ", @$p_files ) );

# Make the dir if it doesn't exist
unless( -d $dstdir )
{
#	&LogMsg( "Create archive directory '$dstdir'" );
	eval{ mkpath( $dstdir ) };
	$msg = $@;
	return( 1, $msg ) unless( $msg eq "" );
}

# Archive all the modules
foreach $file( @$p_files )
{
	next unless( -f "$srcdir/$file" );
#	&LogMsg( "Archive '$srcdir/$file' to '$dstdir'" );
	move( "$srcdir/$file", "$dstdir/$file" );
}

return( 0, "" );

}	# end of Archive Files


#-----------------------------------------
#	Subdir Check
#-----------------------------------------
sub SubdirCheck
{
my( $subdir, $p_untar_flag ) = @_;
my( $err, $msg, $cmd, $path );

$path = "$xc_EQ_PATH/$subdir";

# unless the subdir exists, set the untar flag to true and return
unless( -d "$path" )
{
	$$p_untar_flag = 1;
	return( 0, "" );
}

# subdir exists.  set default to false
$$p_untar_flag = 0;

# Ask user to overwrite existing installation
$msg = &Install_Ask( "'$path' already exists. Overwrite?", "CHAR YN", "N"  );
return( 0, "Skipping overwrite." ) if( $msg =~ /N/i );

# User wants to overwrite, so delete subdir first
if( $^O =~ /win/i )
{
	my $p = $path;
	$p =~ s#/#\\\\#g;
	$cmd = "rmdir /s /q $p";
}
else
{
	"rm -rf $path";
}
$msg = `$cmd 2>&1`;
$err = $?;
return( 1, "Error running '$cmd': $msg" ) if( $err );

# Successfully deleted subdir, so set untar flag to true and return
$$p_untar_flag = 1;
return( 0, "" );

}	# end of Subdir Check


#-----------------------------------------
# Install Update Files
#-----------------------------------------
sub Install_UpdateFiles
{
my( $p_dir ) = @_;
my( $s, @l_files, @a, $eq_path, $unix_os, $err, %SkipDir );

%SkipDir = 
(
	"perl5" 	=> "$xc_EQ_PATH/perl5",
	"apache"	=> "$xc_EQ_PATH/apache",
);

# See if the Skip Update file exists
return( 0, "" ) if( -f "$p_dir/.skip_update" );

# Make sure it's not one of the other special dirs
foreach $s( keys %SkipDir )
{
	return( 0, "" ) if( $p_dir eq $SkipDir{$s} );
}

# Set unix_os to 1 for UNIX and 0 for Windows
$unix_os = $xc_OS =~ /win/i ? 0: 1;

$eq_path = $xc_EQ_PATH . "/";
if	($unix_os)
{
	$s = `id 2>&1`;
	if	(($? == 0)&&($s =~ /^uid=\d+\(([^\)]+)\)\s+gid=\d+\(([^\)]+)\)/))
	{
		$x_data{"UID"} = $1;
		$x_data{"GID"} = $2;
	}
	else
	{
		return( 1, "Cannot get my user id: $s" );
	}
}
else
{
	$x_data{"UID"} = getlogin ();
	$x_data{"GID"} = "*";

	$eq_path =~ s#/#\\#g;
}

# Add environment variables to data array
@a = keys %ENV;
foreach $s (@a)
{
	$x_data{"ENV__" . $s} = $ENV{$s};
}
if	($unix_os)
{
	$x_data{ENV__PATH} .= ":${eq_path}lib"
		unless ($x_data{ENV__PATH} =~ /(^|:)${eq_path}lib(:|$)/);
	$x_data{ENV__PERLLIB} = (($xc_PERL_LIB_PATH)? $xc_PERL_LIB_PATH .":": "") .
		"${eq_path}lib";
}
else
{
	$x_data{ENV__PATH} .= ";${eq_path}lib"
		unless ($x_data{ENV__PATH} =~ /(^|;)${eq_path}lib(;|$)/i);
	# Remove doule quotes from path
	$x_data{ENV__PATH} =~ s/"//g;
	$x_data{ENV__PERLLIB} = (($xc_PERL_LIB_PATH)? $xc_PERL_LIB_PATH .";": "") .
		"${eq_path}lib";
	$x_data{ENV__PERLLIB} =~ s#/#\\#g;
}

@l_files = ();
# Open directory
opendir (IN_DIR, $p_dir) ||
	return( 1, "Cannot open directory '$p_dir': $!" );
while (defined ($s = readdir (IN_DIR)))
{
	# Skip current and parent directories entries and skipdir
	next	if	(($s eq ".")||($s eq ".."));
	$s =~ tr/A-Z/a-z/	unless ($unix_os);
	# Skip directories we don't want to process
	next if( exists( $SkipDir{$s} ) );
	push (@l_files, $p_dir . "/" . $s);
}
closedir (IN_DIR);

# For each file in current directory
foreach $s (@l_files)
{
	# If it's another directory
	if	(-d $s)
	{
		( $err, $msg ) = &Install_UpdateFiles ($s);
		return( $err, $msg ) if( $err );
	}
	# If it's a text file
	elsif	($s =~ /\.(pl|pm|bat|sh|cfg|conf|inc|htaccess|desc|label|trans|html|js)$/i)
	{
		($err, $msg) = &Install_UpdateOneFile( $s );
		return( $err, $msg ) if( $err );
	}
}

return( 0, "" );
	
}	# end of Install Update Files


#-----------------------------------------
#	Install Update One File
#-----------------------------------------
sub Install_UpdateOneFile
{
my	($p_file) = @_;
my	($s, @a, $l_changed, $l_line, $l_var, $l_post, $l_value, $os, $ignore);
my	($unix_os, @l_stat, $comment, $i);

# Set unix_os to 1 for UNIX and 0 for Windows
$unix_os = ($xc_OS =~ /Windows/i)? 0: 1;

$comment = "#";
if	($p_file =~ /\.(html|js)$/i)
{
	$comment = "//";
}
elsif	($p_file =~ /\.bat$/i)
{
	$comment = "rem\\s";
}

# Read data from file
open (IN_FILE, $p_file) || return( 1, "Cannot open file '$p_file': $!" );
@a = <IN_FILE>;
close (IN_FILE);

$l_changed = 0;
# If it's a perl file
if( $p_file =~ /\.pl$/i )
{
	if( @a < 2 || $a[1] !~ /^##DISABLE_UPDATE/ )
	{
		# Generate standard perl header
		$s = "#!" . $x_data{"PERL_BIN_PATH"} . "/perl\n";
		# If generated header is different from current header
		if( $s ne $a[0] )
		{
			$a[0] = $s;
			$l_changed = 1;
		}
	}
}

$ignore = 0;

# Parse all ~VAR~ variables in the file
for	($i = 0; $i < @a; $i++)
{
	$s = $a[$i];
		
	# Ignore the line if necessary
		
	next if( $s =~ /^\s*\#\s*IGNORE\s*/i );
	
	if	($ignore)
	{
		if	($s !~ /^\s*\#/)
		{
			$a[$i] = "#$s";
			$l_changed = 1;
		}
		$ignore = 0;
		next;
	}

	# Of line contains OS specific data
	if	($s =~ s/^\s*\#IF_(WIN|UNIX)#//)
	{
		$os = $1;
		# If this line is not valid for our current system
		if( ($os eq "WIN" && $xc_OS !~ /Windows/ ) ||
			($os eq "UNIX" && $xc_OS =~ /Windows/ ) )
		{
			# Ignore the line and comment out the next line.
			$ignore = 1;
			next;
		}
	}

	# If line contains configurable data
	if	($s =~ /^\s*${comment}.*\~\w+\~/i)
	{
		# Generate new line
		$s =~ s/\s+$//;
		$s =~ s/^(\s*)${comment}(\s*)//;
		$spaces = $1 . $2;
		$l_line = "\n$spaces";
		while ($s =~ /^(.*)\~(\w+)\~(.*)$/)
		{
			# Copy data into internal variables
			$s = $1;
			$l_var = $2;
			$l_post = $3;
			# If configuration data does not exist
			if	(!defined ($x_data{$l_var}))
			{
				if	($l_var =~ /^ENV__/)
				{
					$x_data{$l_var} = "";
				}
				else
				{
					#&LogMsg( "WARNING: Cannot resolve variable '$l_var' in file '$p_file'" );
					$s = $a[$i + 1];
					$l_line = "";
					last;
				}
			}
			$l_value = $x_data{$l_var};
			# If variable contains path
			if	($l_var =~ /_PATH$/i)
			{
				# Convert path to Windows format?
				if	($l_post =~ /^\\\\/)
				{
					$l_value =~ s#/#\\\\#g;
				}
				elsif	($l_post =~ /^\\/)
				{
					$l_value =~ s#/#\\#g;
				}
			}
			$l_line = $l_value . $l_post . $l_line;
		}
		$s .= $l_line;
		$a[$i + 1] = ""	if	(!defined ($a[$i + 1]));
		# If generated line is different from the next line
		if	($s ne $a[$i + 1])
		{
			$l_changed = 1;
			$a[$i + 1] = $s;
		}
	}
}

return( 0, "" ) if( $l_changed == 0 );

if	($unix_os)
{
	# Get original mode of the file
	return( 1, "Cannot get information about file '$p_file': $!" )
		unless (@l_stat = stat ($p_file));
}

# Write data back to file
open (OUT_FILE, ">$p_file") ||
	return( 1, "Cannot create file '$p_file': $!" );
print OUT_FILE join ("", @a);
close (OUT_FILE);

if	($unix_os)
{
	chmod ($l_stat[2] & 0777, $p_file) ||
		return( 1, "Cannot change mode of file '$p_file': $!" );
}

return( 0, "" );
	
}	# end of Install Update One File


#-----------------------------------------
#	Install MkDir
#-----------------------------------------
sub Install_MkDir
{
my( $dir ) = @_;
my( $err, $msg );

if( !-d $dir )
{
	eval { mkpath ($dir) };
	$msg = $@;
	$err = length( $msg ) > 0 ? 1 : 0;
	return( $err, $msg );
}

return( 0, "" );

}	# end of Install MkDir


#---------------------------------------
#	Verify Path
#---------------------------------------
sub VerifyPath
{
my( $add_path, $var ) = @_;
my( $cur_path, $sep, @a, $path );

$sep = $^O =~ /win/i ? ";" : ":";

$var = "PATH" unless( defined( $var ) && $var ne "" );
$cur_path = $ENV{$var};
$cur_path =~ s#\\#/#g;

@a = split( /$sep/, $add_path );
foreach $path( @a )
{
	# Convert to forward slashes for comparison purposes
	$path =~ s#\\#/#g;

	# next if path already included
	next if( $cur_path =~ /(^|$sep)$path($sep|$)/i );

	# Add the path
	$cur_path .= $sep . $path;
}

# Convert to backslashes if windows
$ENV{$var} = $cur_path;
$ENV{$var} =~ s#/#\\#g if( $^O =~ /win/i );

}	# end of Verify Path


#-----------------------------------------
#	Install Save Status
#-----------------------------------------
sub Install_SaveStatus
{
my( $file ) = @_;
my( $s, @a, $s1, $p_data );

open( OUT_FILE, ">$file" ) || return( 1, "Cannot create file '$file': $!" );
print OUT_FILE <<EOF;
# Enterprise-Q configuration file.
# This file may be processed as text file or it
# may be included as a part of perl scripts.
# This file is generated automatically.
EOF

@a = localtime (time());
$s = sprintf ("%02d/%02d/%04d %02d:%02d:%02d",
	$a[4] + 1, $a[3], $a[5] + 1900, $a[2], $a[1], $a[0]);
print OUT_FILE "# Last updated: $s\n\n";

foreach $s( sort keys %x_vars ) 
{
	$p_data = $x_vars{$s};
	if( defined( $$p_data ) ) { $s1 = $$p_data; }
	else { next; }
	$s1 =~ s/^"(.*)"$/$1/;
	$s1 =~ s/([\\\@\"\$])/\\$1/g;
	print OUT_FILE "\$xc_", $s, "=\"", $s1, "\";\n";
}

print OUT_FILE <<EOF;

# Do not remove this line!
1;
EOF
close (OUT_FILE);

return( 0, "" );

}	# end of Install Save Status


#-----------------------------------------
#	Install Load Status
#-----------------------------------------
sub Install_LoadStatus
{
	my	($p_file) = @_;
	my	($s, @a, $l_var, $value);

	open (IN_FILE, $p_file) ||
		&Install_Die ("Cannot open file '$p_file': $!");
	while (defined ($s = <IN_FILE>))
	{
		# Skip empty lines and space
		next	if	($s =~ /^\s*$/);
		next	if	($s =~ /^\s*#/);
		next	if	($s =~ /^1;\s*$/);

		$s =~ s/\s+$//;
		if	($s =~ /^\$xc_(\w+)\s*=\s*"(.*)"\s*;\s*$/)
		{
			$l_var = "\U$1";
			$value = $2;
			$value =~ s/\\\@/\@/g;
			if	(defined ($x_vars{$l_var}))
			{
				${$x_vars{$l_var}} = $value;
			}
		}
		elsif	($s !~ /^\s*$/)
		{
			&LogMsg( "*** Error in file '$p_file': invalid data '$s' ***" );
		}
	}
	close (IN_FILE);

	# Save all variables into data array
	foreach $s ( keys %x_vars ) {
		if( defined (${$x_vars{$s}})) { $x_data{$s} = ${$x_vars{$s}}; }
	}
	
}	# end of Install Load Status


#-------------------------#
# Install Die	          #
#-------------------------# 
sub Install_Die 
{
my	($disp_err) = @_; 
my	($l_button, $frm1, @a, $s, $text);

$disp_err =~ s/\s+$//s;
&LogMsg( "Installation error, message = $disp_err" ); 

print $disp_err, "\n";
exit (1);

}	# end of Install Die


#-----------------------------------------
#	Log Msg
#-----------------------------------------
sub LogMsg
{
my( $msg ) = @_;
my( $ts, @a );

@a = localtime( time() );	
$ts = sprintf( "%02d:%02d:%02d", $a[2], $a[1], $a[0] );

$msg =~ s/\n*$/\n/g;

print LOG_FILE "$ts  $msg";
print $msg;

}	# end of Log Msg


1;
