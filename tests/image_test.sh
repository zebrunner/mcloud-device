#!/bin/bash
# Checks of the docker image: build, contents, configuration and the startup of STF for Android and iOS with fake STF
# services, adb, usbmuxd and WebDriverAgent (a container of the same image with socat listeners and a python HTTP server).
# IMAGE overrides the tag of the tested image (it is built when missing, REBUILD=true builds it anyway),
# PLATFORM its platform (the image is amd64 only, as its base image).
source "$(dirname "$0")/lib.sh"
cd "$REPO" || exit 1

IMAGE="${IMAGE:-mcloud-device:test}"
PLATFORM="${PLATFORM:-linux/amd64}"
PREFIX="mcloud-device-test-$$"
NETWORK="${PREFIX}-net"
SERVICES="${PREFIX}-services"

require_cmd docker
docker info > /dev/null 2>&1 || skip "requires a running docker daemon"

# cleanup: removes the containers and the network of the test
# called by the EXIT trap of lib.sh
# shellcheck disable=SC2329
cleanup() {
  docker rm --force "$SERVICES" "${PREFIX}-android" "${PREFIX}-ios" "${PREFIX}-down" > /dev/null 2>&1
  docker network rm "$NETWORK" > /dev/null 2>&1
}

# in_image <command...>: runs the command in a new container of the image instead of the entrypoint
in_image() {
  docker run --rm --platform "$PLATFORM" --entrypoint "$1" "$IMAGE" "${@:2}" 2>&1
}

# wait_for <seconds> <command...>: retries the command every second until it succeeds
wait_for() {
  local deadline=$((SECONDS + $1))
  while [[ $SECONDS -lt $deadline ]]; do
    "${@:2}" > /dev/null 2>&1 && return 0
    sleep 1
  done
  return 1
}

# shellcheck disable=SC2329
# is_healthy <container>: the healthcheck of the image passes in the container
is_healthy() {
  docker exec "$1" pgrep -f "stf (provider|ios-device)"
}

# shellcheck disable=SC2329
# is_started <container>: the entrypoint has started STF
is_started() {
  docker logs "$1" 2>&1 | grep -q "Starting STF"
}

# start_device <name> <env...>: starts a device container connected to the fake services
start_device() {
  docker run --detach --name "$1" --network "$NETWORK" --platform "$PLATFORM" \
    --env STF_PROVIDER_CONNECT_PUSH="tcp://${SERVICES}:7270" --env STF_PROVIDER_CONNECT_SUB="tcp://${SERVICES}:7250" \
    --env RETHINKDB_PORT_28015_TCP="tcp://${SERVICES}:28015" --env STF_PROVIDER_PUBLIC_IP=stf.example.com \
    --env STF_PROVIDER_HOST=provider.example.com "${@:2}" "$IMAGE" > /dev/null
}

section "build"
if [[ "${REBUILD:-false}" != "true" ]] && docker image inspect "$IMAGE" > /dev/null 2>&1; then
  skip_check "image builds" "$IMAGE exists, REBUILD=true builds it again"
elif docker build --progress=plain --platform "$PLATFORM" --provenance=false --tag "$IMAGE" . > "${WORK}/build.log" 2>&1; then
  pass "image builds"
  # the build checks of docker (#209): "<n> warning(s) found" and the list of the checks
  check "the build has no warnings" "" "$(grep -E -A10 '^ *[0-9]+ warnings? found' "${WORK}/build.log")"
else
  fail "image builds" "docker build failed" "$(tail -100 "${WORK}/build.log")"
  finish
fi

section "contents"
go_ios_version="$(sed -n -E 's/^.*go-ios\/archive\/refs\/tags\/v([0-9.]+)\.tar\.gz.*$/\1/p' Dockerfile)"
check_contains "go-ios ${go_ios_version} works" "\"version\":\"${go_ios_version}\"" "$(in_image ios --version)"
check_contains "go-ios is a static binary: no glibc of the build machine is needed" "statically linked" \
  "$(in_image sh -c 'file -L /usr/local/bin/ios 2> /dev/null || ldd /usr/local/bin/ios 2>&1')"
websocat_version="$(sed -n -E 's/^.*websocat\/releases\/download\/v([0-9.]+)\/.*$/\1/p' Dockerfile)"
check_contains "websocat ${websocat_version} works" "websocat ${websocat_version}" "$(in_image websocat --version)"
for file in /opt/zebrunner/entrypoint.sh /usr/local/bin/ios /usr/local/bin/websocat; do
  if in_image test -x "$file" > /dev/null; then
    pass "${file} is executable"
  else
    fail "${file} is executable" "not executable" "$(in_image ls -l "$file")"
  fi
