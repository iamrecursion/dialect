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

# Four spaces, matching Xcode's editor.
SHFMT_FLAGS := --indent 4 --case-indent

# -- Formatting -----------------------------------------------------------------------------------

# Every formatting target is a no-op when its language has no sources yet, so `make format` works on
# a tree that is still mostly empty. Without the guard, swift-format and shfmt both error out when
# handed an empty argument list.

.PHONY: format-swift
format-swift: ## Format the Swift sources
	$(call require_xcode_tool,$(SWIFT_FORMAT),swift-format)
	@test -z "$(SWIFT_SOURCES)" || $(SWIFT_FORMAT) format --parallel --in-place $(SWIFT_SOURCES)

.PHONY: format-nix
format-nix: ## Format the Nix sources
	@test -z "$(NIX_SOURCES)" || $(SHELL_WRAPPER) nixfmt $(NIX_SOURCES)

.PHONY: format-shell
format-shell: ## Format the shell scripts
	@test -z "$(SHELL_SOURCES)" || $(SHELL_WRAPPER) shfmt $(SHFMT_FLAGS) --write $(SHELL_SOURCES)

.PHONY: format-docs
format-docs: ## Format the docs and configs (Markdown, JSON)
	$(SHELL_WRAPPER) dprint fmt

.PHONY: format
format: format-swift format-nix format-shell format-docs ## Format everything

# -- Checking -------------------------------------------------------------------------------------

# swift-format has no --check, so diff its output against the file. `diff -u` exits non-zero on a
# difference, and the loop keeps going so one run reports every offending file rather than the first.
.PHONY: format-check-swift
format-check-swift: ## Check Swift formatting without changing files
	$(call require_xcode_tool,$(SWIFT_FORMAT),swift-format)
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
format-check-docs: ## Check docs and config formatting without changing files
	$(SHELL_WRAPPER) dprint check

.PHONY: format-check
format-check: format-check-swift format-check-nix format-check-shell format-check-docs ## Check all formatting without changing files

.PHONY: lint
lint: format-check ## Run all the linting tasks

# -- Submodules -----------------------------------------------------------------------------------

.PHONY: submodules
submodules: ## Check out the submodules (the swift-lispkit fork)
	git submodule update --init --recursive

# -- Cleaning -------------------------------------------------------------------------------------

.PHONY: clean
clean: ## Remove build products
	rm -rf .build DerivedData
