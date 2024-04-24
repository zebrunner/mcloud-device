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
  # tcp://192.168.88.88:7250 -> 192.168.88.88 7250

  #192 tcp connection verification doesn't support usage of ip addresses 
  host=`echo $1 | cut -d ':' -f 2`
  # remove forward slashes
  host="${host//\//}"

  port=`echo $1 | cut -d ':' -f 3`
  echo $host $port
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

#### Preparation steps
#converting to lower case just in case
PLATFORM_NAME=${PLATFORM_NAME,,}
PUBLIC_IP_PROTOCOL=${PUBLIC_IP_PROTOCOL,,}

# Note: STF_PROVIDER_... is not a good choice for env variable as STF tries to resolve and provide ... as cmd argument to its service!
if [ -z "${STF_PROVIDER_HOST}" ]; then
  # when STF_PROVIDER_HOST is empty
  STF_PROVIDER_HOST=${STF_PROVIDER_PUBLIC_IP}
fi

SOCKET_PROTOCOL=ws
if [ "${PUBLIC_IP_PROTOCOL}" == "https" ]; then
  SOCKET_PROTOCOL=wss
fi

#### Check STF_PROVIDER vars
if [[ -z $STF_PROVIDER_CONNECT_PUSH ]] || [[ -z $STF_PROVIDER_CONNECT_SUB ]] || [[ -z $STF_PROVIDER_HOST ]]; then
  echo "Exiting without restart as one of important setting is missed!"
  exit 0
else
  check_stf_provider_ports
fi

#### Prepare for iOS
if [[ "$PLATFORM_NAME" == "ios" ]]; then
  #### Connect usbmuxd
  startTime=$(date +%s)
  socketCreated=0
  # Parse usbmuxd host and port ( 'appium:22' -> 'appium 22' )
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

  #### Check {WDA}/status endpoint
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

  echo "WDA status:"
  curl http://${WDA_HOST}:${WDA_PORT}/status
fi


#### Start broadcasting from ws to tcp
websocat tcp-l:0.0.0.0:${BROADCAST_PORT} broadcast:autoreconnect:ws://127.0.0.1:${STF_PROVIDER_MIN_PORT} --binary --autoreconnect-delay-millis 2000 &
echo "Broadcasting from ws screen port ${STF_PROVIDER_MIN_PORT} to tcp ${BROADCAST_PORT} port."

#### Connect to STF
if [ "${PLATFORM_NAME}" == "android" ]; then
  stf provider \
    --allow-remote \
    --connect-url-pattern "${STF_PROVIDER_HOST}:<%= publicPort %>" \
    --storage-url ${PUBLIC_IP_PROTOCOL}://${STF_PROVIDER_PUBLIC_IP}:${PUBLIC_IP_PORT}/ \
    --screen-ws-url-pattern "${SOCKET_PROTOCOL}://${STF_PROVIDER_PUBLIC_IP}:${PUBLIC_IP_PORT}/d/${STF_PROVIDER_HOST}/<%= serial %>/<%= publicPort %>/"
elif [ "${PLATFORM_NAME}" == "ios" ]; then
  node /app/lib/cli ios-device \
    --serial ${DEVICE_UDID} \
    --device-name ${STF_PROVIDER_DEVICE_NAME} \
    --host ${STF_PROVIDER_HOST} \
    --screen-port ${STF_PROVIDER_MIN_PORT} \
    --connect-port ${MJPEG_PORT} \
    --provider ${STF_PROVIDER_NAME} \
    --public-ip ${STF_PROVIDER_PUBLIC_IP} \
    --group-timeout ${STF_PROVIDER_GROUP_TIMEOUT} \
    --storage-url ${PUBLIC_IP_PROTOCOL}://${STF_PROVIDER_PUBLIC_IP}:${PUBLIC_IP_PORT}/ \
    --screen-jpeg-quality ${STF_PROVIDER_SCREEN_JPEG_QUALITY} \
    --screen-ping-interval ${STF_PROVIDER_SCREEN_PING_INTERVAL} \
    --screen-ws-url-pattern "${SOCKET_PROTOCOL}://${STF_PROVIDER_PUBLIC_IP}:${PUBLIC_IP_PORT}/d/${STF_PROVIDER_HOST}/${DEVICE_UDID}/${STF_PROVIDER_MIN_PORT}/" \
    --boot-complete-timeout ${STF_PROVIDER_BOOT_COMPLETE_TIMEOUT} \
    --mute-master ${STF_PROVIDER_MUTE_MASTER} \
    --connect-push ${STF_PROVIDER_CONNECT_PUSH} \
    --connect-sub ${STF_PROVIDER_CONNECT_SUB} \
    --connect-app-dealer ${STF_PROVIDER_CONNECT_APP_DEALER} \
    --connect-dev-dealer ${STF_PROVIDER_CONNECT_DEV_DEALER} \
    --connect-url-pattern "${STF_PROVIDER_HOST}:<%= publicPort %>" \
    --wda-host ${WDA_HOST} \
    --wda-port ${WDA_PORT}
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
