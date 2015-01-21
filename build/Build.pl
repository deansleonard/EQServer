#!C:/dean/EQ-Working/EQServer/perl5/bin/perl
# Build EQ installation version
#
# $Id$
# Copyright (C) 2000-2013  Capital Software Corporation
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License (AGPL) as 
# published by the Free Software Foundation, either version 3 of the 
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along 
# with this program in the file named COPYING.  If not, please see 
# <http://www.gnu.org/licenses/agpl.html>
#
# Current working dir is in build subdir, so set G_TopDir accordingly
use Cwd;
my $G_CurDir = getcwd( );
my $G_TopDir = $G_CurDir;
$G_TopDir =~ s#\\+#/#g;
$G_TopDir =~ s#\/build$##;

# Configurables Parameters
%G_Config = 
(	ARCHCMD			=> $ENV{ARCHCMD},
#	BUILD_BASE		=> "$G_TopDir/../EQBuild",
	BUILD_BASE		=> $ENV{BUILD_BASE},
	BUILD_FLAG		=> 1,
	CFGFILE			=> $ENV{CFGFILE},
	COMPILER		=> $ENV{COMPILER},
	DATFILE			=> $ENV{DATFILE},
	DO_NOT_REMOVE_PL => $ENV{DO_NOT_REMOVE_PL} || 0,
	DO_NOT_COPY_TAR => $ENV{DO_NOT_COPY_TAR} || 0,
	ICON			=> $ENV{ICON} || "",
	ORIGIN			=> $G_TopDir,
	EQPERL_REPOSITORY		=> $ENV{EQPERL_REPOSITORY} || "",
	PERLBIN			=> $ENV{PERLBIN},
	PERLLIB			=> $ENV{PERLLIB},
	PERL5LIB		=> $ENV{PERL5LIB},
	PERLSITELIB		=> $ENV{PERLSITELIB},
	PERL2EXE_PATH	=> $ENV{PERL2EXE_PATH},
	PERL2EXE_CMD	=> $ENV{PERL2EXE_CMD},
	PPOPTIONS		=> $ENV{PPOPTIONS},
	PROCESSORS		=> $ENV{PROCESSORS} || 1,
	PRODUCT			=> $ENV{PRODUCT},
	REGFILE			=> "",
	TEMPLATE		=> $ENV{TEMPLATE},
	EQTEMPDIR		=> $ENV{EQTEMPDIR} || "",
	VERBOSE			=> 0,
	VERSION			=> $ENV{VERSION},
	PATCH			=> "",
);

# Determine OS
if	($^O =~ /MSWin/i)
{
	$x_os_type = $x_os = "WIN";
}
else
{
	$x_os_type = "UNIX";
	$x_os = "\U$^O";
}

# Read parms from config file, if provided, and command line arguments, if provided
&GetParms( \%G_Config );

my $product = $G_Config{PRODUCT};

# Set EQTEMPDIR and make it if it doesn't exist
#if( defined($ENV{EQTEMPDIR}) ) { $G_Config{EQTEMPDIR} = $ENV{EQTEMPDIR}; }
#elsif( defined($G_Config{TEMP}) ) { $G_Config{EQTEMPDIR} = "$G_Config{TEMP}/$product"; }
#elsif( defined($G_Config{TMP}) ) { $G_Config{EQTEMPDIR} = "$G_Config{TMP}/$product"; }
#elsif( $^O =~ /win/i ) { $G_Config{EQTEMPDIR} = "C:/temp/$product"; }
#else { $G_Config{EQTEMPDIR} = "/tmp/$product"; }
#mkdir( "$G_Config{EQTEMPDIR}", 0755 ) unless( -d "$G_Config{EQTEMPDIR}" );

# System specific variables
$x_comp2exe_shell  = "$G_CurDir/comp2exe";
$x_comp2exe_shell .= $x_os =~ /WIN/ ? ".bat" : ".sh";
$x_comp2exe_log    = "$G_CurDir/comp2exe.out";

# set path variable and change forward-slashes to backslashes
$x_path = "$G_Config{PERL2EXE_PATH};$G_Config{PERLBIN};$G_Config{PERLLIB};$G_Config{PERLSITELIB};$ENV{PATH};.";
if( $x_os eq "WIN" )
{
	$x_path = "\%windir\%/system32;\%windir\%;" . $x_path;
}
else
{
	$x_path =~ s/;/:/g;
}

$x_path = &OSDir( $x_path );

# Handle build inclusion/exclusion of perl5.tar
$perl5   = "$G_Config{ORIGIN}/perl5.tar";
$perl5   =~  s/\\+/\//g;

# Don't include perl5.tar if DO_NOT_COPY_TAR flag set
if( $G_Config{DO_NOT_COPY_TAR} )
{
	unlink( $perl5 ) if( -f $perl5 );
}
elsif( -f "$perl5" )
{
	$perltar = $perl5;
}
else
{
	# See if OS-based perl tar file exists.  This may be the case if CVS contains the latest version
	# for each OS platform.  We don't like to do this for space considerations
	if(	-f "./perl5-" . $^O . ".tar" ) 
	{
		$perltar = "./perl5-" . $^O . ".tar";
	}
	
	# if EQPERL_REPOSITORY is null string or directory doesn't exists, assume perl5.tar exists locally.
	# This is useful if CVS doesn't contain the perl5 archives, and the users doesn't want a separate
	# EQPERL_REPOSITORY repository (see below).  Just need to copy the right version of perl5 from our website
	# to your build directory and name it 'perl5.tar'.
	elsif( $G_Config{EQPERL_REPOSITORY} eq "" || ! -d $G_Config{EQPERL_REPOSITORY} )
	{
		$perltar = $perl5;
	}
	# Otherwise, use EQPERL_REPOSITORY to get the correct version of perl archive which is what we use in-house.
	# Notes about EQPERL_REPOSITORY:
	#	- Path where all the different versions of perl5 archives exist. Example: /opt/eqperl.archives
	#	- Purpose is to eliminate the need to keep all the different versions in CVS
	#	- Subdirectories should include at least your platforms version: AIX, LINUX, SOLARIS, or WIN
	#	- Perl archive naming format: perl-<version>.tar where <version> is the perl variable $]
	#	- Example perl5 archive fully qualified filename: /opt/eqperl.archives/LINUX/perl-5.010001.tar  
	else
	{
		$perltar = "$G_Config{EQPERL_REPOSITORY}/$x_os/perl-" . $] . ".tar";
	}
	
	# Make sure perltar exists
	$perltar =~  s/\\+/\//g;
	die "File not found: '$perltar'" unless( -f $perltar );
	
	# See if it's the same file
	if( $perl5 eq $perltar )
	{
		print "Using '$perl5'.\n";
	}
	# See if perl5.tar exists and same size as source
	elsif( -f $perl5 && -s $perltar == -s $perl5 )
	{
		print "Files named '$perltar' and '$perl5' are the same size. Probably the same file.\n";
	}
	# Otherwise, copy of the correct version
	else
	{
		print "'$perl5' file does not exist or not the right version for this OS\n";
		$cmd = "cp -f $perltar $perl5";
		print "Running '$cmd'\n";
		$msg = `$cmd 2>&1`;
		$err = $?;
		die "Error running '$cmd': $msg" if( $err );
	}
}

@x_check_perl_syntax = ();
@x_compile_files = ();
%x_create_dirs = ();
%x_copy_files = ();
%x_temp_files = ();

