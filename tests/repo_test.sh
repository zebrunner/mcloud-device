#!/bin/bash
# Static checks of the repository files, no docker: the pins of the Dockerfile, its env vars and the Dependabot configuration.
source "$(dirname "$0")/lib.sh"
cd "$REPO" || exit 1

section "Dockerfile pins"
from_lines="$(grep '^FROM ' Dockerfile)"
check "the base image and the build stage are <image>:<version>@sha256:<digest>" "" \
  "$(grep -vE '^FROM (--platform=\$\{BUILDPLATFORM\} )?[a-z0-9./-]+:[0-9][A-Za-z0-9.-]*@sha256:[0-9a-f]{64}( AS [a-z-]+)?$' <<< "$from_lines")"
check_contains "the base image is the STF image" "FROM public.ecr.aws/zebrunner/stf:" "$from_lines"
check_not_contains "no unpinned latest tag" ":latest" "$(grep -v '^ *#' Dockerfile)"
# the tools of the entrypoint are installed by the image, the STF base image drops them (zebrunner/stf#1052)
check "the apt packages are the tools of the entrypoint, without recommends" "socat curl procps" \
  "$(sed -n '/apt-get -y install --no-install-recommends/,/&& \\$/p' Dockerfile | tail -1 | sed -E 's/^ +//; s/ *&& \\$//')"
downloads="$(grep -cE 'wget .*https://' Dockerfile)"
check "every download has a sha256 checksum" "$downloads" "$(grep -cE '^ *echo "[0-9a-f]{64}  [^"]+" > ' Dockerfile)"
check "every checksum is checked" "$downloads" "$(grep -cE 'sha256sum -c ' Dockerfile)"
check_contains "go-ios is built without cgo" "CGO_ENABLED=0" "$(cat Dockerfile)"

section "Dockerfile env vars"
# the variables of the configuration are used by the scripts of the image or by STF: the provider of Android reads
# STF_PROVIDER_*, node and ZeroMQ read theirs
env_vars="$(sed -n -E 's/^(ENV)?[[:space:]]+([A-Z][A-Z0-9_]*)=.*/\2/p' Dockerfile | sort -u)"
check "the env vars are found" "true" "$([[ -n "$env_vars" ]] && echo true || echo false)"
unused=""
for var in $env_vars; do
  if ! grep -qw "$var" entrypoint.sh util/*.sh && [[ ! "$var" =~ ^(STF_PROVIDER_|ZMQ_|NODE_) ]]; then
    unused="${unused}${var} "
  fi
done
check "every env var is used by the image" "" "$unused"

section "Dependabot"
config=".github/dependabot.yml"
check_contains "github-actions is updated" "package-ecosystem: github-actions" "$(cat "$config")"
# a new STF base image needs a check of the options of its commands
check_not_contains "the base image is updated by hand" "package-ecosystem: docker" "$(cat "$config")"
check "tests/requirements-lint.txt exists" "true" "$([[ -f tests/requirements-lint.txt ]] && echo true || echo false)"
# the pinned linters: name==version
unpinned="$(grep -vE '^(#|$)' tests/requirements-lint.txt | grep -vE '^[A-Za-z0-9._-]+==[0-9][A-Za-z0-9.]*$' || true)"
check "every linter is pinned as name==version" "" "$unpinned"

finish
