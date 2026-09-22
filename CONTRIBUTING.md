# Contributing to Dialect

Thanks for your interest in contributing to (or even just building) Dialect! This file provides a
brief guide on how to get setup and build the app.

## Prerequisites

- **Xcode 27** or later, with the watchOS 27 SDK. Swift tooling (`swift-format`, `xcodebuild`,
  `simctl`) comes from the active Xcode toolchain as it has to match the SDK we build against.
- **Nix** with flakes enabled, for everything else.

Everything except Xcode lives in the development shell. You should never need to install `xcodegen`,
`dprint`, `nixfmt` or `shfmt` yourself.

## Setting Up

```bash
git clone git@github.com:iamrecursion/dialect.git
cd dialect
make submodules   # checks out the swift-lispkit fork
make project      # generates Dialect.xcodeproj
```

Then open `Dialect.xcodeproj`, or build from the command line.

`make` targets run themselves inside the dev shell automatically, so you do not have to be in
`nix develop` first. If you are already in one, they notice and do not nest.

Run `make help` for the full list of targets.

## Xcode Project Generation

The `Dialect.xcodeproj` is generated and gitignored with `project.yml` as the source of truth. The
project file is an artifact and is intended to be regenerated using `xcodebuild` from the
`project.yml` description.

This means that changes made through Xcode's project UI are **destroyed by the next `make project`**
as this regenerates the files that would store them. Adding a build setting, a target, or a
capability means editing `project.yml` rather than working in XCode.

Adding _source files_ is the exception as `project.yml` globs the `Dialect/` and `DialectCompanion/`
directories, so creating a file within those is enough. Regenerate and it appears.

## Signing

Simulator builds need no signing and work out of the box.

Builds that run on a **physical device** need your Apple Developer team. Because the project is
regenerated, setting it in Xcode's signing UI does not survive. Put it in `Local.xcconfig` instead,
which is gitignored and created for you from `Local.xcconfig.example` on the first `make project`:

```
DEVELOPMENT_TEAM = ABCDE12345
```

Xcode reads it natively, and `xcodebuild` honors it, and CI can still override it on the command
line:

```bash
xcodebuild build -scheme Dialect -destination 'generic/platform=watchOS' \
  DEVELOPMENT_TEAM=ABCDE12345
```

## Formatting and Linting

Both are enforced by CI, as separate jobs, and both are checkable without modifying files:

```bash
make format        # rewrite everything
make format-check  # verify formatting without changing anything
make lint          # run the linters
```

Per-language targets exist too: `format-swift`, `format-nix`, `format-shell`, `format-python`, and
`format-docs`, each with a `format-check-*` twin, and `lint-swift`, `lint-python`, `lint-shell`,
`lint-workflows`, and `lint-nix`. `lint` does not include `format-check`: a lint failure means the
code is wrong, a format failure only that its layout is.

Source lists come from `git ls-files`, so **a new file must be at least staged before the formatters
and linters will see it**. Nix goes further: `flake.nix` must be staged before _any_ `make` target
works at all, because flakes only see tracked files.

`External/` is excluded everywhere as reformatting the fork would turn every rebase into a conflict.

## The LispKit Fork

Dialect's Scheme runtime is a fork of [LispKit](https://github.com/objecthub/swift-lispkit),
referenced as a submodule at `External/swift-lispkit` and consumed by SwiftPM as a local path
dependency. The submodule SHA thus pins the version.

The fork follows strict branch discipline:

- **The default branch carries no changes from us** so that it mirrors upstream exactly.
  `git pull upstream master` must remain trivial.
- **Dialect work lives on `watchos-support`**, as a linear commit series.
- **Rebase, never merge.** Upstream bumps are
  `git rebase --onto <new-upstream> <old-upstream> watchos-support`. `git format-patch` against the
  default branch produces a readable patch set.

Two rules hold inside the fork:

1. **Object Representations are Frozen:** No changes to `Expr`, `Procedure`, `Code`, or anything
   under `Sources/LispKit/Data/`. Divergence there would make upstream merges horrendous.
2. **Modified Files Carry an Apache §4(b) Change Notice:** The first line after the licence header:
   `// DIALECT: modified for watchOS — <one-line reason>`.

Upstream code is never deleted. If it poses a problem for our built it should be guarded with
`#if !os(watchOS)`.

## Verifying a watchOS Build

SwiftPM **silently ignores** `-Xswiftc -target`, producing a macOS build that looks like a success.
Always confirm the platform:

```bash
vtool -show-build <product>   # expect: platform WATCHOSSIMULATOR
```

## Licence

Apache 2.0. By contributing you agree your contributions are licensed under it.
