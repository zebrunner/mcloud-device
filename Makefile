# Project checks; `make check` runs the linters, the script tests and the docker image tests (CONVENTIONS.md)
SHELL := /bin/bash
VENV := .venv
export PATH := $(CURDIR)/$(VENV)/bin:$(PATH)
# the tests of `make docker`, every other tests/*_test.sh is a test of `make test`
DOCKER_TESTS := tests/image_test.sh

# The image (CONVENTIONS.md#makefile): `make build VERSION=<tag>`, `make push VERSION=<tag>` (docker login first);
# IMAGE_REPO overrides the repository, PLATFORMS the platforms of the push
IMAGE_REPO ?= public.ecr.aws/zebrunner/mcloud-device
VERSION ?= dev
PLATFORMS ?= linux/amd64,linux/arm64

.DEFAULT_GOAL := help
.PHONY: help check lint test docker build push

help: ## this list
	@grep -E '^[a-z0-9-]+:.*## ' $(MAKEFILE_LIST) | sed -E 's/:.*## /\t/'

check: ## everything below, as CI runs it; every step runs, the failed ones fail the target
	@status=0; for target in lint test docker; do $(MAKE) --no-print-directory $$target || status=1; done; exit $$status

lint: $(VENV)/.installed ## the linters and the text file checks (tests/lint.sh)
	tests/lint.sh

test: ## every tests/*_test.sh but DOCKER_TESTS: stubs instead of the real tools, no docker needed
	@status=0; for t in $(filter-out $(DOCKER_TESTS),$(sort $(wildcard tests/*_test.sh))); do $$t || status=1; done; exit $$status

docker: ## DOCKER_TESTS: the image is built once, IMAGE overrides its tag and REBUILD=true rebuilds it
	@status=0; for t in $(DOCKER_TESTS); do $$t || status=1; done; exit $$status

build: ## the image IMAGE_REPO:VERSION for the platform of this machine: make build VERSION=<tag>
	docker build --progress=plain --provenance=false --build-arg VERSION=$(VERSION) --tag $(IMAGE_REPO):$(VERSION) .

push: ## the image IMAGE_REPO:VERSION for PLATFORMS, built by docker buildx and pushed: make push VERSION=<tag>
	@[[ "$(VERSION)" != dev ]] || { echo "make push VERSION=<tag>: the tag of the image is required"; exit 1; }
	@docker buildx inspect mcloud > /dev/null 2>&1 || docker buildx create --name mcloud --driver docker-container --driver-opt network=host > /dev/null
	docker buildx build --builder mcloud --progress=plain --provenance=false --platform $(PLATFORMS) \
	  --build-arg VERSION=$(VERSION) --tag $(IMAGE_REPO):$(VERSION) --push .

# The tools of tests/requirements-lint.txt in .venv; the hadolint-py wheel for macOS is broken, brew provides it there
$(VENV)/.installed: tests/requirements-lint.txt
	python3 -m venv $(VENV)
	@if [[ "$$(uname)" == Darwin ]]; then \
	  grep -v '^hadolint-py' tests/requirements-lint.txt > $(VENV)/requirements.txt; \
	else \
	  cp tests/requirements-lint.txt $(VENV)/requirements.txt; \
	fi
	$(VENV)/bin/pip install --quiet --disable-pip-version-check --requirement $(VENV)/requirements.txt
	@command -v hadolint > /dev/null || { echo "hadolint is missing: brew install hadolint"; exit 1; }
	touch $@