done
for file in /opt/zebrunner/util/logger.sh /opt/zebrunner/util/debug.sh; do
  if in_image test -r "$file" > /dev/null; then
    pass "${file} is readable"
  else
    fail "${file} is readable" "not readable" "$(in_image ls -l "$file")"
  fi
done
for tool in bash curl pgrep python3 socat stf; do
  if in_image sh -c "command -v ${tool}" > /dev/null; then
    pass "${tool} is installed"
  else
    fail "${tool} is installed" "${tool} is missing" ""
  fi
done
check "the user is stf" "stf" "$(in_image id -un)"
check "/var/run/usbmuxd is the socket forwarded by the entrypoint" "/tmp/usbmuxd/usbmuxd" "$(in_image readlink /var/run/usbmuxd)"
check "the dirs of the entrypoint belong to stf" "stf stf" "$(in_image stat -c '%U %U' /tmp/usbmuxd /tmp/zebrunner | sort -u | head -1)"

section "configuration"
config="$(docker image inspect "$IMAGE" --format '{{json .Config}}')"
check_contains "entrypoint" '"Entrypoint":["/opt/zebrunner/entrypoint.sh"]' "$config"
check_not_contains "no command of the base image" '"Cmd":[' "$config"
check_contains "user" '"User":"stf"' "$config"
check_contains "healthcheck checks the STF process" '"Test":["CMD","pgrep","-f","stf (provider|ios-device)"]' "$config"
check_contains "license label" '"org.opencontainers.image.licenses":"Apache-2.0"' "$config"
for env in PLATFORM_NAME=android STF_PROVIDER_MIN_PORT=7404 STF_SERVICES_WAIT_TIMEOUT=300 STF_SERVICES_WAIT_RESTARTS=2 \
  WDA_HOST=connector USBMUXD_SOCKET_ADDRESS=connector:2222 BROADCAST_PORT=2223 LOGGER_LEVEL=INFO DEBUG=false; do
  check_contains "default ${env}" "\"${env}\"" "$config"
done

section "configuration validation"
validation="$(docker run --rm --platform "$PLATFORM" "$IMAGE" 2>&1)"
status=$?
check_contains "banner" "MCLOUD-DEVICE" "$validation"
check_contains "the STF services are required" "STF_PROVIDER_CONNECT_PUSH is required but empty or unset." "$validation"
check_contains "invalid configuration ends the entrypoint" "Invalid configuration. Exiting!" "$validation"
check "invalid configuration exits with 0" "0" "$status"
validation="$(docker run --rm --platform "$PLATFORM" --env PLATFORM_NAME=windows "$IMAGE" 2>&1)"
check_contains "invalid PLATFORM_NAME is reported" "PLATFORM_NAME must be android or ios, but it is 'windows'." "$validation"

section "unreachable STF services"
docker run --name "${PREFIX}-down" --platform "$PLATFORM" --env STF_PROVIDER_CONNECT_PUSH=tcp://127.0.0.1:1 \
  --env STF_PROVIDER_CONNECT_SUB=tcp://127.0.0.1:2 --env RETHINKDB_PORT_28015_TCP=tcp://127.0.0.1:3 \
  --env STF_SERVICES_WAIT_TIMEOUT=0 "$IMAGE" > "${WORK}/down.log" 2>&1
check "unreachable services ask for a restart" "1" "$?"
check_contains "the restart is reported" "Restarting (1 of 2)!" "$(cat "${WORK}/down.log")"
check "the restart is counted in the container filesystem" "1" \
  "$(docker cp "${PREFIX}-down:/tmp/zebrunner/stf-services-restarts" - 2> /dev/null | tar -xO 2> /dev/null)"

section "fake STF services"
docker network create "$NETWORK" > /dev/null
# the ports of push, sub, rethinkdb, the dealers, usbmuxd, the MJPEG of WDA and adb accept and ignore the connections,
# WebDriverAgent answers its status
# the script is run by bash of the container
# shellcheck disable=SC2016
docker run --detach --name "$SERVICES" --network "$NETWORK" --platform "$PLATFORM" --entrypoint bash "$IMAGE" -c '
  for port in 7270 7250 28015 7160 7260 2222 8101 5037; do
    socat "TCP-LISTEN:${port},fork,reuseaddr" SYSTEM:"cat > /dev/null" &
  done
  mkdir -p /tmp/wda && echo "{\"value\":{\"ready\":true}}" > /tmp/wda/status
  cd /tmp/wda && exec python3 -m http.server 8100' > /dev/null
# shellcheck disable=SC2329
services_up() {
  docker exec "$SERVICES" curl -sf -o /dev/null http://127.0.0.1:8100/status
}
if wait_for 30 services_up; then
  pass "fake services start"
else
  fail "fake services start" "no answer of the fake WebDriverAgent" "$(docker logs "$SERVICES" 2>&1 | tail -20)"
  finish
