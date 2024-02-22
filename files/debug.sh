#!/bin/bash

# Debug mode activator
# You can use args and env vars for execution control
# -d - turn on debug mode  [  $DEBUG=true  ]
# -v - verbose output      [ $VERBOSE=true ]

if [[ "${DEBUG}" == 'true' || "$*" =~ "-d" ]]; then
  echo "#######################################################"
  echo "#                                                     #"
  echo "#                  DEBUG mode is on!                  #"
  echo "#                                                     #"
  echo "#######################################################"
  trap "echo 'Exit attempt intercepted. Sleep for 24h activated!'; sleep 86400;" EXIT
fi

if [[ "${VERBOSE}" == 'true' || "$*" =~ "-v" ]]; then
  echo "#######################################################"
  echo "#                                                     #"
  echo "#                 VERBOSE mode is on!                 #"
  echo "#                                                     #"
  echo "#######################################################"
  set -x
fi
