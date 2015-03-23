#!C:/scratch/EQServer/perl5/bin/perl

#
# Installation Script
#      
# (C) Copyright Capital Software Corporation, 2000-2014 - All Rights Reserved 
#

$product = $ENV{PRODUCT} || "~~~PRODUCT~~~";
$product_lc = lc($product);

if	((@ARGV == 1)&&($ARGV[0] eq "-v"))
{
	print '$Id: EQServerInstall.pl,v 1.1.2.1 2014/11/21 21:07:12 eqadmin Exp $', "\n";
	exit (0);
}

use DBI;

require "./lib/EQInstallLib." . "pl";
require "./lib/eqclientlib." . "pl";

sub	AskDB;
sub	AskDBinfo;
sub	AskEQCron;
sub	CheckDB2;
sub	CheckMySQL;
sub	CheckOracle;
sub	CompleteMySQLInstall;
sub	GetReg;
sub	Install_CreateEQDBTables;
sub	Install_HandleDB;
sub	Install_Install;
sub	Install_RescheduleTasks;
sub	Install_SaveEnv;
sub	Install_SchedTasks;
sub	Install_ShowMenu;
sub	Install_Uninstall;
sub	Install_UpdateConfig;
sub	InstallMySQL;
sub	InstallRemoveCronJobs;
sub	RemoveEQPolicyCode;
sub	SetReg;
sub	StartServices;
sub	UninstallMySQL;
sub	ValidateDB2Info;
sub	ValidateMySQLInfo;
sub	ValidateOracleInfo;

%x_vars =
(
	"APACHE_PATH",		\$xc_APACHE_PATH,
	"APACHE_PORT",		\$xc_APACHE_PORT,
	"DB_BINDIR",		\$xc_DB_BINDIR,
	"DB_COMMAND",		\$xc_DB_COMMAND,
	"DB_HOST",			\$xc_DB_HOST,
	"DB_PASSWORD",		\$xc_DB_PASSWORD,
	"DB_USERNAME",		\$xc_DB_USERNAME,
	"DB_VENDOR",		\$xc_DB_VENDOR,
	"DEFTARGETTYPE",	\$xc_DEFTARGETTYPE,
	"EQ_DIR_PATH",		\$xc_EQ_DIR_PATH,
	"EQ_DRIVE",			\$xc_EQ_DRIVE,
	"EQ_ID",			\$xc_EQ_ID,
	"EQ_MN",			\$xc_EQ_MN,
	"EQ_PATH",			\$xc_EQ_PATH,
	"EQ_PORT",			\$xc_EQ_PORT,
	"EQ_PR",			\$xc_EQ_PR,
	"EQ_TASKLIB",		\$xc_EQ_TASKLIB,
	"ERROR_LENGTH",		\$xc_ERROR_LENGTH,
	"HOSTNAME",			\$xc_HOSTNAME,
	"IP",				\$xc_IP,
	"LICENSE",			\$xc_LICENSE,
	"OS",				\$xc_OS,
	"PERL_BIN_PATH",	\$xc_PERL_BIN_PATH,
	"PERL_LIB_PATH",	\$xc_PERL_LIB_PATH,
	"REGION",			\$xc_REGION,
	"SITE",				\$xc_SITE,
	"TIVOLI_FRWK",		\$xc_TIVOLI_FRWK,
	"TMR_MN",			\$xc_TMR_MN,
	"TMRNAME",			\$xc_TMRNAME,
	"ITM6_SUPPORT",		\$xc_ITM6_SUPPORT,
	"ITM6_VERSION",		\$xc_ITM6_VERSION,
	"ITM6_TEPSLOGIN",	\$xc_ITM6_TEPSLOGIN,
	"CANDLEHOME",		\$xc_CANDLEHOME,
#	"VERSION",			\$xc_VERSION
);

%x_config_options =
(
	"Update configuration parameters.", "Install_UpdateConfig",
	"Re-schedule EQ tasks.", "Install_RescheduleTasks",
	"Update EQ environment variables.", "Install_SaveEnv",
	"Update Service Registry Keys.", "Install_UpdateServiceRegistry",
	"Un-install Services.", "UnInstall_Services",
	"Re-install Services.", "ReInstall_Services",
);


if( -f "./install/preinst.pl" )
{
	unless( open (IN_FILE, "./install/preinst.pl") )
	{
		print "ERROR: Cannot open file './install/preinst.pl': $!";
		exit( 1 );
	}
	$s = join ("", <IN_FILE>);
	close (IN_FILE);
	eval "$s";
}

%x_data = ();

# Set location of setup_env.pl
#$s = $^O =~ /win/i ?  $ENV{"WINDIR"} . "/system32/drivers/etc/EQ" : "/etc/EQ";
#$s = $^O =~ /win/i ? "$ENV{HOMEDRIVE}/$ENV{HOMEPATH}/.eqserver" : "$ENV{HOME}/.eqserver";
if( defined($ENV{EQHOME}) && -d $ENV{EQHOME} )
{
	$s = $ENV{EQHOME};
}
else
{
	use Cwd;
	$s = &getcwd( );
	$s =~ s#\\#/#g;
	if( $^O =~ /win/i ) { `setx /M EQHOME \"$s\"`; }
	else { `echo export EQHOME=$s >> $ENV{HOME}/.profile`; }
	$ENV{EQHOME} = $s;
}

# Make the $home/cfg directory if it doesn't exist
($err, $msg) = &Install_MkDir( "$s/cfg" );
&LogMsg( $msg ) if( $err );

$x_install_data_file = $s . "/cfg/setup_env.pl";
&Install_LoadStatus( $x_install_data_file ) if( -f $x_install_data_file );

# Make sure top level directory defined
$xc_EQ_PATH = &getcwd( );
$xc_EQ_PATH =~ s#/install$##i;	# prune '/install' subdir

# Check for drive letter on windows systems
if( $xc_EQ_PATH =~ /^([A-Z]:)(.+)/i )
{
	$xc_EQ_DRIVE = $1;
	$xc_EQ_DIR_PATH = $2;
	$xc_EQ_DRIVE =~ tr/a-z/A-Z/;
}
else
{
	$xc_EQ_DRIVE = "";
	$xc_EQ_DIR_PATH = $xc_EQ_PATH;
}

%EQCoreServices =
(
	EQServer	=> 2345,
#	EQScheduler	=> 2330,
#	EQApache	=> $xc_APACHE_PORT,
);

%EQTivoliServices =
(
	EQMDMon		=> 2331,
	EQSPMon		=> 2332,
	EQICMon		=> 2333,
	EQTMMon		=> 2334,
);


$syntax =<<EOF;
Syntax: $0 install
         - install product in specified directory
        $0 uninstall
         - uninstall product
        $0 menu
         - display configuration menu
EOF

my $err = 1;
my $msg = $syntax;
if	($ARGV[0] eq "install")
{
	($err, $msg) = &Install_Install( );
}

elsif( $ARGV[0] eq "uninstall" )
{
	($err, $msg) = &Install_Uninstall( \%EQCoreServices );
	($err, $msg) = &Install_Uninstall( \%EQTivoliServices ) if( $xc_TIVOLI_FRWK );
}

elsif( $ARGV[0] eq "menu" )
{
	($err, $msg) = &Install_ShowMenu( );
}

else
{
	$msg = "Unrecognized option: " . $ARGV[0]. "\n" . $syntax;
	$err = 1;
}

print "$msg\n" if( $err );

exit( $err );


