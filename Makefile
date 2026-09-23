.DEFAULT_GOAL := help

# This is set if inside the devshell, so any command that MUST run in the devshell should have
# $(SHELL_WRAPPER) prefixed.
ifeq ($(IN_NIX_SHELL),)
    SHELL_WRAPPER := nix develop --command
else
    SHELL_WRAPPER :=
endif

.PHONY: help
help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

# -- Tooling --------------------------------------------------------------------------------------

# Swift tooling comes from the active Xcode toolchain, not from nixpkgs: it has to match the SDK we
# build against. The devshell deliberately does not provide it.
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
#                           reports them anyway. Listed for the benefit of anyone who un-ignores it.
NOT_OURS := ^(External|tmp)/

SWIFT_SOURCES := $(shell git ls-files '*.swift' | grep -Ev '$(NOT_OURS)')
NIX_SOURCES   := $(shell git ls-files '*.nix' | grep -Ev '$(NOT_OURS)')
SHELL_SOURCES := $(shell git ls-files '*.sh' | grep -Ev '$(NOT_OURS)')
YAML_SOURCES  := $(shell git ls-files '*.yml' '*.yaml' | grep -Ev '$(NOT_OURS)')
PY_SOURCES    := $(shell git ls-files '*.py' | grep -Ev '$(NOT_OURS)')

WORKFLOW_SOURCES := $(shell git ls-files '.github/workflows/*.yml' '.github/workflows/*.yaml')

# Four spaces, matching Xcode's editor.
SHFMT_FLAGS := --indent 4 --case-indent

# Comments are what the formatters will not touch. swift-format neither breaks a line that runs past
# the limit nor joins short ones back up, and dprint's YAML plugin fixes a comment's indentation but
# never its contents -- so a paragraph wrapped at 60 columns and one wrapped at 140 both pass, for
# ever. This pass is their exact complement: it rewrites comments and never code. It runs after
# swift-format, which reindents comments along with code, so it fills them at their final
# indentation; swift-format never changes comment text, so neither undoes the other. Copied from
# tctiSH, with YAML support added.
#
# Doc comments get a narrower measure than the code above them: they are read as prose, in a popover
# or on a docs page, and 100 columns of that is a wall.
COMMENT_REFLOW    := utils/reflow-comments/reflow_comments.py
COMMENT_WIDTH     := 100
DOC_COMMENT_WIDTH := 80
REFLOW_FLAGS      := --width $(COMMENT_WIDTH) --doc-width $(DOC_COMMENT_WIDTH)
REFLOW            := $(SHELL_WRAPPER) python3 $(COMMENT_REFLOW) $(REFLOW_FLAGS)

# What Dialect adds to its forks (LispKit, MarkdownKit, CLFormat) is formatted by Dialect's rules,
# and nothing upstream owns is touched: files a fork added get swift-format and the full reflow, and
# files upstream owns have only the comments on lines the fork added refilled. The script explains
# why, and skips a fork that is not checked out (as in CI) or has no `upstream` remote.
FORMAT_FORK := $(SHELL_WRAPPER) python3 utils/format-fork/format_fork.py $(REFLOW_FLAGS)

# -- Formatting -----------------------------------------------------------------------------------

# Every formatting target is a no-op when its language has no sources yet, so `make format` works on
# a tree that is still mostly empty. Without the guard, swift-format and shfmt both error out when
# handed an empty argument list.

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

# swift-format has no --check, so diff its output against the file. `diff -u` exits non-zero on a
# difference, and the loop keeps going so one run reports every offending file rather than the first.
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

# Deliberately separate from formatting, and `lint` does not run `format-check`: CI runs the two as
# separate jobs, so a red Lint means the code is wrong and a red Format check means only its layout
# is. Every target is a no-op when its language has no sources yet, as with formatting.

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

# The devshell is the only description of this project's toolchain, so check the flake itself, not
# just that `nix develop` can enter it. Needs no wrapper: it is nix checking nix.
.PHONY: lint-nix
lint-nix: ## Check that the flake evaluates and its outputs build
	nix flake check

.PHONY: lint
lint: lint-swift lint-python lint-shell lint-workflows lint-nix ## Run all the linters

# -- Project ------------------------------------------------------------------------------------

# Dialect.xcodeproj is generated and gitignored; project.yml is the source of truth. Sources are
# globbed from the Dialect/ directory, so adding a file needs no edit here -- only a regeneration.
# Developer-specific settings the generated project needs but git must not carry.
# A file rule rather than a phony one: it is created once, then left alone.
Local.xcconfig: Local.xcconfig.example
	cp $< $@

.PHONY: project
project: Local.xcconfig ## Generate Dialect.xcodeproj from project.yml
	$(SHELL_WRAPPER) xcodegen generate

# -- Submodules -----------------------------------------------------------------------------------

.PHONY: submodules
submodules: ## Check out the submodules (the LispKit, MarkdownKit and CLFormat forks)
	git submodule update --init --recursive

# Builds a fork for the watch simulator and then checks, with vtool, that every object file really
# is for watchOS: SwiftPM ignores `-Xswiftc -target` and reports success on a macOS build, so a
# green build alone proves nothing. Needs only Xcode, not the devshell.
#
# FORK and TARGET pick what to build, e.g. `make fork-watch-build FORK=swift-markdownkit
# TARGET=MarkdownKit`; by default it is LispKit, which builds the MarkdownKit fork along the way.
FORK   ?= swift-lispkit
TARGET ?= LispKit

.PHONY: fork-watch-build
fork-watch-build: ## Build a fork for the watch simulator and verify the platform (FORK=, TARGET=)
	utils/fork-watch-build/fork-watch-build.sh $(FORK) $(TARGET)

# -- Cleaning -------------------------------------------------------------------------------------

.PHONY: clean
clean: ## Remove build products
	rm -rf .build DerivedData
