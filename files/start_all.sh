#!/bin/bash

#converting to lower case just in case
PLATFORM_NAME=${PLATFORM_NAME,,}
PUBLIC_IP_PROTOCOL=${PUBLIC_IP_PROTOCOL,,}

if [[ "$PLATFORM_NAME" == "ios" ]]; then
  # start socat client and connect to appium usbmuxd socket
  rm -f /var/run/usbmuxd
  socat UNIX-LISTEN:/var/run/usbmuxd,fork,reuseaddr,mode=777 TCP:appium:22 &

  sleep 5

  ios list | grep $DEVICE_UDID
  if [ $? == 1 ]; then
    #TODO: #100: find a way to reanimate connected iOS device which is not recognized by go ios utility
    echo "Device is not available!"
    # exit with status 0 to stop stf device container restart
    exit 0
  fi
fi


# Note: STF_PROVIDER_... is not a good choice for env variable as STF tries to resolve and provide ... as cmd argument to its service!
if [ -z "${STF_PROVIDER_HOST}" ]; then
  # when STF_PROVIDER_HOST is empty
  STF_PROVIDER_HOST=${STF_PROVIDER_PUBLIC_IP}
fi

SOCKET_PROTOCOL=ws
if [ "${PUBLIC_IP_PROTOCOL}" == "https" ]; then
  SOCKET_PROTOCOL=wss
fi


if [ "${PLATFORM_NAME}" == "android" ]; then

  # stf provider for Android
  stf provider --allow-remote \
    --connect-url-pattern "${STF_PROVIDER_HOST}:<%= publicPort %>" \
    --storage-url ${PUBLIC_IP_PROTOCOL}://${STF_PROVIDER_PUBLIC_IP}:${PUBLIC_IP_PORT}/ \
    --screen-ws-url-pattern "${SOCKET_PROTOCOL}://${STF_PROVIDER_PUBLIC_IP}:${PUBLIC_IP_PORT}/d/${STF_PROVIDER_HOST}/<%= serial %>/<%= publicPort %>/"

elif [ "${PLATFORM_NAME}" == "ios" ]; then

  #wait until WDA_ENV file exists to read appropriate variables
  for ((i=1; i<=$WDA_WAIT_TIMEOUT; i++))
  do
   if [ -f ${WDA_ENV} ] && [ -s ${WDA_ENV} ]; then
     cat ${WDA_ENV}
     break
   else
     echo "Waiting until WDA settings appear $i sec"
     sleep 1
   fi
  done

  if [ ! -f ${WDA_ENV} ]; then
    echo "ERROR! Unable to get WDA settings from STF!"
    exit -1
  fi

  #source wda.env file
  source ${WDA_ENV}
  . ${WDA_ENV}
  export
  # #91: remove WDA_ENV file before starting stf
  # as we don't have enough permissions to remove we will reset its content completely
  # commented reset as this file is used by appium healthcheck
  # > ${WDA_ENV}

  #TODO: fix hardcoded values: --device-type, --connect-app-dealer, --connect-dev-dealer. Try to remove them at all if possible or find internally as stf provider do
#    --screen-ws-url-pattern "${SOCKET_PROTOCOL}://${STF_PROVIDER_PUBLIC_IP}:${PUBLIC_IP_PORT}/d/${STF_PROVIDER_HOST}/<%= serial %>/<%= publicPort %>/" \

  node /app/lib/cli ios-device --serial ${DEVICE_UDID} \
    --device-name ${STF_PROVIDER_DEVICE_NAME} \
    --device-type phone \
    --host ${STF_PROVIDER_HOST} \
    --screen-port ${STF_PROVIDER_MIN_PORT} \
    --connect-port ${MJPEG_PORT} \
    --provider ${STF_PROVIDER_NAME} \
    --public-ip ${STF_PROVIDER_PUBLIC_IP} \
    --group-timeout ${STF_PROVIDER_GROUP_TIMEOUT} \
    --storage-url ${PUBLIC_IP_PROTOCOL}://${STF_PROVIDER_PUBLIC_IP}:${PUBLIC_IP_PORT}/ \
    --screen-jpeg-quality ${STF_PROVIDER_SCREEN_JPEG_QUALITY} --screen-ping-interval ${STF_PROVIDER_SCREEN_PING_INTERVAL} \
    --screen-ws-url-pattern "${SOCKET_PROTOCOL}://${STF_PROVIDER_PUBLIC_IP}:${PUBLIC_IP_PORT}/d/${STF_PROVIDER_HOST}/${DEVICE_UDID}/${STF_PROVIDER_MIN_PORT}/" \
    --boot-complete-timeout ${STF_PROVIDER_BOOT_COMPLETE_TIMEOUT} --mute-master ${STF_PROVIDER_MUTE_MASTER} \
    --connect-push ${STF_PROVIDER_CONNECT_PUSH} --connect-sub ${STF_PROVIDER_CONNECT_SUB} \
    --connect-app-dealer tcp://stf-triproxy-app:7160 --connect-dev-dealer tcp://stf-triproxy-dev:7260 \
    --connect-url-pattern "${STF_PROVIDER_HOST}:<%= publicPort %>" \
    --wda-host ${WDA_HOST} --wda-port ${WDA_PORT} \
    --appium-port ${STF_PROVIDER_APPIUM_PORT}

fi

exit_status=$?
echo "Exit status: $exit_status"

#TODO: #85 define exit strategy from container on exiit
# do always restart until appium container state is not Exited!
# for android stop of the appium container crash stf asap so verification of the appium container required only for iOS
exit $exit_status