#---------------------------------------
#	Install Install
#---------------------------------------
sub Install_Install
{
my( $err, $msg, $cmd, $file, $s, @a );
	
return( 1, "ERROR: Cannot open file '$xc_EQ_PATH/eq_install_log.txt': $!" )
	unless( open (LOG_FILE, ">$xc_EQ_PATH/eq_install_log.txt") );
	
&LogMsg( "Use CTRL-C to abort installation" );
&LogMsg( "Installation starting" );

&HandleOSSpecificFiles( );

&MakeEQDirs( );

&SetXBit( ) unless( $^O =~ /win/i );

# Display license agreement
if( -f "$xc_EQ_PATH/license/LICENSE" )
{
	$file = "$xc_EQ_PATH/license/LICENSE";
}
elsif( -f "$xc_EQ_PATH/install/eq-license.txt" )
{
	$file = "$xc_EQ_PATH/install/eq-license.txt";
}

open( LA, "$file" ) || return( 1, "Error opening '$file': $!" );
@a = <LA>;
close( LA );

print "   *****\n" . join( "", @a ) . "\n   *****\n\n";

$s = &Install_Ask ("Agree (Y/N)?", "CHAR YN", "Y" );
return( 1, "Must agree to Terms & Conditions prior to installing software" ) unless( $s =~ /y/i );

# Get hostname
if( !defined($xc_HOSTNAME) || $xc_HOSTNAME eq "" ) 
{
	$cmd = "hostname";
	$xc_HOSTNAME = `$cmd 2>&1`;
	return( 1, "Cannot get hostname using '$cmd': $xc_HOSTNAME" ) if( $? || $xc_HOSTNAME =~ /^\s*$/ );
	$xc_HOSTNAME =~ s/\s+$//;
	$xc_HOSTNAME =~ tr/A-Z/a-z/;
}

# Get IP address
&LogMsg( "Getting IP Address of host..." );
@a = gethostbyname ($xc_HOSTNAME);
@a = unpack ('C4', $a[4]);
return( 1, "Cannot get IP address of host '$xc_HOSTNAME'")	if	(@a < 4);

$xc_IP = $a[0] . "." . $a[1] . "." . $a[2] . "." . $a[3];

# Get OS 
$xc_OS = $^O;
$xc_OS =~ tr/a-z/A-Z/;

# For MSWin32, set xc_OS to WINDOWS, as this string is used in many regexs
$xc_OS = "WINDOWS" if( $xc_OS eq "MSWIN32" );

# Set length of the ERROR field in EQServer and in DB.
$xc_ERROR_LENGTH = 1024;
$xc_EQ_PORT = 2345	unless ($xc_EQ_PORT);

# untar perl5 and set perl bin and lib paths
($err, $msg) = &UntarPerl5( );
return( 1, $msg ) if( $err );

$xc_EQ_LIB_PATH = "$xc_EQ_PATH/lib";
$xc_PERL_BIN_PATH = "$xc_EQ_PATH/perl5/bin";
$xc_PERL_LIB_PATH = "$xc_EQ_PATH/perl5/lib";
$xc_PERL_SITE_LIB = $xc_OS =~ /win/i ? "$xc_EQ_PATH/perl5/site/lib" : "$xc_EQ_PATH/perl5/lib/site_perl";

# Make sure these paths are included in PATH & PERL5LIB env vars
@a = ( "$xc_PERL_SITE_LIB", "$xc_PERL_LIB_PATH", "$xc_EQ_LIB_PATH", "." );
foreach $path( @a )
{
	&VerifyPath( $path, "PATH" );
	&VerifyPath( $path, "PERL5LIB" );
}

# Define other perl env variables
$ENV{PERLBIN} = $xc_PERL_BIN_PATH;
$ENV{PERLLIB} = $xc_PERL_LIB_PATH;
$ENV{PERLSITELIB} = $xc_PERL_SITE_LIB;

# Now set windows system PATH env var
if( $xc_OS =~ /win/i )
{
	($err, $msg) = &SetWinPath( $ENV{PATH} );
	if( $err ) { &LogMsg( "Error updating system PATH: $msg" ); }
	else { &LogMsg( "PATH Updated: $msg" ); }
}

# Set DB variables and create tables
($err, $msg) = &Install_HandleDB( );
return( 1, $msg ) if( $err );

# Install apache
if( -f "$xc_EQ_PATH/install/apache.tar" )
{
	($err, $msg) = &UntarApache( \$xc_APACHE_VERSION );
	return( 1, $msg ) if( $err );
	$xc_APACHE_PORT = &Install_Ask( "Please enter Apache Web Server Port", "NUMBER", 80 );
}
else
{
	# Set apache args to null string
	$xc_APACHE_PATH = "";
	$xc_APACHE_PORT = "";
}

# Extract contents of awstats tarfile
($err, $msg) = &UntarAwstats( );
&LogMsg( "Error calling UntarAwstats: $msg" ) if( $err );

unless( $product_lc eq "eqserver" )
{
	# See if Tivoli Framework supported
	($err, $msg) = &Check4TivoliFramework( );
	&LogMsg( $msg ) if( $err );
}

unless( $product_lc eq "eqserver" )
{
	# See if ITM 6 is supported
	($err, $msg) = &Check4ITM6( );
	&LogMsg( $msg ) if( $err );
}

##############################################################################
# DON'T MODIFY INSTALLATION PARAMETERS AFTER THIS LINE - THEY WON'T BE SAVED
##############################################################################

# Add path to shared libraries. This should be done prior to saving env.cfg
# file and prior to updating all other configuration and perl files.
&VerifyPath( "$xc_EQ_PATH/lib",		"LD_LIBRARY_PATH" );
&VerifyPath( $x_ld_library_path,	"LD_LIBRARY_PATH" );
&VerifyPath( "$xc_EQ_PATH/lib",		"LIBPATH" );
&VerifyPath( $x_libpath,			"LIBPATH" );

# Save all variables into data array
foreach $s( keys %x_vars ) 
{
	next unless( defined(${$x_vars{$s}}) );
	$x_data{$s} = ${$x_vars{$s}};
}

&LogMsg( "Updating configuration data in EQ files..." );
($err, $msg) = &Install_UpdateFiles( $xc_EQ_PATH );
return( $err, $msg ) if( $err );

# Generate env.cfg file
&LogMsg( "Creating environment file..." );
($err, $msg) = &Install_SaveEnv( );
return( $err, $msg ) if( $err );

&LogMsg( "Saving installation data..." );
($err, $msg) = &Install_SaveStatus ($x_install_data_file);
return( $err, $msg ) if( $err );

# Start EQ Daemons
&StartServices( \%EQCoreServices );

# Start Tivoli related Daemons if installed
&StartServices( \%EQTivoliServices ) if( $xc_TIVOLI_FRWK );

# Schedule EQ maintenence jobs
if( -f "$xc_EQ_PATH/bin/EQScheduler" || -f "$xc_EQ_PATH/bin/EQScheduler.exe" || -f "$xc_EQ_PATH/bin/EQScheduler.pl" )
{
	&LogMsg( "Scheduling tasks..." );
	($err, $msg) = &Install_SchedTasks ();
	#return( $err, $msg ) if( $err );
}
else
{
	if( $^O =~ /win/i )
	{
		&Install_UpdateAT( );
	}
	else
	{
		&Install_UpdateCron( );
	}
}

# If post-install script exist - start it
if( -f "$xc_EQ_PATH/install/postinst.pl" ) 
{
	&LogMsg( "Starting post-installation script..." );
	&Post_Install( );
}

&LogMsg( "Installation Complete" );

&RootPostInstall( ) unless( $^O =~ /win/i );

return( 0, "" );

}	# end of Install_Install


#########################    SUBROUINTES START HERE    #########################

############################
#	Set X Bit
############################
sub SetXBit
{
my @files = (
	"./*.sh",
	"./*.pl",
	"bin/*",
	"bin/cron/*.sh",
	"install/*.sh",
	"build/*.sh",
	"build/*.pl",
);

foreach my $file( @files )
{
	my $cmd = "chmod +x $file";
	`$cmd 2>&1`;
}

}	# end of Set X Bit


############################
#	Make EQ Dirs
############################
sub MakeEQDirs
{
my @dirs = ( "logs", "temp", "qstore", "qstore/status" );
my $skip_update = 1;

foreach my $dir( @dirs )
{
	&Install_MkDir( $dir, $skip_update );
}

}	# end of Make EQ Dirs


