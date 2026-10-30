#!/bin/bash

# shellcheck source=util/debug.sh
. /opt/zebrunner/util/debug.sh
# shellcheck source=util/logger.sh
. /opt/zebrunner/util/logger.sh

logger "INFO" "\n\n\n\t\tMCLOUD-DEVICE\n\n"

#### Functions

# configError <message>: logs an invalid setting, the entrypoint exits after the validation of all of them
configError() {
  logger "ERROR" "$1"
  isConfigValid=0
}

# parseTcpUrl <url>: sets urlHost and urlPort of tcp://<host>:<port>, fails for another format
parseTcpUrl() {
  [[ "$1" =~ ^tcp://([^:/]+):([0-9]+)/?$ ]] || return 1
  urlHost="${BASH_REMATCH[1]}"
  urlPort="${BASH_REMATCH[2]}"
}

# isTcpReachable <host> <port>: the port accepts a TCP connection within 10 seconds
# (not the connect-timeout option of socat: socat 1.7 exits with 0 with it when the connection is refused)
isTcpReachable() {
  timeout 10 socat -u OPEN:/dev/null "TCP:$1:$2" > /dev/null 2>&1
}

# isWdaUp: WebDriverAgent answers its status
isWdaUp() {
  curl -sf --max-time 5 -o /dev/null "$wdaStatusUrl"
}

#### Preparation steps
# Case-insensitive values
PLATFORM_NAME="${PLATFORM_NAME,,}"
PUBLIC_IP_PROTOCOL="${PUBLIC_IP_PROTOCOL,,}"
WIRELESS="${WIRELESS,,}"
# The provider of Android reads STF_PROVIDER_HOST as its --host option, the public address is its default
export STF_PROVIDER_HOST="${STF_PROVIDER_HOST:-$STF_PROVIDER_PUBLIC_IP}"
wdaStatusUrl="http://${WDA_HOST}:${WDA_PORT}/status"
# The usbmuxd socket of /var/run/usbmuxd (a symlink to it, see Dockerfile)
usbmuxdSocket="/tmp/usbmuxd/usbmuxd"
# The container filesystem survives the restarts, the file counts the restarts asked for unreachable STF services
stfRestartsFile="/tmp/zebrunner/stf-services-restarts"

#### Validate configuration
# A wrong configuration can't be fixed by a restart, so exit with 0
isConfigValid=1
if [[ ! "$PLATFORM_NAME" =~ ^(android|ios)$ ]]; then
  configError "PLATFORM_NAME must be android or ios, but it is '${PLATFORM_NAME}'."
fi
if [[ ! "$PUBLIC_IP_PROTOCOL" =~ ^(http|https)$ ]]; then
  configError "PUBLIC_IP_PROTOCOL must be http or https, but it is '${PUBLIC_IP_PROTOCOL}'."
fi
if [[ ! "$WIRELESS" =~ ^(true|false)$ ]]; then
  configError "WIRELESS must be true or false, but it is '${WIRELESS}'."
fi

# the token of the STF storage and the CURVE keys of ZeroMQ are read by STF itself (the values are not logged)
requiredVars=(STF_PROVIDER_PUBLIC_IP STF_STORAGE_TOKEN STF_ZMQ_CURVE_SERVER_PUBLIC_KEY STF_ZMQ_CURVE_SECRET_KEY)
# the STF services of tcp://<host>:<port>, they are awaited before the start
stfServices=(STF_PROVIDER_CONNECT_PUSH STF_PROVIDER_CONNECT_SUB)
if [[ "$PLATFORM_NAME" == "ios" ]]; then
  requiredVars+=(DEVICE_UDID STF_PROVIDER_NAME)
  stfServices+=(STF_PROVIDER_CONNECT_APP_DEALER STF_PROVIDER_CONNECT_DEV_DEALER)
fi
for var in "${requiredVars[@]}" "${stfServices[@]}"; do
  if [[ -z "${!var}" ]]; then
    configError "${var} is required but empty or unset."
  fi
done
for var in STF_ZMQ_CURVE_SERVER_PUBLIC_KEY STF_ZMQ_CURVE_SECRET_KEY; do
  if [[ -n "${!var}" && ! "${!var}" =~ ^[0-9a-fA-F]{64}$ ]]; then
    configError "${var} must be a key of 64 hex characters (stf curve-keygen)."
  fi
done
for var in "${stfServices[@]}"; do
  if [[ -n "${!var}" ]] && ! parseTcpUrl "${!var}"; then
    configError "${var} must be tcp://<host>:<port>, but it is '${!var}'."
  fi
done

for var in PUBLIC_IP_PORT BROADCAST_PORT STF_SERVICES_WAIT_TIMEOUT STF_SERVICES_WAIT_RETRY STF_SERVICES_WAIT_RESTARTS \
  STF_PROVIDER_ADB_PORT STF_PROVIDER_MIN_PORT STF_PROVIDER_MAX_PORT STF_PROVIDER_BOOT_COMPLETE_TIMEOUT \
  STF_PROVIDER_GROUP_TIMEOUT STF_PROVIDER_HEARTBEAT_INTERVAL STF_PROVIDER_SCREEN_JPEG_QUALITY \
  STF_PROVIDER_SCREEN_PING_INTERVAL STF_PROVIDER_VNC_PORT WDA_PORT MJPEG_PORT WDA_WAIT_TIMEOUT \
  USBMUXD_SOCKET_TIMEOUT USBMUXD_SOCKET_PERIOD; do
  if [[ ! "${!var}" =~ ^[0-9]+$ ]]; then
    configError "${var} must be a non-negative integer, but it is '${!var}'."
  fi
done
if [[ "$STF_PROVIDER_MIN_PORT" =~ ^[0-9]+$ && "$STF_PROVIDER_MAX_PORT" =~ ^[0-9]+$ ]] &&
  ((STF_PROVIDER_MIN_PORT > STF_PROVIDER_MAX_PORT)); then
  configError "STF_PROVIDER_MIN_PORT (${STF_PROVIDER_MIN_PORT}) must not be greater than STF_PROVIDER_MAX_PORT (${STF_PROVIDER_MAX_PORT})."
fi
if [[ "$PLATFORM_NAME" == "ios" && "$WIRELESS" != "true" && ! "$USBMUXD_SOCKET_ADDRESS" =~ ^[^:]+:[0-9]+$ ]]; then
  configError "USBMUXD_SOCKET_ADDRESS must be <host>:<port>, but it is '${USBMUXD_SOCKET_ADDRESS}'."
fi

if [[ "$isConfigValid" -eq 0 ]]; then
  logger "ERROR" "Invalid configuration. Exiting!"
  exit 0
fi

#### Wait for the STF services
# A restart may find the services up (e.g. after an update of STF): after STF_SERVICES_WAIT_TIMEOUT seconds the entrypoint
# asks for a restart up to STF_SERVICES_WAIT_RESTARTS times in a row, then exits with 0 to stop the restarts
pendingServices=("${stfServices[@]}")
deadline=$((SECONDS + STF_SERVICES_WAIT_TIMEOUT))
while :; do
  unreachableServices=()
  for var in "${pendingServices[@]}"; do
    parseTcpUrl "${!var}"
    if isTcpReachable "$urlHost" "$urlPort"; then
      logger "INFO" "${var} '${!var}' is reachable."
    else
      logger "WARN" "${var} '${!var}' is not reachable."
      unreachableServices+=("$var")
    fi
  done
  pendingServices=("${unreachableServices[@]}")
  if [[ ${#pendingServices[@]} -eq 0 || $SECONDS -ge $deadline ]]; then
    break
  fi
  logger "WARN" "One more attempt in ${STF_SERVICES_WAIT_RETRY} seconds."
  sleep "$STF_SERVICES_WAIT_RETRY"
done

if [[ ${#pendingServices[@]} -gt 0 ]]; then
  restarts="$(cat "$stfRestartsFile" 2> /dev/null)"
  [[ "$restarts" =~ ^[0-9]+$ ]] || restarts=0
  if [[ "$restarts" -lt "$STF_SERVICES_WAIT_RESTARTS" ]]; then
    mkdir -p "$(dirname "$stfRestartsFile")"
    echo "$((restarts + 1))" > "$stfRestartsFile"
    logger "ERROR" "STF services are not reachable: ${pendingServices[*]}. Restarting ($((restarts + 1)) of ${STF_SERVICES_WAIT_RESTARTS})!"
    exit 1
  fi
  rm -f "$stfRestartsFile"
  logger "ERROR" "STF services are not reachable after ${restarts} restarts: ${pendingServices[*]}. Exiting!"
  exit 0
fi
rm -f "$stfRestartsFile"
logger "INFO" "All the STF services are reachable."

#### Forward usbmuxd (iOS)
# go-ios and the other tools read USBMUXD_SOCKET_ADDRESS themselves, /var/run/usbmuxd is forwarded for the ones that don't.
# WIRELESS=true: a device without a usb path (e.g. Apple TV reached over a network tunnel of the host) has no usbmuxd,
# only WebDriverAgent is needed (mcloud-agent sets it for the wireless devices)
if [[ "$PLATFORM_NAME" == "ios" && "$WIRELESS" == "true" ]]; then
  logger "INFO" "WIRELESS=true: usbmuxd is not forwarded, the device has no usb path."
elif [[ "$PLATFORM_NAME" == "ios" ]]; then
  usbmuxdHost="${USBMUXD_SOCKET_ADDRESS%:*}"
  usbmuxdPort="${USBMUXD_SOCKET_ADDRESS##*:}"
  isUsbmuxdForwarded=0
  deadline=$((SECONDS + USBMUXD_SOCKET_TIMEOUT))
  while :; do
    if isTcpReachable "$usbmuxdHost" "$usbmuxdPort"; then
      rm -f "$usbmuxdSocket"
      socat UNIX-LISTEN:"$usbmuxdSocket",fork,reuseaddr,mode=777 TCP:"$USBMUXD_SOCKET_ADDRESS" &
      socatPid=$!
      for _ in $(seq 1 50); do
        [[ -S "$usbmuxdSocket" ]] && break
        sleep 0.2
      done
      if [[ -S "$usbmuxdSocket" ]]; then
        isUsbmuxdForwarded=1
        break
      fi
      logger "WARN" "socat did not create ${usbmuxdSocket}."
      kill "$socatPid" 2> /dev/null
    else
      logger "WARN" "usbmuxd '${USBMUXD_SOCKET_ADDRESS}' is not reachable."
    fi
    [[ $SECONDS -ge $deadline ]] && break
    logger "WARN" "One more attempt in ${USBMUXD_SOCKET_PERIOD} seconds."
    sleep "$USBMUXD_SOCKET_PERIOD"
  done

  if [[ "$isUsbmuxdForwarded" -eq 0 ]]; then
    logger "ERROR" "/var/run/usbmuxd is not forwarded to '${USBMUXD_SOCKET_ADDRESS}'. Restarting!"
    exit 1
  fi
  logger "INFO" "/var/run/usbmuxd is forwarded to '${USBMUXD_SOCKET_ADDRESS}'."
fi

#### Wait for WebDriverAgent (iOS)
if [[ "$PLATFORM_NAME" == "ios" ]]; then
  deadline=$((SECONDS + WDA_WAIT_TIMEOUT))
  until isWdaUp; do
    if [[ $SECONDS -ge $deadline ]]; then
      logger "ERROR" "WebDriverAgent does not answer ${wdaStatusUrl}. Restarting!"
      exit 1
    fi
    logger "WARN" "WebDriverAgent does not answer ${wdaStatusUrl}, one more attempt in 2 seconds."
    sleep 2
  done
  logger "INFO" "WebDriverAgent is up: $(curl -s --max-time 5 "$wdaStatusUrl")"
fi

#### Broadcast the screen
# The screen WebSocket of STF (STF_PROVIDER_MIN_PORT) is also served as TCP on BROADCAST_PORT: the video recording of the
# appium container reads it. websocat is started again when it exits, until the entrypoint ends
entrypointPid=$$
(
  while kill -0 "$entrypointPid" 2> /dev/null; do
    websocat --binary "tcp-l:0.0.0.0:${BROADCAST_PORT}" "broadcast:ws://127.0.0.1:${STF_PROVIDER_MIN_PORT}"
    logger "WARN" "The screen broadcast (websocat) exited with $?, it is started again in 1 second."
    sleep 1
  done
) &
logger "INFO" "The screen WebSocket port ${STF_PROVIDER_MIN_PORT} is broadcast to the TCP port ${BROADCAST_PORT}."

#### Start STF
storageUrl="${PUBLIC_IP_PROTOCOL}://${STF_PROVIDER_PUBLIC_IP}:${PUBLIC_IP_PORT}/"
socketProtocol="ws"
if [[ "$PUBLIC_IP_PROTOCOL" == "https" ]]; then
  socketProtocol="wss"
fi
# The provider of Android reads the STF_PROVIDER_* variables as its options: an empty one would replace the default of its
# option and an unknown one (the dealers of iOS) stops it, so they are removed from its environment
unsetVars=(-u STF_PROVIDER_CONNECT_APP_DEALER -u STF_PROVIDER_CONNECT_DEV_DEALER)
# the names of the exported variables, one per word
for var in $(compgen -e); do
  if [[ "$var" == STF_PROVIDER_* && "$var" != STF_PROVIDER_CONNECT_*_DEALER && -z "${!var}" ]]; then
    unsetVars+=(-u "$var")
  fi
done

# The patterns are the lodash templates of STF
if [[ "$PLATFORM_NAME" == "android" ]]; then
  stfCommand=(env "${unsetVars[@]}" stf provider
    --allow-remote
    --connect-url-pattern "${STF_PROVIDER_HOST}:<%= publicPort %>"
    --storage-url "$storageUrl"
    --screen-ws-url-pattern "${socketProtocol}://${STF_PROVIDER_PUBLIC_IP}:${PUBLIC_IP_PORT}/d/${STF_PROVIDER_HOST}/<%= serial %>/<%= publicPort %>/")
else
  stfCommand=(stf ios-device
    --serial "$DEVICE_UDID"
    --device-name "$STF_PROVIDER_DEVICE_NAME"
    --host "$STF_PROVIDER_HOST"
    --screen-port "$STF_PROVIDER_MIN_PORT"
    --connect-port "$MJPEG_PORT"
    --provider "$STF_PROVIDER_NAME"
    --public-ip "$STF_PROVIDER_PUBLIC_IP"
    --group-timeout "$STF_PROVIDER_GROUP_TIMEOUT"
    --storage-url "$storageUrl"
    --screen-jpeg-quality "$STF_PROVIDER_SCREEN_JPEG_QUALITY"
    --screen-ping-interval "$STF_PROVIDER_SCREEN_PING_INTERVAL"
    --screen-ws-url-pattern "${socketProtocol}://${STF_PROVIDER_PUBLIC_IP}:${PUBLIC_IP_PORT}/d/${STF_PROVIDER_HOST}/${DEVICE_UDID}/${STF_PROVIDER_MIN_PORT}/"
    --boot-complete-timeout "$STF_PROVIDER_BOOT_COMPLETE_TIMEOUT"
    --heartbeat-interval "$STF_PROVIDER_HEARTBEAT_INTERVAL"
    --mute-master "$STF_PROVIDER_MUTE_MASTER"
    --connect-push "$STF_PROVIDER_CONNECT_PUSH"
    --connect-sub "$STF_PROVIDER_CONNECT_SUB"
    --connect-app-dealer "$STF_PROVIDER_CONNECT_APP_DEALER"
    --connect-dev-dealer "$STF_PROVIDER_CONNECT_DEV_DEALER"
    --connect-url-pattern "${STF_PROVIDER_HOST}:<%= publicPort %>"
    --wda-host "$WDA_HOST"
    --wda-port "$WDA_PORT")
fi

logger "INFO" "Starting STF ${PLATFORM_NAME}: ${stfCommand[*]}"
"${stfCommand[@]}" &
stfPid=$!
# docker stop sends SIGTERM to the entrypoint (PID 1): STF gets it to stop gracefully
trap 'kill -TERM "$stfPid" 2> /dev/null' TERM INT
wait "$stfPid"
exitStatus=$?
# wait is interrupted by a trapped signal before STF has stopped
while kill -0 "$stfPid" 2> /dev/null; do
  wait "$stfPid"
  exitStatus=$?
done
logger "WARN" "STF exited with ${exitStatus}."

# #184: the state of WebDriverAgent explains why STF has stopped
if [[ "$PLATFORM_NAME" == "ios" ]]; then
  logger "INFO" "WebDriverAgent status:"
  curl --verbose --max-time 5 "$wdaStatusUrl" 2>&1
fi

exit "$exitStatus"
