ifneq (,)
.error This Makefile requires GNU Make.
endif

# Ensure additional Makefiles are present
MAKEFILES = Makefile.docker Makefile.lint
$(MAKEFILES): URL=https://raw.githubusercontent.com/devilbox/makefiles/master/$(@)
$(MAKEFILES):
	@if ! (curl --fail -sS -o $(@) $(URL) || wget -O $(@) $(URL)); then \
		echo "Error, curl or wget required."; \
		echo "Exiting."; \
		false; \
	fi
include $(MAKEFILES)

# Set default Target
.DEFAULT_GOAL := help


# -------------------------------------------------------------------------------------------------
# Default configuration
# -------------------------------------------------------------------------------------------------
# Own vars
TAG = latest

# Makefile.docker overwrites
NAME       = bandit
VERSION    = latest
IMAGE      = cytopia/bandit
FLAVOUR    = latest
DIR        = Dockerfiles

# Extract PHP- and PCS- version from VERSION string
ifeq ($(strip $(VERSION)),latest)
	PYTHON_VERSION = latest
	BANDIT_VERSION  = latest
else
	PYTHON_VERSION = $(subst PYTHON-,,$(shell echo "$(VERSION)" | grep -Eo 'PYTHON-([.0-9]+|latest)'))
	BANDIT_VERSION  = $(subst BANDIT-,,$(shell echo "$(VERSION)"  | grep -Eo 'BANDIT-([.0-9]+|latest)'))
endif

FILE = Dockerfile.${PYTHON_VERSION}
ifneq ($(strip $(PYTHON_VERSION)),latest)
	FILE = Dockerfile.python${PYTHON_VERSION}
endif


# Building from master branch: Tag == 'latest'
ifeq ($(strip $(TAG)),latest)
	ifeq ($(strip $(VERSION)),latest)
		DOCKER_TAG = $(FLAVOUR)
	else
		ifeq ($(strip $(FLAVOUR)),latest)
			ifeq ($(strip $(PYTHON_VERSION)),latest)
				DOCKER_TAG = $(BANDIT_VERSION)
		else
				DOCKER_TAG = $(BANDIT_VERSION)-py$(PYTHON_VERSION)
			endif
		else
			ifeq ($(strip $(PYTHON_VERSION)),latest)
				DOCKER_TAG = $(FLAVOUR)-$(BANDIT_VERSION)
			else
				DOCKER_TAG = $(FLAVOUR)-$(BANDIT_VERSION)-py$(PYTHON_VERSION)
			endif
		endif
	endif
# Building from any other branch or tag: Tag == '<REF>'
else
	ifeq ($(strip $(VERSION)),latest)
	ifeq ($(strip $(FLAVOUR)),latest)
			DOCKER_TAG = latest-$(TAG)
	else
			DOCKER_TAG = $(FLAVOUR)-latest-$(TAG)
		endif
	else
		ifeq ($(strip $(FLAVOUR)),latest)
			ifeq ($(strip $(PYTHON_VERSION)),latest)
				DOCKER_TAG = $(BANDIT_VERSION)-$(TAG)
			else
				DOCKER_TAG = $(BANDIT_VERSION)-py$(PYTHON_VERSION)-$(TAG)
			endif
		else
			ifeq ($(strip $(PYTHON_VERSION)),latest)
				DOCKER_TAG = $(FLAVOUR)-$(BANDIT_VERSION)-$(TAG)
			else
				DOCKER_TAG = $(FLAVOUR)-$(BANDIT_VERSION)-py$(PYTHON_VERSION)-$(TAG)
			endif
		endif
	endif
endif

# Makefile.lint overwrites
FL_IGNORES  = .git/,.github/
SC_IGNORES  = .git/,.github/
JL_IGNORES  = .git/,.github/


