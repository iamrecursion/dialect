# Dialect

> di·a·lect /ˈdaɪ.ə.lɛkt/ noun
>
> A lisp-based computation toolbox for your wrist that works without your phone nearby.

Dialect lets you write, manage and run Scheme scripts on your Apple Watch using
[LispKit](https://github.com/objecthub/swift-lispkit). It's a standalone environment, meaning that
_everything_—editing, evaluation, file management and more—happens on your watch.

## Goals

Dialect is very firm on its stance of being _standalone first_, with the companion app helpful but
**never** required for computation, writing scripts, or any other action. OUr main design goals are:

- **Standalone First:** Dialect should work fully without a phone. While the optional iOS companion
  app helps with file transfer, organization and configuration, the watch app must _never_ depend on
  it being installed or nearby.
- **Wrist-First Authoring:** Writing, editing, and running code on the wrist is the _entire point_
  of the app, rather than a fallback for when your phone is not near. Scheme makes this tractable in
  a way that traditional languages cannot: code is made up of s-expressions, which let Dialect offer
  _structural_ editing where you navigate and build programs by selecting and inserting expressions
  rather than typing characters. The Digital Crown is used to move through the syntax tree, and you
  should rarely need to type a parenthesis. Heck, you should rarely need to type _at all_.
- **Computation that Survives the Wrist:** Apple Watch apps are suspended almost the moment you
  lower your arm. Dialect plans to snapshot the whole virtual machine, so a long-running computation
  can be resumed _exactly_ where it stopped rather than abandoned on wrist-down.
- **Not a Toy:** Sessions are editable notebooks of top-level forms with their results, saved
  alongside their live VM state. We plan to include a full file manager with media viewing,
  scope-aware editing tools, and libraries for filesystem access, web protocols, mathematics,
  graphics, and more.

## Status

**Extremely early** in development. We have successfully proven that the LispKit bytecode VM can be
compiled (with some tweaks) to run on watchOS, and have done design work for what a wrist-based
editing workflow looks like, but we're only at the very start of the application's development.

## Thanks To

- **[LispKit](https://github.com/objecthub/swift-lispkit) by Matthias Zenger:** a comprehensive R7RS
  Scheme implementation in Swift, used via a fork that adds watchOS support. LispKit is licensed
  under Apache 2.0, and Dialect bundles a number of third-party Scheme libraries; full attribution
  will ship in the app.

## Licence

Copyright 2026 Ara Adkins, licensed under the [Apache License 2.0](LICENSE).

Dialect builds on LispKit and bundles third-party Scheme libraries under their own permissive
licences; the complete attribution set is in [`NOTICE-dialect.md`](NOTICE-dialect.md), and ships
inside the app.
