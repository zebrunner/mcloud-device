#!/bin/bash
# Tests of the debug mode util/debug.sh: the DEBUG pause on exit and the VERBOSE tracing.
source "$(dirname "$0")/lib.sh"
cd "$REPO" || exit 1

# the script under test: util/ of an image, files/util/ of appium, shared/util/ of mcloud-conventions
for debug_sh in util/debug.sh files/util/debug.sh shared/util/debug.sh; do
  [[ -f "$debug_sh" ]] && break
done

# run_debug <env assignments...> -- <script body>: the output of a script sourcing the debug mode
run_debug() {
  local env=()
  while [[ "$1" != "--" ]]; do
    env+=("$1")
    shift
  done
  shift
  env -u DEBUG -u VERBOSE -u DEBUG_TIMEOUT "${env[@]}" bash -c "source ${debug_sh}; $1" 2>&1
}

# the pause of the DEBUG mode is a stub printing its argument
stub sleep 'echo "sleep $*"'

section "plain"
check "no banner and no trace by default" "ok" "$(run_debug -- 'echo ok')"
check "DEBUG=false is ignored" "ok" "$(run_debug DEBUG=false -- 'echo ok')"

section "DEBUG"
out="$(run_debug DEBUG=true DEBUG_TIMEOUT=0 PATH="${WORK}/bin:${PATH}" -- 'echo ok')"
check_contains "banner" "DEBUG mode is on!" "$out"
check_contains "exit is intercepted" "Exit attempt intercepted." "$out"
check_contains "default timeout is 3600" "Sleep for 3600 seconds activated!" "$(run_debug DEBUG=true PATH="${WORK}/bin:${PATH}" -- 'exit 0')"
out="$(run_debug DEBUG=true DEBUG_TIMEOUT=42 PATH="${WORK}/bin:${PATH}" -- 'exit 3')"
check_contains "custom timeout is shown" "Sleep for 42 seconds activated!" "$out"
check_contains "the pause uses DEBUG_TIMEOUT" "sleep 42" "$out"
run_debug DEBUG=true DEBUG_TIMEOUT=0 PATH="${WORK}/bin:${PATH}" -- 'exit 3' > /dev/null
check "exit status is kept" "3" "$?"

section "VERBOSE"
out="$(run_debug VERBOSE=true -- ': probe')"
check_contains "banner" "VERBOSE mode is on!" "$out"
check_contains "commands are traced" "+ : probe" "$out"
check_not_contains "no DEBUG banner" "DEBUG mode" "$out"
check_not_contains "no trace without VERBOSE" "+ :" "$(run_debug -- ': probe')"

finish