############################
#	Handle OS Specific Files
############################
sub HandleOSSpecificFiles
{
my( $dir, $file, $type, $os, $base, $ext );
my @dirs = ( "./", "./bin", "./lib", "./install" );
my %OSFileType = 
(
	"linux"	=> "linux",
	"solaris" => "solaris",
	"aix" => "aix",
	"exe" => "MSWin32",
	"dll" => "MSWin32",
	"bat" => "MSWin32",
	"ico" => "MSWin32",
);

use File::Copy;
foreach $dir( @dirs )
{
	opendir( DH, "$dir" ) || next;
	while( $file = readdir( DH ) )
	{
		next if( -d "$file" );
		foreach $type( keys %OSFileType )
		{
			next unless( $file =~ /^(.+)\.$type(.*)$/ );
			$base = $1;
			$ext = $2;
			$os = $OSFileType{$type};
			if( $os eq $^O )
			{
				next if( $^O =~ /win/i );	# All windows files stay as is
				copy( "$dir/$file", "$dir/$base$ext" );
			}
			else
			{
				unlink( "$dir/$file" );
			}
		}
	}
	closedir( DH );
}
}	# end of Handle OS Specific Files


#######################
#	Set Win Path
#######################
sub SetWinPath
{
my( $path ) = @_;
my( $err, $msg, $key, @a, %hash, $dir, $lcdir );

# convert backslashes to forward slashes
$path =~ s#\\#/#g;

# get array of dirs
@a = split( /;/, $path );

# start with empty path
$path = "";
foreach $dir( @a )
{
	# store lowercase version of dir
	$lcdir = lc($dir);
	
	# skip dups and temp dirs used for pp executables
	next if( defined($hash{$lcdir}) || $lcdir =~ /par-/ );
	
	# store lc dir in hash to check for dups
	$hash{$lcdir} = 1;
	
	# add dir to path
	if( $path eq "" ) { $path = $dir; }
	else { $path .= ";$dir"; }
}

# convert forward slashes with backslashes
$path =~ s#/#\\#g;

# store path in env var
$ENV{PATH} = $path;

# set the system path registry variable
$key = "HKEY_LOCAL_MACHINE\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Environment\\Path";
($err, $msg) = &SetReg( $key, $path );
return( $err, $msg );

}	# end of Set Win Path


#######################
#	Root Post Install
#######################
sub RootPostInstall
{
my( $msg );
my( $src, $dst, $startdir, $killdir );

$src = "$xc_EQ_PATH/install/data";
if( $^O =~ /aix/i )
{
	$dst = "/etc/rc.d/init.d";
	$startdir = "/etc/rc.d/rc2.d";
	$killdir = "/etc/rc.d/rc2.d";
}
elsif( $^O =~ /sol/i )
{
	$dst = "/etc/init.d";
	$startdir = "/etc/rc3.d";
	$killdir = "/etc/rc2.d";
}
elsif( $^O =~ /linux/i )
{
	$dst = "/etc/init.d";
	$startdir = "/etc/rc.d/rc3.d";
	$killdir = "/etc/rc.d/rc2.d";
}
else
{
	&LogMsg( "Unknown OS: $^O" );
	return;
}

# Copy our shell scripts to system init.d location and 
# create sym links to start/stop on boot/shutdown
$s = <<EOT;
\#\!/bin/sh

cp		$src/S99VEQ.sh			$dst
cp		$src/S99VEQScheduler.sh	$dst
cp		$src/S50apache.sh		$dst

ln -s 	$dst/S99VEQ.sh			$startdir/S99VEQ
ln -s 	$dst/S99VEQScheduler.sh	$startdir/S99VEQScheduler
ln -s 	$dst/S50apache.sh		$startdir/S50apache

ln -s 	$dst/S99VEQ.sh			$killdir/K20VEQ
ln -s 	$dst/S99VEQScheduler.sh	$killdir/K20VEQScheduler
ln -s 	$dst/S50apache.sh		$killdir/K50apache

EOT

if( $xc_TIVOLI_FRWK )
{
$s .= <<EOT;
cp		$src/S99VEQICMon.sh		$dst
cp		$src/S99VEQSPMon.sh		$dst
cp		$src/S99VEQTMMon.sh		$dst
cp		$src/S99VEQMDMon.sh		$dst

ln -s 	$dst/S99VEQICMon.sh		$startdir/S99VEQICMon
ln -s 	$dst/S99VEQSPMon.sh		$startdir/S99VEQSPMon
ln -s 	$dst/S99VEQTMMon.sh		$startdir/S99VEQTMMon
ln -s 	$dst/S99VEQMDMon.sh		$startdir/S99VEQMDMon

ln -s 	$dst/S99VEQICMon.sh		$killdir/K20VEQICMon
ln -s 	$dst/S99VEQSPMon.sh		$killdir/K20VEQSPMon
ln -s 	$dst/S99VEQTMMon.sh		$killdir/K20VEQTMMon
ln -s 	$dst/S99VEQMDMon.sh		$killdir/K20VEQMDMon

EOT
}

$file = "$xc_EQ_PATH/RootPostInst.sh";
unless( open( FH, ">$file" ) )
{
	&LogMsg( "Error opening '$file': $!" );
	return;
}
print FH $s;
close( FH );

$msg = <<EOT;

Please log into host as ROOT user to:
=================================================

EOT

if( -f "$xc_APACHE_PATH/bin/apachectl" )
{
$msg = <<EOT;
- Start Apache:

	$xc_APACHE_PATH/bin/apachectl start

EOT
}

$msg = <<EOT;
- Auto-Start daemons on system boot:

	$file

EOT

&LogMsg( $msg );

}	# end of Root Post Install


#######################
#	Install Update Service Registry
#######################
sub Install_UpdateServiceRegistry
{
my( $err, $msg );

# Remove EQ Services	
($err, $msg) = &UpdateServiceRegistry( \%EQCoreServices );

# Remove Tivoli Services	
($err, $msg) = &UpdateServiceRegistry( \%EQTivoliServices ) if( $xc_TIVOLI_FRWK );

}	# end of Install Update Service Registry


#######################
#	UnInstall Services
#######################
sub UnInstall_Services
{
my( $err, $msg );

# Remove EQ Services	
($err, $msg) = &Install_Uninstall( \%EQCoreServices );

# Remove Tivoli Services	
($err, $msg) = &Install_Uninstall( \%EQTivoliServices ) if( $xc_TIVOLI_FRWK );

}	# end of ReInstall Services


#######################
#	ReInstall Services
#######################
sub ReInstall_Services
{
my( $err, $msg );

# Remove EQ Services	
($err, $msg) = &Install_Uninstall( \%EQCoreServices );

# Remove Tivoli Services	
($err, $msg) = &Install_Uninstall( \%EQTivoliServices ) if( $xc_TIVOLI_FRWK );

# Install/Start EQ Services
&StartServices( \%EQCoreServices );

# Install/Start Tivoli Services
&StartServices( \%EQTivoliServices ) if( $xc_TIVOLI_FRWK );

}	# end of ReInstall Services


#######################
#	Start Services
#######################
sub StartServices
{
my( $p_services ) = @_;
my( $err, $msg, $cmd, $i, $service, $port, $winsrv );

foreach $service( keys %$p_services )
{
	$port = $p_services->{$service};
	if( $service eq "EQApache" && $xc_APACHE_PATH ne "" )
	{
		($err, $msg) = &Install_Apache( );
		&LogMsg( $msg ) if( length($msg) > 0 );
		next;
	}
	
	next unless( -f "$xc_EQ_PATH/bin/${service}.exe" || -f "$xc_EQ_PATH/bin/${service}" || -f "$xc_EQ_PATH/bin/${service}.pl" );
	
	if( $xc_OS =~ /win/i )
	{
		&LogMsg( "Installing $service..." );
		($err, $msg) = &InstallW_EQService( $service, $port );
		&LogMsg( $msg ) unless( $msg eq "" );
	}
	else
	{
		my( $script ) = "$xc_EQ_PATH/bin/${service}";
		my( $ext ) = -f "${script}.pl" ? ".pl" : "";
		$cmd = "nohup ${script}${ext} >$xc_EQ_PATH/temp/$service.nohup 2>&1 &";
		&LogMsg( "Starting $service using '$cmd'" );
		($err, $msg ) = &InstallU_CheckService( $service . $ext, $cmd, $port );
		&LogMsg( $msg ) if( $err || length($msg) );
	}
}

}	# end of Start Services


