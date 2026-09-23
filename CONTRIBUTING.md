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
make submodules   # checks out the forks: LispKit and two of its dependencies
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

Per-language targets exist too: `format-swift`, `format-nix`, `format-shell`, `format-python`,
`format-docs`, and `format-fork`, each with a `format-check-*` twin, and `lint-swift`,
`lint-python`, `lint-shell`, `lint-workflows`, and `lint-nix`. `lint` does not include
`format-check`: a lint failure means the code is wrong, a format failure only that its layout is.

Source lists come from `git ls-files`, so **a new file must be at least staged before the formatters
and linters will see it**. Nix goes further: `flake.nix` must be staged before _any_ `make` target
works at all, because flakes only see tracked files.

`External/` is excluded from every target except `format-fork`, which formats only what Dialect adds
to the forks (see [The Forks](#the-forks)). Reformatting upstream's code would turn every rebase
into a conflict.

## The Forks

Dialect's Scheme runtime is a fork of [LispKit](https://github.com/objecthub/swift-lispkit). Two of
its dependencies are forked as well: [MarkdownKit](https://github.com/objecthub/swift-markdownkit),
which does not build for watchOS, and [CLFormat](https://github.com/objecthub/swift-clformat), only
so that it takes MarkdownKit from the same fork.

| Submodule                    | Upstream                      | Upstream's default branch |
| ---------------------------- | ----------------------------- | ------------------------- |
| `External/swift-lispkit`     | `objecthub/swift-lispkit`     | `master`                  |
| `External/swift-markdownkit` | `objecthub/swift-markdownkit` | `master`                  |
| `External/swift-clformat`    | `objecthub/swift-clformat`    | `main`                    |

Each is consumed by SwiftPM as a local path dependency: Dialect takes `External/swift-lispkit`, and
LispKit's manifest takes its siblings as `../swift-markdownkit` and `../swift-clformat`. The
submodule SHAs thus pin every version, and an edit in any fork is picked up without pushing it.

Both dependencies have to come by path as SwiftPM keys a package by its name, not its location. If
LispKit took MarkdownKit by path while CLFormat still asked for it by URL, one package would have
two locations. SwiftPM builds that today, with a warning that it will become an error in the future,
so the CLFormat fork is insurance against that change.

`make submodules` clones only the forks. Working on them also needs each upstream as a remote, which
`make format-fork` uses to tell our changes from upstream's. Fetching needs network access:

```bash
git -C External/swift-lispkit remote add upstream git@github.com:objecthub/swift-lispkit.git
git -C External/swift-markdownkit remote add upstream git@github.com:objecthub/swift-markdownkit.git
git -C External/swift-clformat remote add upstream git@github.com:objecthub/swift-clformat.git
git submodule foreach git fetch upstream
```

Every fork follows the same strict branch discipline:

- **The default branch carries no changes from us** so that it mirrors upstream exactly.
  `git pull upstream <default branch>` must remain trivial.
- **Dialect work lives on `watchos-support`**, as a linear commit series.
- **Rebase, never merge.** Upstream bumps are
  `git rebase --onto <new-upstream> <old-upstream> watchos-support`. `git format-patch` against the
  default branch produces a readable patch set.

Two rules hold inside the forks:

1. **Object Representations are Frozen:** No changes to LispKit's `Expr`, `Procedure`, `Code`, or
   anything under `Sources/LispKit/Data/`. Divergence there would make upstream merges horrendous.
2. **Modified Files Carry an Apache §4(b) Change Notice:** The first line after the licence header:
   `// DIALECT: modified for watchOS — <one-line reason>`.

Upstream code is never deleted. If it poses a problem for our build it should be guarded with
`#if !os(watchOS)`.

**What we add follows Dialect's style; what upstream owns keeps its own.** `make format-fork`, which
is part of `make format` and `make format-check`, compares each fork with its merge base on its
upstream's default branch and formats by ownership:

- files a fork added are ours, and get `swift-format` with Dialect's `.swift-format` plus the
  comment reflow;
- in files upstream owns, only the comments on lines we added are refilled. Their code is never
  reformatted, as that would mix two indentation styles in one file and grow the diff every rebase
  has to carry.

So substantial new code is better placed in a file of its own, where it gets the full treatment. A
fork that is not checked out, or has no `upstream` remote, is skipped with a note saying so.

## Verifying a watchOS Build

SwiftPM **silently ignores** `-Xswiftc -target`, producing a macOS build that looks like a success.
`make fork-watch-build` builds through a destination file instead, then checks every object file
with `vtool` and fails unless each is for the watchOS simulator:

```bash
make fork-watch-build                                             # LispKit, and the forks it uses
make fork-watch-build FORK=swift-markdownkit TARGET=MarkdownKit   # one fork on its own
```

## Licence

Apache 2.0. By contributing you agree your contributions are licensed under it.
