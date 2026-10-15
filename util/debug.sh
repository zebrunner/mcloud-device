#!/bin/bash

#### Help:
# To use debug mode you need to call this file from your code e.g.
# '. /some/path/debug.sh'
#
# You can use following env vars to control debug mode:
# DEBUG=[true/false]       (default: false)    - Intercept exit from script and wait for DEBUG_TIMEOUT
# DEBUG_TIMEOUT <seconds>  (default: 3600)     - Timeout of debug pause
# VERBOSE=[true/false]     (default: false)    - Verbose script execution

# Set default value
: "${DEBUG_TIMEOUT:=3600}"

if [[ "${DEBUG}" == "true" ]]; then
  echo "#######################################################"
  echo "#                                                     #"
  echo "#                  DEBUG mode is on!                  #"
  echo "#                                                     #"
  echo "#######################################################"
  trap 'echo "Exit attempt intercepted. Sleep for ${DEBUG_TIMEOUT} seconds activated!"; sleep "${DEBUG_TIMEOUT}"' EXIT
fi

if [[ "${VERBOSE}" == "true" ]]; then
  echo "#######################################################"
  echo "#                                                     #"
  echo "#                 VERBOSE mode is on!                 #"
  echo "#                                                     #"
  echo "#######################################################"
  set -x
fi