# Set PERL5LIB if configured
$ENV{PERL5LIB} = $G_Config{PERL5LIB} if( defined($G_Config{PERL5LIB}) );

### END OF BUILD CONFIGURATION PARAMETERS

# Generate date stamp for build info
@datearr = localtime( time );
$x_date  = sprintf( "%d%02d%02d", $datearr[5]+1900, $datearr[4]+1, $datearr[3] );

$operating_system = "unk";
if( $^O =~ /aix/i ) { $operating_system = "aix"; }
elsif( $^O =~ /sol/i ) { $operating_system = "sol"; }
elsif( $^O =~ /linux/i ) { $operating_system = "linux"; }
elsif( $^O =~ /win/i ) { $operating_system = "win"; }

$G_BuildName  = ($G_Config{PRODUCT} =~ /enterprise\-Q/i)? "eq-":
	(($G_Config{PRODUCT} =~ /EQAgent/i)? 'EQA-': $G_Config{PRODUCT} . "-");
$G_BuildName .= "$G_Config{VERSION}-";
$G_BuildName .= "$G_Config{PATCH}-" unless( $G_Config{PATCH} eq "" );
$G_BuildName .= "$operating_system-";
$G_BuildName .= "$x_date";

# Append Build Name to base directory
$x_base  = "$G_Config{BUILD_BASE}/$G_BuildName/";

#----------------------------------------

# Read definitions to memory
open (DAT_FILE, $G_Config{DATFILE}) || die ("Cannot open dat file '$G_Config{DATFILE}': $!\n");
@x_files = <DAT_FILE>;
close (DAT_FILE);

