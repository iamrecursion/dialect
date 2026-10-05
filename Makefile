.DEFAULT_GOAL := help

# Commands that must run in the devshell are prefixed with $(SHELL_WRAPPER), which enters it when
# make runs outside it.
ifeq ($(IN_NIX_SHELL),)
    SHELL_WRAPPER := nix develop --command
else
    SHELL_WRAPPER :=
endif

.PHONY: help
help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

# -- Tooling --------------------------------------------------------------------------------------

# Swift tooling comes from the active Xcode toolchain, as it must match the SDK we build against.
# The devshell doesn't provide it.
SWIFT_FORMAT := $(shell xcrun --find swift-format 2>/dev/null)

define require_xcode_tool
@test -n "$(1)" || { \
	echo "error: $(2) is not in the active Xcode toolchain." >&2; \
	echo "       'xcode-select -p' says: $$(xcode-select -p)" >&2; \
	exit 1; \
}
endef

# -- Sources --------------------------------------------------------------------------------------

# Not ours to reformat, and excluded everywhere.
#
#   External                the swift-lispkit fork, carried as a submodule. Its formatting is
#                           upstream's, and reformatting it would make every rebase a conflict.
#   tmp                     local design notes and plans; gitignored, so `git ls-files` never
#                           reports them. Listed in case it's ever un-ignored.
NOT_OURS := ^(External|tmp)/

SWIFT_SOURCES := $(shell git ls-files '*.swift' | grep -Ev '$(NOT_OURS)')
NIX_SOURCES   := $(shell git ls-files '*.nix' | grep -Ev '$(NOT_OURS)')
SHELL_SOURCES := $(shell git ls-files '*.sh' | grep -Ev '$(NOT_OURS)')
YAML_SOURCES  := $(shell git ls-files '*.yml' '*.yaml' | grep -Ev '$(NOT_OURS)')
PY_SOURCES    := $(shell git ls-files '*.py' | grep -Ev '$(NOT_OURS)')

WORKFLOW_SOURCES := $(shell git ls-files '.github/workflows/*.yml' '.github/workflows/*.yaml')

# Four spaces, matching Xcode's editor.
SHFMT_FLAGS := --indent 4 --case-indent

# The formatters leave comment text alone: swift-format neither breaks long lines nor joins short
# ones, and dprint's YAML plugin fixes only a comment's indentation, so comments wrapped at any
# width pass. This pass rewraps comments and never touches code. It runs after swift-format, which
# reindents comments with the code, so it wraps them at their final indentation; swift-format never
# changes comment text, so neither undoes the other.
#
# Doc comments are narrower, as they're read as prose in a popover or on a docs page.
COMMENT_REFLOW    := utils/reflow-comments/reflow_comments.py
COMMENT_WIDTH     := 100
DOC_COMMENT_WIDTH := 80
REFLOW_FLAGS      := --width $(COMMENT_WIDTH) --doc-width $(DOC_COMMENT_WIDTH)
REFLOW            := $(SHELL_WRAPPER) python3 $(COMMENT_REFLOW) $(REFLOW_FLAGS)

# What Dialect adds to its forks (LispKit, MarkdownKit, CLFormat) is formatted by Dialect's rules,
# and nothing upstream owns is touched: files a fork added get swift-format and the full reflow, and
# files upstream owns have only the comments on lines the fork added refilled. The script skips a
# fork that isn't checked out (as in CI) or has no `upstream` remote.
FORMAT_FORK := $(SHELL_WRAPPER) python3 utils/format-fork/format_fork.py $(REFLOW_FLAGS)

# -- Formatting -----------------------------------------------------------------------------------

# Each formatting target does nothing when its language has no sources, as swift-format and shfmt
# fail on an empty argument list.

