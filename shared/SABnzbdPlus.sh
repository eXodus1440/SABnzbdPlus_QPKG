#!/bin/sh
CONF=/etc/config/qpkg.conf
QPKG_NAME="SABnzbdPlus"
QPKG_DIR=`/sbin/getcfg $QPKG_NAME Install_Path -f ${CONF}`
PUBLIC_SHARE=`/sbin/getcfg SHARE_DEF defPublic -d Public -f /etc/config/def_share.info`
WEBUI_IP=`/sbin/getcfg misc host -f ${QPKG_DIR}/.sabnzbd/sabnzbd.ini`
API_KEY=`/sbin/getcfg misc api_key -f ${QPKG_DIR}/.sabnzbd/sabnzbd.ini`
WEBUI_USER=`/sbin/getcfg misc username -f ${QPKG_DIR}/.sabnzbd/sabnzbd.ini`
WEBUI_PASS=`/sbin/getcfg misc password -f ${QPKG_DIR}/.sabnzbd/sabnzbd.ini`
SHUTDOWN_WAIT=300

# Determine Protocol being used: http/https
WEBUI_HTTPS=$(/sbin/getcfg misc enable_https -f ${QPKG_DIR}/.sabnzbd/sabnzbd.ini)
if [ "$WEBUI_HTTPS" = "0" ]; then
  WEBUI_PORT=`/sbin/getcfg misc port -f ${QPKG_DIR}/.sabnzbd/sabnzbd.ini`
else
  WEBUI_PORT=`/sbin/getcfg misc https_port -f ${QPKG_DIR}/.sabnzbd/sabnzbd.ini`
fi

# Determine BASE installation location according to smb.conf
BASE=
publicdir=`/sbin/getcfg $PUBLIC_SHARE path -f /etc/config/smb.conf`
if [ ! -z $publicdir ] && [ -d $publicdir ];then
  publicdirp1=`/bin/echo $publicdir | /bin/cut -d "/" -f 2`
  publicdirp2=`/bin/echo $publicdir | /bin/cut -d "/" -f 3`
  publicdirp3=`/bin/echo $publicdir | /bin/cut -d "/" -f 4`
  if [ ! -z $publicdirp1 ] && [ ! -z $publicdirp2 ] && [ ! -z $publicdirp3 ]; then
    [ -d "/${publicdirp1}/${publicdirp2}/${PUBLIC_SHARE}" ] && BASE="/${publicdirp1}/${publicdirp2}"
  fi
fi

# Determine BASE installation location by checking where the Public folder is.
if [ -z $BASE ]; then
  for datadirtest in /share/HDA_DATA /share/HDB_DATA /share/HDC_DATA /share/HDD_DATA /share/MD0_DATA; do
    [ -d $datadirtest/$PUBLIC_SHARE ] && BASE="/${publicdirp1}/${publicdirp2}"
  done
fi
if [ -z $BASE ] ; then
  echo "The Public share not found."
  /sbin/write_log "[$QPKG_NAME] The Public share not found." 1
  exit 1
fi

####

