# VICAR Native Toolkit - Makefile
#
# Automates setup of the Docker/OCI container environment for VICAR.
# Ports the former bootstrap.sh into make targets.
#
# Usage:
#   make bootstrap                 # prereq check + pull image + write config + arm direnv
#   make bootstrap CONFIG_ONLY=1   # same, but skip pulling the image
#   make config                    # write .envrc.local only
#   make pull                      # pull the container image only
#   make check                     # verify prerequisites (docker, direnv, daemon)
#   make workspace                 # create the workspace directory
#   make allow                     # run `direnv allow`
#   make help                      # list targets and variables
#
# Configuration (override on the command line, e.g. make bootstrap IMAGE=...):
#   IMAGE          Container image to use
#   CONTAINER      Container name to create
#   MARS_CALIB     Path to MARS calibration files (optional, mounted in container)
#   DISABLE_SELINUX Set to 1 to disable SELinux labeling (required for the M20 image)
#   CONFIG_ONLY    Set to 1 to skip pulling the image during `make bootstrap`

# ===== Configuration =====
IMAGE           ?= ghcr.io/nasa-ammos/tig/terrain-intelligence-generator:opensource
CONTAINER       ?= vicar-sidecar
MARS_CALIB      ?=
DISABLE_SELINUX ?=
CONFIG_ONLY     ?=

# Directory containing this Makefile (works regardless of make -C / cwd).
TOOLKIT_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
CONFIG_FILE := $(TOOLKIT_DIR)/.envrc.local
WORKSPACE   := $(TOOLKIT_DIR)/workspace

# Image is published for linux/amd64 only. Force that platform so pulls
# succeed on Apple Silicon / arm64 hosts (runs via emulation).
PLATFORM ?= linux/amd64

