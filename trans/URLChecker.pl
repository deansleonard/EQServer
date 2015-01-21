#!C:/dean/EQ-Working/EQServer/perl5/bin/perl
#
#	$Id$
#
# Queue this transaction script using:
#
#	<eq>/bin/EQMsg "t_msg=Add;t_trans=URLChecker;t_target=<target>[;wgetpath=/path/to/wget/directory;webPage=index.html]
#
# Keywords passed via environment variables prefixing each with 'EQ_'.
# EQServer reserved keywords will be all caps. 
# Application keywords case sensitive.  Notice 'wgetpath' and 'WebPage' set to 'EQ_wgetpath' and 'EQ_WebPage', respectively
#

my $wget = $ENV{EQ_wgetpath} ? $ENV{EQ_wgetpath} . "/wget" : "wget";	
my $result = `$wget --delete-after http://$ENV{EQ_T_TARGET}/$ENV{EQ_webPage} 2>&1`;
my $err = $? ? 1 : 0;
print $result;
exit( $err );