.PHONY: format-swift
format-swift: ## Format the Swift sources
	$(call require_xcode_tool,$(SWIFT_FORMAT),swift-format)
	@test -z "$(SWIFT_SOURCES)" || $(SWIFT_FORMAT) format --parallel --in-place $(SWIFT_SOURCES)
	@test -z "$(SWIFT_SOURCES)" || $(REFLOW) $(SWIFT_SOURCES)

.PHONY: format-nix
format-nix: ## Format the Nix sources
	@test -z "$(NIX_SOURCES)" || $(SHELL_WRAPPER) nixfmt $(NIX_SOURCES)

.PHONY: format-shell
format-shell: ## Format the shell scripts
	@test -z "$(SHELL_SOURCES)" || $(SHELL_WRAPPER) shfmt $(SHFMT_FLAGS) --write $(SHELL_SOURCES)

.PHONY: format-docs
format-docs: ## Format the docs and configs (Markdown, JSON, YAML)
	@test -z "$(YAML_SOURCES)" || $(REFLOW) $(YAML_SOURCES)
	$(SHELL_WRAPPER) dprint fmt

.PHONY: format-python
format-python: ## Format the Python sources
	@test -z "$(PY_SOURCES)" || $(SHELL_WRAPPER) ruff format $(PY_SOURCES)

.PHONY: format-fork
format-fork: ## Format what Dialect has added to its forks
	$(call require_xcode_tool,$(SWIFT_FORMAT),swift-format)
	@$(FORMAT_FORK) --swift-format $(SWIFT_FORMAT)

.PHONY: format
format: format-swift format-nix format-shell format-python format-docs format-fork ## Format everything

# -- Checking -------------------------------------------------------------------------------------

# swift-format has no --check, so this diffs its output against the file. `diff -u` exits non-zero
# on a difference, and the loop continues so one run reports every offending file.
.PHONY: format-check-swift
format-check-swift: ## Check Swift formatting without changing files
	$(call require_xcode_tool,$(SWIFT_FORMAT),swift-format)
	@test -z "$(SWIFT_SOURCES)" || $(REFLOW) --check $(SWIFT_SOURCES)
	@failed=0; for f in $(SWIFT_SOURCES); do \
		$(SWIFT_FORMAT) format "$$f" | diff -u --label "$$f" --label "$$f (formatted)" "$$f" - || failed=1; \
	done; exit $$failed

.PHONY: format-check-nix
format-check-nix: ## Check Nix formatting without changing files
	@test -z "$(NIX_SOURCES)" || $(SHELL_WRAPPER) nixfmt --check $(NIX_SOURCES)

.PHONY: format-check-shell
format-check-shell: ## Check shell formatting without changing files
	@test -z "$(SHELL_SOURCES)" || $(SHELL_WRAPPER) shfmt $(SHFMT_FLAGS) --diff $(SHELL_SOURCES)

.PHONY: format-check-docs
format-check-docs: ## Check docs and config formatting (Markdown, JSON, YAML)
	@test -z "$(YAML_SOURCES)" || $(REFLOW) --check $(YAML_SOURCES)
	$(SHELL_WRAPPER) dprint check

.PHONY: format-check-python
format-check-python: ## Check Python formatting without changing files
	@test -z "$(PY_SOURCES)" || $(SHELL_WRAPPER) ruff format --check $(PY_SOURCES)

.PHONY: format-check-fork
format-check-fork: ## Check formatting of what Dialect has added to its forks
	$(call require_xcode_tool,$(SWIFT_FORMAT),swift-format)
	@$(FORMAT_FORK) --swift-format $(SWIFT_FORMAT) --check

.PHONY: format-check
format-check: format-check-swift format-check-nix format-check-shell format-check-python format-check-docs format-check-fork ## Check all formatting without changing files

# -- Linting --------------------------------------------------------------------------------------

# `lint` doesn't run `format-check`: CI runs them as separate jobs, so a red Lint means the code is
# wrong and a red Format check means only its layout is. Each target does nothing when its language
# has no sources.

