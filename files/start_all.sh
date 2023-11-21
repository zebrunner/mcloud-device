#!/bin/bash


#154 don't start stf and uploader if related settings are empty

if [[ -z $STF_PROVIDER_CONNECT_PUSH ]] || [[ -z $STF_PROVIDER_CONNECT_SUB ]] || [[ -z $STF_PROVIDER_HOST ]]; then
  echo "Existing without restart as one of important setting is missed!"
  exit 0
fi

#converting to lower case just in case
PLATFORM_NAME=${PLATFORM_NAME,,}
PUBLIC_IP_PROTOCOL=${PUBLIC_IP_PROTOCOL,,}

if [[ "$PLATFORM_NAME" == "ios" ]]; then
  # start socat client and connect to appium usbmuxd socket
  rm -f /var/run/usbmuxd
  socat UNIX-LISTEN:/var/run/usbmuxd,fork,reuseaddr,mode=777 TCP:${USBMUXD_SOCKET_ADDRESS} &

  sleep 5

  res=$(ios list 2>&1)
  #echo "res: $res"
  # {"err":"dial tcp 172.18.0.66:22: connect: connection refused","level":"fatal","msg":"failed getting device list","time":"2023-08-24T16:28:27Z"}
  if [[ "${res}" == *"connection refused"* ]]; then
    echo "ERROR! Mounting is broken due to the invalid paring. Please re pair again!"
    exit 1
  fi

  if [[ "${res}" == *"no such host"* ]]; then
    echo "ERROR! Appium is not ready yet!"
    exit 1
  fi


  deviceInfo=$(ios info --udid=$DEVICE_UDID 2>&1)
  echo "device info: " $deviceInfo

  #{"err":"Device '111' not found. Is it attached to the machine?","level":"fatal","msg":"error getting devicelist","time":"2023-08-25T02:11:45-07:00"}
  if [[ "${deviceInfo}" == *"not found. Is it attached to the machine"* ]]; then
    echo "Device is not available!"
    echo "Exiting without restarting..."
    # exit with status 0 to stf device container restart
    exit 0
  fi

  #{"err":"could not retrieve PairRecord with error: ReadPair failed with errorcode '2', is the device paired?","level":"fatal","msg":"failed getting info","time":"2023-08-24T16:20:00Z"}
  if [[ "${deviceInfo}" == *"could not retrieve PairRecord with error"* ]]; then
    echo "ERROR! Mounting is broken due to the invalid paring. Please re pair again!"
    exit 1
  fi

  deviceClass=$(echo $deviceInfo | jq -r ".DeviceClass | select( . != null )")
  export DEVICETYPE='Phone'
  if [ "$deviceClass" = "iPad" ]; then
    export DEVICETYPE='Tablet'
  fi
  if [ "$deviceClass" = "AppleTV" ]; then
    export DEVICETYPE='tvOS'
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

  ##Hit the WDA status URL to see if it is available
  RETRY_DELAY=$(( $WDA_WAIT_TIMEOUT / 3 ))
  if curl --retry 3 --retry-delay ${RETRY_DELAY} -Is "http://${WDA_HOST}:${WDA_PORT}/status" | head -1 | grep -q '200 OK'
  then
    echo "Linked appium container is up and running."
  else
    echo "ERROR! Unable to get WDA status successfully!"
    exit -1
  fi


#    --screen-ws-url-pattern "${SOCKET_PROTOCOL}://${STF_PROVIDER_PUBLIC_IP}:${PUBLIC_IP_PORT}/d/${STF_PROVIDER_HOST}/<%= serial %>/<%= publicPort %>/" \

  node /app/lib/cli ios-device --serial ${DEVICE_UDID} \
    --device-name ${STF_PROVIDER_DEVICE_NAME} \
    --device-type ${DEVICETYPE} \
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
    --connect-app-dealer ${STF_PROVIDER_CONNECT_APP_DEALER} --connect-dev-dealer ${STF_PROVIDER_CONNECT_DEV_DEALER} \
    --connect-url-pattern "${STF_PROVIDER_HOST}:<%= publicPort %>" \
    --wda-host ${WDA_HOST} --wda-port ${WDA_PORT}

fi

exit_status=$?
echo "Exit status: $exit_status"

#TODO: #85 define exit strategy from container on exiit
# do always restart until appium container state is not Exited!
# for android stop of the appium container crash stf asap so verification of the appium container required only for iOS
exit $exit_status
