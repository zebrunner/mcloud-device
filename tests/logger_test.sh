#!/bin/bash
# Tests of the logger util/logger.sh: level filtering, the default level, case-insensitive levels, multi-word messages.
source "$(dirname "$0")/lib.sh"
cd "$REPO" || exit 1

# the script under test: util/ of an image, files/util/ of appium, shared/util/ of mcloud-conventions
for LOGGER_SH in util/logger.sh files/util/logger.sh shared/util/logger.sh; do
  [[ -f "$LOGGER_SH" ]] && break
done
export LOGGER_SH

# run_logger <LOGGER_LEVEL, empty for unset> <logger arguments...>: the output of one logger call
run_logger() {
  local level="$1"
  shift
  LEVEL="$level" bash -c '
    [[ -n "$LEVEL" ]] && export LOGGER_LEVEL="$LEVEL" || unset LOGGER_LEVEL
    source "$LOGGER_SH"
    logger "$@"
  ' _ "$@"
}

section "default level"
check_contains "INFO is shown" "[INFO] visible" "$(run_logger "" INFO visible)"
check_contains "no level means INFO" "[INFO] plain message" "$(run_logger "" plain message)"
check "DEBUG is hidden" "" "$(run_logger "" DEBUG hidden)"
check_contains "ERROR is shown" "[ERROR] broken" "$(run_logger "" ERROR broken)"

section "levels"
check_contains "DEBUG level shows DEBUG" "[DEBUG] visible" "$(run_logger DEBUG DEBUG visible)"
check "WARN level hides INFO" "" "$(run_logger WARN INFO hidden)"
check_contains "WARN level shows WARN" "[WARN] visible" "$(run_logger WARN WARN visible)"
check "ERROR level hides WARN" "" "$(run_logger ERROR WARN hidden)"
check_contains "ERROR level shows ERROR" "[ERROR] visible" "$(run_logger ERROR ERROR visible)"

section "unknown level"
check_contains "unknown LOGGER_LEVEL means INFO" "[INFO] visible" "$(run_logger TRACE INFO visible)"
check "unknown LOGGER_LEVEL hides DEBUG" "" "$(run_logger TRACE DEBUG hidden)"
check_contains "unknown message level is a part of the INFO message" "[INFO] TRACE text" "$(run_logger "" TRACE text)"

section "empty call"
check_contains "no arguments is an empty INFO message" "[INFO]" "$(run_logger "" 2>&1)"
check_not_contains "no arguments is not an error" "bad array subscript" "$(run_logger "" 2>&1)"

section "case"
check_contains "lower case message level" "[WARN] visible" "$(run_logger INFO warn visible)"
check_contains "lower case LOGGER_LEVEL" "[ERROR] visible" "$(run_logger error ERROR visible)"
check "lower case LOGGER_LEVEL filters" "" "$(run_logger error warn hidden)"

section "format"
check_contains "message words are joined" "[INFO] one two three" "$(run_logger INFO INFO one two three)"
line="$(run_logger INFO INFO message)"
if [[ "$line" =~ ^\[[0-9]{2}/[0-9]{2}/[0-9]{4}\ [0-9]{2}:[0-9]{2}:[0-9]{2}\]\ \[INFO\]\ message$ ]]; then
  pass "line is '[dd/mm/yyyy HH:MM:SS] [LEVEL] message'"
else
  fail "line is '[dd/mm/yyyy HH:MM:SS] [LEVEL] message'" "unexpected format" "$line"
fi
check_contains "escapes are interpreted" "$(printf 'a\nb')" "$(run_logger INFO INFO 'a\nb')"

finish
