## eQ Server

Capital Software began development of enterprise-Q in 1998 and still continues to enhance and support it today.  One of the core components of enterprise-Q is the backend queuing server call eQServer; enterprise queue server.  eQServer is a TCP/IP-based server daemon used to initiate, track, throttle, retry, and report on thousands of "transactions".  An eQServer "transaction" is the execution of a program/script given a "target" for the script.  A "target" can be a computer, agent, web server, user, or anything else.  Companies have used eQServer to execute literally tens of millions of transactions, automating their entire enterprise management operations around the eQServer.

Functional examples of a "transaction" include:
* Run a task on a remote system
* Ping a host
* wget a web page from a remote server and measure response
* Push monitors and/or pull monitoring data to/from a remote system
* Software distribution
* Inventory
* etc.

enterprise-Q was originally developed to integrate with IBM Tivoli software.  However, eQServer has never been Tivoli-centric.  That is, eQServer is independent, stand-alone software that can run on any platform that supports Perl 5 and has been deployed in production environments running on Windows, Linux, AIX, and Solaris.  As such, we provide everything you need here to build eQServer on all of those operating systems.  Pre-built distributions of eQServer can be downloaded from our [website] (http://www.eQServer.org).  

Technical details about the eQ Server are documented in the [eQ Technical Reference] (http://www.eqserver.org/documents/EQServerTechRef.pdf)


## Installation Process

EQServer can be installed from sources with only Perl 5 as a prerequisite (versions available on our website).  If you wish to use your own installation of perl, make sure it has DBI and DBD::SQLite module installed.

1. Download ZIP and extract or 'git clone git://github.com/deansleonard/EQServer'
1. Change into the **EQServer** subdirectory.
1. Download Perl5 for your platform from our website:
	* [Perl5 for Windows] (http://www.eqserver.org/downloads/windows/perl5.tar)
	* [Perl5 for Linux] (http://www.eqserver.org/downloads/linux/perl5.tar)
	* [Perl5 for AIX] (http://www.eqserver.org/downloads/aix/perl5.tar)
	* [Perl5 for Solaris] (http://www.eqserver.org/downloads/solaris/perl5.tar)
1. Extract **perl5.tar** into **EQServer** subdirectory, creating a subdirectory named **perl5**:
	* Windows: Use WinZip or some other extraction application
	* Unix-base: **tar xvf /path/to/perl5.tar**
1. Run install script. If you're using your own version of Perl, first edit the script to set EQPERL to the correct path:
	* Windows: **Install-EQServer.bat**
	* Unix-base: **Install-EQServer.sh**

Please note that, after running the install, some shared library files will be renamed and other deleted, such as files not required for your platform, but all the core perl scripts remain the same.


## Build Process

EQServer can also be built into an installable package  

To build eQServer follow installation steps 1-4, then:

1. Change current working directory **EQServer/build/**
1. Run build script. If you're using your own version of Perl, first edit the script to set EQPERL to the correct path:
	* Windows: **Build-EQServer.bat**
	* Unix-base: **Build-EQServer.sh**
1. This creates an archive file in the current working directory named **EQServer-\<version\>-\<date\>.\[zip\|tar\]**.

## Deploying

After building eQ Server, you will find either a WinZip file (Windows) or tar file (Unix-base) in the **build** subdirectory.  This can be deployed, extracted, and installed using the [eQ Server Installation Guide] (http://www.eqserver.org/documents/EQServerInstallation.pdf)


## Contributing changes

* See [CONTRIB.md](CONTRIB.md)


## Licensing

* See [LICENSE](license/LICENSE)
