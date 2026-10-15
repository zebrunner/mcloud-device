#!/bin/bash

#### Help:
# To use logger you need to call this file from your code e.g.
# '. /some/path/logger.sh'
#
# You can use following env vars to control logger:
# LOGGER_LEVEL=[DEBUG/INFO/WARN/ERROR]       (default: INFO)    - Lower level of logs to show
#
# Examples:
# > logger info info_message
#   [26/03/2024 10:20:22] [INFO] info_message
# > logger Error error_message
#   [26/03/2024 10:22:53] [ERROR] error_message
# > logger no_logger_level
#   [26/03/2024 10:24:38] [INFO] no_logger_level
# NOTE: if logger level is not set or unknown it will always be 'INFO'
# Compatible with the macOS system bash 3.2: no associative arrays, no ${var^^} (CONVENTIONS.md).

# Set default value
: "${LOGGER_LEVEL:=INFO}"

# loggerLevel <level>: sets levelPriority and levelName of the caller for a level in any case, fails for an unknown one
loggerLevel() {
  case "$1" in
  [Dd][Ee][Bb][Uu][Gg]) levelPriority=0 levelName=DEBUG ;;
  [Ii][Nn][Ff][Oo]) levelPriority=1 levelName=INFO ;;
  [Ww][Aa][Rr][Nn]) levelPriority=2 levelName=WARN ;;
  [Ee][Rr][Rr][Oo][Rr]) levelPriority=3 levelName=ERROR ;;
  *) return 1 ;;
  esac
}

# logger [<level>] <message...>: prints the message with the time and the level (INFO by default),
# fails without printing when the level is lower than LOGGER_LEVEL
logger() {
  local levelPriority levelName
  # An unknown level is the default one
  local minPriority=1
  loggerLevel "$LOGGER_LEVEL" && minPriority="$levelPriority"

  local logPriority=1
  local logName="INFO"
  local logMessage="$*"
  if [[ $# -gt 0 ]] && loggerLevel "$1"; then
    logPriority="$levelPriority"
    logName="$levelName"
    logMessage="${*:2}"
  fi

  # Check if level is enough
  [[ "$logPriority" -lt "$minPriority" ]] && return 1

  # Log here
  echo -e "[$(date +'%d/%m/%Y %H:%M:%S')] [${logName}] ${logMessage}"
}
