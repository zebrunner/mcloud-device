#!/bin/bash


. /opt/debug.sh

check_tcp_connection() {
  # -z          - Zero-I/O mode [used for scanning]
  # -v          - Verbose
  # -w timeout  - Timeout for connects and final net reads
  nc -z -v -w 10 $1
}

parse_url_for_nc() {
  # tcp://demo.zebrunner.farm:7250 -> demo.zebrunner.farm 7250
  echo "$1" | sed -nE 's/^([a-z]*:\/\/)*([a-z\.]+):([0-9]*)/\2 \3/pI'
}

check_stf_provider_ports() {
  push_port=$(parse_url_for_nc $STF_PROVIDER_CONNECT_PUSH)
  sub_port=$(parse_url_for_nc $STF_PROVIDER_CONNECT_SUB)
  rethink_port=$(parse_url_for_nc $RETHINKDB_PORT_28015_TCP)

  check_tcp_connection "$push_port"
  if [[ $? -ne 0 ]]; then
    echo "ERROR! STF_PROVIDER_CONNECT_PUSH [$STF_PROVIDER_CONNECT_PUSH] is not accessible! Stopping container."
    exit 0
  fi

  check_tcp_connection "$sub_port"
  if [[ $? -ne 0 ]]; then
    echo "ERROR! STF_PROVIDER_CONNECT_SUB [$STF_PROVIDER_CONNECT_SUB] is not accessible! Stopping container."
    exit 0
  fi

  check_tcp_connection "$rethink_port"
  if [[ $? -ne 0 ]]; then
    echo "ERROR! RETHINKDB_PORT_28015_TCP [$RETHINKDB_PORT_28015_TCP] is not accessible! Stopping container."
    exit 0
  fi
}

#154 don't start stf and uploader if related settings are empty

if [[ -z $STF_PROVIDER_CONNECT_PUSH ]] || [[ -z $STF_PROVIDER_CONNECT_SUB ]] || [[ -z $STF_PROVIDER_HOST ]]; then
  echo "Exiting without restart as one of important setting is missed!"
  exit 0
else
  check_stf_provider_ports
fi

#converting to lower case just in case
PLATFORM_NAME=${PLATFORM_NAME,,}
PUBLIC_IP_PROTOCOL=${PUBLIC_IP_PROTOCOL,,}

if [[ "$PLATFORM_NAME" == "ios" ]]; then
  # Time variables
  startTime=$(date +%s)
  # Socket creation status
  socketCreated=0
  # Parse usbmuxd host and port
  IFS=: read -r USBMUXD_SOCKET_HOST USBMUXD_SOCKET_PORT <<< "$USBMUXD_SOCKET_ADDRESS"

  while [[ $(( startTime + $USBMUXD_SOCKET_TIMEOUT )) -gt "$(date +%s)" ]]; do
    # Check connection
    check_tcp_connection "$USBMUXD_SOCKET_HOST $USBMUXD_SOCKET_PORT"
    if [[ $? -eq 0 ]]; then
      # start socat client and connect to appium usbmuxd socket
      rm -f /var/run/usbmuxd
      socat UNIX-LISTEN:/var/run/usbmuxd,fork,reuseaddr,mode=777 TCP:${USBMUXD_SOCKET_ADDRESS} &
      timeout 10 bash -c 'until [[ -S /var/run/usbmuxd ]]; do sleep 1; echo "/var/run/usbmuxd socket existence check"; done'
      if [[ $? -eq 0 ]]; then
        socketCreated=1
        break
      fi
    else
      echo "Can't establish connection to usbmuxd socket [$USBMUXD_SOCKET_ADDRESS], one more attempt in $USBMUXD_SOCKET_PERIOD seconds."
    fi
    sleep "$USBMUXD_SOCKET_PERIOD"
  done

  if [[ $socketCreated -eq 0 ]]; then
    echo "ERROR! usbmuxd socket not created"
    exit 1
  fi

  res=$(ios list 2>&1)
  #echo "res: $res"
  # {"err":"dial tcp 172.18.0.66:22: connect: connection refused","level":"fatal","msg":"failed getting device list","time":"2023-08-24T16:28:27Z"}
  if [[ "${res}" == *"connection refused"* ]]; then
    echo "ERROR! Can't establish connection to usbmuxd socket!"
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
  timeout "$WDA_WAIT_TIMEOUT" bash -c "
    until curl -sf \"http://${WDA_HOST}:${WDA_PORT}/status\";
    do
      echo \"http://${WDA_HOST}:${WDA_PORT}/status endpoint not available, one more attempt\";
      sleep ${RETRY_DELAY};
    done"
  if [[ $? -eq 0 ]]; then
    echo "Linked appium container is up and running."
  else
    echo "ERROR! Unable to get WDA status successfully!"
    exit 1
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

# #184 https://github.com/zebrunner/mcloud-device/issues/184
if [ "${PLATFORM_NAME}" == "ios" ]; then
  echo "WDA connection status:"
  curl --verbose "http://${WDA_HOST}:${WDA_PORT}/status"
fi


#TODO: #85 define exit strategy from container on exit
# do always restart until appium container state is not Exited!
# for android stop of the appium container crash stf asap so verification of the appium container required only for iOS
exit $exit_status
