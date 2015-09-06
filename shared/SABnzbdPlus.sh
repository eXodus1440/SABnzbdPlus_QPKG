#!/bin/sh
CONF=/etc/config/qpkg.conf
QPKG_NAME="SABnzbdPlus"
QPKG_ROOT=`/sbin/getcfg $QPKG_NAME Install_Path -f ${CONF}`
ENABLED=$(/sbin/getcfg $QPKG_NAME Enable -u -d FALSE -f $CONF)
PUBLIC_SHARE=`/sbin/getcfg SHARE_DEF defPublic -d Public -f /etc/config/def_share.info`
API_KEY=`/sbin/getcfg misc api_key -f ${QPKG_ROOT}/.sabnzbd/sabnzbd.ini`
WEBUI_USER=`/sbin/getcfg misc username -f ${QPKG_ROOT}/.sabnzbd/sabnzbd.ini`
WEBUI_PASS=`/sbin/getcfg misc password -f ${QPKG_ROOT}/.sabnzbd/sabnzbd.ini`
SHUTDOWN_WAIT=25

# Determine IP being used
WEBUI_IP=`/sbin/getcfg misc host -f ${QPKG_ROOT}/.sabnzbd/sabnzbd.ini`
if [ -z ${WEBUI_IP} ]; then WEBUI_IP="0.0.0.0" ; fi

# Determine protocol & port being used
WEBUI_HTTPS=$(/sbin/getcfg misc enable_https -f ${QPKG_ROOT}/.sabnzbd/sabnzbd.ini)
if [ "$WEBUI_HTTPS" = "0" ]; then
  WEBUI_PORT=`/sbin/getcfg misc port -f ${QPKG_ROOT}/.sabnzbd/sabnzbd.ini`
else
  WEBUI_PORT=`/sbin/getcfg misc https_port -f ${QPKG_ROOT}/.sabnzbd/sabnzbd.ini`
fi
if [ -z ${WEBUI_PORT} ]; then WEBUI_PORT=8085 ; fi # Default to port 8085

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
####

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
    # Check if enabled
    #ENABLED=$(/sbin/getcfg $QPKG_NAME Enable -u -d FALSE -f $CONF)
    if [ "$ENABLED" != "TRUE" ]; then
      echo "$QPKG_NAME is disabled."
      exit 1
    fi

    # Check if instance already exist
    if [ -f ${QPKG_ROOT}/sabnzbd-${WEBUI_PORT}.pid ]; then
      echo "$QPKG_NAME is currently running or hasn't been shutdown properly."
      echo "Please stop it before starting a new instance."
      exit 1
    fi

    # Create symlinks
    echo "Creating symlinks ..."
    [ -d ${QPKG_ROOT}/.sabnzbd/Downloads ] || /bin/ln -sf ${BASE}/${PUBLIC_SHARE}/Downloads ${QPKG_ROOT}/.sabnzbd/Downloads
    [ -d /root/.sabnzbd ] || /bin/ln -sf ${QPKG_ROOT}/.sabnzbd /root/.sabnzbd
    [ -d /root/Downloads ] || /bin/ln -sf ${BASE}/${PUBLIC_SHARE}/Downloads /root/Downloads
    [ -d /root/nzb ] || /bin/ln -sf ${BASE}/${PUBLIC_SHARE}/nzb /root/nzb
    [ -h /usr/bin/nice ] || /bin/ln -sf ${QPKG_ROOT}/bin-utils/nice /usr/bin/nice
    [ -h /usr/bin/ionice ] || /bin/ln -sf ${QPKG_ROOT}/bin-utils/ionice /usr/bin/ionice
    [ -h /usr/bin/unrar ] || /bin/ln -sf /opt/bin/unrar /usr/bin/unrar
    [ -h /usr/bin/par2 ] || /bin/ln -sf /opt/bin/par2 /usr/bin/par2
    [ -h /opt/lib/python2.6/site-packages/yenc.py ] || /bin/ln -sf ${QPKG_ROOT}/lib/yenc.py /opt/lib/python2.6/site-packages/yenc.py
    [ -h /opt/lib/python2.6/site-packages/_yenc.so ] || /bin/ln -sf ${QPKG_ROOT}/lib/_yenc.so /opt/lib/python2.6/site-packages/_yenc.so

    # Start SABnzbdPlus
    /opt/bin/python2.6 ${QPKG_ROOT}/SABnzbd.py -s ${WEBUI_IP}:${WEBUI_PORT} -b 0 --pid ${QPKG_ROOT} -f /root/.sabnzbd/sabnzbd.ini -d

    ;;

  stop)
    # Stop SABnzbdPlus
    if [ -f "$QPKG_ROOT/sabnzbd-$WEBUI_PORT.pid" ]; then
      PID=$(cat ${QPKG_ROOT}/sabnzbd-${WEBUI_PORT}.pid)
      if [ `ps ax | grep -v grep | grep -c ${PID}` = '0' ]; then
        echo "$QPKG_NAME not running, cleaning up ${QPKG_ROOT}/sabnzbd-${WEBUI_PORT}.pid ..."
        /bin/rm -f ${QPKG_ROOT}/sabnzbd-$WEBUI_PORT.pid
      else
        echo "Stopping $QPKG_NAME ..."
        WEBUI_PASS=`sed -e 's/^"//' -e 's/"$//' <<< $WEBUI_PASS`
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
            kill -9 ${PID}
            kill -9 `ps ax | grep 'par2' | grep -v grep | awk ' { print $1;}'`

            # Clean up PIDFile
            if [ -f ${QPKG_ROOT}/sabnzbd-$WEBUI_PORT.pid ] ; then /bin/rm -f ${QPKG_ROOT}/sabnzbd-$WEBUI_PORT.pid ; fi
          fi
        fi
      fi
    fi
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

