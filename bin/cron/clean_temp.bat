@echo off
REM $Id: clean_temp.bat,v 1.3 2014/11/06 23:32:01 eqadmin Exp $
REM Batch script used to run clean_temp.pl perl script.
REM This script should be called from NT's AT command.
set SETUP_ENV=%WINDIR%\system32\drivers\etc\tivoli\setup_env.cmd
IF EXIST %SETUP_ENV% (
	call %SETUP_ENV%
)

rem ~EQ_DRIVE~
C:

rem set EQHOME=~EQ_PATH~\.
set EQHOME=C:\dean\EQ-Working\EQServer\.

%EQHOME%\perl5\bin\perl -I %EQHOME%\perl5\lib %EQHOME%\bin\clean_temp.pl > %EQHOME%\temp\clean_temp.out
