ifneq (,)
.error This Makefile requires GNU Make.
endif

.PHONY: build rebuild lint test _test-version tag pull login push enter

CURRENT_DIR = $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

DIR = .
FILE = Dockerfile
IMAGE = cytopia/bandit
TAG = latest
VERSION = latest
NO_CACHE =


# --------------------------------------------------------------------------------------------------
# Default Target
# --------------------------------------------------------------------------------------------------
help:
	@echo "lint                      Lint project files and repository"
	@echo "build   [VERSION=...]     Build bandit docker image"
	@echo "rebuild [VERSION=...]     Build bandit docker image without cache"
	@echo "test    [VERSION=...]     Test built bandit docker image"
	@echo "tag TAG=...               Retag Docker image"
	@echo "login USER=... PASS=...   Login to Docker hub"
	@echo "push [TAG=...]            Push Docker image to Docker hub"


# --------------------------------------------------------------------------------------------------
# Lint Targets
# --------------------------------------------------------------------------------------------------
lint: lint-workflow
lint: lint-files

.PHONY: lint-workflow
lint-workflow:
	@echo "################################################################################"
	@echo "# Lint Workflow"
	@echo "################################################################################"
	@\
	GIT_CURR_MAJOR="$$( git tag | sort -V | tail -1 | sed 's|\.[0-9]*$$||g' )"; \
	GIT_CURR_MINOR="$$( git tag | sort -V | tail -1 | sed 's|^[0-9]*\.||g' )"; \
	if test -z "$${GIT_CURR_MAJOR}"; then \
		GIT_CURR_MAJOR="0"; \
	fi; \
	if test -z "$${GIT_CURR_MINOR}"; then \
		GIT_CURR_MINOR="0"; \
	fi; \
	GIT_NEXT_TAG="$${GIT_CURR_MAJOR}.$$(( GIT_CURR_MINOR + 1 ))"; \
	if ! grep 'refs:' -A 100 .github/workflows/nightly.yml \
		| grep  "          - '$${GIT_NEXT_TAG}'" >/dev/null; then \
		echo "[ERR] New Tag required in .github/workflows/nightly.yml: $${GIT_NEXT_TAG}"; \
			exit 1; \
		else \
		echo "[OK] Git Tag present in .github/workflows/nightly.yml: $${GIT_NEXT_TAG}"; \
	fi
	@echo

.PHONY: lint-files
lint-files:
	@echo "################################################################################"
	@echo "# Lint Files"
	@echo "################################################################################"
	@docker run --rm -v $(PWD):/data cytopia/file-lint file-cr --text --ignore '.git/,.github/,tests/' --path .
	@docker run --rm -v $(PWD):/data cytopia/file-lint file-crlf --text --ignore '.git/,.github/,tests/' --path .
	@docker run --rm -v $(PWD):/data cytopia/file-lint file-trailing-single-newline --text --ignore '.git/,.github/,tests/' --path .
	@docker run --rm -v $(PWD):/data cytopia/file-lint file-trailing-space --text --ignore '.git/,.github/,tests/' --path .
	@docker run --rm -v $(PWD):/data cytopia/file-lint file-utf8 --text --ignore '.git/,.github/,tests/' --path .
	@docker run --rm -v $(PWD):/data cytopia/file-lint file-utf8-bom --text --ignore '.git/,.github/,tests/' --path .
	@echo


# --------------------------------------------------------------------------------------------------
# Build Targets
# --------------------------------------------------------------------------------------------------
build:
	docker build $(NO_CACHE) \
		--label "org.opencontainers.image.created"="$$(date --rfc-3339=s)" \
		--label "org.opencontainers.image.revision"="$$(git rev-parse HEAD)" \
		--label "org.opencontainers.image.version"="${VERSION}" \
		--build-arg VERSION=$(VERSION) \
		-t $(IMAGE) \
		-f $(DIR)/$(FILE) $(DIR)

rebuild: NO_CACHE=--no-cache
rebuild: pull-base-image
rebuild: build


# --------------------------------------------------------------------------------------------------
# Test Targets
# --------------------------------------------------------------------------------------------------
test:
	@$(MAKE) --no-print-directory _test-version

_test-version:
	@echo "------------------------------------------------------------"
	@echo "- Testing correct version"
	@echo "------------------------------------------------------------"
	@if [ "$(VERSION)" = "latest" ]; then \
		echo "Fetching latest version from GitHub"; \
		LATEST="$$( \
			curl -Ss https://github.com/PyCQA/bandit/releases \
				| tac \
				| tac \
				| grep -Eo 'archive/v[.0-9]+\.zip' \
				| grep -Eo '[.0-9]+[0-9]' \
				| sort -V \
				| tail -1 \
		)"; \
		echo "Testing for latest: $${LATEST}"; \
		if ! docker run --rm $(IMAGE) --version | grep -E "^bandit $${LATEST}"; then \
			echo "Failed"; \
			exit 1; \
		fi; \
	else \
		echo "Testing for version: $(VERSION)"; \
		if ! docker run --rm $(IMAGE) --version | grep -E "^bandit $(VERSION)"; then \
			echo "Failed"; \
			exit 1; \
		fi; \
	fi; \
	echo "Success";


# -------------------------------------------------------------------------------------------------
#  Deploy Targets
# -------------------------------------------------------------------------------------------------
tag:
	docker tag $(IMAGE) $(IMAGE):$(TAG)

login:
	yes | docker login --username $(USER) --password $(PASS)

push:
	docker push $(IMAGE):$(TAG)


# --------------------------------------------------------------------------------------------------
# Helper Targets
# --------------------------------------------------------------------------------------------------
pull-base-image:
	@grep -E '^\s*FROM' Dockerfile-0.11 \
		| sed -e 's/^FROM//g' -e 's/[[:space:]]*as[[:space:]]*.*$$//g' \
		| xargs -n1 docker pull;
	@grep -E '^\s*FROM' Dockerfile-0.12 \
		| sed -e 's/^FROM//g' -e 's/[[:space:]]*as[[:space:]]*.*$$//g' \
		| xargs -n1 docker pull;

enter:
	docker run --rm --name $(subst /,-,$(IMAGE)) -it --entrypoint=/bin/sh $(ARG) $(IMAGE):$(VERSION)

