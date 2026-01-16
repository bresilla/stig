SHELL := /bin/bash

# ==================================================================================================
# Project configuration
# ==================================================================================================
PROJECT_NAME := $(shell cat NAME 2>/dev/null | tr -d '[:space:]')
ifeq ($(PROJECT_NAME),)
    $(error Error: NAME file not found or empty)
endif

PROJECT_VERSION := $(shell cat VERSION 2>/dev/null | tr -d '[:space:]')
ifeq ($(PROJECT_VERSION),)
    $(error Error: VERSION file not found or empty)
endif

PROJECT_CAP  := $(shell echo $(PROJECT_NAME) | tr '[:lower:]' '[:upper:]')
LATEST_TAG   ?= $(shell git describe --tags --abbrev=0 2>/dev/null)
TOP_DIR      := $(CURDIR)
BUILD_DIR    := $(TOP_DIR)/zig-out

# ==================================================================================================
# Build commands (Zig build system)
# ==================================================================================================
CMD_BUILD       := zig build 2>&1 | tee "$(TOP_DIR)/.complog"
CMD_CONFIG      := zig build --help >/dev/null 2>&1
CMD_RECONFIG    := rm -rf .zig-cache zig-out $(BUILD_DIR) && zig build --help >/dev/null 2>&1
CMD_CLEAN       := rm -rf .zig-cache zig-out $(BUILD_DIR)
CMD_TEST        := zig build test
CMD_TEST_SINGLE  = ./zig-out/bin/$(TEST)
CMD_QUICKFIX    := grep "error:" "$(TOP_DIR)/.complog" > "$(TOP_DIR)/.quickfix" || true

# ==================================================================================================
# Info
# ==================================================================================================
$(info ------------------------------------------)
$(info Project: $(PROJECT_NAME))
$(info Version: $(PROJECT_VERSION))
$(info Build System: zig)
$(info ------------------------------------------)

.PHONY: build b config c reconfig run r test t help h clean docs release

# ==================================================================================================
# Build targets
# ==================================================================================================
build:
	@$(CMD_BUILD)
	@$(CMD_QUICKFIX)

b: build

config:
	@$(CMD_CONFIG)

c: config

reconfig:
	@$(CMD_RECONFIG)

clean:
	@echo "Cleaning build directory..."
	@$(CMD_CLEAN)
	@echo "Build directory cleaned."

# ==================================================================================================
# Run and test
# ==================================================================================================
run:
	@./zig-out/bin/stig

r: run

TEST ?=

test:
	@if [ -n "$(TEST)" ]; then \
		$(CMD_TEST_SINGLE); \
	else \
		$(CMD_TEST); \
	fi

t: test

# ==================================================================================================
# Help
# ==================================================================================================
help:
	@echo
	@echo "Usage: make [target]"
	@echo
	@echo "Available targets:"
	@echo "  build        Build project"
	@echo "  config       Configure and generate build files (preserves cache)"
	@echo "  reconfig     Full reconfigure (cleans everything including cache)"
	@echo "  run          Run the main executable"
	@echo "  test         Run tests (TEST=<name> to run specific test)"
	@echo "  docs         Build documentation (TYPE=mdbook|doxygen)"
	@echo "  release      Create a new release (TYPE=patch|minor|major)"
	@echo
	@echo "Build system: zig"
	@echo

h: help

# ==================================================================================================
# Documentation
# ==================================================================================================
docs:
ifeq ($(TYPE),mdbook)
	@command -v mdbook >/dev/null 2>&1 || { echo "mdbook is not installed. Please install it first."; exit 1; }
	@mdbook build $(TOP_DIR)/book --dest-dir $(TOP_DIR)/docs
	@git add --all && git commit -m "docs: building website/mdbook"
else ifeq ($(TYPE),doxygen)
	@command -v doxygen >/dev/null 2>&1 || { echo "doxygen is not installed. Please install it first."; exit 1; }
else
	$(error Invalid documentation type. Use 'make docs TYPE=mdbook' or 'make docs TYPE=doxygen')
endif

# ==================================================================================================
# Release
# ==================================================================================================
TYPE ?= patch
HAS_REL := $(shell command -v git-rel 2>/dev/null)

release:
	@if [ -z "$(HAS_REL)" ]; then \
		echo "git-rel is not installed. Please install it first."; \
		exit 1; \
	fi
	@if [ -z "$(TYPE)" ]; then \
		echo "Release type not specified. Use 'make release TYPE=[patch|minor|major|m.m.p]'"; \
		exit 1; \
	fi
	@git rel $(TYPE)
