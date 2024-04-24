#!/bin/bash

. /opt/debug.sh

#### Broadcasting from ws to tcp port
while :; do
  websocat tcp-l:127.0.0.1:"${BROADCASTING_PORT}" broadcast:autoreconnect:ws://localhost:"${STF_PROVIDER_MIN_PORT}" --binary --autoreconnect-delay-millis 2000
  echo "Broadcasting from ws to tcp port is broken. Trying to reconnect in ${BROADCASTING_RETRY_PERIOD} sec."
  sleep "${BROADCASTING_RETRY_PERIOD}"
done
