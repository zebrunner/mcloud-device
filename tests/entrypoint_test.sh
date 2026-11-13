#!/bin/bash
# Tests of entrypoint.sh with stubs of stf, socat, curl, websocat and sleep: no STF, no device, no docker.
# The image paths (/opt/zebrunner, /tmp/usbmuxd, /tmp/zebrunner) are replaced with the repository and the workspace.
# The entrypoint needs bash 4, on macOS use the bash of brew; python3 creates the unix socket of the socat stub.
source "$(dirname "$0")/lib.sh"
cd "$REPO" || exit 1

(("$(bash -c 'echo "${BASH_VERSINFO[0]}"')" >= 4)) || skip "requires bash 4 in PATH"
require_cmd python3

sed -e "s#/opt/zebrunner/#${REPO}/#g" -e "s#/tmp/usbmuxd/#${WORK}/usbmuxd/#g" -e "s#/tmp/zebrunner/#${WORK}/zebrunner/#g" \
  entrypoint.sh > "${WORK}/entrypoint.sh"
mkdir -p "${WORK}/usbmuxd" "${WORK}/zebrunner"

# the stubs read their behavior from the FAKE_* variables of the scenario
export FAKE_WORK="$WORK"
# sleep: returns at once, FAKE_SLEEP_HANG=<seconds>: the sleep of these seconds runs until it is killed (its pid in
# sleep.pid)
# the stub body is expanded when the stub runs
# shellcheck disable=SC2016
stub sleep '(IFS="|"; echo "sleep|$*") >> "$FAKE_WORK/calls.log"
if [[ -n "$FAKE_SLEEP_HANG" && "$1" == "$FAKE_SLEEP_HANG" ]]; then
  echo "$$" > "$FAKE_WORK/sleep.pid"
  exec /bin/sleep 30
fi
exit 0'
# websocat: runs for a while (FAKE_WEBSOCAT_SEC) and exits
# the stub body is expanded when the stub runs
# shellcheck disable=SC2016
stub websocat '(IFS="|"; echo "websocat|$*") >> "$FAKE_WORK/calls.log"
/bin/sleep "$FAKE_WEBSOCAT_SEC"
exit 3'
# timeout: runs the command, it is not stopped
# the stub body is expanded when the stub runs
# shellcheck disable=SC2016
stub timeout 'echo "timeout|$1" >> "$FAKE_WORK/calls.log"
exec "${@:2}"'
# socat: the reachability check of a port (-u OPEN:/dev/null TCP:<host>:<port>) fails for the hosts of FAKE_DOWN
# and for the first FAKE_FLAKY_CHECKS checks of the host FAKE_FLAKY; the usbmuxd forwarding (UNIX-LISTEN:<path>,...)
# creates the unix socket unless FAKE_SOCKET=none
# the stub body is expanded when the stub runs
# shellcheck disable=SC2016
stub socat '(IFS="|"; echo "socat|$*") >> "$FAKE_WORK/calls.log"
if [[ "$1" == -u ]]; then
  target="${3#TCP:}"
  host="${target%%:*}"
  [[ " $FAKE_DOWN " == *" $host "* ]] && exit 1
  if [[ "$host" == "$FAKE_FLAKY" ]]; then
    n=$(cat "$FAKE_WORK/flaky.n" 2> /dev/null || echo 0)
    echo $((n + 1)) > "$FAKE_WORK/flaky.n"
    [[ "$n" -lt "$FAKE_FLAKY_CHECKS" ]] && exit 1
  fi
  exit 0
fi
if [[ "$1" == UNIX-LISTEN:* && "$FAKE_SOCKET" != none ]]; then
  path="${1#UNIX-LISTEN:}"
  python3 -c "import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])" "${path%%,*}"
fi
exit 0'
# curl: the status of WebDriverAgent, it does not answer the first FAKE_WDA_AFTER requests, never with FAKE_WDA=down
# the stub body is expanded when the stub runs
# shellcheck disable=SC2016
stub curl '(IFS="|"; echo "curl|$*") >> "$FAKE_WORK/calls.log"
[[ "$FAKE_WDA" == down ]] && exit 7
n=$(cat "$FAKE_WORK/curl.n" 2> /dev/null || echo 0)
echo $((n + 1)) > "$FAKE_WORK/curl.n"
[[ "$n" -lt "$FAKE_WDA_AFTER" ]] && exit 7
[[ "$*" == *-o\ /dev/null* ]] || echo "{\"value\":{\"ready\":true}}"
exit 0'
# stf: records its arguments and the variables of its environment, exits with FAKE_STF_EXIT;
# FAKE_STF=hang: runs until SIGTERM, FAKE_STF=busy: runs for a second
# the stub body is expanded when the stub runs
# shellcheck disable=SC2016
stub stf '(IFS="|"; echo "stf|$*") >> "$FAKE_WORK/calls.log"
for var in STF_NODE_TOKEN STF_PROVIDER_HOST STF_PROVIDER_CONNECT_APP_DEALER STF_PROVIDER_CONNECT_DEV_DEALER \
  STF_PROVIDER_CONNECT_PORT STF_PROVIDER_DEVICE_NAME STF_PROVIDER_NAME STF_PROVIDER_MIN_PORT STF_ZMQ_CURVE_SERVER_PUBLIC_KEY STF_ZMQ_CURVE_SECRET_KEY; do
  echo "env|${var}=${!var-<unset>}" >> "$FAKE_WORK/calls.log"
