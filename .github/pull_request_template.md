<!-- Thanks for the contribution. Please read CONTRIBUTING.md if you have not already. -->

## Description

<!-- What the change does, and why. If it fixes an issue, say `Fixes #123`. -->

## How it was Verified

<!--
`make format-check` is necessary but almost never sufficient. A watch is not a simulator: memory
limits, suspension when the wrist drops, and crown input all behave differently. Say what you
actually exercised, and on what.
-->

- [ ] `make format-check` passes from a clean tree
- [ ] Builds for watchOS — and the artifact was confirmed with `vtool -show-build`, not just a green
      build (SwiftPM silently ignores `-Xswiftc -target`)
- [ ] Exercised in the simulator — surfaces touched:
- [ ] Exercised on a physical watch (required for anything touching memory, suspension, or input)

## Tests

- [ ] New behavior has tests, or this section says why it cannot
- [ ] Editor-model changes carry property tests for their invariants — parens stay balanced, the AST
      is never invalid, selection survives a reflow

## If this touches the LispKit fork

<!-- Delete this section if it does not. -->

- [ ] No changes to `Expr`, `Procedure`, `Code`, or anything under `Sources/LispKit/Data/` — object
      representations are frozen
- [ ] Upstream code is guarded with `#if !os(watchOS)` rather than deleted
- [ ] Every modified file carries its Apache §4(b) notice:
      `// DIALECT: modified for watchOS — <reason>`
- [ ] The branch is still linear on top of upstream, with no merge commits
- [ ] macOS and iOS builds are not regressed

## Docs

- [ ] `CONTRIBUTING.md` updated if the workflow changed
- [ ] `README.md` updated if the project's goals or scope changed

## Anything Else

<!-- Trade-offs you made, things you were unsure about, things you would like looked at closely. -->
