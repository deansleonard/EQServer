#!C:/dean/EQ-Working/EQServer/perl5/bin/perl
#
#	EQCommonLib.pl - Common enterprise-Q Routines
#
#	Copyright Capital Software Corporation - All Rights Reserved
#
#	$Id: EQCommonLib.pl,v 1.8 2014/11/06 23:35:57 eqadmin Exp $

#use strict;
#use warnings;

use POSIX qw( uname tzname mktime );

my	%x__cl_months =
(	JAN => 1, JANUARY => 1, FEB => 2, FEBRUARY => 1, MAR => 3, MARCH => 3,
	APR => 4, APRIL => 4, MAY => 5, JUN => 6, JUNE => 6,
	JUL => 7, JULY => 7, AUG => 8, AUGUST => 8, SEP => 9, SEPTEMBER => 9,
	OCT => 10, OCTOBER => 10, NOV => 11, NOVEMBER => 11, DEC => 12, DECEMBER => 12
);

#-----------------------------------------
#	EQ String To Time
#-----------------------------------------
sub	EQ_StringToTime
{
	my	($p_time, $p_rel) = @_;
	my	($uts, $Y, $M, $D, $h, $m, $s, $aorp);
	my	(%month) =
	(
		"JAN" => 0, "FEB" => 1, "MAR" => 2, "APR" => 3, "MAY" => 4, "JUN" => 5,
		"JUL" => 6, "AUG" => 7, "SEP" => 8, "OCT" => 9, "NOV" =>10, "DEC" =>11,
		"Jan" => 0, "Feb" => 1, "Mar" => 2, "Apr" => 3, "May" => 4, "Jun" => 5,
		"Jul" => 6, "Aug" => 7, "Sep" => 8, "Oct" => 9, "Nov" =>10, "Dec" =>11,
		"jan" => 0, "feb" => 1, "mar" => 2, "apr" => 3, "may" => 4, "jun" => 5,
		"jul" => 6, "aug" => 7, "sep" => 8, "oct" => 9, "nov" =>10, "dec" =>11,
		# French months not covered yet...
		"Fév" => 1, "Avr" => 3, "Mai" => 4, "Aoû" => 7, "Déc" =>11,
		"fév" => 1, "avr" => 3, "mai" => 4, "aoû" => 7, "déc" =>11,
	);

#	return (1, "Time string is not provided")	if	($p_time =~ /^\s*$/);
	return( 0, "NULL" ) if( $p_time eq "" );
	return (0, $p_time)	if	($p_time =~ /^\d+$/);

	$Y = -1;
	$uts = 0;

	# Format: YYYY-MM-DD hh:mm:ss or YYYY/MM/DD hh:mm:ss
	if( $p_time =~ /(\d{4})[\/-](\d+)[\/-](\d+)\s+(\d+):(\d+):(\d+)/ )
	{
		$Y=$1; $M=$2-1; $D=$3; $h=$4; $m=$5; $s=$6;
	}

	# Format from 'wmdist -l -i <mdistid> -v': 2002.07.24 15:32:03
	elsif( $p_time =~ /(\d+)\.(\d+)\.(\d+)\s+(\d+):(\d+):(\d+)$/ )
	{
		$Y=$1; $M=$2-1; $D=$3; $h=$4; $m=$5; $s=$6;
	}

	# Format from logfile/wgetscanstat on Windows: MM/DD/YYYY hh:mm:ss [A|P]M
	elsif( $p_time =~ /(\d+)\/(\d+)\/(\d+)\s+(\d+):(\d+):(\d+)\s+(.)M/i ) 
	{
		$Y=$3; $M=$1-1; $D=$2; $h=$4; $m=$5; $s=$6; $aorp=$7;
		$h = 0 if( $h == 12 );
		$h += 12 if( $aorp eq "P" || $aorp eq "p" );	# adjust for PM
	}

	# Format from IC logfile on Windows: MM/DD/YYYY hh:mm:ss
	elsif( $p_time =~ /(\d+)\/(\d+)\/(\d+)\s+(\d+):(\d+):(\d+)/i ) 
	{
		$Y=$3; $M=$1-1; $D=$2; $h=$4; $m=$5; $s=$6;
	}

	# Format from logfile on UNIX: Mon Jan 25 hh:mm:ss [YY]YY
	elsif( $p_time =~ /(\S+)\s+(\S+)\s+(\d+)\s+(\d+):(\d+):(\d+)\s+(\d+)/ )
	{
		$Y=$7; $M=$month{$2}; $D=$3; $h=$4; $m=$5; $s=$6;
	}

	# Format from wdate on UNIX: Mon Jan 25 hh:mm:ss [UTC|GMT] [YY]YY
	elsif( $p_time =~ /(\S+)\s+(\S+)\s+(\d+)\s+(\d+):(\d+):(\d+)\s+[A-Za-z]+\s+(\d+)/ )
	{
		$Y=$7; $M=$month{$2}; $D=$3; $h=$4; $m=$5; $s=$6;
	}

	# French time format: Mon 25 Jan hh:mm:ss [UTC|GMT] [YY]YY
	elsif( $p_time =~ /(\S+)\s+(\d+)\s+(\S+)\s+(\d+):(\d+):(\d+)\s+[A-Za-z]+\s+(\d+)/ )
	{
		$Y=$7; $M=$month{$3}; $D=$2; $h=$4; $m=$5; $s=$6;
	}

	# Format from Inv 4.2.1 on UNIX: Mon 25 Jan YYYY hh:mm:ss [A|P]M EST
	elsif( $p_time =~ /^\s*\S+\s+(\d+)\s+(\S+)\s+(\d+)\s+(\d+):(\d+):(\d+)\s+(.)M/i )
	{
		$D=$1; $M=$month{$2}; $Y=$3; $h=$4; $m=$5; $s=$6; $aorp=$7;
		$h = 0 if( $h == 12 );
		$h += 12 if( $aorp eq "P" || $aorp eq "p" );	# adjust for PM
	}

	elsif	(($p_rel)&&($p_time =~ /\s*(\d+)\s*(h|d|m|y|hour|day|month|year|hours|days|months|years)\s*$/i))
	{
		my	(%seconds) = ( "H" => 3600, "D" => 86400, "M" => 2592000, "Y" => 31536000 );
		return (0, time () - ($1 * $seconds{substr ("\U$2", 0, 1)}));
	}

	else
	{
		return (1, "Cannot convert time '$p_time' to UTS");
	}

	unless( $Y == -1 )
	{
		# Adjust the year in preparation of mktime call
		if( $Y > 1900 ) { $Y -= 1900; }
		elsif ($Y < 70) { $Y += 100; }
	}

	# Since we only define English and French months, check if months field defined before converting to UTS
	return( 1, "Cannot convert time '$p_time' to UTS. Please check 'lib/EQCommonLib' for proper month conversion" )
		unless( defined($M) );
		
	# Get the number of seconds since Jan 1, 1970 GMT
	$uts = &POSIX::mktime( $s, $m, $h, $D, $M, $Y, "", "", -1 );

	return (0, $uts);
	
}	# end of EQ String To Time