done
if [[ "$FAKE_STF" == hang ]]; then
  trap "echo \"stf|SIGTERM\" >> \"$FAKE_WORK/calls.log\"; exit 143" TERM
  for _ in $(seq 100); do /bin/sleep 0.1; done
  exit 0
fi
[[ "$FAKE_STF" == busy ]] && /bin/sleep 1
exit "${FAKE_STF_EXIT:-0}"'

# the CURVE keys of the scenarios, 64 hex characters
server_key="$(printf '%064d' 0 | tr 0 a)"
secret_key="$(printf '%064d' 0 | tr 0 b)"
# the node token of mcloud-agent ./zebrunner.sh join: mcn1.<label>.<43 base64url characters>
node_secret="Ab_-$(printf '%039d' 0 | tr 0 c)"
node_token="mcn1.agent-1.${node_secret}"

# scenario <platform>: a fresh state, an Android (by default) or an iOS device with reachable STF services
scenario() {
  rm -rf "${WORK:?}"/zebrunner/* "${WORK:?}"/usbmuxd/* "${WORK}"/*.n
  reset_calls
  # the variables of the previous scenario
  unset DEBUG VERBOSE FAKE_STF FAKE_STF_EXIT FAKE_SLEEP_HANG
  # the defaults of the Dockerfile
  export PLATFORM_NAME="${1:-android}" DEVICE_UDID=00008030-TEST WIRELESS=false
  export STF_PROVIDER_CONNECT_PUSH=tcp://push-host:7270 STF_PROVIDER_CONNECT_SUB=tcp://sub-host:7250
  export STF_PROVIDER_CONNECT_APP_DEALER=tcp://app-host:7160 STF_PROVIDER_CONNECT_DEV_DEALER=tcp://dev-host:7260
  export STF_NODE_TOKEN="$node_token"
  export STF_ZMQ_CURVE_SERVER_PUBLIC_KEY="$server_key" STF_ZMQ_CURVE_SECRET_KEY="$secret_key"
  export STF_SERVICES_WAIT_TIMEOUT=300 STF_SERVICES_WAIT_RETRY=30 STF_SERVICES_WAIT_RESTARTS=2
  export STF_PROVIDER_PUBLIC_IP=stf.example.com PUBLIC_IP_PORT=80 PUBLIC_IP_PROTOCOL=http
  export STF_PROVIDER_NAME=mcloud-linux STF_PROVIDER_HOST=provider-host STF_PROVIDER_DEVICE_NAME="My Phone"
  export REMOTE_CONNECT_HOST=""
  export STF_PROVIDER_ADB_HOST=connector STF_PROVIDER_ADB_PORT=5037 STF_PROVIDER_MIN_PORT=7404 STF_PROVIDER_MAX_PORT=7410
  export STF_PROVIDER_CONNECT_PORT=""
  export STF_PROVIDER_BOOT_COMPLETE_TIMEOUT=60000 STF_PROVIDER_CLEANUP=false STF_PROVIDER_GROUP_TIMEOUT=3600
  export STF_PROVIDER_HEARTBEAT_INTERVAL=10000 STF_PROVIDER_LOCK_ROTATION=false STF_PROVIDER_MUTE_MASTER=never
  export STF_PROVIDER_SCREEN_JPEG_QUALITY=30 STF_PROVIDER_SCREEN_PING_INTERVAL=30000 STF_PROVIDER_SCREEN_RESET=false
  export STF_PROVIDER_VNC_INITIAL_SIZE=600x800 STF_PROVIDER_VNC_PORT=5900 BROADCAST_PORT=2223
  export WDA_HOST=connector WDA_PORT=8100 MJPEG_PORT=8101 WDA_WAIT_TIMEOUT=30
  export USBMUXD_SOCKET_ADDRESS=usbmuxd-host:2222 USBMUXD_SOCKET_TIMEOUT=60 USBMUXD_SOCKET_PERIOD=5
  export LOGGER_LEVEL=DEBUG
  # the stubs
  export FAKE_DOWN="" FAKE_FLAKY="" FAKE_FLAKY_CHECKS=0 FAKE_SOCKET=ok FAKE_WDA=up FAKE_WDA_AFTER=0 FAKE_WEBSOCAT_SEC=0
}

# run_entrypoint: output of the entrypoint in $OUT, its exit status in $STATUS
run_entrypoint() {
  OUT="$(PATH="${WORK}/bin:${PATH}" bash "${WORK}/entrypoint.sh" 2>&1)"
  STATUS=$?
}

# waits: the sleeps of the entrypoint but the restarts of websocat (1 second)
waits() {
  calls sleep | grep -vxF 1
}

# started: the stf calls, empty when STF was not started
started() {
  calls stf
}

section "configuration"
scenario
run_entrypoint
check "valid configuration starts STF" "0" "$STATUS"
check_contains "banner" "MCLOUD-DEVICE" "$OUT"
check_not_contains "valid configuration is not reported" "Invalid configuration" "$OUT"

for var in STF_PROVIDER_CONNECT_PUSH STF_PROVIDER_CONNECT_SUB STF_PROVIDER_PUBLIC_IP STF_NODE_TOKEN \
  STF_ZMQ_CURVE_SERVER_PUBLIC_KEY STF_ZMQ_CURVE_SECRET_KEY; do
  scenario
  export "${var}="
  run_entrypoint
  check_contains "empty ${var} is reported" "${var} is required but empty or unset." "$OUT"
  check_contains "empty ${var} ends the entrypoint" "Invalid configuration. Exiting!" "$OUT"
  check "empty ${var} exits with 0" "0" "$STATUS"
  check "nothing is started without ${var}" "" "$(calls socat)$(started)$(calls websocat)"
done

scenario
unset STF_PROVIDER_CONNECT_PUSH
run_entrypoint
check_contains "unset STF_PROVIDER_CONNECT_PUSH is reported" "STF_PROVIDER_CONNECT_PUSH is required but empty or unset." "$OUT"

for var in DEVICE_UDID STF_PROVIDER_NAME STF_PROVIDER_CONNECT_APP_DEALER STF_PROVIDER_CONNECT_DEV_DEALER; do
  scenario ios
  export "${var}="
  run_entrypoint
  check_contains "iOS: empty ${var} is reported" "${var} is required but empty or unset." "$OUT"
  check "iOS: empty ${var} exits with 0" "0" "$STATUS"
  check "iOS: nothing is started without ${var}" "" "$(calls socat)$(started)"

  scenario android
  export "${var}="
  run_entrypoint
  check_not_contains "Android: ${var} is not required" "${var} is required" "$OUT"
  check_contains "Android: STF starts without ${var}" "provider" "$(started)"
done

for value in push-host:7270 http://push-host:7270 tcp://push-host tcp://push-host:port "tcp://push-host:7270 x"; do
  scenario
  STF_PROVIDER_CONNECT_PUSH="$value"
  run_entrypoint
  check_contains "STF_PROVIDER_CONNECT_PUSH='${value}' is reported" \
    "STF_PROVIDER_CONNECT_PUSH must be tcp://<host>:<port>, but it is '${value}'." "$OUT"
  check "STF_PROVIDER_CONNECT_PUSH='${value}' exits with 0" "0" "$STATUS"
done
scenario
STF_PROVIDER_CONNECT_PUSH=tcp://192.168.88.88:7270/
run_entrypoint
check_not_contains "tcp://<ip>:<port>/ is valid" "must be tcp://" "$OUT"
check_contains "the host of tcp://<ip>:<port>/ is checked" "-u|OPEN:/dev/null|TCP:192.168.88.88:7270" "$(calls socat)"

for value in Android ANDROID iOS IOS; do
  scenario
  PLATFORM_NAME="$value"
  run_entrypoint
  check "PLATFORM_NAME='${value}' is valid" "0" "$STATUS"
  check_not_contains "PLATFORM_NAME='${value}' is not reported" "PLATFORM_NAME must be" "$OUT"
done
for value in "" windows tvos; do
  scenario
  PLATFORM_NAME="$value"
  run_entrypoint
  check_contains "PLATFORM_NAME='${value}' is reported" "PLATFORM_NAME must be android or ios, but it is '${value}'." "$OUT"
  check "PLATFORM_NAME='${value}' exits with 0" "0" "$STATUS"
  check "nothing is started with PLATFORM_NAME='${value}'" "" "$(calls socat)$(started)"
done

for value in ftp "" ws; do
  scenario
  PUBLIC_IP_PROTOCOL="$value"
  run_entrypoint
  check_contains "PUBLIC_IP_PROTOCOL='${value}' is reported" "PUBLIC_IP_PROTOCOL must be http or https, but it is '${value}'." "$OUT"
done

for value in yes 1 ""; do
  scenario
  WIRELESS="$value"
  run_entrypoint
  check_contains "WIRELESS='${value}' is reported" "WIRELESS must be true or false, but it is '${value}'." "$OUT"
done

for var in PUBLIC_IP_PORT BROADCAST_PORT STF_SERVICES_WAIT_TIMEOUT STF_SERVICES_WAIT_RETRY STF_SERVICES_WAIT_RESTARTS \
  STF_PROVIDER_ADB_PORT STF_PROVIDER_MIN_PORT STF_PROVIDER_MAX_PORT STF_PROVIDER_BOOT_COMPLETE_TIMEOUT \
  STF_PROVIDER_GROUP_TIMEOUT STF_PROVIDER_HEARTBEAT_INTERVAL STF_PROVIDER_SCREEN_JPEG_QUALITY \
  STF_PROVIDER_SCREEN_PING_INTERVAL STF_PROVIDER_VNC_PORT WDA_PORT MJPEG_PORT WDA_WAIT_TIMEOUT \
  USBMUXD_SOCKET_TIMEOUT USBMUXD_SOCKET_PERIOD; do
  for value in "" abc -1 1.5; do
    scenario
    export "${var}=${value}"
    run_entrypoint
    check_contains "${var}='${value}' is reported" "${var} must be a non-negative integer, but it is '${value}'." "$OUT"
    check "${var}='${value}' exits with 0" "0" "$STATUS"
  done
done

scenario
STF_PROVIDER_MIN_PORT=7410
STF_PROVIDER_MAX_PORT=7404
run_entrypoint
check_contains "STF_PROVIDER_MIN_PORT greater than STF_PROVIDER_MAX_PORT is reported" \
  "STF_PROVIDER_MIN_PORT (7410) must not be greater than STF_PROVIDER_MAX_PORT (7404)." "$OUT"
check "STF_PROVIDER_MIN_PORT greater than STF_PROVIDER_MAX_PORT exits with 0" "0" "$STATUS"

for value in "" usbmuxd-host "usbmuxd-host:port" ":2222"; do
  scenario ios
  USBMUXD_SOCKET_ADDRESS="$value"
  run_entrypoint
  check_contains "iOS: USBMUXD_SOCKET_ADDRESS='${value}' is reported" \
    "USBMUXD_SOCKET_ADDRESS must be <host>:<port>, but it is '${value}'." "$OUT"
  check "iOS: USBMUXD_SOCKET_ADDRESS='${value}' exits with 0" "0" "$STATUS"
done
scenario ios
USBMUXD_SOCKET_ADDRESS=""
WIRELESS=true
run_entrypoint
check_not_contains "iOS: USBMUXD_SOCKET_ADDRESS is not needed with WIRELESS=true" "USBMUXD_SOCKET_ADDRESS must be" "$OUT"
scenario
USBMUXD_SOCKET_ADDRESS=""
run_entrypoint
check_not_contains "Android: USBMUXD_SOCKET_ADDRESS is not needed" "USBMUXD_SOCKET_ADDRESS must be" "$OUT"

for value in abc 80 1023 65536 99999 07400 0x1F90 "7400 " -7400; do
  scenario
  STF_PROVIDER_CONNECT_PORT="$value"
  run_entrypoint
  check_contains "Android: STF_PROVIDER_CONNECT_PORT='${value}' is reported" \
    "STF_PROVIDER_CONNECT_PORT must be a port 1024-65535, but it is '${value}'." "$OUT"
  check "Android: STF_PROVIDER_CONNECT_PORT='${value}' exits with 0" "0" "$STATUS"
  check "Android: nothing is started with STF_PROVIDER_CONNECT_PORT='${value}'" "" "$(calls socat)$(started)"
done
for value in 1024 7400 65535; do
  scenario
  STF_PROVIDER_CONNECT_PORT="$value"
  run_entrypoint
  check_not_contains "Android: STF_PROVIDER_CONNECT_PORT='${value}' is valid" "STF_PROVIDER_CONNECT_PORT must be" "$OUT"
done
scenario ios
STF_PROVIDER_CONNECT_PORT=abc
run_entrypoint
check_not_contains "iOS: STF_PROVIDER_CONNECT_PORT is ignored" "STF_PROVIDER_CONNECT_PORT must be" "$OUT"
check_contains "iOS: STF starts with any STF_PROVIDER_CONNECT_PORT" "ios-device" "$(started)"

for value in "tcp://mcloud.example.com" "mcloud.example.com:5555" "mcloud.example.com/" "mcloud example.com"; do
  scenario
  REMOTE_CONNECT_HOST="$value"
  run_entrypoint
  check_contains "REMOTE_CONNECT_HOST='${value}' is reported" \
    "REMOTE_CONNECT_HOST must be a host name or address without a scheme and a port, but it is '${value}'." "$OUT"
  check "REMOTE_CONNECT_HOST='${value}' exits with 0" "0" "$STATUS"
  check "nothing is started with REMOTE_CONNECT_HOST='${value}'" "" "$(calls socat)$(started)"
done
for value in mcloud.example.com 203.0.113.10; do
  scenario
  REMOTE_CONNECT_HOST="$value"
  run_entrypoint
  check_not_contains "REMOTE_CONNECT_HOST='${value}' is valid" "REMOTE_CONNECT_HOST must be" "$OUT"
done

scenario
STF_PROVIDER_CONNECT_PUSH=""
WDA_PORT=abc
PLATFORM_NAME=windows
run_entrypoint
check_contains "every invalid variable is reported: first" "PLATFORM_NAME must be" "$OUT"
check_contains "every invalid variable is reported: second" "STF_PROVIDER_CONNECT_PUSH is required" "$OUT"
check_contains "every invalid variable is reported: third" "WDA_PORT must be" "$OUT"

section "STF services"
scenario
run_entrypoint
socat_checks="$(calls socat)"
for host in push-host:7270 sub-host:7250; do
  check_contains "Android: ${host} is checked" "TCP:${host}" "$socat_checks"
done
check_not_contains "Android: the dealers are not checked" "app-host" "$socat_checks"
check "a check is limited to 10 seconds" "10" "$(calls timeout | sort -u)"
check_contains "reachable services are reported" "All the STF services are reachable." "$OUT"
check "reachable services are not awaited" "" "$(waits)"

scenario ios
run_entrypoint
for host in push-host:7270 sub-host:7250 app-host:7160 dev-host:7260; do
  check_contains "iOS: ${host} is checked" "TCP:${host}" "$(calls socat)"
done

scenario
FAKE_FLAKY=sub-host
FAKE_FLAKY_CHECKS=2
STF_SERVICES_WAIT_RETRY=7
run_entrypoint
check "a service reachable on the third check starts STF" "0" "$STATUS"
check_contains "STF starts after the services are reachable" "provider" "$(started)"
check "the checks are repeated every STF_SERVICES_WAIT_RETRY seconds" "$(printf '7\n7')" "$(waits)"
check "the unreachable service is checked again" "3" "$(calls socat | grep -c sub-host)"
check "a reachable service is not checked again" "1" "$(calls socat | grep -c push-host)"
check_contains "an unreachable service is reported" "STF_PROVIDER_CONNECT_SUB 'tcp://sub-host:7250' is not reachable." "$OUT"

scenario
FAKE_DOWN="push-host sub-host"
STF_SERVICES_WAIT_TIMEOUT=0
run_entrypoint
check "unreachable services ask for a restart" "1" "$STATUS"
check_contains "the unreachable services are listed" \
  "STF services are not reachable: STF_PROVIDER_CONNECT_PUSH STF_PROVIDER_CONNECT_SUB. Restarting (1 of 2)!" "$OUT"
check "the restart is counted" "1" "$(cat "${WORK}/zebrunner/stf-services-restarts")"
check "STF is not started with unreachable services" "" "$(started)$(calls websocat)"
run_entrypoint
check "the second restart is asked" "1" "$STATUS"
check_contains "the second restart is reported" "Restarting (2 of 2)!" "$OUT"
# after the restarts the services are awaited in place: the third check of sub-host succeeds
FAKE_DOWN=''
FAKE_FLAKY=sub-host
FAKE_FLAKY_CHECKS=2
reset_calls
run_entrypoint
check "unreachable services after STF_SERVICES_WAIT_RESTARTS restarts are awaited without an exit" "0" "$STATUS"
check_contains "the end of the restarts is reported" "STF services are not reachable after 2 restarts: STF_PROVIDER_CONNECT_SUB. Waiting for them" "$OUT"
check "the awaited services are checked every STF_SERVICES_WAIT_RETRY seconds" "$(printf '30\n30')" "$(waits)"
check_contains "STF starts when the awaited services are back" "provider" "$(started)"
check "the counter is reset for the next start" "false" "$([[ -e "${WORK}/zebrunner/stf-services-restarts" ]] && echo true || echo false)"

scenario
echo 1 > "${WORK}/zebrunner/stf-services-restarts"
run_entrypoint
check "reachable services start STF after a restart" "0" "$STATUS"
check "reachable services reset the counter" "false" "$([[ -e "${WORK}/zebrunner/stf-services-restarts" ]] && echo true || echo false)"

scenario
echo garbage > "${WORK}/zebrunner/stf-services-restarts"
FAKE_DOWN=sub-host
STF_SERVICES_WAIT_TIMEOUT=0
run_entrypoint
check "an invalid counter is 0" "1" "$(cat "${WORK}/zebrunner/stf-services-restarts")"

scenario
FAKE_DOWN=sub-host
STF_SERVICES_WAIT_TIMEOUT=0
STF_SERVICES_WAIT_RESTARTS=0
FAKE_DOWN=''
FAKE_FLAKY=sub-host
FAKE_FLAKY_CHECKS=2
run_entrypoint
check "STF_SERVICES_WAIT_RESTARTS=0 waits without a restart" "0" "$STATUS"
check_contains "STF_SERVICES_WAIT_RESTARTS=0 is reported" "STF services are not reachable after 0 restarts" "$OUT"
check_not_contains "STF_SERVICES_WAIT_RESTARTS=0 asks for no restart" "Restarting" "$OUT"

section "usbmuxd"
scenario ios
run_entrypoint
check_contains "iOS: usbmuxd is checked" "TCP:usbmuxd-host:2222" "$(calls socat)"
check_contains "iOS: /var/run/usbmuxd is forwarded to USBMUXD_SOCKET_ADDRESS" \
  "UNIX-LISTEN:${WORK}/usbmuxd/usbmuxd,fork,reuseaddr,mode=777|TCP:usbmuxd-host:2222" "$(calls socat)"
check_contains "iOS: the forwarding is reported" "/var/run/usbmuxd is forwarded to 'usbmuxd-host:2222'." "$OUT"

scenario ios
echo stale > "${WORK}/usbmuxd/usbmuxd"
run_entrypoint
check "iOS: a stale socket file is replaced" "0" "$STATUS"

scenario ios
FAKE_FLAKY=usbmuxd-host
FAKE_FLAKY_CHECKS=1
USBMUXD_SOCKET_PERIOD=4
run_entrypoint
check "iOS: usbmuxd reachable on the second check is forwarded" "0" "$STATUS"
check_contains "iOS: usbmuxd is checked every USBMUXD_SOCKET_PERIOD seconds" "4" "$(waits)"
check_contains "iOS: unreachable usbmuxd is reported" "usbmuxd 'usbmuxd-host:2222' is not reachable." "$OUT"

scenario ios
FAKE_DOWN=usbmuxd-host
USBMUXD_SOCKET_TIMEOUT=0
run_entrypoint
check "iOS: unreachable usbmuxd asks for a restart" "1" "$STATUS"
check_contains "iOS: unreachable usbmuxd is reported at the end" \
  "/var/run/usbmuxd is not forwarded to 'usbmuxd-host:2222'. Restarting!" "$OUT"
check "iOS: STF is not started without usbmuxd" "" "$(started)"

scenario ios
FAKE_SOCKET=none
USBMUXD_SOCKET_TIMEOUT=0
run_entrypoint
check "iOS: a socket not created asks for a restart" "1" "$STATUS"
check_contains "iOS: a socket not created is reported" "socat did not create ${WORK}/usbmuxd/usbmuxd." "$OUT"

scenario ios
WIRELESS=TRUE
FAKE_DOWN=usbmuxd-host
run_entrypoint
check "iOS: WIRELESS=true starts STF without usbmuxd" "0" "$STATUS"
check_not_contains "iOS: WIRELESS=true does not check usbmuxd" "usbmuxd-host" "$(calls socat)"
check_contains "iOS: WIRELESS=true is reported" "WIRELESS=true: usbmuxd is not forwarded" "$OUT"
check_contains "iOS: WIRELESS=true still waits for WebDriverAgent" "http://connector:8100/status" "$(calls curl)"

scenario
run_entrypoint
check_not_contains "Android: usbmuxd is not forwarded" "usbmuxd" "$(calls socat)"
check "Android: WebDriverAgent is not awaited" "" "$(calls curl)"

section "WebDriverAgent"
scenario ios
WDA_HOST=wda-host
WDA_PORT=8200
run_entrypoint
check_contains "iOS: WDA_HOST and WDA_PORT are checked" "-sf|--max-time|5|-o|/dev/null|http://wda-host:8200/status" "$(calls curl)"
check_contains "iOS: the status of WebDriverAgent is logged" 'WebDriverAgent is up: {"value":{"ready":true}}' "$OUT"

scenario ios
FAKE_WDA_AFTER=2
run_entrypoint
check "iOS: WebDriverAgent up on the third request starts STF" "0" "$STATUS"
# the other sleeps are the waits for the usbmuxd socket
check "iOS: WebDriverAgent is requested every 2 seconds" "$(printf '2\n2')" "$(waits | grep -vxF 0.2)"

scenario ios
FAKE_WDA=down
WDA_WAIT_TIMEOUT=0
run_entrypoint
check "iOS: WebDriverAgent down asks for a restart" "1" "$STATUS"
check_contains "iOS: WebDriverAgent down is reported" "WebDriverAgent does not answer http://connector:8100/status. Restarting!" "$OUT"
check "iOS: STF is not started without WebDriverAgent" "" "$(started)"

section "broadcast"
scenario
BROADCAST_PORT=3333
STF_PROVIDER_MIN_PORT=7500
STF_PROVIDER_MAX_PORT=7510
run_entrypoint
check "the screen WebSocket is broadcast to BROADCAST_PORT" "--binary|tcp-l:0.0.0.0:3333|broadcast:ws://127.0.0.1:7500" \
  "$(calls websocat | head -1)"

scenario
export FAKE_STF=busy FAKE_WEBSOCAT_SEC=0.2
run_entrypoint
check "websocat is started again when it exits" "true" "$([[ "$(calls websocat | wc -l)" -ge 2 ]] && echo true || echo false)"
check_contains "the exit of websocat is logged" "The screen broadcast (websocat) exited with 3, it is started again in 1 second." "$OUT"
broadcasts="$(calls websocat | wc -l)"
/bin/sleep 0.5
check "websocat is not started again after the entrypoint" "$broadcasts" "$(calls websocat | wc -l)"

section "ZeroMQ security and the node token"
for platform in android ios; do
  for verbose in false true; do
    scenario "$platform"
    export VERBOSE="$verbose"
    run_entrypoint
    check "${platform}, VERBOSE=${verbose}: the CURVE keys and the node token start STF" "0:yes" \
      "${STATUS}:$([[ -n "$(started)" ]] && echo yes)"
    stf_env="$(calls env)"
    check_contains "${platform}, VERBOSE=${verbose}: STF gets the public key of the server" \
      "STF_ZMQ_CURVE_SERVER_PUBLIC_KEY=${server_key}" "$stf_env"
    check_contains "${platform}, VERBOSE=${verbose}: STF gets the secret key" "STF_ZMQ_CURVE_SECRET_KEY=${secret_key}" "$stf_env"
    check_contains "${platform}, VERBOSE=${verbose}: STF gets the node token" "STF_NODE_TOKEN=${node_token}" "$stf_env"
    check_contains "${platform}, VERBOSE=${verbose}: STF is started" "Starting STF ${platform}" "$OUT"
    check_not_contains "${platform}, VERBOSE=${verbose}: the secret key is not logged" "$secret_key" "$OUT"
    check_not_contains "${platform}, VERBOSE=${verbose}: the node token is not logged" "$node_secret" "$OUT"
    [[ "$verbose" == true ]] && check_contains "${platform}: VERBOSE=true traces the entrypoint" "+ untraced validateSecrets" "$OUT"
  done

  for var in STF_NODE_TOKEN STF_ZMQ_CURVE_SERVER_PUBLIC_KEY STF_ZMQ_CURVE_SECRET_KEY; do
    scenario "$platform"
    unset "$var"
    run_entrypoint
    check_contains "${platform}: a missing ${var} is a configuration error" "${var} is required but empty or unset." "$OUT"
    check "${platform}: nothing is started without ${var}" "0:" "${STATUS}:$(calls socat)$(started)"
  done

  # a wrong prefix, an upper case or too long label, a short or long secret, a character out of base64url, no label
  for value in "mcn2.agent-1.${node_secret}" "mcn1.Agent-1.${node_secret}" "mcn1.-agent.${node_secret}" \
    "mcn1.$(printf '%041d' 0 | tr 0 a).${node_secret}" "mcn1.agent-1.${node_secret%?}" "mcn1.agent-1.${node_secret}c" \
    "mcn1.agent-1.${node_secret%?}=" "mcn1..${node_secret}" "mcn1.agent-1.${node_secret} " "${node_secret}"; do
    for verbose in false true; do
      scenario "$platform"
      export STF_NODE_TOKEN="$value" VERBOSE="$verbose"
      run_entrypoint
      check_contains "${platform}, VERBOSE=${verbose}: the node token '${value:0:20}...' is reported" \
        "STF_NODE_TOKEN must be a node token mcn1.<label>.<secret> (./zebrunner.sh join of mcloud-agent)." "$OUT"
      check "${platform}, VERBOSE=${verbose}: an invalid node token exits with 0 and starts nothing" "0:" \
        "${STATUS}:$(calls socat)$(started)"
      check_not_contains "${platform}, VERBOSE=${verbose}: the invalid node token is not logged" "${node_secret:4:30}" "$OUT"
    done
  done
  for value in "mcn1.a.${node_secret}" "mcn1.$(printf '%040d' 0 | tr 0 a).${node_secret}" "mcn1.0-node-.${node_secret}"; do
    scenario "$platform"
    export STF_NODE_TOKEN="$value"
    run_entrypoint
    check_not_contains "${platform}: the node token '${value:0:20}...' is valid" "STF_NODE_TOKEN must be" "$OUT"
  done
done

scenario
export VERBOSE=true
STF_NODE_TOKEN=""
run_entrypoint
check_contains "VERBOSE=true: the untraced checks still report" "STF_NODE_TOKEN is required but empty or unset." "$OUT"
check_contains "VERBOSE=true: the trace goes on after the untraced checks" "+ untraced validateSecrets" "$OUT"
check_contains "VERBOSE=true: the commands after the secrets are traced" "+ [[ ! 7404 =~" "$OUT"

scenario
export STF_ZMQ_CURVE_SECRET_KEY="not-a-key-${secret_key}"
run_entrypoint
check_contains "an invalid CURVE key is reported" "STF_ZMQ_CURVE_SECRET_KEY must be a key of 64 hex characters" "$OUT"
check_not_contains "the invalid secret key is not logged" "not-a-key" "$OUT"
check "nothing is started with an invalid CURVE key" "" "$(started)"

section "STF of Android"
scenario
run_entrypoint
check "the provider options" \
  "provider|--allow-remote|--connect-url-pattern|provider-host:<%= publicPort %>|--storage-url|http://stf.example.com:80/|--screen-ws-url-pattern|ws://stf.example.com:80/d/provider-host/<%= serial %>/<%= publicPort %>/" \
  "$(started)"
stf_env="$(calls env)"
check_contains "the provider gets STF_PROVIDER_* as its options" "STF_PROVIDER_MIN_PORT=7404" "$stf_env"
check_contains "the provider gets STF_PROVIDER_NAME" "STF_PROVIDER_NAME=mcloud-linux" "$stf_env"
check_contains "the dealers of iOS are removed for the provider: app" "STF_PROVIDER_CONNECT_APP_DEALER=<unset>" "$stf_env"
check_contains "the dealers of iOS are removed for the provider: dev" "STF_PROVIDER_CONNECT_DEV_DEALER=<unset>" "$stf_env"
check_contains "an empty STF_PROVIDER_CONNECT_PORT is removed: the second port of the range" \
  "STF_PROVIDER_CONNECT_PORT=<unset>" "$stf_env"

scenario
STF_PROVIDER_NAME=""
STF_PROVIDER_DEVICE_NAME=""
run_entrypoint
check_contains "an empty STF_PROVIDER_NAME is removed: the provider uses its default" "STF_PROVIDER_NAME=<unset>" "$(calls env)"
check_contains "an empty STF_PROVIDER_DEVICE_NAME is removed" "STF_PROVIDER_DEVICE_NAME=<unset>" "$(calls env)"

scenario
STF_PROVIDER_HOST=""
STF_PROVIDER_PUBLIC_IP=10.0.0.1
run_entrypoint
check_contains "STF_PROVIDER_HOST is STF_PROVIDER_PUBLIC_IP by default" "--connect-url-pattern|10.0.0.1:<%= publicPort %>" "$(started)"
check_contains "the provider gets the default STF_PROVIDER_HOST" "STF_PROVIDER_HOST=10.0.0.1" "$(calls env)"

scenario
STF_PROVIDER_CONNECT_PORT=7400
run_entrypoint
check_contains "the provider gets STF_PROVIDER_CONNECT_PORT as its --connect-port" "STF_PROVIDER_CONNECT_PORT=7400" "$(calls env)"
check_not_contains "STF_PROVIDER_CONNECT_PORT is not passed twice" "--connect-port" "$(started)"

scenario
unset REMOTE_CONNECT_HOST
run_entrypoint
check_contains "the adb connect URL is STF_PROVIDER_HOST without REMOTE_CONNECT_HOST" \
  "--connect-url-pattern|provider-host:<%= publicPort %>|" "$(started)"

scenario
REMOTE_CONNECT_HOST=mcloud.example.com
run_entrypoint
check_contains "REMOTE_CONNECT_HOST is the host of the adb connect URL" \
  "--connect-url-pattern|mcloud.example.com:<%= publicPort %>|" "$(started)"
check_contains "the screen WebSocket keeps STF_PROVIDER_HOST with REMOTE_CONNECT_HOST" \
  "--screen-ws-url-pattern|ws://stf.example.com:80/d/provider-host/<%= serial %>/<%= publicPort %>/" "$(started)"
check_contains "the provider keeps STF_PROVIDER_HOST with REMOTE_CONNECT_HOST" "STF_PROVIDER_HOST=provider-host" "$(calls env)"

scenario
PUBLIC_IP_PROTOCOL=HTTPS
PUBLIC_IP_PORT=443
run_entrypoint
check_contains "https: the storage URL" "--storage-url|https://stf.example.com:443/" "$(started)"
check_contains "https: the screen WebSocket is wss" "--screen-ws-url-pattern|wss://stf.example.com:443/d/" "$(started)"

section "STF of iOS"
scenario ios
run_entrypoint
check "the ios-device options" \
  "ios-device|--serial|00008030-TEST|--device-name|My Phone|--host|provider-host|--screen-port|7404|--connect-port|8101|--provider|mcloud-linux|--public-ip|stf.example.com|--group-timeout|3600|--storage-url|http://stf.example.com:80/|--screen-jpeg-quality|30|--screen-ping-interval|30000|--screen-ws-url-pattern|ws://stf.example.com:80/d/provider-host/00008030-TEST/7404/|--boot-complete-timeout|60000|--heartbeat-interval|10000|--mute-master|never|--connect-push|tcp://push-host:7270|--connect-sub|tcp://sub-host:7250|--connect-app-dealer|tcp://app-host:7160|--connect-dev-dealer|tcp://dev-host:7260|--connect-url-pattern|provider-host:<%= publicPort %>|--wda-host|connector|--wda-port|8100" \
  "$(started)"

scenario ios
REMOTE_CONNECT_HOST=mcloud.example.com
run_entrypoint
check_contains "iOS: REMOTE_CONNECT_HOST is the host of the adb connect URL" \
  "--connect-url-pattern|mcloud.example.com:<%= publicPort %>|" "$(started)"
check_contains "iOS: the screen WebSocket keeps STF_PROVIDER_HOST with REMOTE_CONNECT_HOST" \
  "--screen-ws-url-pattern|ws://stf.example.com:80/d/provider-host/00008030-TEST/7404/" "$(started)"
check_contains "iOS: --host keeps STF_PROVIDER_HOST with REMOTE_CONNECT_HOST" "--host|provider-host|" "$(started)"

scenario ios
STF_PROVIDER_CONNECT_PORT=7400
run_entrypoint
check_contains "iOS: --connect-port stays MJPEG_PORT with STF_PROVIDER_CONNECT_PORT" "--connect-port|8101|" "$(started)"
check_not_contains "iOS: STF_PROVIDER_CONNECT_PORT is not an option" "7400" "$(started)"

scenario ios
STF_PROVIDER_DEVICE_NAME=""
run_entrypoint
check_contains "an empty device name is passed as it is" "--device-name||--host" "$(started)"

section "exit"
scenario
FAKE_STF_EXIT=3
export FAKE_STF_EXIT
run_entrypoint
check "the exit status of STF is the one of the entrypoint" "3" "$STATUS"
check_contains "the exit status of STF is logged" "STF exited with 3." "$OUT"
check "Android: WebDriverAgent is not requested after STF" "" "$(calls curl)"

scenario ios
run_entrypoint
check "STF exited with 0 ends the entrypoint with 0" "0" "$STATUS"
check_contains "iOS: the status of WebDriverAgent is logged after STF (#184)" "--verbose|--max-time|5|http://connector:8100/status" "$(calls curl)"

scenario
export FAKE_STF=hang
PATH="${WORK}/bin:${PATH}" bash "${WORK}/entrypoint.sh" > "${WORK}/hang.out" 2>&1 &
entrypoint_pid=$!
for _ in $(seq 50); do
  [[ -n "$(started)" ]] && break
  /bin/sleep 0.1
done
/bin/sleep 0.3
kill -TERM "$entrypoint_pid"
wait "$entrypoint_pid"
STATUS=$?
check_contains "SIGTERM of the entrypoint is passed to STF" "SIGTERM" "$(started)"
check "the entrypoint exits with the status of the stopped STF" "143" "$STATUS"
check_contains "the stop of STF is logged" "STF exited with 143." "$(cat "${WORK}/hang.out")"

# stop_while <description> <sleep seconds>: SIGTERM while the entrypoint sleeps these seconds before the start of STF
# ends it at once with 0 and stops its background processes
stop_while() {
  export FAKE_SLEEP_HANG="$2"
  PATH="${WORK}/bin:${PATH}" bash "${WORK}/entrypoint.sh" > "${WORK}/stop.out" 2>&1 &
  local entrypoint_pid=$!
  for _ in $(seq 50); do
    [[ -n "$(calls sleep | grep -xF "$2")" ]] && break
    /bin/sleep 0.1
  done
  local started="$SECONDS"
  kill -TERM "$entrypoint_pid"
  wait "$entrypoint_pid"
  STATUS=$?
  check "$1: SIGTERM ends the entrypoint with 0" "0" "$STATUS"
  check "$1: SIGTERM ends the wait at once" "true" "$([[ $((SECONDS - started)) -lt 5 ]] && echo true || echo false)"
  check_contains "$1: the stop is logged" "Stopped before the start of STF. Exiting!" "$(cat "${WORK}/stop.out")"
  /bin/sleep 0.2
  local sleep_pid
  sleep_pid="$(cat "${WORK}/sleep.pid" 2> /dev/null)"
  check "$1: the background sleep is stopped" "false" "$(kill -0 "$sleep_pid" 2> /dev/null && echo true || echo false)"
  kill "$sleep_pid" 2> /dev/null
  check "$1: STF is not started" "" "$(started)"
}

scenario
FAKE_DOWN=sub-host
STF_SERVICES_WAIT_RETRY=7
stop_while "the wait for the STF services" 7

scenario ios
FAKE_SOCKET=none
stop_while "the wait for usbmuxd" 5

scenario ios
FAKE_WDA=down
stop_while "the wait for WebDriverAgent" 2

section "logs"
scenario
LOGGER_LEVEL=ERROR
run_entrypoint
check_not_contains "LOGGER_LEVEL=ERROR hides INFO" "[INFO]" "$OUT"
scenario
LOGGER_LEVEL=DEBUG
run_entrypoint
check_contains "the log lines have the format of util/logger.sh" "] [INFO] All the STF services are reachable." "$OUT"

finish