case "$1" in
  start)
    #ENABLED=$(/sbin/getcfg $QPKG_NAME Enable -u -d FALSE -f $CONF)
    #if [ "$ENABLED" != "TRUE" ]; then
    #    echo "$QPKG_NAME is disabled."
    #    exit 1
    #fi

    if [ -f ${QPKG_DIR}/sabnzbd-${WEBUI_PORT}.pid ]; then
      echo "$QPKG_NAME is currently running or hasn't been shutdown properly. Please stop it before starting a new instance."
      exit 1
    fi
  
    echo "Creating symlinks ..."
    [ -d $QPKG_DIR}/.sabnzbd/Downloads ] || /bin/ln -sf ${BASE}/${PUBLIC_SHARE}/Downloads $QPKG_DIR}/.sabnzbd/Downloads
    [ -d /root/.sabnzbd ] || /bin/ln -sf ${QPKG_DIR}/.sabnzbd /root/.sabnzbd
    [ -d /root/Downloads ] || /bin/ln -sf ${BASE}/${PUBLIC_SHARE}/Downloads /root/Downloads
    [ -d /root/nzb ] || /bin/ln -sf ${BASE}/${PUBLIC_SHARE}/nzb /root/nzb
    [ -f /usr/bin/ionice ] || /bin/rm -f /usr/bin/ionice
    [ -f /opt/lib/python2.6/site-packages/yenc.py ] || /bin/rm -f /opt/lib/python2.6/site-packages/yenc.py
    [ -f /opt/lib/python2.6/site-packages/_yenc.so ] || /bin/rm -f /opt/lib/python2.6/site-packages/_yenc.so

    echo "Starting $QPKG_NAME ..."
    if [ -f /root/.sabnzbd/sabnzbd.ini ]; then
      /opt/bin/python2.6 ${QPKG_DIR}/SABnzbd.py --pid ${QPKG_DIR} -f /root/.sabnzbd/sabnzbd.ini -d &
    else
      # Start on port 8085 by default
      /opt/bin/python2.6 ${QPKG_DIR}/SABnzbd.py -s 0.0.0.0:8085 -b 0 --pid ${QPKG_DIR} &
    fi

    # Enabling SABnzbdPlus within qpkg.conf
    /sbin/setcfg $QPKG_NAME Enable TRUE -f $CONF
    ;;

  stop)
    if [ -f "$QPKG_DIR/sabnzbd-$WEBUI_PORT.pid" ]; then
      PID=$(cat ${QPKG_DIR}/sabnzbd-${WEBUI_PORT}.pid)
      if [ `ps ax | grep -v grep | grep -c ${PID}` = '0' ]; then
        echo "$QPKG_NAME not running, cleaning up ${QPKG_DIR}/sabnzbd-${WEBUI_PORT}.pid ..."
        /bin/rm -f ${QPKG_DIR}/sabnzbd-$WEBUI_PORT.pid
      else
        echo "Stopping $QPKG_NAME ..."
        if [ -n ${WEBUI_PASS} ]; then
          /usr/bin/wget -q --delete-after "http://${WEBUI_IP}:${WEBUI_PORT}/sabnzbd/api?mode=shutdown&apikey=${API_KEY}" &
        else
          /usr/bin/wget -q --delete-after "http://${WEBUI_IP}:${WEBUI_PORT}/sabnzbd/api?mode=shutdown&ma_username=${WEBUI_USER}&ma_password=${WEBUI_PASS}&apikey=${API_KEY}" &
        fi

        # Waiting for SABnzbdPlus to shutdown gracefully
        if [ -n ${PID} ]; then
          KWAIT=${SHUTDOWN_WAIT}
          COUNT=0
          until [ `ps ax | grep -v grep | grep -c ${PID}` = '0' ] || [ "${COUNT}" -gt "${KWAIT}" ]
          do
            echo "Waiting ${COUNT}/${SHUTDOWN_WAIT} seconds for ${QPKG_NAME} processes to exit ..."
            sleep 1
            COUNT=$(( $COUNT + 1 ))
          done
        
          # Killing SABnzbdPlus and par2 after SHUTDOWN_WAIT period
          if [ "${COUNT}" -gt "${KWAIT}" ]; then
            echo "Killing ${QPKG_NAME} processes which didn't stop after ${SHUTDOWN_WAIT} seconds"
            kill -9 `ps ax | grep 'SABnzbd' | grep -v grep | awk ' { print $1;}'`
            kill -9 `ps ax | grep 'par2' | grep -v grep | awk ' { print $1;}'`
          fi
        fi
      fi
    fi

    # Cleaning up other items
    /bin/sleep 2
    
    # Clean up symlinks in event that SABnzbdPlus was shutdown outside QPKG manager
    echo "Removing symlinks ..."
    if [ -d $QPKG_DIR}/.sabnzbd/Downloads ]; then /bin/rm -rf $QPKG_DIR}/.sabnzbd/Downloads ; fi
    if [ -d /root/.sabnzbd ]; then /bin/rm -rf /root/.sabnzbd ; fi
    if [ -d /root/Downloads ]; then /bin/rm -rf /root/Downloads ; fi
    if [ -d /root/nzb ]; then /bin/rm -rf /root/nzb ; fi
    if [ -f /usr/bin/ionice ]; then /bin/rm -f /usr/bin/ionice ; fi
    if [ -f /opt/lib/python2.6/site-packages/yenc.py ]; then /bin/rm -f /opt/lib/python2.6/site-packages/yenc.py ; fi
    if [ -f /opt/lib/python2.6/site-packages/_yenc.so ]; then /bin/rm -f /opt/lib/python2.6/site-packages/_yenc.so ; fi

    # Disabling SABnzbdPlus within qpkg.conf
    /sbin/setcfg $QPKG_NAME Enable FALSE -f $CONF
    exit 0
    ;;

  restart)
    $0 stop
    $0 start
    ;;

  *)
    echo "Usage: $0 {start|stop|restart}"
    exit 1
esac

exit 0