#---------------------------------------------------------
#	EQ Time To String
#---------------------------------------------------------
sub	EQ_TimeToString
{
	my	($p_time) = @_;
	my	($rel, $time, @a);

	#return (1, "Time is not provided")	if	($p_time =~ /^\s*$/);
	return( 0, "NULL" ) if( $p_time eq "" );
	return (0, $p_time)	if	($p_time !~ /^([\+\-]?)(\d+)$/);

	$rel = (defined ($1))? $1: "";
	$time = $2;

	$time = time() + ($rel eq "+")? $time: -$time	if	($rel ne "");
	@a = localtime ($time);

	return (0, sprintf ("%04d-%02d-%02d %02d:%02d:%02d",
		$a[5] + 1900, $a[4] + 1, $a[3], $a[2], $a[1], $a[0]));
}

# EQ GUI uses different time format than EQ_StringToTime suboutine:
#   YYYY/MONTH/DD HH:MM:SS
sub	EQ_DateTimeToUTS
{
	my	($p_time) = @_;

	return (1, "Date/time should be in format YYYY/MONTH/DD HH:MM:SS or YYYY/MONTH/DD HH:MM")
		if	($p_time !~ m#^\s*(\d+)/(\w+)/(\d+)\s+(\d+):(\d+)(?::(\d+))?\s*$#);
	my	$year = $1;
	my	$month = $2;
	my	$day = $3;
	my	$hr = $4;
	my	$min = $5;
	my	$sec = $6 || 0;

	# Check MIN/MAX thresholds
	return (1, "Invalid year specified")
		if (($year < 1970)||($year > 2020));
	if ($month =~ /^\d+$/)
	{
		return (1, "Invalid month '$month' specified")
			if	(($month < 1)||($month > 12));
	}
	else
	{
		$month = $x__cl_months{uc($month)};
		return (1, "Invalid month specified")	if (!$month);
	}
	return (1, "Invalid day specified")
		if	(($day < 1)||($day > 31));
	return (1, "Invalid hour specified")
		if( $hr < 0 || $hr > 23 );
	return (1, "Invalid minute specifed")
		if( $min < 0 || $min > 59 );
	return (1, "Invalid seconds specified")
		if	(($sec < 0)||($sec > 59));

	$month--;
	$year -= 1900;

	# Get the number of seconds since Jan 1, 1970 GMT
	my	$uts = &POSIX::mktime($sec, $min, $hr, $day, $month, $year, "", "", -1);

	return (0, $uts);
}

# EQ_DateToUTS returns UTS of the date, i.e. time is assumed to  be 00:00:00
sub	EQ_DateToUTS
{
	my	($p_time) = @_;

	return (1, "Date/time should be in format YYYY/MONTH/DD")
		if	($p_time !~ m#^(\d+)/(\w+)/(\d+)$#);
	my	$year = $1;
	my	$month = $2;
	my	$day = $3;

	# Check MIN/MAX thresholds
	return (1, "Invalid year specified")
		if (($year < 1970)||($year > 2020));
	if (($month =~ /^\d+$/)&&(($month < 1)||($month > 12)))
	{
		return (1, "Invalid month specified");
	}
	else
	{
		$month = $x__cl_months{uc($month)};
		return (1, "Invalid month specified")	if (!$month);
	}
	return (1, "Invalid day specified")
		if	(($day < 1)||($day > 31));

	$month--;
	$year -= 1900;

	# Get the number of seconds since Jan 1, 1970 GMT
	my	$uts = &POSIX::mktime (0, 0, 0, $day, $month, $year, "", "", -1);

	return (0, $uts);
}

sub	EQ_UTSToDateTime
{
	my	($p_time) = @_;

	my @a = localtime($p_time);
	return sprintf ("%04d/%02d/%02d %02d:%02d:%02d",
		$a[5] + 1900, $a[4] + 1, $a[3], $a[2], $a[1], $a[0]);
}

# This subroutine returns date, calculated as a relative (-/+ N days/months/years)
# to current date
sub	EQ_GetRelativeDate
{
	my	($p_rel, $p_time) = @_;
	my	@days_per_month = ( 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 );

	if	($p_rel !~ /^([\+\-])(\d*)([dmy])$/)
	{
		warn ("Invalid relative date '$p_rel': $!\n");
		return '';
	}

	my	$n = $2 || 1;
	$n = -$n	if	($1 eq '-');
	my	$unit = $3;

	my	$time = time ();
	my	(@a, $m, $d, $y);
	if	($unit eq 'd')
	{
		$time += ($n * 86400);
		@a = gmtime ($time);
	}
	elsif	($unit eq 'm')
	{
		@a = gmtime ($time);
		$m = $a[4];
		$y = $a[5];
		my	$incm = abs ($n);
		my	$incy = int ($incm / 12);
		$incm = $incm % 12;
		# If the date is in the past
		if	($n < 0)
		{
			$m -= $incm;
			if	($m < 0)
			{
				$m += 12;
				$y--;
			}
			$y -= $incy;
		}
		else
		{
			$m += $incm;
			if	($m > 11)
			{
				$m -= 12;
				$y++;
			}
			$y += $incy;
		}
		$a[4] = $m;
		$a[5] = $y;
	}
	elsif	($unit eq 'y')
	{
		@a = gmtime ($time);
		$a[5] += $n;
	}

	# Make sure that the date is valid
	$d = $a[3];
	$m = $a[4];
	$y = $a[5];
	if	($d > $days_per_month[$m])
	{
		if	($n < 0)
		{
			$d = $days_per_month[$m];
		}
		else
		{
			$d = 1;
			$m++;
			if	($m > 11)
			{
				$m -= 12;
				$y++;
			}
		}
	}

	# Adjust date if necessary it falls on February 29
	if	(($m == 1)&&($d == 29))
	{
		# Determine if the year is a leap year
		my	$leap = ($y % 4)? 0: (($y % 100)? 1: (($y % 400)? 0: 1));
		if	(!$leap)
		{
			if	($n < 0)
			{
				$d = 28;
			}
			else
			{
				$d = 1;
				$m = 3;
			}
		}
	}

	$m++;
	$y += 1900;
	return "$m/$d/$y";
}

1;
