#!/bin/bash
# shellcheck disable=SC2034
# The settings and the checks of the project for tests/lint.sh (CONVENTIONS.md): mcloud-device.

scripts=(entrypoint.sh util/*.sh tests/*.sh)

# project_checks: the versions of the Dockerfile in the README
project_checks() {
  section "image contents"
  # the versions of the Dockerfile are listed in the README (Image contents)
  for pattern in 'FROM (public\.ecr\.aws\/zebrunner\/stf:[^@ ]+)@' 'go-ios\/archive\/refs\/tags\/v([0-9.]+)\.tar\.gz' \
    'websocat\/releases\/download\/v([0-9.]+)\/' 'FROM [^ ]* ?(golang:[^@ ]+)@'; do
    version="$(sed -n -E "s/^.*${pattern}.*$/\1/p" Dockerfile | head -1)"
    if [[ -n "$version" ]] && grep -qF "$version" README.md; then
      pass "README lists ${version}"
    else
      fail "README lists the Dockerfile version of '${pattern}'" "'${version}' is missing in README.md" "update the Image contents of README.md"
    fi
  done
}
