#!/bin/bash

#### Debug mode activator
# To use this mode you need to call this file from your code e.g.
# '. /some/path/debug.sh'
# You can use following env vars to control debug mode:
# DEBUG=[true/false]       - debug mode         (default: false)
# DEBUG_TIMEOUT <seconds>  - delay before exit  (default: 3600)
# VERBOSE=[true/false]     - verbose mode       (default: false)

# Set default value
: ${DEBUG_TIMEOUT:=3600}

if [[ "${DEBUG}" == "true" ]]; then
  echo "#######################################################"
  echo "#                                                     #"
  echo "#                  DEBUG mode is on!                  #"
  echo "#                                                     #"
  echo "#######################################################"
  trap 'echo "Exit attempt intercepted. Sleep for ${DEBUG_TIMEOUT} seconds activated!"; sleep ${DEBUG_TIMEOUT};' EXIT
fi

if [[ "${VERBOSE}" == "true" ]]; then
  echo "#######################################################"
  echo "#                                                     #"
  echo "#                 VERBOSE mode is on!                 #"
  echo "#                                                     #"
  echo "#######################################################"
  set -x
fi