.PHONY: lint-swift
lint-swift: ## Lint the Swift sources
	$(call require_xcode_tool,$(SWIFT_FORMAT),swift-format)
	@test -z "$(SWIFT_SOURCES)" || $(SWIFT_FORMAT) lint --strict --parallel $(SWIFT_SOURCES)

.PHONY: lint-python
lint-python: ## Lint the Python sources
	@test -z "$(PY_SOURCES)" || $(SHELL_WRAPPER) ruff check $(PY_SOURCES)

.PHONY: lint-shell
lint-shell: ## Lint the shell scripts
	@test -z "$(SHELL_SOURCES)" || $(SHELL_WRAPPER) shellcheck $(SHELL_SOURCES)

# actionlint type-checks `${{ }}` expressions, runner labels, and action inputs, and hands every
# `run:` block to shellcheck -- which it finds on PATH, so this must run inside the devshell.
.PHONY: lint-workflows
lint-workflows: ## Lint the GitHub Actions workflows
	@test -z "$(WORKFLOW_SOURCES)" || $(SHELL_WRAPPER) actionlint $(WORKFLOW_SOURCES)

# The devshell is the only description of the toolchain, so this checks that the flake evaluates
# and builds. It needs no wrapper.
.PHONY: lint-nix
lint-nix: ## Check that the flake evaluates and its outputs build
	nix flake check

.PHONY: lint
lint: lint-swift lint-python lint-shell lint-workflows lint-nix ## Run all the linters

# -- Project ------------------------------------------------------------------------------------

# Dialect.xcodeproj is generated from project.yml and gitignored. Sources are globbed from
# Dialect/, so a new file needs only a regeneration.
#
# Local.xcconfig holds developer-specific settings the generated project needs and git must not
# carry. It's copied once, then left alone.
Local.xcconfig: Local.xcconfig.example
	cp $< $@

.PHONY: project
project: Local.xcconfig ## Generate Dialect.xcodeproj from project.yml
	$(SHELL_WRAPPER) xcodegen generate

# -- Submodules -----------------------------------------------------------------------------------

.PHONY: submodules
submodules: ## Check out the submodules (the LispKit, MarkdownKit and CLFormat forks)
	git submodule update --init --recursive

# Builds a fork for the watch simulator, then checks with vtool that every object file is for
# watchOS: SwiftPM ignores `-Xswiftc -target` and reports success on a macOS build. Needs only
# Xcode.
#
# FORK and TARGET pick what to build, e.g. `make fork-watch-build FORK=swift-markdownkit
# TARGET=MarkdownKit`; by default it is LispKit, which builds the MarkdownKit fork along the way.
FORK   ?= swift-lispkit
TARGET ?= LispKit

.PHONY: fork-watch-build
fork-watch-build: ## Build a fork for the watch simulator and verify the platform (FORK=, TARGET=)
	utils/fork-watch-build/fork-watch-build.sh $(FORK) $(TARGET)

# The app's tests run in a watchOS simulator.
.PHONY: test unit-test smoke-test ui-test
test: unit-test smoke-test ui-test ## Run every test: unit, smoke, then UI (SIMULATOR=)

unit-test: project ## Run the unit tests in a watch simulator (SIMULATOR=)
	SIMULATOR='$(SIMULATOR)' utils/app-test/app-test.sh unit

smoke-test: project ## Run the smoke tests: the app starts and its main screens open (SIMULATOR=)
	SIMULATOR='$(SIMULATOR)' utils/app-test/app-test.sh smoke

ui-test: project ## Run the UI tests but the smoke tests, in parallel (SIMULATOR=, UI_WORKERS=)
	SIMULATOR='$(SIMULATOR)' UI_WORKERS='$(UI_WORKERS)' utils/app-test/app-test.sh ui

# -- Cleaning -------------------------------------------------------------------------------------

.PHONY: clean
clean: ## Remove build products
	rm -rf .build DerivedData
