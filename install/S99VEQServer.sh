#!/bin/sh
#
# Copyright (c) 2001 by Capital Software Corporation.
# All rights reserved.
#

case "$1" in
start)
#	su - ~UID~ -c "nohup ~EQ_PATH~/bin/EQServer > ~EQ_PATH~/temp/EQServer.nohup 2>&1 &"
su - Dean -c "nohup C:/dean/EQ-Working/EQServer/bin/EQServer > C:/dean/EQ-Working/EQServer/temp/EQServer.nohup 2>&1 &"
																MSG="starting"
	;;
restart)
#	su - ~UID~ -c "~EQ_PATH~/bin/EQMsg t_msg=stop; sleep 5; nohup ~EQ_PATH~/bin/EQServer > ~EQ_PATH~/temp/EQServer.nohup 2>&1 &"
su - Dean -c "C:/dean/EQ-Working/EQServer/bin/EQMsg t_msg=stop; sleep 5; nohup C:/dean/EQ-Working/EQServer/bin/EQServer > C:/dean/EQ-Working/EQServer/temp/EQServer.nohup 2>&1 &"
																MSG="restarting"
	;;
stop)
#	su - ~UID~ -c "~EQ_PATH~/bin/EQMsg t_msg=stop"
su - Dean -c "C:/dean/EQ-Working/EQServer/bin/EQMsg t_msg=stop"
																MSG="stopping"
	;;
*)
	echo "Usage: $0 {start|stop|restart}"
	exit 1
	;;
esac

echo "EQServer $MSG."

exit 0