fi

section "Android"
start_device "${PREFIX}-android" --env STF_PROVIDER_ADB_HOST="$SERVICES" \
  --env STF_PROVIDER_CONNECT_APP_DEALER=tcp://unknown:1 --env STF_PROVIDER_CONNECT_DEV_DEALER=tcp://unknown:2
wait_for 60 is_started "${PREFIX}-android"
if wait_for 30 is_healthy "${PREFIX}-android"; then
  pass "Android: the provider runs, the container is healthy"
else
  fail "Android: the provider runs, the container is healthy" "no STF process" "$(docker logs "${PREFIX}-android" 2>&1 | tail -30)"
fi
# the provider runs for a while: its options are accepted
sleep 5
logs="$(docker logs "${PREFIX}-android" 2>&1)"
check "Android: the provider still runs" "true" "$(docker inspect "${PREFIX}-android" --format '{{.State.Running}}')"
check_contains "Android: the provider connects to the STF services" "Sending output to \"tcp://${SERVICES}:7270\"" "$logs"
check_not_contains "Android: the provider accepts its options and env vars" "Unknown argument" "$logs"
check_not_contains "Android: the dealers of iOS are not checked" "unknown:1" "$logs"
run_check "Android: the broadcast of the screen listens on BROADCAST_PORT" \
  docker exec "${PREFIX}-android" socat -u OPEN:/dev/null TCP:127.0.0.1:2223
# the pid is expanded in the container
# shellcheck disable=SC2016
docker exec "${PREFIX}-android" sh -c 'kill "$(pgrep -x websocat)"'
# shellcheck disable=SC2329
broadcast_up() {
  docker exec "${PREFIX}-android" socat -u OPEN:/dev/null TCP:127.0.0.1:2223
}
sleep 1
if wait_for 10 broadcast_up; then
  pass "Android: the broadcast is started again after the exit of websocat"
else
  fail "Android: the broadcast is started again after the exit of websocat" "no listener" \
    "$(docker logs "${PREFIX}-android" 2>&1 | tail -10)"
fi
check_contains "Android: the exit of websocat is logged" "The screen broadcast (websocat) exited" "$(docker logs "${PREFIX}-android" 2>&1)"
started="$SECONDS"
docker stop --time 30 "${PREFIX}-android" > /dev/null
check "Android: docker stop stops STF gracefully, without SIGKILL" "true" "$([[ $((SECONDS - started)) -lt 20 ]] && echo true || echo false)"
check "Android: the stopped provider exits with 0" "0" "$(docker inspect "${PREFIX}-android" --format '{{.State.ExitCode}}')"
check_contains "Android: the stop is logged" "STF exited with 0." "$(docker logs "${PREFIX}-android" 2>&1)"

section "iOS"
start_device "${PREFIX}-ios" --env PLATFORM_NAME=ios --env DEVICE_UDID=00008030-TEST --env STF_PROVIDER_NAME=mcloud-test \
  --env STF_PROVIDER_DEVICE_NAME="My iPhone" --env WDA_HOST="$SERVICES" --env USBMUXD_SOCKET_ADDRESS="${SERVICES}:2222" \
  --env STF_PROVIDER_CONNECT_APP_DEALER="tcp://${SERVICES}:7160" --env STF_PROVIDER_CONNECT_DEV_DEALER="tcp://${SERVICES}:7260"
wait_for 60 is_started "${PREFIX}-ios"
if wait_for 30 is_healthy "${PREFIX}-ios"; then
  pass "iOS: ios-device runs, the container is healthy"
else
  fail "iOS: ios-device runs, the container is healthy" "no STF process" "$(docker logs "${PREFIX}-ios" 2>&1 | tail -30)"
fi
sleep 5
logs="$(docker logs "${PREFIX}-ios" 2>&1)"
check "iOS: ios-device still runs" "true" "$(docker inspect "${PREFIX}-ios" --format '{{.State.Running}}')"
check_not_contains "iOS: ios-device accepts its options" "Unknown argument" "$logs"
check_contains "iOS: usbmuxd is forwarded" "/var/run/usbmuxd is forwarded to '${SERVICES}:2222'." "$logs"
check_contains "iOS: WebDriverAgent is awaited" 'WebDriverAgent is up: {"value":{"ready":true}}' "$logs"
check "iOS: /var/run/usbmuxd is a socket of stf" "socket stf" \
  "$(docker exec "${PREFIX}-ios" stat -L -c '%F %U' /var/run/usbmuxd 2>&1 | sed 's/^.*socket/socket/')"
docker stop --time 30 "${PREFIX}-ios" > /dev/null
check_contains "iOS: the status of WebDriverAgent is logged after STF" "HTTP/1.0 200 OK" "$(docker logs "${PREFIX}-ios" 2>&1)"

finish