# Colors
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
NC := \033[0m

.DEFAULT_GOAL := help
.PHONY: help bootstrap check pull config workspace allow clean-config

## help: List available targets and configuration variables
help:
	@printf "VICAR Native Toolkit - make targets\n\n"
	@printf "Targets:\n"
	@printf "  %-14s %s\n" "bootstrap" "Full setup: check + pull + config + workspace + direnv allow"
	@printf "  %-14s %s\n" "check"     "Verify prerequisites (docker, direnv, docker daemon)"
	@printf "  %-14s %s\n" "pull"      "Pull the container image ($(PLATFORM))"
	@printf "  %-14s %s\n" "config"    "Write .envrc.local (backs up any existing file)"
	@printf "  %-14s %s\n" "workspace" "Create the workspace directory"
	@printf "  %-14s %s\n" "allow"     "Run 'direnv allow' to arm the toolkit"
	@printf "  %-14s %s\n" "clean-config" "Remove .envrc.local (keeps .backup)"
	@printf "\nVariables (override on the command line):\n"
	@printf "  %-12s %s\n" "IMAGE"       "$(IMAGE)"
	@printf "  %-12s %s\n" "CONTAINER"   "$(CONTAINER)"
	@printf "  %-12s %s\n" "MARS_CALIB"  "$(if $(MARS_CALIB),$(MARS_CALIB),(none))"
	@printf "  %-12s %s\n" "DISABLE_SELINUX" "$(if $(DISABLE_SELINUX),$(DISABLE_SELINUX),(unset))"
	@printf "  %-12s %s\n" "CONFIG_ONLY" "$(if $(CONFIG_ONLY),$(CONFIG_ONLY),(unset))"
	@printf "\nExamples:\n"
	@printf "  make bootstrap\n"
	@printf "  make bootstrap IMAGE=myregistry/vicar:custom\n"
	@printf "  make bootstrap MARS_CALIB=/path/to/mars_calibration_m20\n"
	@printf "  make bootstrap MARS_CALIB=/path/to/mars_calibration_m20 DISABLE_SELINUX=1\n"
	@printf "  make bootstrap CONFIG_ONLY=1\n"

## check: Verify prerequisites are installed and the docker daemon is running
check:
	@echo "=== VICAR Native Toolkit: prerequisite check ==="
	@command -v docker >/dev/null 2>&1 || { \
		printf "$(RED)[x]$(NC) Docker not found\n" >&2; \
		echo "  Ubuntu/Debian: sudo apt install docker.io"; \
		echo "  macOS:         brew install docker"; \
		echo "  Fedora:        sudo dnf install docker"; \
		echo "  See: https://docs.docker.com/get-docker/"; \
		exit 1; }
	@printf "$(GREEN)[v]$(NC) Docker installed\n"
	@command -v direnv >/dev/null 2>&1 || { \
		printf "$(RED)[x]$(NC) direnv not found\n" >&2; \
		echo "  Ubuntu/Debian: sudo apt install direnv"; \
		echo "  macOS:         brew install direnv"; \
		echo "  Fedora:        sudo dnf install direnv"; \
		echo "  Then hook your shell: eval \"\$$(direnv hook bash)\""; \
		echo "  See: https://direnv.net/docs/installation.html"; \
		exit 1; }
	@printf "$(GREEN)[v]$(NC) direnv installed\n"
	@docker info >/dev/null 2>&1 || { \
		printf "$(RED)[x]$(NC) Docker daemon not running\n" >&2; \
		echo "  Ubuntu/Debian: sudo systemctl start docker"; \
		echo "  macOS:         Start Docker Desktop"; \
		echo "  Fedora:        sudo systemctl start docker"; \
		exit 1; }
	@printf "$(GREEN)[v]$(NC) Docker daemon running\n"

## pull: Pull the container image for the target platform
pull: check
	@echo "Pulling container image: $(IMAGE) ($(PLATFORM))"
	@docker pull --platform $(PLATFORM) "$(IMAGE)" || { \
		printf "$(RED)[x]$(NC) Failed to pull image\n" >&2; \
		echo "  - Check the image name is correct"; \
		echo "  - Ensure you have pull access (docker login)"; \
		echo "  - Ensure the image exists in the registry"; \
		exit 1; }
	@printf "$(GREEN)[v]$(NC) Image pulled successfully\n"

## config: Generate .envrc.local (backs up an existing one)
config:
	@echo "Writing configuration: $(CONFIG_FILE)"
	@if [ -f "$(CONFIG_FILE)" ]; then \
		printf "$(YELLOW)[!]$(NC) Existing config found, backing up to $(CONFIG_FILE).backup\n"; \
		cp "$(CONFIG_FILE)" "$(CONFIG_FILE).backup"; \
	fi
	@{ \
		echo "# VICAR Native Toolkit Configuration"; \
		echo "# Generated by 'make config' on $$(date)"; \
		echo ""; \
		echo "# Container settings"; \
		echo "CONTAINER_NAME=\"$(CONTAINER)\""; \
		echo "CONTAINER_IMAGE=\"$(IMAGE)\""; \
		echo ""; \
	} > "$(CONFIG_FILE)"
	@if [ -n "$(MARS_CALIB)" ]; then \
		if [ -d "$(MARS_CALIB)" ]; then \
			abs="$$(cd "$(MARS_CALIB)" && pwd)"; \
			echo "# MARS calibration files" >> "$(CONFIG_FILE)"; \
			echo "MARS_CONFIG_PATH=\"$$abs\"" >> "$(CONFIG_FILE)"; \
			printf "$(GREEN)[v]$(NC) MARS calibration configured: %s\n" "$$abs"; \
		else \
			printf "$(YELLOW)[!]$(NC) MARS calibration path does not exist: $(MARS_CALIB)\n"; \
		fi; \
	fi
	@if [ -n "$(DISABLE_SELINUX)" ]; then \
		echo "" >> "$(CONFIG_FILE)"; \
		echo "# M20: m20filter (32-bit libgfortran.so.3) needs SELinux label enforcement off" >> "$(CONFIG_FILE)"; \
		echo "DISABLE_SELINUX_LABEL=\"true\"" >> "$(CONFIG_FILE)"; \
		printf "$(GREEN)[v]$(NC) SELinux labeling disabled (M20 mode)\n"; \
	fi
	@printf "$(GREEN)[v]$(NC) Configuration created: $(CONFIG_FILE)\n"

## workspace: Create the workspace directory
workspace:
	@mkdir -p "$(WORKSPACE)"
	@printf "$(GREEN)[v]$(NC) Workspace ready: $(WORKSPACE)\n"

## allow: Arm direnv for the toolkit directory
allow:
	@[ -f "$(TOOLKIT_DIR)/.envrc" ] || { \
		printf "$(RED)[x]$(NC) .envrc not found in $(TOOLKIT_DIR)\n" >&2; exit 1; }
	@direnv allow "$(TOOLKIT_DIR)"
	@printf "$(GREEN)[v]$(NC) direnv configured\n"

## bootstrap: Full setup (check, pull unless CONFIG_ONLY, config, workspace, allow)
bootstrap: check
	@echo ""
	@echo "Configuration:"
	@echo "  Image:      $(IMAGE)"
	@echo "  Container:  $(CONTAINER)"
	@if [ -n "$(MARS_CALIB)" ]; then echo "  MARS Calib: $(MARS_CALIB)"; fi
	@echo ""
ifeq ($(CONFIG_ONLY),)
	@$(MAKE) --no-print-directory -f "$(lastword $(MAKEFILE_LIST))" pull
endif
	@$(MAKE) --no-print-directory -f "$(lastword $(MAKEFILE_LIST))" config
	@$(MAKE) --no-print-directory -f "$(lastword $(MAKEFILE_LIST))" workspace
	@$(MAKE) --no-print-directory -f "$(lastword $(MAKEFILE_LIST))" allow
	@echo ""
	@echo "=== Bootstrap Complete ==="
	@printf "$(GREEN)[v]$(NC) VICAR Native Toolkit is ready!\n"
	@echo ""
	@echo "Next steps:"
	@echo "  1. cd $(TOOLKIT_DIR)   (direnv activates the toolkit automatically)"
	@echo "  2. Try:  gen out=test.img nl=10 ns=10"
	@echo "           toolkit-status"
	@if [ -n "$(MARS_CALIB)" ]; then echo "  3. Verify calibration:  toolkit-verify-calib"; fi

## clean-config: Remove the generated .envrc.local (keeps any .backup)
clean-config:
	@rm -f "$(CONFIG_FILE)"
	@printf "$(GREEN)[v]$(NC) Removed $(CONFIG_FILE)\n"
