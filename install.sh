#!/bin/bash

clear

osDebian="no"

d=$(dirname $0)

MIRROR="https://mirror.gsmanager.ru"

##
## Debian
##
if [ -f "/etc/debian_version" ]; then
	ver=`cat /etc/issue.net | awk '{print $1$3}'`
	echo "Detected OS Version: "$ver

# Debian 8
if [ $ver = "Debian8" ]; then
	osDebian="yes"
	apt-get install -y --force-yes wget > /dev/null 2>&1
	echo -en "Download install script... "
	rm -f ${d}/deb.install.sh
	wget --no-check-certificate -t 2 $MIRROR/install/deb.install.sh > /dev/null 2>&1
	if [ $? -eq 0 ]; then
		echo -en "\033[1;32m [OK] \033[0m\n"
		tput sgr0
	else
		echo -en "\033[1;31m [ERROR] \033[0m\n"
		tput sgr0 
		exit
	fi
exit 0
fi

fi

echo -en "\033[1;31mSystem not found!!!\033[0m"
tput sgr0
exit 0