# -------------------------------------------------------------------------------------------------
# Default Target
# -------------------------------------------------------------------------------------------------
.PHONY: help
help:
	@echo "lint                      Lint project files and repository"
	@echo
	@echo "build [ARCH=...] [TAG=...]               Build Docker image"
	@echo "rebuild [ARCH=...] [TAG=...]             Build Docker image without cache"
	@echo "push [ARCH=...] [TAG=...]                Push Docker image to Docker hub"
	@echo
	@echo "manifest-create [ARCHES=...] [TAG=...]   Create multi-arch manifest"
	@echo "manifest-push [TAG=...]                  Push multi-arch manifest"
	@echo
	@echo "test [ARCH=...]                          Test built Docker image"
	@echo


# -------------------------------------------------------------------------------------------------
#  Docker Targets
# -------------------------------------------------------------------------------------------------
.PHONY: build
build: ARGS+=--build-arg BANDIT_VERSION=$(BANDIT_VERSION)
build: docker-arch-build

.PHONY: rebuild
rebuild: ARGS+=--build-arg BANDIT_VERSION=$(BANDIT_VERSION)
rebuild: docker-arch-rebuild

.PHONY: push
push: docker-arch-push


# -------------------------------------------------------------------------------------------------
#  Manifest Targets
# -------------------------------------------------------------------------------------------------
.PHONY: manifest-create
manifest-create: docker-manifest-create

.PHONY: manifest-push
manifest-push: docker-manifest-push


# -------------------------------------------------------------------------------------------------
# Test Targets
# -------------------------------------------------------------------------------------------------
.PHONY: test
test: _test-bandit-version
test: _test-python-version
test: _test-run

.PHONY: _test-bandit-version
_test-bandit-version:
	@echo "------------------------------------------------------------"
	@echo "- Testing correct version"
	@echo "------------------------------------------------------------"
	@if [ "$(BANDIT_VERSION)" = "latest" ]; then \
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
		if ! docker run --rm --platform $(ARCH) $(IMAGE):$(DOCKER_TAG) --version | grep -E "^bandit $${LATEST}"; then \
			echo "Failed"; \
			exit 1; \
		fi; \
	else \
		echo "Testing for version: $(BANDIT_VERSION)"; \
		if ! docker run --rm --platform $(ARCH) $(IMAGE):$(DOCKER_TAG) --version | grep -E "^bandit $(BANDIT_VERSION)"; then \
			echo "Failed"; \
			exit 1; \
		fi; \
	fi; \
	echo "Success";

.PHONY: _test-python-version
_test-python-version:
	@echo "------------------------------------------------------------"
	@echo "- Testing correct Python version"
	@echo "------------------------------------------------------------"
	@if [ "$(PYTHON_VERSION)" = "latest" ]; then \
		if ! docker run --rm --platform $(ARCH) --entrypoint=python $(IMAGE):$(DOCKER_TAG) --version | grep -E '^Python [.0-9]+'; then \
			echo "Failed"; \
			exit 1; \
		fi; \
	else \
		echo "Testing for tag: $(PYTHON_VERSION)"; \
		if ! docker run --rm --platform $(ARCH) --entrypoint=python $(IMAGE):$(DOCKER_TAG) --version | grep -E "^Python $(PYTHON_VERSION)"; then \
			echo "Failed"; \
			exit 1; \
		fi; \
	fi; \
	echo "Success"

.PHONY: _test-run
_test-run:
	@echo "------------------------------------------------------------"
	@echo "- Testing python bandit (Failure)"
	@echo "------------------------------------------------------------"
	@if docker run --rm --platform $(ARCH) -v $(CURRENT_DIR)/tests:/data $(IMAGE):$(DOCKER_TAG) failure.py ; then \
		echo "Failed"; \
		exit 1; \
	else \
		echo "OK"; \
	fi;
	@echo "------------------------------------------------------------"
	@echo "- Testing python bandit (Success)"
	@echo "------------------------------------------------------------"
	@if ! docker run --rm --platform $(ARCH) -v $(CURRENT_DIR)/tests:/data $(IMAGE):$(DOCKER_TAG) success.py ; then \
		echo "Failed"; \
		exit 1; \
	else \
		echo "OK"; \
	fi;
	@echo "Success";
