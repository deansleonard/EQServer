#!C:/dean/EQ-Working/EQServer/perl5/bin/perl
# Author: Include
#use strict;
#use warnings;
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use Getopt::Std;
use Cwd;

&getopts('xctvf:C:', \%G_opt);

&Usage( ) unless( ($G_opt{x} || $G_opt{c} || $G_opt{t}) && $G_opt{f} );

$verbose = $G_opt{v} || 0;
$directory = $G_opt{C} || &getcwd( );
$directory =~ s#\\+#/#g;

print "DIR: $directory\n";

if( $G_opt{t} )
{
	#show contents
	($err, $msg) = &ShowFiles( );
}
elsif( $G_opt{x} )
{
	#extract contents
	($err, $msg) = &ExtractFiles( );
}
elsif( $G_opt{c} )
{
	#create archive
	($err, $msg) = &CreateFile( $directory );
}
else
{
	&Usage( );
}

print "$msg\n" unless( $msg eq "" );
exit( $err );


#---------------------------------------------
#	Show Files
#---------------------------------------------
sub ShowFiles
{
my( $zip, @members, $member );

print "Contents of $G_opt{f}\n" if( $G_opt{v} );
$zip = Archive::Zip->new( );
return( 1, "Error reading zip file $G_opt{f}" ) unless( $zip->read($G_opt{f}) == AZ_OK );

@members = $zip->memberNames();
foreach $member( @members )
{
	print "$member\n" if( $G_opt{v} );
}

return( 0, "" );

}	# end of Show Files


#---------------------------------------------
#	Extract Files
#---------------------------------------------
sub ExtractFiles
{
my( $zip, @members, $member );

print "Extracting contents of $G_opt{f}\n" if( $G_opt{v} );
$zip = Archive::Zip->new( );
return( 1, "Error reading zip file $G_opt{f}" ) unless( $zip->read($G_opt{f}) == AZ_OK );

@members = $zip->memberNames();
foreach $member( @members )
{
	print "$member\n" if( $G_opt{v} );
	return( 1, "Error extracting '$member'" ) unless( $zip->extractMember( $member ) == AZ_OK );
}

return( 0, "" );

}	# end of Extract Files


#---------------------------------------------
#	Create File
#---------------------------------------------
sub CreateFile
{
my( $dir ) = @_;
my( $err, $msg, $zip, $file, @files );

$dir =~ s#/+$##;
foreach $file ( map { glob } @ARGV )
{
	$file =~ s#\\#/#g;
	if( -f "$dir/$file" )
	{
		push( @files, "$dir/$file" );
	}
	elsif( -d "$dir/$file" )
	{
		($err, $msg) = &GetFiles( "$dir/$file", \@files );
		return( 1, $msg ) if( $err );
	}
}

print "Creating $G_opt{f}\n" if( $G_opt{v} );
$zip = Archive::Zip->new( );
foreach $file( @files )
{
	$file =~ s#$dir/##;
	print $file . "\n" if( $G_opt{v} );
	if( -d "$dir/$file" )
	{
		$zip->addDirectory( "$dir/$file", $file );
	}
	else
	{
		$zip->addFile( "$dir/$file", $file );
	}
}

return( 1, "Error writing '$G_opt{f}'" ) unless( $zip->writeToFileNamed($G_opt{f}) == AZ_OK );
return( 0, "" );
    
}	# end of Create File


#---------------------------------------------
#	Get Files
#---------------------------------------------
sub GetFiles
{
my( $dir, $p_files ) = @_;
my( $err, $msg, @flist, $file );

opendir( DH, "$dir" ) || return( 1, "Error opening dir '$dir': $!" );
@flist = readdir( DH );
closedir( DH );

foreach $file( @flist )
{
	# skip links and current/parent dirs
	next if( -l "$dir/$file" || $file =~ /^\.+$/ );
	$file =~ s#\\+#/#g;
	($err, $msg) = &GetFiles( "$dir/$file", $p_files ) if( -d "$dir/$file" );
	return( $err, $msg ) if( $err );
	push( @$p_files, "$dir/$file" );
}

return( 0, "" );

}	# end of Get Files


#---------------------------------------------
#	Usage
#---------------------------------------------
sub Usage
{

print <<EOT;
Usage: $0 [-x|-c|-t] [-v] -f <file> [file1, file2, ...]

-x = Extract <file> to current location
-c = Create <file> from [file1, file2, ...]
-t = Show members of <file>
-v = Verbose
-C = Directory from which to pull files
Example:

To display contents of zip file:

\t$0 -tvf file.zip

To extract zip file to local directory:

\t$0 -xvf file.zip

To create zip file containing three files; a.ext, b.ext, and c.ext:

\t$0 -cvf file.zip a.ext b.ext c.ext

To create zip file containing the 'trouble' directory and file named 'tree.pl' from directory named 'www/cgi-bin':

\t$0 -cvf file.zip -C www/cgi-bin trouble tree.pl

EOT

exit( 0 );

}	# end of Usage


