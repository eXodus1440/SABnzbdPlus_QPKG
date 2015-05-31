#!/bin/sh

RETVAL=0
QDOWNLOAD=`/sbin/getcfg SHARE_DEF defDownload -d Qdownload -f /etc/config/def_share.info`
QPKG_NAME=SABnzbdplus
QPKG_BASE=
QPKG_DIR=
PATH=/opt/bin:$PATH


find_base(){
	# Determine BASE installation location according to smb.conf
	publicdir=`/sbin/getcfg Public path -f /etc/config/smb.conf`
	if [ ! -z $publicdir ] && [ -d $publicdir ];then
	        publicdirp1=`/bin/echo $publicdir | /bin/cut -d "/" -f 2`
	        publicdirp2=`/bin/echo $publicdir | /bin/cut -d "/" -f 3`
	        publicdirp3=`/bin/echo $publicdir | /bin/cut -d "/" -f 4`
	        if [ ! -z $publicdirp1 ] && [ ! -z $publicdirp2 ] && [ ! -z $publicdirp3 ]; then
	                [ -d "/${publicdirp1}/${publicdirp2}/Public" ] && QPKG_BASE="/${publicdirp1}/${publicdirp2}"
	        fi
	fi

	# Determine BASE installation location by checking where the Public folder is.
	if [ -z $QPKG_BASE ]; then
	        for datadirtest in /share/HDA_DATA /share/HDB_DATA /share/HDC_DATA /share/HDD_DATA /share/MD0_DATA /share/MD1_DATA; do
			  [ -d $datadirtest/Public ] && QPKG_BASE="$datadirtest"
	        done
	fi
	if [ -z $QPKG_BASE ] ; then
	        echo "The Public share not found."
	        exit 1
	fi
	QPKG_DIR=${QPKG_BASE}/.qpkg/${QPKG_NAME}
}

case "$1" in
  start)
	#Does /opt exist? if not check if it's optware that's installed or opkg, and start the package 
	if [ ! -d /opt/bin ]; then
		/bin/echo "/opt not found, enabling optware or opkg..."
		#if optware start optware
		[ -x /etc/init.d/Optware.sh ] && /etc/init.d/Optware.sh start
		#if opkg, start opkg
		[ -x /etc/init.d/opkg.sh ] && /etc/init.d/opkg.sh start
		/bin/sync
		sleep 2
	fi

	find_base
	SABNZBD="/opt/bin/python2.6 SABnzbd.py"
	OPTIONS="-f Config/sabnzbd.ini -l 0 -b 0 -d"

	  REAL_PATH=`/sbin/getcfg ${QDOWNLOAD} path -f /etc/config/smb.conf -d /ERROR`
	  if [ ! -d $REAL_PATH ] || [ ! -d "/share/${QDOWNLOAD}" ]; then
	 		echo "${QDOWNLOAD} not ready."
	 		exit 1
	  fi
	

	  if [ `/sbin/getcfg ${QPKG_NAME} Enable -u -d FALSE -f /etc/config/qpkg.conf` = UNKNOWN ]; then
	  	/sbin/setcfg ${QPKG_NAME} Enable TRUE -f /etc/config/qpkg.conf
	  elif [ `/sbin/getcfg ${QPKG_NAME} Enable -u -d FALSE -f /etc/config/qpkg.conf` != TRUE ]; then
	  	echo "${QPKG_NAME} is disabled."
	  	exit 1
	  fi
	  
		echo -n "Starting ${QPKG_NAME}... "
		[ -d "/share/${QDOWNLOAD}/sabnzbd" ] || /bin/mkdir "/share/${QDOWNLOAD}/sabnzbd"
		/bin/chmod 777 /share/${QDOWNLOAD}/sabnzbd	
		[ -d "/share/${QDOWNLOAD}/sabnzbd/temp" ] || /bin/mkdir -p "/share/${QDOWNLOAD}/sabnzbd/temp"
		/bin/chmod 777 /share/${QDOWNLOAD}/sabnzbd/temp	
		[ -d "/share/${QDOWNLOAD}/sabnzbd/complete" ] || /bin/mkdir "/share/${QDOWNLOAD}/sabnzbd/complete"
		/bin/chmod 777 /share/${QDOWNLOAD}/sabnzbd/complete	
		[ -d "/share/${QDOWNLOAD}//sabnzbd/incomplete" ] || /bin/mkdir -p "/share/${QDOWNLOAD}/sabnzbd/incomplete"
		/bin/chmod 777 /share/${QDOWNLOAD}/sabnzbd/incomplete	
		[ -d "/share/${QDOWNLOAD}/sabnzbd/logs" ] || /bin/mkdir -p "/share/${QDOWNLOAD}/sabnzbd/logs"
		/bin/chmod 777 /share/${QDOWNLOAD}/sabnzbd/logs
		[ -d "/share/${QDOWNLOAD}/sabnzbd/nzb" ] || /bin/mkdir -p "/share/${QDOWNLOAD}/sabnzbd/nzb"
		/bin/chmod 777 /share/${QDOWNLOAD}/sabnzbd/nzb	
		[ -d "/share/${QDOWNLOAD}/sabnzbd/nzb/backup" ] || /bin/mkdir -p "/share/${QDOWNLOAD}/sabnzbd/nzb/backup"
		/bin/chmod 777 /share/${QDOWNLOAD}/sabnzbd/nzb/backup	
		
		#create symbolic links for required bin-utils and library files
		/bin/ln -sf "${QPKG_DIR}/bin-utils/ionice" "/usr/bin/ionice"		
		/bin/ln -sf "${QPKG_DIR}/lib/_yenc.so" "/opt/lib/python2.6/site-packages/_yenc.so" 
		/bin/ln -sf "${QPKG_DIR}/lib/yenc.py" "/opt/lib/python2.6/site-packages/yenc.py" 

		# starting sabnzbd...
		echo " Daemonizing... "
		cd $QPKG_DIR
		${SABNZBD} ${OPTIONS}
		RETVAL=$?
	;;
  stop)
		echo "Shutting down ${QPKG_NAME}... "
		for pid in $(/bin/pidof python2.6); do
		   /bin/grep -q "SABnzbd.py" /proc/$pid/cmdline && /bin/kill $pid
		done
		
		#give sab 5 seconds to shut down gracefully
		/bin/sleep 5
		
		#final check if sab has really stopped, kill forced if needed
	        for pid in $(/bin/pidof python); do
       		   /bin/grep -q "SABnzbd.py" /proc/$pid/cmdline && /bin/kill -9 $pid
	        done
		sync

 		RETVAL=$?
	;;
  restart)
		$0 stop
		$0 start
		RETVAL=$?
	;;
  *)
	echo "Usage: $0 {start|stop|restart}"
	exit 1
esac

exit $RETVAL