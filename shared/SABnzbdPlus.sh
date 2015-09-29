#!/bin/sh
CONF=/etc/config/qpkg.conf
CMD_GETCFG="/sbin/getcfg"
CMD_SETCFG="/sbin/setcfg"

QPKG_NAME="SABnzbdPlus"
QPKG_ROOT=$(${CMD_GETCFG} ${QPKG_NAME} Install_Path -f ${CONF})
PYTHON_DIR="/usr/bin"
#PATH="${QPKG_ROOT}/bin:${QPKG_ROOT}/env/bin:${PYTHON_DIR}/bin:/usr/local/bin:/bin:/usr/bin:/usr/syno/bin"
PYTHON="${PYTHON_DIR}/python2.7"
SABNZBD="${QPKG_ROOT}/SABnzbd.py"
QPKG_DATA=${QPKG_ROOT}/.sabnzbd
QPKG_CONF=${QPKG_DATA}/sabnzbd.ini
WEBUI_PORT=$(${CMD_GETCFG} misc port -f ${QPKG_CONF})
QPKG_PID=${QPKG_ROOT}/sabnzbd-${WEBUI_PORT}.pid
# Determine IP being used
WEBUI_IP=$(${CMD_GETCFG} misc host -f ${QPKG_CONF})
if [ -z ${WEBUI_IP} ]; then WEBUI_IP="0.0.0.0" ; fi

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

start_daemon() {
  ${PYTHON} ${SABNZBD} -s ${WEBUI_IP}:${WEBUI_PORT} -b 0 --pid ${QPKG_ROOT} -f ${QPKG_CONF} -d
}

stop_daemon() {
  kill $(cat ${QPKG_PID})
  wait_for_status 1 20
  if [ -f ${QPKG_PID} ] ; then rm -f ${QPKG_PID} ; fi
}

daemon_status() {
  if [ -f ${QPKG_PID} ] && [ -d /proc/$(cat ${QPKG_PID} 2>/dev/null) ]; then
    return 0
  fi
  return 1
}

wait_for_status() {
  counter=$2
  while [ ${counter} -gt 0 ]; do
    daemon_status
    [ $? -eq $1 ] && break
    let counter=counter-1
    sleep 1
  done
}

case "$1" in
  start)
    ENABLED=$(/sbin/getcfg ${QPKG_NAME} Enable -u -d FALSE -f $CONF)
    if [ "${ENABLED}" != "TRUE" ]; then
        echo "${QPKG_NAME} is disabled ..."
        exit 1
    fi
    
    if daemon_status; then
      echo "${QPKG_NAME} is already running"
    else
      echo "Starting ${QPKG_NAME} ..."
      start_daemon
    fi
    ;;

  stop)
    if daemon_status; then
      echo "Stopping ${QPKG_NAME} ..."
      stop_daemon
    else
      echo "${QPKG_NAME} is not running"
    fi
    ;;

  status)
    if daemon_status; then
      echo "${QPKG_NAME} is running"
      exit 0
    else
      echo "${QPKG_NAME} is not running"
      exit 1
    fi
    ;;

  relink)
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

    #[ -h /usr/lib/python2.7/site-packages/Cheetah-2.4.4 ] || /bin/ln -sf ${QPKG_ROOT}/lib/Cheetah-2.4.4 /usr/lib/python2.7/site-packages/Cheetah-2.4.4
    #[ -h /usr/lib/python2.7/site-packages/pyOpenSSL-0.11 ] || /bin/ln -sf ${QPKG_ROOT}/lib/pyOpenSSL-0.11 /usr/lib/python2.7/site-packages/pyOpenSSL-0.11

    [ -h /usr/lib/python2.7/site-packages/yenc.py ] || /bin/ln -sf ${QPKG_ROOT}/lib/yenc.py /usr/lib/python2.7/site-packages/yenc.py
    [ -h /usr/lib/python2.7/site-packages/_yenc.so ] || /bin/ln -sf ${QPKG_ROOT}/lib/_yenc.so /usr/lib/python2.7/site-packages/_yenc.so
    ;;

  restart)
    $0 stop
    $0 start
    ;;

  *)
    echo "Usage: $0 {start|stop|status|relink|restart}"
    exit 1
esac

exit 0
