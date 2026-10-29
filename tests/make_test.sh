#!/bin/bash
# The build and push targets of the Makefile (CONVENTIONS.md#makefile) with a docker stub: the commands they run.
source "$(dirname "$0")/lib.sh"
cd "$REPO" || exit 1

record_stub docker
# make_out <make args...>: the output of a make target with the docker stub, its calls are recorded
make_out() {
  reset_calls
  PATH="${WORK}/bin:${PATH}" make --no-print-directory "$@" 2>&1
}

section "build"
make_out build VERSION=1.2.3 > /dev/null
check "make build: the image of this machine" \
  "build|--progress=plain|--provenance=false|--build-arg|VERSION=1.2.3|--tag|public.ecr.aws/zebrunner/mcloud-device:1.2.3|." \
  "$(calls docker)"
make_out build VERSION=1.2.3 IMAGE_REPO=registry.example.com/mcloud-device > /dev/null
check_contains "make build IMAGE_REPO: another repository" "|--tag|registry.example.com/mcloud-device:1.2.3|" "$(calls docker)"
make_out build > /dev/null
check_contains "make build without VERSION: the dev image" "|VERSION=dev|--tag|public.ecr.aws/zebrunner/mcloud-device:dev|" "$(calls docker)"

section "push"
output="$(make_out push)"
check "make push without VERSION: no docker call" "" "$(calls docker)"
check_contains "make push without VERSION: the tag is asked" "make push VERSION=<tag>" "$output"
make_out push VERSION=1.2.3 > /dev/null
check "make push: buildx builds the platforms and pushes" \
  "buildx|inspect|mcloud
buildx|build|--builder|mcloud|--progress=plain|--provenance=false|--platform|linux/amd64,linux/arm64|--build-arg|VERSION=1.2.3|--tag|public.ecr.aws/zebrunner/mcloud-device:1.2.3|--push|." \
  "$(calls docker)"
make_out push VERSION=1.2.3 PLATFORMS=linux/arm64 > /dev/null
check_contains "make push PLATFORMS: other platforms" "|--platform|linux/arm64|" "$(calls docker)"

finish