#######################
#	Update Service Registry
#######################
sub UpdateServiceRegistry
{
my( $p_services ) = @_;
my( $err, $msg, $service, $port, $eqpath );

$eqpath = $xc_EQ_PATH;
$eqpath =~ s#/#\\#g;

foreach $service( keys %$p_services )
{
	# next if not windows, the service is apache, or the service exe doesn't exist
	next if( $xc_OS !~ /win/i  || $service eq "EQApache" );
	next unless( -f "$xc_EQ_PATH/bin/${service}.exe" || -f "$xc_EQ_PATH/bin/${service}.pl" );

	$port = $p_services->{$service};
	
	&LogMsg( "Updating Registry Parameters for $service..." );
	($err, $msg) = &InstallW_UpdateServiceRegistry( $eqpath, $service, $port );
	&LogMsg( $msg ) unless( $msg eq "" );
}

}	# end of Update Service Registry


#-----------------------------------------
#	Install Uninstall
#-----------------------------------------
sub Install_Uninstall
{
my( $p_services ) = @_;
my( $err, $msg, @a, $s, $i, $service, $port );

if( $^O =~ /win/i )
{
	# undef EQHOME environment variable
	`setx /M EQHOME \"\"`;
	&Install_RemoveATJobs( );
	foreach $service( keys %$p_services )
	{
		next unless( -f "$xc_EQ_PATH/bin/${service}.exe" || -f "$xc_EQ_PATH/bin/${service}.pl" );
		$port = $p_services->{$service};
		# Stop and remove service
		&LogMsg( "Removing $service service..." );
		`$xc_EQ_PATH/bin/eqsrv.exe stop $service 2>&1`;
		`$xc_EQ_PATH/bin/eqsrv.exe remove $service 2>&1`;
	}
	return( 0, "" );
}

# Remove EQHOME from .profile
`mv $ENV{HOME}/.profile $ENV{HOME}/.profile.save 2>&1`;
unless( $? )
{
	`sed "/export EQHOME/d" $ENV{HOME}/.profile.save > $ENV{HOME}/.profile`;
}

# Must be *nix, so remove cron jobs first
&Install_RemoveCronJobs( );

# For *nix, stop the processes using EQMsg t_msg=stop
foreach $service( keys %$p_services )
{
	next unless( -f "$xc_EQ_PATH/bin/${service}" || -f "$xc_EQ_PATH/bin/${service}.pl");
	$port = $p_services->{$service};
	next if( $service eq "EQApache" );
	&LogMsg( "Stopping $service..." );
	`$xc_EQ_PATH/bin/EQMsg -p $port t_msg=stop 2>&1`;
}

# Tell user how to stop Apache
&LogMsg( "To stop Apache, login as 'root' user and run '$xc_APACHE_PATH/bin/apachectl stop'" ) unless( $product_lc eq "eqserver" );

# Now, make sure all daemons are stopped
@a = `ps -e -o pid,comm 2>&1`;
$err = $?;
return( 0, "*** ERROR: Cannot get a list of all processes:\n", join ("", @a) ) if( $err );

foreach $s (@a)
{
	foreach $service( keys %$p_services )
	{
		next unless( ($s =~ m#^(\d+)\s+($service)#) ||
			 		 ($s =~ m#^(\d+)\s+$xc_EQ_PATH/bin/($service)#) );
		`kill -9 $1 2>&1`;
		last;
	}
}

return( 0, "" );

}	# end of Install Uninstall


#------------------------------------------------
#	Check MySQL
#------------------------------------------------
sub CheckMySQL 
{
my( $err, $msg, $dir, $s, $sep );

$sep = $^O =~ /win/i ? ";" : ":";
$s  = defined($ENV{MYSQL_HOME}) ? $ENV{MYSQL_HOME} . "/bin" . $sep : "";
$s .= $ENV{"PATH"};
@a = split ("$sep", $s);

# For each directory in the PATH statement
$dir = "";
foreach $s (@a)
{
	# If this directory contains mysql program
	if	(-f "$s/mysql")
	{
		$dir = $s;
		$dir =~ s#/bin$##i;
		last;
	}
}

# If everything else fails
$dir = &Install_Ask ("MySql home directory", "PATH DIR", undef ) if( $dir eq "" );

$dir =~ s#/bin$##i;

$xc_DB_VENDOR   = "MYSQL";
$xc_DB_BINDIR   = "$dir/bin";
$xc_DB_USERNAME = "EQUser";
$xc_DB_PASSWORD = "";
$xc_DB_HOST     = "localhost";
$xc_DB_COMMAND  = "mysql";

return( 0, "" );

}	# end of Check MySQL


#------------------------------------------------
#	Check Oracle
#------------------------------------------------
sub CheckOracle
{
my( $err, $msg );

if( $xc_OS =~ /win/i )
{
	($err, $msg) = &WinCheckOracle( );
}
else
{
	($err, $msg) = &UnixCheckOracle( );
}

return( $err, $msg );

}	# end of Check Oracle


#------------------------------------------------
#	Check DB2
#------------------------------------------------
sub CheckDB2
{
my( $err, $msg );

if( $xc_OS =~ /win/i )
{
	($err, $msg) = &WinCheckDB2( );
}
else
{
	($err, $msg) = &UnixCheckDB2( );
}

return( $err, $msg );

}	# end of Check DB2


#---------------------------------------
#	Install Create EQ DB Tables
#---------------------------------------
sub Install_CreateEQDBTables
{

my( $d, $c, $u, $p, $h, $cmd );
my( $s, @a, $i, $db_dir, $sql_file );

$d = $xc_DB_VENDOR;
$c = $xc_DB_COMMAND;
$u = $xc_DB_USERNAME;
$p = $xc_DB_PASSWORD;
$h = $xc_DB_HOST;
$db_dir = $xc_DB_BINDIR;
$cmd = "$db_dir/$c";

if( $^O =~ /win/i )
{
	$cmd =~ s#/#\\#g;
	$db_dir =~ s#/#\\#g;
}

if( $d =~ /ORACLE/i )
{
	$s = $p;
	$s .= "\@" . $h if( defined($h) && $h ne "" );
	@a = `echo quit | \"$cmd\" $u/$s \@unin_ora.sql 2>&1`;
	@a = `echo quit | \"$cmd\" $u/$s \@inst_ora.sql 2>&1`;
	for ($i = 0; $i < @a; $i++)
	{
		$s = $a[$i];
		if( $s =~ /^ERROR at line/i || $s =~ /^ORA\-\d\d\d/ )
		{
			# Skip "DROP ..." errors
			next if( $s =~ /^ORA\-00942/ );
			next if( $s =~ /^ERROR at line/i &&
					$i < @a - 1 && $a[$i + 1] =~ /^ORA\-00942/ );
			return( 1, "Error creating tables:\n    " . join ("   ", @a) . "\n" );
		}
	}
}
elsif	($d =~ /DB2/i)
{
	# Generate file with "connect to ..." statement and all table creation
	# SQL statements
	$sql_file = "$xc_EQ_PATH/install/inst_db2.sql";
	$s = &Install_RunDB2Script ($sql_file, $cmd, $u, $p, $h, \@a);
	return( 1, $s ) if( $s );
	for ($i = 0; $i < @a; $i++)
	{
		$s = $a[$i];
		# Look for error message
		if	($s =~ /^SQL\d\w+\s+/)
		{
			# Skip "DROP ..." errors
			next if( $s =~ /^SQL0204N\s+"[^"]+\.([^"]+)" is an undefined name\./i );
			return( 1, "Error creating tables:\n    " . join ("   ", @a) . "\n" );
		}
	}
}
elsif( $d =~ /MYSQL/i )
{
#	&LogMsg( "Removing MySQL Tables..." );
#	@a = `\"$cmd\" -u $u --password=\"$p\" -f EQ_DB < unin_my.sql 2>&1`;
	&LogMsg( "Creating MySQL Tables..." );
	@a = `\"$cmd\" -u $u --password=\"$p\" -f EQ_DB < inst_my.sql 2>&1`;
}

elsif( $d =~ /SQLite/i )
{
	$s = "$xc_EQ_PATH/lib/SQLite." . "pl";
	require $s;
	my $dbfile = "$xc_EQ_PATH/EQ_DB";
	my $sqlfile = "$xc_EQ_PATH/install/" . $product_lc . "_sqlite.sql";
	$sqlfile = "$xc_EQ_PATH/install/inst_sqlite.sql" unless( -f "$sqlfile" );
	($err, $msg) = &CreateSQLiteDB( $dbfile, $sqlfile, 1, 1 );
	return( $err, $msg ) if( $err );
}

return( 0, "" );

}	# end of Install Create EQ DB Tables


#------------------------------------------------
#	Install Run DB2 Script
#------------------------------------------------
sub	Install_RunDB2Script
{
my	($file, $cmd, $user, $pwd, $host, $p_data) = @_;
my	(@a, $temp_file);

# Generate file with "connect to ..." statement and all table creation
# SQL statements.
# First, get data from user's SQL file
open (SQL_FILE, $file) || return "Error opening file '$file': $!";
@a = <SQL_FILE>;
close (SQL_FILE);

# Create temporary file with combined SQL code
$temp_file = "$xc_EQ_PATH/temp/install.DB2.$$.sql";
open (TEMP_FILE, ">$temp_file") || return "Error creating file '$temp_file': $!";
print TEMP_FILE "connect to $host user $user using $pwd;\n\n", join ("", @a), "\n";
close (TEMP_FILE);

if( $^O =~ /win/i )
{
	$temp_file =~ s#/#\\#g;
	$cmd =~ s#/#\\#g;
	$cmd = "\"$cmd\" -c -w -i db2 -f $temp_file -t -o";
}
else
{
	$cmd = "\"$cmd\" -f $temp_file -t -o";
}

&LogMsg( "Executing: '$cmd'" );
@$p_data = `$cmd 2>&1`;
&LogMsg( "Result: ", join ("", @$p_data) );
unlink ($temp_file);

return "";

}	# end of Install Run DB2 Script


#-----------------------------------------
#	Install Save Env
#-----------------------------------------
sub Install_SaveEnv
{
my( $s, $file, %hash, @arr, $i );

$file = $xc_EQ_PATH . "/cfg/env.cfg";

open (OUT_FILE, ">$file") || return( 1, "Cannot create file '$file': $!");
foreach $s( sort keys %ENV )
{
	print OUT_FILE "$s=$ENV{$s}\n";
}
close (OUT_FILE);

return( 0, "" );

}	# end of Install Save Env


#-----------------------------------------
#	Install Sched Tasks
#-----------------------------------------
sub Install_SchedTasks
{
my( $err, $msg, $cmd, $eqmsg, %tasks, $task, $p_hash, $key );

my %tasks =
{ 
	EQUpdateStatus	=>	{	T_SCHED_MINS	=>	"5",
							T_SCHED_OCCURS	=>	"Mins",
							T_SCHED_TIME	=>	"00:00:00",
						},

	EQCleanTemp		=>	{	T_SCHED_DAYS	=>	"Monday Tuesday Wednesday Thursday Friday Saturday Sunday",
							T_SCHED_OCCURS	=>	"Every",
							T_SCHED_TIME	=>	"00:35:00",
						},

	EQMaint			=>	{	T_SCHED_DAYS	=>	"Monday Tuesday Wednesday Thursday Friday Saturday Sunday",
							T_SCHED_OCCURS	=>	"Every",
							T_SCHED_TIME	=>	"02:35:00",
						}
};

foreach $task( keys %tasks )
{
	$eqmsg =	"T_MSG=Add;T_TRANS=User;T_PROFILE=$task;T_TARGETTYPE=Computer;T_TARGETS=$xc_HOSTNAME;" .
				"T_BATCHDELAY=0;T_BATCHMAX=1;T_CLASS=User;T_PRIORITY=5;T_SKIP=1;T_SCHED_AUDIT=1;" .
				"T_REASON=Initiated during installation;T_EQUSER=eqadmin;T_RECORD=1";

	$p_hash = $tasks{$task};
	foreach $key( keys %$p_hash )
	{
		$eqmsg .= ";$key=$p_hash->{$key}";
	}
	
	$cmd = "$xc_EQ_PATH/bin/EQMsg -p 2330 \"$eqmsg\"";
	$msg = `$cmd 2>&1`;
	$err = $?;
	return( $err, $msg ) if( $err );
}

return( 0, "" );
	
}	# end of Install Sched Tasks


#-----------------------------------------
#	Install Update Cron
#-----------------------------------------
sub Install_UpdateCron
{
my( $s, @a, $l_file, $l_lf, $err );

@a = `crontab -l 2>&1`;
@a = ( )	if	(($? != 0)||($a[0] =~ /^crontab: can't open/i));

$l_lf = 0;
foreach $s (@a)
{
	$s = ""
		if	($s =~ m#$xc_EQ_PATH/bin/cron/(clean_temp|eqmaint|update_status)#);
	$l_lf = ($s =~ /^\s+$/)? $l_lf + 1: 0;
	$s = ""	if	($l_lf > 1);
}
# Schedule EQ's scripts
push( @a,
	"35 0 * * * $xc_EQ_PATH/bin/cron/clean_temp.sh > $xc_EQ_PATH/temp/clean_temp.cron 2>&1",
#	"35 2 * * * $xc_EQ_PATH/bin/cron/eqmaint.sh > $xc_EQ_PATH/temp/eqmaint.cron 2>&1",
	"5 * * * * $xc_EQ_PATH/bin/cron/update_status.sh > $xc_EQ_PATH/temp/update_status.cron 2>&1",
	);

$l_file = $xc_EQ_PATH . "/temp/install.cron";
open (CRON_FILE, ">$l_file") || return( 1, "Cannot create file '$l_file': $!");
print CRON_FILE join ("\n", @a) . "\n";
close (CRON_FILE);

# Set new cron file
$s = `crontab $l_file 2>&1`;
$err = $?;
return( 1, "Cannot setup EQ cron jobs: $s" ) if( $err );
return( 0, "" );
	
}	# end of Install Update Cron


#---------------------------------------------------
#	Install Remove Cron Jobs
#---------------------------------------------------
sub Install_RemoveCronJobs
{
my	($s, @a, $l_lf, $l_changed);

@a = `crontab -l 2>&1`;
return	if	(($? != 0)||($a[0] =~ /^crontab: can't open/i));

if( $^O =~ /linux/i )
{
	@a = `crontab -r 2>&1`;
	return;
}

$l_lf = 0;
$l_changed = 0;
foreach $s (@a)
{
	if	($s =~ m#$xc_EQ_PATH/bin/cron/(clean_temp|eqmaint|update_status)#)
	{
		$s = "";
		$l_changed = 1;
	}
	$l_lf = ($s =~ /^\s+$/)? $l_lf + 1: 0;
	if	($l_lf > 1)
	{
		$s = "";
		$l_changed = 1;
	}
}

if	($l_changed != 0)
{
	$l_file = $xc_EQ_PATH . "/temp/install.cron";
	open (CRON_FILE, ">$l_file") ||
		&Install_Die ("Cannot create file '$l_file': $!");
	print CRON_FILE join ("", @a);
	close (CRON_FILE);

	# Set new cron file
	$s = `crontab $l_file 2>&1`;
	&Install_Die ("Cannot setup EQ cron jobs: $s")
		if	($? != 0);
}

}	# end of Install Remove Cron Jobs


#------------------------------------------------
#	Install Update AT
#------------------------------------------------
sub Install_UpdateAT
{
my( @update_sched ) = ( "00:35:00", "07:05:00", "08:05:00", "09:05:00",
				"10:05:00", "11:05:00", "12:05:00", "13:05:00",
				"14:05:00", "15:05:00", "16:05:00", "17:05:00" );
my	($s, @a, $l_sched, $l_eq, $time);

$l_eq = $xc_EQ_PATH;
$l_eq =~ s#/#\\#g;
# Check if Schedule is running
@a = `net start 2>&1`;
if	($? != 0)
{
	&LogMsg( "ERROR: Cannot execute 'net start' command: ", join ("", @a) );
	return;
}
$l_sched = "";
foreach $s (@a)
{
	if	($s =~ /^\s*(Schedule)\s*$/i)
	{
		$l_sched = $1;
		last;
	}
	elsif	($s =~ /^\s*(Task Scheduler)\s*$/i)
	{
		$l_sched = $1;
		last;
	}
}
# If Schedule is not running
if	($l_sched eq "")
{
	# Change scheduler to start automatically
	$s = `$xc_EQ_PATH/bin/eqsrv.exe auto Schedule 2>&1`;
	if	($? != 0)
	{
		&LogMsg( "ERROR: Cannot change 'Shedule' service: $s" );
		return;
	}
	$s = `$xc_EQ_PATH/bin/eqsrv.exe start Schedule 2>&1`;
	if	($? != 0)
	{
		&LogMsg( "ERROR: Cannot execute 'net start Schedule' command: $s" );
		return;
	}
}

@a = `at 2>&1`;
if	($? != 0)
{
	&LogMsg( "ERROR: Cannot execute 'at' command: ", join ("", @a) );
	return;
}

&Install_RemoveATJobs ();

# Schedule EQ's scripts
$s = `AT 00:15:00 /Every:M,T,W,Th,F,S,Su "$l_eq\\bin\\cron\\clean_temp.bat" 2>&1`;
#	$s = `AT 02:05:00 /Every:M,T,W,Th,F,S,Su "$l_eq\\bin\\cron\\eqmaint.bat" 2>&1`;
foreach $time( @update_sched ) 
{
	$s = `AT $time /Every:M,T,W,Th,F,S,Su "$l_eq\\bin\\cron\\update_status.bat" 2>&1`; 
}

}	# end of Install Update AT


#---------------------------------------------------
#	Install Remove AT Jobs
#---------------------------------------------------
sub Install_RemoveATJobs
{
my	($s, @a, $i);

@a = `at 2>&1`;
return	if	($? != 0);

# Check if some of scripts are already scheduled
foreach $s (@a)
{
	$s =~ s#\\#/#g;
	# If scheduled script is one of our scripts
	if	($s =~ m#^\s+(\d+).+\s+$xc_EQ_PATH/bin/cron/#i)
	{
		$i = $1;
		$s = `at $i /DELETE 2>&1`;
		if	($? != 0)
		{
			&LogMsg( "ERROR: Cannot execute 'at $i /DELETE' command: $s" );
		}
	}
}
	
}	# end of Install Remove AT Jobs


#-----------------------------------------
#	Install Show Menu
#-----------------------------------------
sub Install_ShowMenu
{
	my	($l_text, $s, $i, @a, %l_choices, $l_chars);
	my( $err, $msg );
	
#	open (LOG_FILE, ">-") || return( 1, "ERROR: Cannot open STDOUT: $!" );
	return( 1, "ERROR: Cannot open file '$xc_EQ_PATH/eq_install_log.txt': $!" )
		unless( open (LOG_FILE, ">>$xc_EQ_PATH/eq_install_log.txt") );

	&LogMsg( "Running EQ Installation Menu" );
	
	@a = sort keys %x_config_options;
	$i = 1;
	$l_chars = "CHAR Q";
	%l_choices = ();
	foreach $s (@a)
	{
		$l_choices{$i} = $s;
		$s = $i . ". " . $s;
		$l_chars .= $i;
		$i++;
		$i = "A"	if	($i > 9);
	}
	$s = join ("\n", @a);

	$l_text = <<EOF;
---------------- Select action ----------------

$s
Q. quit

-----------------------------------------------
EOF
	while (1)
	{
		$s = &Install_Ask ($l_text, $l_chars, undef );
		$s =~ tr/a-z/A-Z/;

		if	($s eq "Q")
		{
			($err, $msg) = &Install_SaveStatus ($x_install_data_file);
			return( $err, $msg );
		}
		else
		{
			$s = $l_choices{$s};
			if	(!defined ($x_config_options{$s}))
			{
				&LogMsg( "\nInternal error: cannot process '$s'" );
			}
			else
			{
				($err, $msg) = &{$x_config_options{$s}} ();
				return( $err, $msg ) if( $err );
			}
		}
	}

return( 0, "" );
	
}	# end of Install Show Menu


#-----------------------------------------
#	Install Update Config
#-----------------------------------------
sub Install_UpdateConfig
{
my( $err, $msg, $cmd, $s, @a );

# Check if hostname was changed
$cmd = "hostname";
$s = `$cmd 2>&1`;
if	($s !~ /^\s*$/)
{
	$xc_HOSTNAME = $s;
	$xc_HOSTNAME =~ s/\s+$//;
	$xc_HOSTNAME =~ tr/A-Z/a-z/;
}

# Save all variables into data array
@a = keys %x_vars;
foreach $s (@a)
{
	if	(defined (${$x_vars{$s}}))
	{
		$x_data{$s} = ${$x_vars{$s}};
	}
}

&LogMsg( "Updating configuration information..." );
($err, $msg) = &Install_UpdateFiles ($xc_EQ_PATH);
return( $err, $msg );
	
}	# end of Install Update Config


#-----------------------------------------
# Install Reschedule Tasks
#-----------------------------------------
sub Install_RescheduleTasks
{
my( $err, $msg );

&LogMsg( "Re-scheduling EQ tasks..." );
$err = 1;
while( $err )
{
	($err, $msg) = &Install_SchedTasks ();
	if( $err )
	{
		&LogMsg( $msg );
		$err = &AskEQCron( );
	}
}

}	# end of Install Reschedule Tasks


#---------------------------------------------------
#	Remove EQ Policy Code
#---------------------------------------------------
sub RemoveEQPolicyCode
{
my( $p_arr ) = @_;
my( $i, $j );

# Remove EQ code from there if necessary
for ($i = 0, $j = ""; $i < @a; $i++)
{
	# If we didn't find EQ custom code yet
	if	($j eq "") {
		$j = $i if( $a[$i] =~ /^#\[EQ CODE STARTS HERE\]\s*$/ );
	}

	elsif	($a[$i] =~ /^#\[EQ CODE ENDS HERE\]\s*$/) {
		splice (@a, $j, $i - $j + 1);
		$i = $j - 1;
		$j = "";
	}
}

}	# end of Remove EQ Policy Code


#---------------------------------------------------
#	Install Remove Cron Jobs
#---------------------------------------------------
sub InstallRemoveCronJobs
{
	my	($s, @a, $l_lf, $l_changed);

	@a = `crontab -l 2>&1`;
	return	if	(($? != 0)||($a[0] =~ /^crontab: can't open/i));

	$l_lf = 0;
	$l_changed = 0;
	foreach $s (@a)
	{
		if	($s =~ m#$xc_EQ_PATH/bin/cron/(clean_temp|eqmaint|update_status)#)
		{
			$s = "";
			$l_changed = 1;
		}
		$l_lf = ($s =~ /^\s+$/)? $l_lf + 1: 0;
		if	($l_lf > 1)
		{
			$s = "";
			$l_changed = 1;
		}
	}

	if	($l_changed != 0)
	{
		$l_file = $xc_EQ_PATH . "/temp/install.cron";
		open (CRON_FILE, ">$l_file") ||
			return( 1, "Cannot create file '$l_file': $!" );
		print CRON_FILE join ("", @a);
		close (CRON_FILE);

		# Set new cron file
		$s = `crontab $l_file 2>&1`;
		return( 1, "Cannot setup EQ cron jobs: $s") if	($? != 0);
	}

return( 0, "" );

}	# end of Install Remove Cron Jobs


####################  D B   R O U T I N E S   ########################


#---------------------------------------
#	Install Handle DB
#---------------------------------------
sub Install_HandleDB
{
my( $err, $msg );

#&AskDB( );
$xc_DB_VENDOR = "SQLite";

if ($xc_DB_VENDOR =~ /ORACLE/i )
{
	($err, $msg) = &CheckOracle( );
	return( 1, $msg ) if( $err );
	
	($err, $msg) = &AskDBinfo( );
	return( 1, $msg ) if( $err );
	
	&VerifyPath( $xc_DB_BINDIR );
}
	
elsif ($xc_DB_VENDOR =~ /DB2/i )
{
	($err, $msg) = &CheckDB2( );
	return( 1, $msg ) if( $err );
	
	($err, $msg) = &AskDBinfo( );
	return( 1, $msg ) if( $err );
	
	&VerifyPath( $xc_DB_BINDIR );
}
	
elsif ($xc_DB_VENDOR =~ /MYSQL/i )
{
	($err, $msg) = &CheckMySQL ();
	return( 1, $msg ) if( $err );
	
	($err, $msg) = &AskDBinfo( );
	return( 1, $msg ) if( $err );
		
	&VerifyPath( $xc_DB_BINDIR );

	($err, $msg) = &CompleteMySQLInstall( );
	return( 1, $msg ) if( $err );
}
	
elsif( $xc_DB_VENDOR =~ /SQLITE/i )
{
	$xc_DB_BINDIR = "";
	$xc_DB_USERNAME = "";
	$xc_DB_HOST = "";
	$xc_DB_COMMAND = "";
	$err = 0;
}

else
{
	$xc_DB_VENDOR   = "NONE";
	$xc_DB_BINDIR   = "";
	$xc_DB_USERNAME = "";
	$xc_DB_PASSWORD = "";
	$xc_DB_HOST     = "";
	$xc_DB_COMMAND  = "";
	$err = 0;
}

# Create EQ Tables
unless( $xc_DB_VENDOR =~ /NONE/i )
{
	$msg = "Create DB tables? (Y/N)\n(Enter 'N' if tables exist)";
	$s = &Install_Ask( $msg, "CHAR YN", "Y" );
	($err, $msg) = &Install_CreateEQDBTables( ) if( $s =~ /Y/i );
	return( 1, $msg ) if( $err );
}

return( 0, "" );

}	# end of Install Handle DB


#----------------------------------------------#
#	Ask DB
#----------------------------------------------#
sub AskDB
{
my	($l_mysql, $frm1, $prompt, $choice );

$xc_DB_VENDOR = "Oracle"	if	($xc_DB_VENDOR eq "ORACLE");

if( $^O =~ /win/i )
{
	$prompt = "Database vendor ('DB2', 'Oracle', 'MYSQL', 'SQLite' (included), or 'None') ";
	$choice = "CHOICE DB2,ORACLE,MYSQL,SQLITE,NONE";
}
else
{
	$prompt = "Database vendor ('DB2', 'Oracle', 'SQLite' (included), or 'None') ";
	$choice = "CHOICE DB2,ORACLE,SQLITE,NONE";
}

$xc_DB_VENDOR = &Install_Ask ( $prompt, $choice, $xc_DB_VENDOR );

$xc_DB_VENDOR = "DB2"		if	($xc_DB_VENDOR =~ /DB2/i);
$xc_DB_VENDOR = "MYSQL"		if	($xc_DB_VENDOR =~ /MySQL/i);
$xc_DB_VENDOR = "ORACLE"	if	($xc_DB_VENDOR =~ /Oracle/i);
$xc_DB_VENDOR = "SQLite"	if	($xc_DB_VENDOR =~ /SQLite/i);
$xc_DB_VENDOR = "NONE"		if	($xc_DB_VENDOR =~ /None/i);

}	# end of Ask DB


#---------------------------------------
#	Validate MySQL Info
#---------------------------------------
sub ValidateMySQLInfo
{
my( $c, $u, $p ) = @_;
my( @a, $cmd, $err, $msg );

$c =~ s#/#\\#g if( $^O =~ /win/i );
$cmd = "\"$c\" -u $u --password=\"$p\"";
@a = `echo quit | $cmd 2>&1`;
$err = $?;
return( "" ) if( !$err );

$msg = "Error connecting to MySQL Server using $cmd: $a[0]\n";
return( $msg );

}	# end of Validate MySQL Info


#---------------------------------------
#	Validate Oracle Info
#---------------------------------------
sub ValidateOracleInfo
{
my( $dir, $cmd, $user, $pass, $host) = @_;
my( $s, @a, $failed, $version, $home);

# Verify connection to Oracle database
$s = $pass;
$s .= "\@$host" if( defined($host) && $host ne "" );

$failed = 1;
$cmd = "$dir/$cmd";
$cmd =~ s#/#\\#g if( $^O =~ /win/i );
@a = `echo quit | \"$cmd\" $user/$s \@conn_ora.sql 2>&1`;
foreach $s (@a)
{
	$failed = 0		if	($s =~ /^EQ: database connection OK/i);
}

# If we didn't receive what we expected
return "Error connecting to Oracle DB using supplied elements:\n" .
	join ("   ", @a) . "\n"	if	($failed); 

return "" unless( $xc_OS =~ /solaris/i );

# Get Oracle version
$version = "";
$home = $dir;
$home =~ s#/[^/]+$##;
if	(open (RGS_FILE, "$home/install/unix.rgs"))
{
	while ($s = <RGS_FILE>)
	{
		if	($s =~ /^rdbms\s+(\d+)/)
		{
			$version = $1;
			last;
		}
	}
	close (RGS_FILE);
}
elsif	($home =~ /.*(\d+)\.\d+\.\d+/)
{
	$version = $1;
}

if	($version eq "")
{
	&LogMsg( "WARNING: Cannot determine Oracle version. Assuming Oracle 8" );
	$version = 8;
}

# Rename shared library file
copy( "$xc_EQ_PATH/lib/Solaris-Oracle$version.so", "$xc_EQ_PATH/lib/Oracle.so" ) || return( $! );

# Determine if 64-bit version of Oracle is installed
if	(-f "$home/lib32/libclntsh.so")
{
	# Set new LD_LIBRARY_PATH environment variable
	if	($ENV{LD_LIBRARY_PATH})
	{
		@a = split (":", $ENV{LD_LIBRARY_PATH});
		foreach $s (@a)
		{
			$s = "$home/lib32"	if	($s eq "$home/lib");
		}
		$x_ld_library_path = join (":", @a);
	}
	# Set new LIBPATH environment variable
	if	($ENV{LIBPATH})
	{
		@a = split (":", $ENV{LIBPATH});
		foreach $s (@a)
		{
			$s = "$home/lib32"	if	($s eq "$home/lib");
		}
		$x_libpath = join (":", @a);
	}
}

return "";

}	# end of Validate Oracle Info


#---------------------------------------
#	Validate DB2 Info
#---------------------------------------
sub ValidateDB2Info
{
my( $cmd, $user, $pwd, $host ) = @_;
my( $s, @a, $success, $error );

# Verify connection to DB2 database
$s = &Install_RunDB2Script( "$xc_EQ_PATH/install/conn_db2.sql", $cmd, $user, $pwd, $host, \@a );

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
return "" if( $success && !$error );

$msg = "Error connecting to DB2 database using supplied elements:\n" . join ("   ", @a) . "\n"; 

return $msg;

}	# end of Validate DB2 Info


#----------------------------------------------#
#	Ask DB Info
#----------------------------------------------#
sub AskDBinfo 
{
my( $label, $pwd, $s, $maxtries );
my( %db_host_name ) =
(
	"ORACLE"	=>	"Oracle SID",
	"DB2"		=>	"DB2 database name",
	"MYSQL"		=>	"MySQL hostname",
);

$maxtries = 5;
$label = $xc_DB_VENDOR;
$label =~ tr/a-z/A-Z/;
while( $maxtries )
{
	print "Please enter $xc_DB_VENDOR database parameters:\n";

	$xc_DB_BINDIR = &Install_Ask( "Database binaries directory", "PATH DIR", $xc_DB_BINDIR );
	$xc_DB_USERNAME = &Install_Ask( "Database user name", "STRING 1,100 [^;]+", $xc_DB_USERNAME );

	# Get user's password
	while (1)
	{
		$xc_DB_PASSWORD = &Install_Ask( "Database password", "STRING 0,100 [^;]*", $xc_DB_PASSWORD );
		$pwd = &Install_Ask ("Confirm database password", "STRING 0,100 [^;]*", undef );
		last	if	($xc_DB_PASSWORD eq $pwd);
		print "*** Database passwords do not match ***\n";
	}

	$xc_DB_HOST = &Install_Ask( $db_host_name{$label}, "STRING 0,100 [^;]*", $xc_DB_HOST );

	if ($label eq "MYSQL")
	{ 
		$xc_DB_COMMAND = "mysql" unless( -f "$xc_DB_BINDIR/$xc_DB_COMMAND" ); 
		$s = &ValidateMySQLInfo( "$xc_DB_BINDIR/$xc_DB_COMMAND", $xc_DB_USERNAME, $xc_DB_PASSWORD );
	}
	elsif ($label eq "DB2")
	{
		$xc_DB_COMMAND = "db2" unless( -f "$xc_DB_BINDIR/$xc_DB_COMMAND" );
		$s = &ValidateDB2Info( "$xc_DB_BINDIR/$xc_DB_COMMAND", $xc_DB_USERNAME, $xc_DB_PASSWORD, $xc_DB_HOST ) 
	}
	elsif ($label eq "ORACLE")
	{
		$xc_DB_COMMAND = "sqlplus" unless( -f "$xc_DB_BINDIR/$xc_DB_COMMAND" );
		$s = &ValidateOracleInfo( $xc_DB_BINDIR, $xc_DB_COMMAND, $xc_DB_USERNAME, $xc_DB_PASSWORD, $xc_DB_HOST ) 
	}
	else 
	{
		return( 1, "Database vendor '$xc_DB_VENDOR' is not supported. Must be 'ORACLE', DB2, or 'MYSQL'" );
	}

	# return success if no error message returned
	return( 0, "" ) if( $s eq "" );
	
	$s =~ s/\s+$//;
	print "*** $s ***\n";
	$maxtries -= 1;
}

return( 1, "Exceeded maximum DB connection attempts" );

}	# end of Ask DB info


#------------------------------------------------
#	Complete MySQL Install
#------------------------------------------------
sub CompleteMySQLInstall
{
my( $line, $answer, @arr, $err, $msg );

$line = `net start`;
$line =~ s/\n/ /g;

if ($line =~ /MySQL/i )
{
	$msg = "Remove current installation of MySQL\nand then re-install?";
	$answer = &Install_Ask( $msg, "CHAR YN", "N" );
	return( 0, "" ) if( $answer =~ /N/i );

	($err, $msg ) = &UninstallMySQL( );
	return( 1, $msg ) if( $err );
}

($err, $msg) = &InstallMySQL( );
return( $err, $msg );

}	# end of Complete MySQL Install


#------------------------------------------------
#	Uninstall MySQL
#------------------------------------------------
sub UninstallMySQL
{
my	($file, @arr, $db_dir);

$db_dir = $xc_DB_BINDIR;

&LogMsg( "Uninstalling MySQL..." );
&LogMsg( "Dropping EQ_DB" );
@arr = `$db_dir/mysqladmin.exe -f drop EQ_DB 2>&1`;
sleep( 2 );

&LogMsg( "Deleting EQUser" );
$file = "$xc_EQ_PATH/temp/temp$$.tmp";
open( TFH, ">$file" ) || return( 1, "Cannot create file '$file': $!");
print TFH "delete from user where user='$xc_DB_USERNAME'";
close( TFH );

$file =~ s#/#\\#g;
@arr = `$db_dir/mysql mysql < $file`;
unlink($file);
sleep( 2 );

&LogMsg( "Stopping MySQL Service" );
@arr = `$xc_EQ_PATH/bin/eqsrv.exe stop MySQL 2>&1`;
sleep( 2 );

&LogMsg( "Removing MySQL Service" );
@arr = `$xc_EQ_PATH/bin/eqsrv.exe remove MySQL 2>&1`;
sleep( 2 );

return( 0, "" );

}	# end of Uninstall MySQL


#------------------------------------------------
#	Install MySQL
#------------------------------------------------
sub InstallMySQL
{
my( @arr, $file, $db_dir);

$db_dir = $xc_DB_BINDIR;

&LogMsg( "Install MySQL as Service: $db_dir/mysqld.exe --install" );
@arr = `$db_dir/mysqld.exe --install 2>&1`;
return( 1, "Error installing MySQL Service " . join( "", @arr ) . "\n" ) if( $? );

&LogMsg( "Start MySQL Server: $xc_EQ_PATH/bin/eqsrv.exe start MySQL" );
sleep( 2 );
@arr = `$xc_EQ_PATH/bin/eqsrv.exe start MySQL 2>&1`;
return( 1, "Error Starting MySQL Service " . join( "", @arr ) . "\n" ) if( $? );

&LogMsg( "Create EQ_DB database: $db_dir/mysqladmin.exe -f create EQ_DB" );
sleep( 2 );
@arr = `$db_dir/mysqladmin.exe -f create EQ_DB 2>&1`;
return( 1, "Error Creating EQ_DB " . join( "", @arr ) . "\n" ) if( $? );

&LogMsg( "Reload MySQL: $db_dir/mysqladmin.exe -f reload" );
sleep( 2 );
@arr = `$db_dir/mysqladmin.exe -f reload 2>&1`;
return( 1, "Error Reloading MySQL " . join( "", @arr ) . "\n" ) if( $? );

&LogMsg( "Create EQUser" );
sleep( 2 );

$file = "$xc_EQ_PATH/temp/temp$$.tmp";
open( TFH, ">$file" ) || return( 1, "Cannot create file '$file': $!");
print TFH "insert into user values('%','equser','',";
print TFH "'Y','Y','Y','Y','Y','Y','Y','Y','Y','Y','Y','Y','Y','Y')";
close( TFH );

$file =~ s#/#\\#g;
@arr = `$db_dir/mysql mysql < $file`;
return( 1, "Error Creating EQUser " . join( "", @arr ) . "\n" ) if( $? );
unlink( $file );

&LogMsg( "Reload MySQL: $db_dir/mysqladmin.exe -f reload" );
sleep( 2 );
@arr = `$db_dir/mysqladmin.exe -f reload 2>&1`;
return( 1, "Error Reloading MySQL " . join( "", @arr ) . "\n" ) if( $? );

return( 0, "MySQL Successfully installed\n" );

}	# end of Install MySQL


#------------------------------------#
# Ask to create EQ cron jobs         #
#------------------------------------#
sub AskEQCron
{
my( $s );

$s = &Install_Ask ("Schedule EQ cron jobs (Y/N)?", "CHAR YN", "N" );
if	($s =~ /y/i)
{
	$s = 1;
}
else
{
	$s = 0;
}

return( $s );

}	# end of Ask EQ Cron


#------------------------------------------------
#	Get Reg
#------------------------------------------------
sub GetReg
{
my( $key, $p_value ) = @_;
my( $cmd, $err );

$cmd = "$xc_EQ_PATH/bin/EQReg -gv \"$key\"";

$$p_value = `$cmd 2>&1`;
$err = $?;
return( 1, "Error running '$cmd': $$p_value\n" ) if( $err );

$$p_value =~ s/^SUCCESS:\s*|\s+$//gi;
return( 0, "" );

}	# end of Get Reg


#------------------------------------------------
#	Set Reg
#------------------------------------------------
sub SetReg
{
my( $key, $value ) = @_;
my( $cmd, $err, $msg );

# remove all double-quotes
$value =~ s/\"//g;
$cmd = "$xc_EQ_PATH/bin/EQReg -sv \"$key\" \"$value\"";

$msg = `$cmd 2>&1`;
$err = $?;
return( 1, "Error running '$cmd': $msg\n" ) if( $err );

return( 0, "$key set to $value: $msg" );

}	# end of Set Reg