# Process list of files
foreach $x_line (@x_files)
{
	# Skip empty lines and comments
	$x_line =~ s/^\s+|\s+$//g;
	next if( $x_line eq ""  || $x_line =~ /^#/ );
	
	# See if we need to include another set of files from another DAT file
	if( $x_line =~ /^\%INCLUDE\%\s+(.+)$/ )
	{
		my $file = $1;
		open( DAT_FILE, "$file" ) || die( "Cannot open dat file '$file': $!\n" );
		my @a;
		@a = <DAT_FILE>;
		push( @x_files, @a );
		close (DAT_FILE);
	}
	else
	{
		&VariableSubstitution( \$x_line );
		&Build_ProcessLine ($x_line);
	}
}

# Run syntax check on all perl scripts
$err = 0;
$outfile = "./eqperlcheck.out";
open( PERLCHK, ">$outfile" );
$cmd = "$G_Config{PERLBIN}/perl -V";
print PERLCHK "Running '$cmd'\n";
$msg = `$cmd 2>&1`;
print PERLCHK "Results:\n$msg\n";

foreach $file( @x_check_perl_syntax )
{
	$cmd = "$G_Config{PERLBIN}/perl -c $file";
	print PERLCHK "$cmd\n";
	$msg = `$cmd 2>&1`;
	$err = $?;
	next unless( $err );
	$cmd =~ s#/#\\#g if( $^O =~ /win/i );
	$msg = "Syntax Error $err - $msg:\n$cmd\n";
	print $msg
	print PERLCHK $msg;
}
close( PERLCHK );

if( $err )
{
	print "Fix all syntax errors before proceeding. Check $outfile for details.\n";
	exit( 1 );
}

if	(@x_compile_files != 0)
{
	if	($x_processors > 1)
	{
		# Split data array into multiple arrays
		@{$compile_data[0 .. $x_processors - 1]} = ();
		$i = 0;
		foreach $s (@x_compile_files)
		{
			if	($s eq "#")
			{
				$i++;
				$i = 0	if	($i >= $x_processors);
				push (@{$compile_data[$i]}, "");
			}
			else
			{
				push (@{$compile_data[$i]}, $s);
			}
		}

		# Main file calls all other shell files in background
		open (MAIN_FILE, ">$x_comp2exe_shell") ||
			die ("Cannot create temp file '$x_comp2exe_shell': $!\n");
		print MAIN_FILE "#!/bin/sh\ncd $G_Config{ORIGIN}\n";

		# Write data to batch/shell files
		for ($i = 0; $i < $x_processors; $i++)
		{
			open (BAT_FILE, ">$G_Config{ORIGIN}/comp2exe_$i.sh") ||
				die ("Cannot create temp file '$G_Config{ORIGIN}/comp2exe_$i.sh': $!\n");
			if	($x_os eq "WIN")
			{
				print BAT_FILE "set PATH=$x_path\n";
			}
			else
			{
				print BAT_FILE "#!/bin/sh\n";
				print BAT_FILE "PATH=$x_path\n";
				print BAT_FILE "export PATH\n";
			}
			print BAT_FILE join ("\n", @{$compile_data[$i]}), "\n";
			print BAT_FILE "\nrm $G_Config{ORIGIN}/proc_$i.finished\n";
			close (BAT_FILE);
			`chmod +x $G_Config{ORIGIN}/comp2exe_$i.sh 2>&1`;

			print MAIN_FILE "touch $G_Config{ORIGIN}/proc_$i.finished\n";
			print MAIN_FILE "$G_Config{ORIGIN}/comp2exe_$i.sh & 2>&1\n";
		}

		close (MAIN_FILE);
	}
	else
	{
		print "Creating '$x_comp2exe_shell'\n";
		open (BAT_FILE, ">$x_comp2exe_shell") ||
			die ("Cannot create file '$x_comp2exe_shell': $!\n");
		if	($x_os eq "WIN")
		{
			print BAT_FILE "set PATH=$x_path\n";
		}
		else
		{
			print BAT_FILE "#!/bin/sh\n";
			print BAT_FILE "PATH=$x_path\n";
			print BAT_FILE "export PATH\n";
		}
		print BAT_FILE "echo Start Build > $x_comp2exe_log\n";
		print BAT_FILE join ("\n", @x_compile_files), "\n";
		close (BAT_FILE);
	}

	$msg = localtime( time() );
	print "$msg\n";
	print "Please wait while perl scripts are compiled using '$x_comp2exe_shell' script\n";
	print "Check '$x_comp2exe_log' for details\n";
	`chmod +x $x_comp2exe_shell 2>&1` if( $x_os ne "WIN" );
	#`$x_comp2exe_shell > $x_comp2exe_log 2>&1`;
	$cmd = $x_comp2exe_shell;
	$msg = `$x_comp2exe_shell 2>&1`;
	$err = $?;
	if( $err )
	{
		print "Error running '$cmd':\n";
		print "$msg";
		exit( 1 );
	}
	
	if	($x_processors > 1)
	{
		# Check and see if all shell scripts are completed
		while (1)
		{
			sleep (1);
			for ($i = 0; $i < $x_processors; $i++)
			{
				last	if	(-f "$G_Config{ORIGIN}/proc_$i.finished");
			}
			last	if	($i >= $x_processors);
		}
	}
	print "Please, check file $x_comp2exe_log file for possible error message\n";
	$msg = localtime( time() );
	print "$msg\n";
}

#unlink ($x_comp2exe_shell);

# EQfiles must exist before generating iss file
mkdir( "$x_base/install", 0755 ) 
	unless( -d "$x_base/install" );

if( $G_Config{PATCH} eq "" )
{
	$eqfiles_name = $x_base . "install/EQfiles.dat";
}
else
{
	$eqfiles_name = $x_base . "install/EQfiles-$G_Config{VERSION}-$G_Config{PATCH}.dat";
}

$eqfiles_name = &OSDir( $eqfiles_name );

&CreateEQfiles( $eqfiles_name );
@x_lib_files = ();

# If we are on Windows, process/generate .iss file
if	($x_os eq "WIN")
{
	($err, $msg) = &ProcessISSTemplate( $x_base, \%x_create_dirs, \%x_copy_files, \@x_lib_files );
	print "$msg\n" if( $err );
}

&UpdateEQfiles( $eqfiles_name );

#if	($x_os ne "WIN")
#{
	&BuildCreateDirs( $x_base );
#}

# Perform Variable Substitution on upgrade script
($err, $msg) = &ProcessUPGScript( );
print "ProcessUPGScript: ERR: $err  MSG: '$msg'\n" if( $err );

# Delete temporary files
foreach $file (keys %x_temp_files)
{
	print "Removing TEMP file: $file\n";
	unlink ($file) ||
		warn ("*** Cannot remove file '$file': $!\n");
}

if	($G_Config{BUILD_FLAG})
{
#	if	($x_os eq "WIN")
#	{
#		$cmd = "\"$G_Config{COMPILER}\" /cc $G_Config{VERSION}.iss";
#		print "Generating setup.exe using cmd: '$cmd'\n";
#		@arr = `$cmd 2>&1`;
#		if( $? ) { print "Error: ", join ("", @arr), "\n"; }
#		else { print "Success generating setup.exe\n"; }
#	}
#	else
#	{
		# Generate tar file
		if( defined($G_Config{ARCHCMD}) && $G_Config{ARCHCMD} ne "" )
		{
			$archcmd = $G_Config{ARCHCMD};
		}
		elsif( $x_os eq "WIN" )
		{
#			$archcmd = "$G_TopDir/bin/tar.exe cvf ARCHFILE.tar -C SRCDIR .";
			$archcmd = "PERLBIN ./eqzip.pl -cvf ARCHFILE.zip -C SRCDIR .";
		}
		else
		{
			$archcmd = "tar cvf ARCHFILE.tar -C SRCDIR .";
		}
		
		$archcmd =~ s#PERLBIN#$G_Config{PERLBIN}/perl#g;
		$archcmd =~ s#ARCHFILE#$G_CurDir/$G_BuildName#g;
		$archcmd =~ s/SRCDIR/$x_base/g;
		$archcmd =~ s/ISSFILE/$G_Config{ISSFILE}/g;
		
		print "Creating archive using '$archcmd'...\n";
		$results = `$archcmd 2>&1`;
		$err = $?;
		if( $err ) { print "$results\n"; }
		else 
		{
			my $archive = "$G_CurDir/$G_BuildName";
			if( $^O =~ /win/i )
			{
				$archive .= ".zip";
				$archive =~ s#/#\\#g;
			}
			else
			{
				$archive .= ".tar";
			}	
			print "\n\nArchive file successfully created.  Please find it here:\n\n\t$archive\n\n";
		}
#	}
}

# Delete the iss file
#unlink( "$G_Config{VERSION}.iss" );

exit( 0 );



#-------------------------------------------------
#	Build Create Dirs
#-------------------------------------------------
sub BuildCreateDirs
{
my( $x_base ) = @_;

# print "Creating directories...\n";
if	($G_Config{PRODUCT} =~ /EQAgent/i)
{
	mkdir ("$x_base/data", 0750);
	mkdir ("$x_base/logs", 0750);
	mkdir ("$x_base/temp", 0750);
	mkdir ("$x_base/upgrade", 0750);
	mkdir ("$x_base/upgrade/incoming", 0750);
}
else
{
	#mkdir ("$x_base/cfg/AutoI", 0750);
	#mkdir ("$x_base/cfg/menu_history", 0750);
	#mkdir ("$x_base/cfg/users", 0750);
	#mkdir ("$x_base/data", 0750);
	#mkdir ("$x_base/data/ip", 0750);
	#mkdir ("$x_base/data/renamed", 0750);
	#mkdir ("$x_base/data/sid", 0750);
	#mkdir ("$x_base/data/users", 0750);
	mkdir ("$x_base/logs", 0750);
	#mkdir ("$x_base/logs/spmon", 0750);
	#mkdir ("$x_base/logs/icmon", 0750);
	mkdir ("$x_base/qstore", 0750);
	mkdir ("$x_base/qstore/status", 0750);
	mkdir ("$x_base/temp", 0750);
}

}	# end of Build Create Dirs


#-------------------------------------------------
#	Process ISS Template
#-------------------------------------------------
sub ProcessISSTemplate
{
my( $x_base, $p_create_dirs, $p_copy_files, $p_lib_files ) = @_;
my( @x_iss, $i, @a, $s, $s1, $s2, $dir, $file, $lib_dir );

return( 0, "" ) unless( -f "$G_Config{TEMPLATE}" );

# Load template
open (TPL_FILE, $G_Config{TEMPLATE}) || return( 1, "Cannot open template file '$G_Config{TEMPLATE}': $!\n" );
@x_iss = <TPL_FILE>;
close (TPL_FILE);

# Process template file
for ($i = 0; $i < @x_iss; $i++)
{
	$s = $x_iss[$i];
	# If we need to include list of directories to create
	if	($s =~ /^\%DIRS\%\s*$/i)
	{
		# Get list of directories
		@a = sort keys %$p_create_dirs;
		foreach $dir (@a)
		{
			$s1 = $p_create_dirs->{$dir};
			$dir = "Name: {app}\\$s1; Flags:  uninsalwaysuninstall\n";
		}
		splice (@x_iss, $i, 1, @a);
		$i--;
	}
	# If we need to include a list of files to copy
	elsif	($s =~ /^\%FILES\%\s*$/i)
	{
		# Get list of files
		@a = sort keys %$p_copy_files;
		foreach $file (@a)
		{
			# Get subdirectory name
			$s1 = substr ($file, length ($x_base));
			$s1 =~ s#^\\##;
			$s1 =~ s#\\[^\\]+$##;
			$s2 = $file;
			$s2 =~ s#^.*\\##;
			$file = "Source: $file; DestDir: {app}\\$s1; DestName: $s2\n";
		}
		# Add DLL files to a list of files.
		$lib_dir = $x_base . "lib";
		$lib_dir =~ s#/#\\#g;
		# Add a list of DLL files
		if	(opendir (LIB_DIR, "${x_base}lib"))
		{
			while (defined ($file = readdir (LIB_DIR)))
			{
				next	if	($file !~ /\.dll$/i);
				push (@$p_lib_files, "$lib_dir\\$file");
				push (@a, "Source: $lib_dir\\$file; DestDir: {app}\\lib; DestName: $file\n");
			}
			close (LIB_DIR);
		}
		splice (@x_iss, $i, 1, @a);
		$i--;
	}

	# If we need to include version-dependent registry entries
	if	($s =~ /^\%REGFILE\%\s*$/i)
	{
		@a = ();
		if	($G_Config{REGFILE})
		{
			if	(open (REG_FILE, "$G_Config{REGFILE}"))
			{
				while (defined ($s1 = <REG_FILE>))
				{
					$s1 =~ s/\s+$//;
					push (@a, $s1 . "\n")	if	($s1);
				}
			}
			else
			{
				print "*** ERROR: Cannot read the file '$G_Config{REGFILE}': $!\n";
			}	
			close (REG_FILE);
		}
		else
		{
			print "*** NOTICE: Registry file was not specified\n";
		}
		splice (@x_iss, $i, 1, @a);
		$i--;
	}

	# Perform variable substitution
	&VariableSubstitution( \$x_iss[$i] );
}

# Save ISS file
$G_Config{ISSFILE} = $G_Config{PRODUCT} . "-" . $G_Config{VERSION} . ".iss";
open (ISS_FILE, ">$G_Config{ISSFILE}") || return( 1, "Cannot create file '$G_Config{VERSION}.iss': $!\n" );
print ISS_FILE join ("", @x_iss);
close (ISS_FILE);

return( 0, "" );

}	# end of Process ISS Template


#-------------------------------------------------
#	Create EQfiles
#-------------------------------------------------
sub CreateEQfiles
{
my( $file ) = @_;
my( $s );

# Create EQfiles.dat file in install subdirectory
open (LIST_FILE, ">$file") || die ("Cannot create file '$file': $!\n");

# First line contains version that's displayed in from GUI when 'HELP' button clicked
$s  = $G_Config{PRODUCT} =~ /enterprise-Q/i ? "# EQ " : "# $G_Config{PRODUCT} ";
$s .= "$G_Config{VERSION} ";
$s .= "$G_Config{PATCH} " unless( $G_Config{PATCH} eq "" );
$s .= "Build $x_date\n";

print LIST_FILE $s;

close( LIST_FILE );

}	# end of Create EQfiles


#-------------------------------------------------
#	Update EQfiles
#-------------------------------------------------
sub UpdateEQfiles
{
my( $file ) = @_;
my( $s, @a );

open (LIST_FILE, ">>$file") || die ("Cannot open file '$file': $!\n");

@a = sort keys %x_copy_files;
push (@a, @x_lib_files);
foreach $l_file (@a)
{
	substr ($l_file, 0, length ($x_base)) = "";
	$l_file =~ s#\\#/#g;
	print LIST_FILE $l_file, "\n";
}

close (LIST_FILE);
	
}	# end of Update EQfiles


#-------------------------------------------------
#	Process UPG Script
#-------------------------------------------------
sub ProcessUPGScript
{
my( $d, $f, @files, @data, $line, $success, $msg, $fqn );

$msg = "";
$d = $x_base;
$d = &OSDir( $d );
$d =~ s/\\+$//;

opendir( DH, "$d" ) || return( 1, "Error opening dir '$d': $!" );
while( $f = readdir( DH ) )
{
	next unless( $f =~ /\.upg$/i );
	
	$fqn = "$d/$f";
	$fqn = &OSDir( $fqn );
	
	open(FH, "$fqn" ) || return( 1, "Error opening file '$fqn': $!" );
	@data = <FH>;
	close( FH );
	foreach $line( @data )
	{
		&VariableSubstitution( \$line );
	}

	$success = rename( "$fqn", "$fqn.save" );
	return( 1, "Error renaming '$fqn': $!" ) unless( $success );
	
	open(FH, ">$fqn" ) || return( 1, "Error opening file '$fqn': $!" );
	print FH @data;
	close( FH );
	
	$msg .= "Processed '$fqn'\n";
}

return( 0, $msg );

}	# end of Process UPG Script


#-------------------------------------------------
#	Variable Substitution
#-------------------------------------------------
sub VariableSubstitution
{
my( $p_line ) = @_;
my( $k, $var, $val, $build_base );

$build_base = $G_Config{BUILD_BASE};
$build_base =~ s#\/#\\#g;
my( %varhash ) =
(
	BUILD_BASE	=> $build_base,
	ORIGIN		=> $G_Config{ORIGIN},
	DATE		=> $x_date,
	PRODUCT		=> $G_Config{PRODUCT},
	VERSION		=> $G_Config{VERSION},
	PATCH		=> $G_Config{PATCH},
);

foreach $k( keys %varhash )
{
	$var = "\%" . $k . "\%";
	$val = $varhash{$k};

	$$p_line =~ s/$var/$val/ig;
}

}	# end of Variable Substitution


#-------------------------------------------------
#	Build Process Line
#-------------------------------------------------
sub		Build_ProcessLine
{
my	($p_line) = @_;
my( $src, $dst, $convert, $regex, $dir );
my( $x_default_drive, $x_replace_drive, @a );

# Default drive for filenames in data file if those filenames do not have a drive letter specified
$x_default_drive = "C";

# Replace drive for source files to this drive. Leave this variable blank if you don't need a replacement. 
$x_replace_drive = "";

$p_line = $x_default_drive . ":" . $p_line
	if	(($x_os eq "WIN")&&($p_line !~ /^\w:/));
$p_line =~ s/^\w:/$x_replace_drive:/	if	($x_replace_drive ne "");

# Get source and destination directories, as well as conversion option
my($src, $dst, @a) = split (" ", $p_line);
$convert = join( " ", @a );
if( !defined ($dst) )
{
	$p_line =~ s/\s+$//;
	print "*** Invalid line '$p_line'\n";
	return;
}

$convert = ""	if	(!defined ($convert));
$src =~ s/\%20/ /g;
$convert =~ s/\%20/ /g;

if( $convert =~ /(^|,)(UNIX|WIN|SOLARIS|AIX|LINUX)(,|$)/i )
{
	return	if	(($x_os ne "\U$2")&&($x_os_type ne "\U$2"));
}
	

if	($x_os ne "WIN" && $convert !~ /KEEP_CASE/i )
{
	# Convert src dir to lowercase for input & output files
	if( $src =~ m#^$G_Config{ORIGIN}(.*)/([^/]+)$# )
	{
		$src = $G_Config{ORIGIN} . "\L$1" . "/" . $2;
	}
	elsif( $src =~ m#^(.*)/([^/]+)$# )
	{
		$src = "\L$1" . "/" . $2;
	}
	
	# Convert dst dir to lowercase
	if( $dst =~ m#^$G_Config{ORIGIN}(.*)/([^/]*)$# )
	{
		$dst = $G_Config{ORIGIN} . "\L$1" . "/" . $2;
	}
	elsif( $dst =~ m#^(.*)/([^/]*)$# )
	{
		$dst = "\L$1" . "/" . $2;
	}
}


# Separate src into dir and file
$dir = $file = "";
if( $src =~ /^(.*)\/(.+)$/ )
{
	$dir = $1;
	$file = $2;
}

# Check file for wildcard
if( $file =~ /\*/ )
{
	$regex = $file;
	$regex =~ s/\*/.+/g;	# replace all instances of asterisk '*' with '.+'

	# open the dir and process each file for match
	opendir( DH, "$dir" );
	while( my $file = readdir( DH ) )
	{
		# skip it unless it's a file and matches regex
		next unless( -f "$dir/$file" && $file =~ /${regex}/ );
		$src = "$dir/$file";
		&Build_SrcDstConvert( $src, $dst, $convert );
	}
	closedir( DH );
}
	
# Must be single file, so make sure it exists
elsif( -f $src )
{
	&Build_SrcDstConvert( $src, $dst, $convert );
}

# File does not exist, so print message indicating such
else
{
	print "$src - not exist\n";
}

return;

}	# end of Build Process Line


#-------------------------------------------------
#	Build Src Dst Convert
#-------------------------------------------------
sub Build_SrcDstConvert
{
my( $src, $dst, $convert ) = @_;
my( $s1, $s2, $l_out_file, @l_dest );

# Get input file name
($s1) = $src =~ m#([^/]+)$#;

# Destination directory may be more than one
@l_dest = split (/\s*,\s*/, $dst);
foreach $dst (@l_dest)
{
	# If destination is a directory - append filename to it
	$dst .= $s1	if	($dst =~ m#/$#);
	$dst = $x_base . $dst;
	$dst =~ s#/+#/#g;

	# Generate output file name
	$l_out_file = $dst;
	
	# If we need to convert perl files to exe files
	$l_out_file =~ s/\.pl$/$x_exe_ext/i if( $convert =~ /(^|,)TOEXE(,|$)/i );
		
	# Check if file was modified
	if	(&Build_CheckDates ($src, $l_out_file) != 0)
	{
		if	(&Build_ProcessFile ($src, $dst, $convert) != 0)
		{
			print "$src -> $l_out_file - ok\n" if( $G_Config{VERBOSE} != 0 );
		}
	}
	else
	{
		print "$src - not modified\n" if( $G_Config{VERBOSE} != 0 );
	}

	# Update list of dirs to be created prior to copying this file
	$s2 = substr ($l_out_file, length ($x_base));
	$s2 =~ s#\\#/#g;
	if	($s2 =~ m#/#)
	{
		$s2 =~ s#/[^/]+$##;
		$s2 =~ s#^/##;
		$s2 = &OSDir( $s2 );
		$x_create_dirs{"\U$s2"} = $s2
			if	(!defined ($x_create_dirs{"\U$s2"}));
	}

	$s2 = &OSDir ($l_out_file);
	if	($convert =~ /(^|,)TEMP(,|$)/i)
	{
		$x_temp_files{$s2} = 1;
	}
	# Update list of files that should be copied by installation program
	else
	{
		$x_copy_files{$s2} = 1;
	}		
	push( @x_check_perl_syntax, $l_out_file ) if( $l_out_file =~ /.pl$/i );
}

return;

}	# end of Build Src Dst Convert


#-------------------------------------------------
#	Build Process File
#-------------------------------------------------
sub Build_ProcessFile
{
	my	($p_in, $p_out, $p_convert) = @_;
	my	($s, $i, @a, @l_data, $l_dir, $l_file, $option, $lib_dir, %setx, $ext);

	%setx = ( pl => 1, sh => 1 );
	
	# Check if destination directory exist
	$l_dir = $p_out;
	$l_dir =~ s#/([^/]+)$##;
	$l_file = $1;
	unless (-d $l_dir)
	{
		# Create directory structure
		@a = split ("/", $l_dir);
		$s = $a[0];
		for ($i = 1; $i < @a; $i++)
		{
			# Add another subdirectory to the path
			$s .= "/" . $a[$i];
			# if it doesn't exist yet
			unless (-d $s)
			{
				# Create it
				unless (mkdir ($s, 0755))
				{
					print "*** Cannot create directory '$s': $!\n";
					return 0;
				}
			}
		}
	}

	# Convert file if necessary
	if	($p_convert =~ /(^|,)TOEXE(,|$)/i)
	{
		# Read input file into memory
		unless (open (IN_FILE, $p_in))
		{
			print "*** Cannot open file '$p_in': $!\n";
			return 0;
		}
		@l_data = <IN_FILE>;
		close (IN_FILE);

		&Build_Convert ($p_out, \@l_data);

		if	($x_os ne "WIN")
		{
			# Get original mode of the file
			unless (@a = stat ($p_in))
			{
				print "*** Cannot get information about file '$p_in': $!\n";
				return 0;
			}
		}

		# Write the file
		unless (open (OUT_FILE, ">$p_out"))
		{
			print "*** Cannot create file '$p_out': $!\n";
			return 0;
		}
		print OUT_FILE join ("", @l_data);
		close (OUT_FILE);

		if	($x_os ne "WIN")
		{
			unless (chmod ($a[2] & 0777, $p_out))
			{
				print "*** Cannot change mode of file '$p_out': $!\n";
				return 0;
			}
		}

		# If we need to compile the file
		if	($p_out =~ /\.pl$/i)
		{
			push (@x_compile_files, (($x_os eq "WIN")? "": "#"));
			$s = &OSDir ($l_dir);
			push (@x_compile_files, "$1:") if( $s =~ /^(\w):/ );
			push (@x_compile_files, "cd $s");
			if( $x_os eq "WIN" )
			{
				push( @x_compile_files, "time /t >> $x_comp2exe_log\n" );
			}
			else
			{
				push( @x_compile_files, "date >> $x_comp2exe_log\n" );
			}
			push(  @x_compile_files, "echo Building '$l_file' >> $x_comp2exe_log\n" );
			&AddPerl2Compile( $l_file, $p_convert, $l_dir );
		}
	}
	else
	{
		($err, $msg) = &CopyFile( $p_in, $p_out, $p_convert, $x_os );
		if( $err ) 
		{
			print $msg;
			return 0;
		}
	}
	
	# Get the file extension and see if we need to set it to be executable
	$ext = $p_out =~ /^.+\.(.+)$/ ? $1 : "";
	if( ($p_convert =~ /(^|,)SETX(,|$)/i || defined($setx{$ext}) )&& ($x_os ne "WIN") )
	{
		unless (chmod (0755, $p_out))
		{
			print "$p_out - error (chmod): $!\n";
			return 0;
		}
	}
	
	return 1;
	
}	# Build Process File


#-------------------------------------------------
#	Add Perl 2 Compile
#-------------------------------------------------
sub AddPerl2Compile
{
my( $script, $attribs, $dir ) = @_;
my( $cmd, $lib_dir, $options, @a, $runlib, $perlpath );

@a = ( );
$cmd = $G_Config{PERL2EXE_CMD};
if( $cmd eq "perl2exe" )
{
	$lib_dir = &OSDir ($x_base . "lib");
	$options = $attribs =~ /(^|,)SMALL(,|$)/i ? "-small ": "-tiny ";
	if( $x_os eq "WIN" )
	{
		$options  = "-icon=$G_Config{ICON} $options " if( -f "$G_Config{ICON}" );
		$options .= "-perloptions=\"-p2x_noshow_includes -I$G_Config{PERLLIB}\" ";
		push (@a, "del p2xdll.dll");
		push (@a, "move *.dll $lib_dir");
		push (@a, "del $script") unless( $G_Config{DO_NOT_REMOVE_PL} );
	}
	else
	{
		$options .= "-perloptions=\"-p2x_noshow_includes\" ";
		push (@a, "mv *.so $lib_dir");
		push (@a, "rm $script") unless( $G_Config{DO_NOT_REMOVE_PL} );
	}
}

elsif( $cmd eq "perlapp" )
{
	$options = "";
	# add --perl /path/to/perl/bin"
	$options .= "--perl $G_Config{PERLBIN} ";
	# add --runlib ../../../perl5/lib.  Must determine how many '..' to include
	$options .= &GetRunLib( $dir );
	$options .= $attribs =~ /(^|,)(SMALL|FREE)(,|$)/i ? "--freestanding ": "--dependent ";
#	$options .= "--freestanding ";
	$options .= "--force ";
	if( $x_os eq "WIN" )
	{
		$options .= "--icon $G_Config{ICON} " if( -f "$G_Config{ICON}" );
		push (@a, "del $script") unless( $G_Config{DO_NOT_REMOVE_PL} );
	}
	else
	{
		push (@a, "rm $script") unless( $G_Config{DO_NOT_REMOVE_PL} );
	}
}

elsif( $cmd eq "pp" )
{
	my $outfile;
	$outfile = $script;
	$outfile =~ s/\.pl$//;
	$outfile .= ".exe" if( $x_os eq "WIN" );

#	pp Options:
#	-f		: filter for encrypting source code (Bleach or Filter::Crypto )
#	-F		: filter for encrypting modules
#	-M		: module to include
#	-C		: clean up cache files created by application
#	-o		: output filename

#	Option Examples:	-f Bleach
#						-l /path/to/libcrypto.so.1.0.0 -f Crypto -F Crypto -M Filter::Crypto::Decrypt -M XML::SAX::PurePerl 
#
#	-C = Clean up temporary files extracted from the application at runtime
#	-o = name of output file

	# See if attribs includes PPOPTIONS, like PPOPTIONS="-l c:/eq/lib/libeay32.dll"
	$options  = $G_Config{PPOPTIONS};
	$options .= " $1" if( $attribs =~ /PPOPTIONS=\"([^\"]+)\"/i );
	$options .= " -C -o $outfile ";
	if( $x_os eq "WIN" )
	{
		$options .= "--icon $G_Config{ICON} " if( -f "$G_Config{ICON}" );
		push (@a, "del $script") unless( $G_Config{DO_NOT_REMOVE_PL} );
	}
	else
	{
		push (@a, "rm $script") unless( $G_Config{DO_NOT_REMOVE_PL} );
	}
}


$cmd = "$G_Config{PERL2EXE_PATH}/$cmd";
$cmd = &OSDir( $cmd );

# For some reason, the 'pp' compiler terminates the bat file after the first time under Windows
# So, we gotta START the 'pp' command in a separate MINimized CMD window and WAIT for it to complete
if( $G_Config{PERL2EXE_CMD} eq "pp" && $x_os eq "WIN" )
{
	$cmd = "START /WAIT /MIN CMD /C \"echo Building $script \&\& $cmd $options $script\"";
}
else
{
	$cmd = "$cmd $options $script";
}

push (@x_compile_files, $cmd );
push( @x_compile_files, @a ) unless( scalar(@a) == 0 );

}	# end of Add Perl 2 Compile


#-------------------------------------------------
#	Get Run Lib
#-------------------------------------------------
sub GetRunLib
{
my( $dir ) = @_;
my( @a, $runlib, $path, $base );

# initialize runlib
$path = "";

# initialize base
$base = $x_base;

# Change all slashes to forward slash
$dir  =~ s#\\#/#g;
$base =~ s#\\#/#g;

return "" unless( $dir =~ s/^$x_base// );	# remove base

# determine how many subdirs there are
@a = split( "/", $dir );
foreach $s( @a )
{
	$path .= "../";
}

# append perl5 lib directory
$runlib = "";
if( $x_os eq "WIN" )
{
	$runlib .= $path . "perl5/lib ";
	$runlib .= $path . "perl5/site/lib ";
	$runlib .= ".";
}
else
{
	$runlib .= $path . "perl5/lib ";
	$runlib .= $path . "perl5/lib/site_perl ";
	$runlib .= ".";
}

#return "--runlib \"$runlib\" ";
return "--norunlib ";

}	# end of Get Run Lib


#-------------------------------------------------
#	Copy File
#-------------------------------------------------
sub CopyFile
{
my( $in, $out, $convert, $os ) = @_;
my( $s, @data );

if( $convert =~ /(^|,)STRIP_RET(,|$)/i )
{
	return( 1, "*** Cannot open file '$in': $!\n" ) unless (open (IN_FILE, $in));

	# Read input file into memory
	binmode(IN_FILE);
	@data = <IN_FILE>;
	close (IN_FILE);

	return( 1, "*** Cannot create file '$out': $!\n" ) unless (open (OUT_FILE, ">$out"));

	# Write the file
	binmode( OUT_FILE );
	foreach $s( @data )
	{
		$s =~ s/\r+//g;
		print OUT_FILE $s;
	}
	close( OUT_FILE );
}

else
{
	use File::Copy;
	$in  =~ s#\\#/#g;
	$out =~ s#\\#/#g;
	# Just copy it
	copy( $in, $out ) || return( 1, "Error copying file: $!" );
}

return( 0, "" );

}	# end of Copy File



#-------------------------------------------------
#	Build Check Dates
#-------------------------------------------------
sub		Build_CheckDates
{
	my	($p_in, $p_out) = @_;
	my	(@a, @b);

	# If input or output file do not exist
	return 1	unless	(-f $p_in);
	return 1	unless	(-f $p_out);

	# Get modification time for both files
	@a = stat ($p_in);
	@b = stat ($p_out);
	return ($a[9] <= $b[9])? 0: 1;
}


#-------------------------------------------------
#	Build Convert
#-------------------------------------------------
sub		Build_Convert
{
	my	($p_file, $p_data) = @_;
	my	($s, $i, $j, @a, %l_libs, $sub, $sub_line);
	my	(%sub_start, %sub_end, %sub_refer, %sub_keep, $l_eof);

	# The first pass - insert library modules into file, build a
	# list of defined routines, and create a list of referenced routines.
	# This only should be done for perl files
	if	($p_file =~ /\.pl$/i)
	{
		%l_libs = ();
		$l_eof = "";
		$sub = "";
		%sub_start = ();
		%sub_end = ();
		%sub_refer = ();
		# Search for 'require' statement
		for($i = 0; $i < @$p_data; $i++)
		{
			$s = $$p_data[$i];
			# If library file should be included
			if	($s =~ /^\s*require\s*\(?\s*"(\S+)"\s*\)?\s*;/i)
			{
				$s = $1;
				# If it's not our library
				next	if	(($s !~ s#^\$xc_EQ_PATH[\\/]?##i)&&
						 ($s !~ s#^\$x_EQ_PATH[\\/]?##i));

				# Exclude setup_env.pl (although it should be
				# excluded by previous if statement) and
				# postinst.pl
				next	if	($s =~ /setup_env\.pl$/i);
				next	if	($s =~ /postinst\.pl$/i);

				# Convert all backslashes to forward slashes and
				# generate full path to library file
				$s = "$G_Config{ORIGIN}/" . $s;
				$s =~ s#\\#/#g;
				$s =~ s#/+#/#g;
				# Do not include the library if we can't find it
				unless (-f $s)
				{
					print "*** Cannot find library '$s' in '$p_file' near line '$i'\n";
					next;
				}

				# If we already included this library
				if	(defined ($l_libs{"\U$s"}))
				{
					$$p_data[$i] = "";
					next;
				}
				# Don't forget to mark this library as included
				$l_libs{"\U$s"} = 1;

				# Read library data from file
				unless (open (LIB_FILE, $s))
				{
					print "*** Cannot open library '$s' in '$p_file' near line '$i': $!\n";
					next;
				}
				@a = <LIB_FILE>;
				close (LIB_FILE);

				# Remove empty lines and return code at the end of the
				# library
				for ($j = @a - 1; $j >= 0; $j--)
				{
					$s = $a[$j];
					last	if	(($s !~ /^\s*$/)&&($s !~ /^1;\s*$/));
					$a[$j] = "";
				}
				# Insert library code
				splice (@$p_data, $i, 1, @a);
				$i--;
				@a = ();
			}
			elsif	($l_eof)
			{
				$l_eof = ""		if	($s =~ /^$l_eof\s*$/);
			}
			elsif	($s =~ /^\s*[^#\s].*<<(EOF|EOT);\s*$/)
			{
				$l_eof = $1;
			}
			elsif	(($s =~ /^\s*#/)||($s =~ /^\s*$/))
			{
				$$p_data[$i] = "";
			}
			# Start of a new subroutine?
			elsif	($s =~ /^sub\s+(\w+)\s*$/)
			{
				# If previous subroutine was not properly closed
				if	($sub ne "")
				{
#print "Subroutine '$sub' not closed\n";
					# Do not remove it! - assume that it was called from
					# the main script body
					if	($sub_refer{""})
					{
						$sub_refer{""} .= "," . $sub;
					}
					else
					{
						$sub_refer{""} = $sub;
					}
				}
				$sub = "";
#print "Subroutine start: $1\n";
				if	($sub_start{$1})
				{
					print "*** Multiple definition of subroutine '$1' in '$p_file' near line '$i'\n";
					$sub = "";
				}
				else
				{
					$sub = $1;
					$sub_line = $i;
				}
			}
			# If we found end of subroutine
			elsif	($s =~ /^\}\s+#sub\s+(\w+)\s*$/)
			{
#print "Subroutine end: $1\n";
				# Verify that we found a start of this subroutine
				if	($sub eq $1)
				{
					$sub_start{$sub} = $sub_line;
					$sub_end{$sub} = $i;
				}
				else
				{
					print "*** Invalid closing of subroutine '$sub' ($1) in '$p_file' near line '$i'\n";
				}
				$s =~ s/\s*#.+$//;
				$$p_data[$i] = $s . "\n";
				$sub = "";
			}
			else
			{
				while ($s =~ /\&(\w+)\s*\(/g)
				{
					if	($sub_refer{$sub})
					{
						$sub_refer{$sub} .= "," . $1;
					}
					else
					{
						$sub_refer{$sub} = $1;
					}
#print "Sub [$sub] references '$1'\n";
				}
				if	($s =~ /\&(\w+)\s*$/g)
				{
					if	($sub_refer{$sub})
					{
						$sub_refer{$sub} .= "," . $1;
					}
					else
					{
						$sub_refer{$sub} = $1;
					}
#print "Sub [$sub] references '$1'\n";
				}

				$$p_data[$i] =~ s/^\s+//;
				$$p_data[$i] =~ s/\~\~\~PRODUCT\~\~\~/$G_Config{PRODUCT}/g;
				$$p_data[$i] =~ s/\~\~\~VERSION\~\~\~/$G_Config{VERSION}/g;
				$$p_data[$i] =~ s/\~\~\~PATCH\~\~\~/$G_Config{PATCH}/g;
			}
		}

		# If the last subroutine in the script was not properly closed
		if	($sub ne "")
		{
#print "Subroutine '$sub' not closed\n";
			# Do not remove it! - assume that it was called from
			# the main script body
			if	($sub_refer{""})
			{
				$sub_refer{""} .= "," . $sub;
			}
			else
			{
				$sub_refer{""} = $sub;
			}
		}

		# Resolve all of subroutine references and determine
		# what soubroutines to keep
		%sub_keep = ();
		@a = ($sub_refer{""})? split (",", $sub_refer{""}): ();
		for ($i = 0; $i < @a; $i++)
		{
			$sub = $a[$i];
			# If haven't processed this subroutine yet
			if	(!defined ($sub_keep{$sub}))
			{
				$sub_keep{$sub} = 1;
				# If we know what this subroutine references
				if	($sub_refer{$sub})
				{
					# Add referenced fuctions to a list of functions to keep
					push (@a, split (",", $sub_refer{$sub}));
				}
			}
		}

		# Remove all non-referenced functions from the files
		@a = keys %sub_start;
		foreach $sub (@a)
		{
			next	if	($sub_keep{$sub});
			for ($i = $sub_start{$sub}, $j = $sub_end{$sub}; $i <= $j; $i++)
			{
				$$p_data[$i] = "";
			}
#print "Removed function '$sub'\n";
		}
	}

	# The second pass - just convert .pl to .exe
	foreach $s (@$p_data)
	{
		# If we found reference to perl file
		if	(($s =~ /[\w\~]\.pl$/i)||($s =~ /[\w\~]\.pl\W/i))
		{
			# Don't modify 'require' commands
			next	if	($s =~ /^\s*require\s*\(?\s*"\S+"/i);
			# Don't modify calls to setup_env.pl and postinst.pl
			next	if	($s =~ /setup_env\.pl/i);
			next	if	($s =~ /postinst\.pl/i);

#print "BEFORE:[$s]\n";
			# Make sure that command line does not call perl
			if	($s !~ s#[\\\~\w/:\-\$]+[\\/]perl\s+(\S*[\w\~])\.pl#$1$x_exe_ext#ig)
			{
				$s =~ s#([\w\~])\.pl#$1$x_exe_ext#ig
					if	($s !~ s#[\\\~\w/:\-\$]+[\\/]perl$x_exe_ext_m\s+(\S*[\w\~])\.pl#$1$x_exe_ext#ig);
			}
#print "AFTER:$s";
		}
	}
}


#-------------------------------------------------
#	Prompt User
#-------------------------------------------------
sub PromptUser
{
my( $p_prompts, $p_vars ) = @_;
my( $err, $msg, $i, $input, $p_var );

print "-----------------------\n";
for( $i = 0; $i < @$p_prompts; $i++ ) 
{
	print "$$p_prompts[$i]:  ";
	$input = <STDIN>;
	chomp( $input );
	next if( $input eq "" );
	$p_var = $$p_vars[$i];
	$$p_var = $input;
}
print "-----------------------\n";

return( 0, "" );

}	# end of Prompt User


#-------------------------------------------------
#	OS Dir
#-------------------------------------------------
sub	OSDir
{
	my	($p_dir) = @_;

	if	($x_os eq "WIN")
	{
		$p_dir =~ s#/+#\\#g;
	}
	else
	{
		$p_dir =~ s#\\+#/#g;
	}

	return $p_dir;
}


#-------------------------------------------------
#	Get Parms
#-------------------------------------------------
sub GetParms
{
my( $p_cfghash ) = @_;
my( $line, $cfgfile );

use Getopt::Std;
&getopts('a:C:P:V:o:d:t:b:c:r:p:U:e:i:vnhkT');

&Usage( ) if( $opt_h );

&DisplayParms( "Default Settings" ) if( $opt_v );

# Use 'build.cfg' as default config file if none supplied
$cfgfile = $opt_C || $p_cfghash->{CFGFILE};
$p_cfghash->{CFGFILE} = $cfgfile;

# Check if config file exists
if( -f $cfgfile )
{
	open( FH, $cfgfile ) || die "Error opening '$cfgfile': $!";
	while( $line = <FH> )
	{
		$line =~ s/^\s+|\s+$//g;				# strip leading/trailing spaces
		next if( $line eq "" || $line =~ /^\#/ );		# skip blank lines and comments
		next unless( $line =~ /^(\S+)\s*=\s*(.*)$/ );
		$$p_cfghash{"\U$1"} = $2;
	}
	close( FH );
} 

&DisplayParms( "After '$cfgfile' Processing" ) if( $opt_v );

# Now, use arguments passed on command line
&SetBuildBase( $p_cfghash, $opt_b );

$$p_cfghash{BUILD_FLAG}	= 0			if( defined($opt_n) );
$$p_cfghash{COMPILER}	= $opt_c	if( defined($opt_c) );

$$p_cfghash{DATFILE}	= $opt_d if( defined($opt_d) );
$$p_cfghash{DATFILE}	.= ".dat" if( $$p_cfghash{DATFILE} !~ /\.dat$/i );	# Ensure data file exists
die ("File '$$p_cfghash{DATFILE}' does not exist\n") unless(-f $$p_cfghash{DATFILE});

#$$p_cfghash{ORIGIN}	= $opt_o if( defined($opt_o) );

if( defined( $opt_e ) )
{
	$$p_cfghash{EQPERL_REPOSITORY} = $opt_e;
}
elsif( length($$p_cfghash{EQPERL_REPOSITORY}) == 0 )
{
	$$p_cfghash{EQPERL_REPOSITORY} = "$G_Config{ORIGIN}/../EQPerl";	# set default value
}

die "EQPerl directory named '$$p_cfghash{EQPERL_REPOSITORY}' does not exist" 
	unless( -d $$p_cfghash{EQPERL_REPOSITORY} );

$$p_cfghash{ARCHCMD}	= $opt_a if( defined($opt_a) );
$$p_cfghash{PROCESSORS}	= $opt_U if( defined($opt_U) );
$$p_cfghash{PRODUCT}	= $opt_P if( defined($opt_P) );
$$p_cfghash{TEMPLATE}	= $opt_t if( defined($opt_t) );
$$p_cfghash{VERBOSE}	= $opt_v if( defined($opt_v) );
$$p_cfghash{VERSION}	= $opt_V if( defined($opt_V) );
$$p_cfghash{PATCH}		= $opt_p if( defined($opt_p) );
$$p_cfghash{REGFILE}	= $opt_r if( defined($opt_r) );
$$p_cfghash{DO_NOT_REMOVE_PL} = $opt_k	if	(defined($opt_k));
$$p_cfghash{DO_NOT_COPY_TAR} = 1	if	(defined($opt_T));

# Set default value for icon file if nothing supplied
$$p_cfghash{ICON}		= $opt_i if( defined($opt_i) );
$$p_cfghash{ICON}		= &OSDir (($G_Config{PRODUCT} =~ /eQ\-tilities/i)?
	"$$p_cfghash{ORIGIN}/install/eqt.ico": "$$p_cfghash{ORIGIN}/install/EQ.ico")
		if( $$p_cfghash{ICON} eq "" );

&DisplayParms( "After Command Line Processing" );

}	# end of Get Parms


#-------------------------------------------------
#	Set Build Base
#-------------------------------------------------
sub SetBuildBase
{
my( $p_cfghash, $build_base_arg ) = @_;

if( defined($build_base_arg) && $build_base_arg ne "" )
{
	$p_cfghash->{BUILD_BASE} = $build_base_arg;
}

elsif	($x_os eq "WIN")
{
	$x_exe_ext = ".exe";		# Extension of executable files
	$x_exe_ext_m = "\\.exe";	# Used for matches
	$x_comp2exe_log =~ s#[\\/]+#\\\\#g;
	
	# make sure BUILD_BASE defined
	if( !defined($p_cfghash->{BUILD_BASE}) || $p_cfghash->{BUILD_BASE} eq "" )
	{
		$p_cfghash->{BUILD_BASE} = $G_TopDir . "/../EQBuild";
	}
	# convert relative BUILD_BASE to absolute path
	elsif( $p_cfghash->{BUILD_BASE} !~ /^[A-Za-z]\:/ )
	{
		$p_cfghash->{BUILD_BASE} = $G_TopDir . "/" . $p_cfghash->{BUILD_BASE};
	}
}

else
{
	$x_exe_ext = "";
	$x_exe_ext_m = "";
	
	# make sure BUILD_BASE defined
	if( !defined($p_cfghash->{BUILD_BASE}) || $p_cfghash->{BUILD_BASE} eq "" )
	{
		$p_cfghash->{BUILD_BASE} = $G_TopDir . "/../EQBuild";
	}
	# convert relative BUILD_BASE to absolute path
	elsif( $p_cfghash->{BUILD_BASE} !~ /^\// )
	{
		$p_cfghash->{BUILD_BASE} = $G_TopDir . "/" . $p_cfghash->{BUILD_BASE};
	}
}

$p_cfghash->{BUILD_BASE} =~ s#\\+#/#g;
unless( -d $p_cfghash->{BUILD_BASE} )	# Ensure build directory exists
{
	$result = mkdir( $p_cfghash->{BUILD_BASE}, 0750 );
	die( "Error creating directory '$p_cfghash->{BUILD_BASE}': $!" ) unless( $result == 1 );
}

}	# end of Set Build Base


#-------------------------------------------------
#	Display Parms
#-------------------------------------------------
sub DisplayParms
{
my( $title ) = @_;
my( $k, $v );

print "Parms - $title\n" if( $title );
foreach $k( sort keys %G_Config )
{
	$v = $G_Config{$k};
	if( $v =~ /^\d+$/ ) { print "\t$k = $v\n"; }
	else { print "\t$k = '$v'\n"; }
}
print "\n\n";

}	# end of Display Parms


#-------------------------------------------------
#	Usage
#-------------------------------------------------
sub Usage
{
my( $k, $v );

print <<EOT;

Usage: $0 [-h] [-C <cfg file>] [-<option> <value>] -V <version> -d <.dat file>

Builds Enterprise-Q tar file and places it in current working directory

where:
	-a = ARCHCMD - Archive command used to build distribution.  'ARCHFILE' and 'SRCDIR' 
			are replaced with proper values.
				Default: 'tar cvf ARCHFILE.tar -C SRCDIR .'
				Example: \"/path/to/inno/Compil32.exe\" /cc ISSFILE
    -b = BUILD_BASE - Temp location from which to build distribution (def = '$G_Config{BUILD_BASE}')
    -n = BUILD_FLAG - Do not create setup.exe / tar file
    -c = COMPILER - Utility used to create 'setup.exe' (def = '$G_Config{COMPILER}')
    -d = DATFILE = Data file containing source file names (required)
    -i = ICON - Path to icon file (default = '$G_Config{ICON}')
    -o = ORIGIN - Root directory of source files (default = '$G_Config{ORIGIN}')
    -U = PROCESSORS - Processor count (default = $G_Config{PROCESSOR})
    -P = PRODUCT - Product name (example: '$G_Config{PRODUCT}')
    -V = VERSION - Version (example: '1.6.5')
    -p = PATCH - Patch (example: 'Patch-0166')
    -t = TEMPLATE - Inno template file used for building 'setup.exe' (def = '$G_Config{TEMPLATE}')
    -r = REGFILE - Registry file contains Windows Registry keys to include in 'iss' file.
    -v = VERBOSE - Verbose information
    -h = HELP - Generate usage statement
	-e = EQPERL_REPOSITORY - path to find correct perl tar file to include with distribution
	-k = DO_NOT_REMOVE_PL - Keep .pl files after compile use for testing, and Unix, only!
	-T = DO_NOT_COPY_TAR - Do not copy perl tar file
	
Configuration File Arguments (and default values):

EOT

&DisplayParms(  );

exit( 0 );

}	# end of Usage
