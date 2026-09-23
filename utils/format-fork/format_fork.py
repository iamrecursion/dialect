#!/usr/bin/env python3
"""
Formats what Dialect adds to its forks of LispKit and its dependencies, and nothing upstream owns.

Each fork is formatted in its upstream's style, and reformatting upstream's code would turn every
rebase into a conflict. So this works from the diff between a fork and the upstream commit it is
based on, and treats each changed Swift file according to who owns it:

- a file the fork added is Dialect's own code, and gets Dialect's full treatment: swift-format
  with Dialect's `.swift-format`, then the comment reflow over the whole file;
- a file upstream owns has only the comments on lines the fork added refilled, via the reflow's
  `--lines`. Its code is left exactly as written, since reformatting even the lines we added
  would mix two indentation styles in one file.

The base is the upstream default branch, `upstream/master` or `upstream/main`, if the fork has that
remote, as a fork set up per CONTRIBUTING.md does. Without it the fork cannot be told apart from upstream, so this reports that and skips the
fork, as it also does when the submodule is not checked out at all (as in CI).
"""

import argparse
import difflib
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "reflow-comments"))
import reflow_comments

REPO = Path(__file__).resolve().parents[2]
#: Each fork, and the upstream branch its `watchos-support` is based on.
FORKS = {
    "swift-lispkit": "upstream/master",
    "swift-markdownkit": "upstream/master",
    "swift-clformat": "upstream/main",
}
SWIFT_FORMAT_CONFIG = REPO / ".swift-format"

#: `@@ -a,b +c,d @@`: the added side of a hunk starts at line c and runs for d lines (default 1).
HUNK = re.compile(r"^@@ -\S+ \+(\d+)(?:,(\d+))? @@", re.MULTILINE)


def git(fork, *args, check=True):
    result = subprocess.run(
        ["git", "-C", str(fork), *args], capture_output=True, text=True, check=False
    )
    if check and result.returncode != 0:
        print(f"format-fork: git {' '.join(args)} failed: {result.stderr.strip()}", file=sys.stderr)
        sys.exit(2)
    return result


def fork_base(fork, upstream):
    """The upstream commit the fork's branch is based on, or None if it cannot be found."""
    # A submodule that is not checked out is an empty directory, and `git -C` on it would
    # silently run against Dialect's own repository instead.
    if not (fork / ".git").exists():
        print(f"format-fork: {fork.name} is not checked out; skipping it.")
        return None
    if git(fork, "rev-parse", "--verify", "--quiet", upstream, check=False).returncode != 0:
        print(f"format-fork: {fork.name} has no {upstream}; see CONTRIBUTING.md. Skipping it.")
        return None
    return git(fork, "merge-base", "HEAD", upstream).stdout.strip()


def changed_files(fork, base):
    """Swift files that differ from `base`, including uncommitted and untracked ones."""
    tracked = git(fork, "diff", "--name-only", "--diff-filter=AM", base, "--", "*.swift")
    untracked = git(fork, "ls-files", "--others", "--exclude-standard", "--", "*.swift")
    return sorted(set(tracked.stdout.split()) | set(untracked.stdout.split()))


def is_ours(fork, base, path):
    """Whether the fork added `path`, rather than modified a file upstream has."""
    return git(fork, "cat-file", "-e", f"{base}:{path}", check=False).returncode != 0


def added_ranges(fork, base, path):
    """The line ranges in `path`'s working copy that the fork added relative to `base`."""
    diff = git(fork, "diff", "--unified=0", "--no-color", base, "--", path).stdout
    ranges = []
    for match in HUNK.finditer(diff):
        first, count = int(match[1]), int(match[2] or 1)
        if count:
            ranges.append((first, first + count - 1))
    return ranges


def swift_format(swift_format_path, text, path):
    result = subprocess.run(
        [
            swift_format_path,
            "format",
            "--configuration",
            str(SWIFT_FORMAT_CONFIG),
            "--assume-filename",
            path,
        ],
        input=text,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        print(f"format-fork: swift-format failed on {path}:\n{result.stderr}", file=sys.stderr)
        sys.exit(2)
    return result.stdout


def format_file(args, fork, base, path):
    """Formats one changed file of `fork`, or checks it with --check. Returns whether it changed."""
    shown = f"External/{fork.name}/{path}"
    original = (fork / path).read_text(encoding="utf-8")
    if is_ours(fork, base, path):
        # swift-format first: it reindents, which moves comments too, and the reflow must fill
        # them at their final indentation. It never changes comment text and the reflow never
        # changes code, so neither undoes the other.
        updated = swift_format(args.swift_format, original, path)
        updated = reflow_comments.reflow(updated, reflow_comments.SWIFT, args.width, args.doc_width)
    else:
        ranges = added_ranges(fork, base, path)
        if not ranges:
            return False
        updated = reflow_comments.reflow(
            original, reflow_comments.SWIFT, args.width, args.doc_width, ranges
        )
    if updated == original:
        return False

    if args.check:
        sys.stdout.writelines(
            difflib.unified_diff(
                original.splitlines(keepends=True),
                updated.splitlines(keepends=True),
                fromfile=shown,
                tofile=f"{shown} (formatted)",
            )
        )
    else:
        (fork / path).write_text(updated, encoding="utf-8")
        print(f"format-fork: formatted {shown}")
    return True


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.strip().splitlines()[0])
    parser.add_argument("--width", type=int, default=100, help="columns to fill comments to")
    parser.add_argument("--doc-width", type=int, default=80, help="columns to fill doc comments to")
    parser.add_argument("--swift-format", required=True, help="path to swift-format")
    parser.add_argument(
        "--check", action="store_true", help="write nothing; exit 1 if anything would change"
    )
    args = parser.parse_args(argv)

    changed = []
    for name, upstream in FORKS.items():
        fork = REPO / "External" / name
        base = fork_base(fork, upstream)
        if base is None:
            continue
        for path in changed_files(fork, base):
            if format_file(args, fork, base, path):
                changed.append(f"External/{fork.name}/{path}")

    return 1 if (args.check and changed) else 0


if __name__ == "__main__":
    sys.exit(main())
