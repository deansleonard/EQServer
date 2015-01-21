#!/bin/sh

# $Id: EQServer-PostInstall-linux.sh,v 1.2 2014/11/06 23:35:27 eqadmin Exp $

#
# EQ Post Install -  Run as root to configure enterprise-Q to start automatically after boot
#

set +x

#cd ~EQ_PATH~/install
cd C:/dean/EQ-Working/EQServer/install

#cp		S50apache.sh			/etc/init.d
#cp		S99VEQScheduler.sh		/etc/init.d
cp		S99VEQServer.sh			/etc/init.d

cd /etc/init.d

#ln -s 	./S50apache.sh			/etc/rc.d/rc3.d/S50apache
#ln -s 	./S99VEQScheduler.sh	/etc/rc.d/rc3.d/S99VEQScheduler
ln -s 	./S99VEQServer.sh		/etc/rc.d/rc3.d/S99VEQ

#ln -s 	./S50apache.sh			/etc/rc.d/rc2.d/K50apache
#ln -s 	./S99VEQScheduler.sh	/etc/rc.d/rc2.d/K20VEQScheduler
ln -s 	./S99VEQServer.sh		/etc/rc.d/rc2.d/K20VEQ
