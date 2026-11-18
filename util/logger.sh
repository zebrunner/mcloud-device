#!/bin/bash

#### Help:
# To use logger you need to call this file from your code e.g.
# '. /some/path/logger.sh'
#
# You can use following env vars to control logger:
# LOGGER_LEVEL=[DEBUG/INFO/WARN/ERROR]       (default: INFO)    - Lower level of logs to show
# LOGGER_COLOR=[auto/always/never]           (default: auto)    - Colored level: auto on a terminal without NO_COLOR
#
# Examples:
# > logger info info_message
#   [26/03/2024 10:20:22] [INFO] info_message
# > logger Error error_message
#   [26/03/2024 10:22:53] [ERROR] error_message
# > logger no_logger_level
#   [26/03/2024 10:24:38] [INFO] no_logger_level
# > loggerBanner mcloud-device 3.2.0 "udid 00008110-001A"
#   [26/03/2024 10:24:38] [INFO] <U+2501><U+2501> mcloud-device 3.2.0 <U+00B7> udid 00008110-001A
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

  # The level is colored on a terminal only: the lines of docker logs stay plain
  local levelText="[${logName}]"
  local color="${LOGGER_COLOR:-auto}"
  if [[ "$color" == "always" || ("$color" == "auto" && -t 1 && -z "${NO_COLOR:-}" && "${TERM:-}" != "dumb") ]]; then
    case "$logName" in
    DEBUG) levelText=$'\033[90m'"${levelText}"$'\033[0m' ;;
    INFO) levelText=$'\033[32m'"${levelText}"$'\033[0m' ;;
    WARN) levelText=$'\033[33m'"${levelText}"$'\033[0m' ;;
    ERROR) levelText=$'\033[31m'"${levelText}"$'\033[0m' ;;
    esac
  fi

  # Log here
  echo -e "[$(date +'%d/%m/%Y %H:%M:%S')] ${levelText} ${logMessage}"
}

# loggerBanner <service> <version> [<fact>...]: the first log line of a service (CONVENTIONS.md#terminal-output), an
# INFO line '<heavy line> <service> <version> <middle dot> <fact> ...'; the glyphs are the bytes of U+2501 and U+00B7
loggerBanner() {
  local line=$'\xe2\x94\x81\xe2\x94\x81'" $1 $2"
  local fact
  for fact in "${@:3}"; do
    line+=$' \xc2\xb7 '"${fact}"
  done
  logger "INFO" "$line"
}
