// Boots LispKit the way Dialect will, from the resources SwiftPM bundles with it, then checks what
// the watchOS fork changed. Prints one line per check and exits non-zero if any fails. It also
// reports the process's memory footprint as it goes, which is reported and never checked.
//
// The keychain and `make-password` checks run on watchOS only: on the Mac those procedures keep
// upstream's behaviour, and the Mac run would touch the login keychain.

import Foundation
import LispKit

/// What a check expects of its form.
enum Expectation {
    /// The printed value, as the REPL would print it.
    case value(String)
    /// An error whose message contains this.
    case error(containing: String)
    /// Anything that is not an error. The value is printed for the record.
    case report
}

struct Check {
    let form: String
    let expectation: Expectation

    init(_ form: String, _ expectation: Expectation) {
        self.form = form
        self.expectation = expectation
    }
}

#if os(watchOS)
    let platform = "watchOS"
#else
    let platform = "macOS"
#endif

var failures = 0

/// The process's physical footprint in MB: what watchOS counts against an app's
/// memory limit.
func footprint() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
        MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : .nan
}

var memory: [(stage: String, megabytes: Double)] = [("start", footprint())]

func note(_ stage: String) {
    memory.append((stage, footprint()))
}

func fail(_ message: String) {
    print("FAIL \(message)")
    failures += 1
}

// Created here, before the boot below, so that the memory report can separate the two.
let context = LispKitContext(
    delegate: CommandLineDelegate(),
    implementationName: "Dialect",
    implementationVersion: "0.0.0",
    commandLineArguments: [],
    includeInternalResources: false,
    includeDocumentPath: nil
)

func evaluate(_ form: String) -> Expr {
    return context.evaluator.execute { machine in
        try machine.eval(
            str: form,
            sourceId: SourceManager.consoleSourceId,
            in: context.global,
            as: "<smoke>"
        )
    }
}

func run(_ check: Check) {
    let result = evaluate(check.form)
    switch (check.expectation, result) {
    case (.value(let want), .error(let error)):
        fail("\(check.form): error \(error.message), want \(want)")
    case (.value(let want), _) where result.description != want:
        fail("\(check.form): got \(result.description), want \(want)")
    case (.error(let want), .error(let error)) where !error.message.contains(want):
        fail("\(check.form): error \(error.message), want an error containing \"\(want)\"")
    case (.error(let want), let result) where !result.isError:
        fail("\(check.form): got \(result.description), want an error containing \"\(want)\"")
    case (.report, .error(let error)):
        fail("\(check.form): error \(error.message)")
    default:
        print("ok   \(check.form) => \(result.isError ? "error" : result.description)")
    }
}

extension Expr {
    var isError: Bool {
        if case .error = self {
            return true
        }
        return false
    }
}

/// Boots LispKit, runs the checks, reports, and exits: nonzero if any check
/// failed.
func smoke() -> Never {
    // -- Boot -------------------------------------------------------------------------------------

    print("LispKitSmoke on \(platform)")
    note("context created")
    let bootStart = Date()

    guard let resources = LispKitContext.packageResourceURL else {
        print("SMOKE: FAIL the LispKit bundle has no resource directory")
        exit(1)
    }
    print("resources: \(resources.path)")
    guard context.usePackageResources() else {
        print("SMOKE: FAIL usePackageResources() found no Libraries/ in \(resources.path)")
        exit(1)
    }
    guard let prelude = LispKitContext.packagePreludePath else {
        print("SMOKE: FAIL no Prelude.scm in \(resources.path)")
        exit(1)
    }
    do {
        try context.bootstrap()
        _ = try context.evaluator.machine.eval(file: prelude, in: context.global)
    } catch {
        print("SMOKE: FAIL boot: \(error)")
        exit(1)
    }
    print(String(format: "booted in %.2f s", Date().timeIntervalSince(bootStart)))
    note("booted, with the prelude")

    // -- Checks -----------------------------------------------------------------------------------

    var checks: [Check] = [
        // The prelude ran: `while` is its macro.
        Check("(let ((i 0)) (while (< i 3) (set! i (+ i 1))) i)", .value("3")),
        Check("(map (lambda (x) (* x x)) '(1 2 3))", .value("(1 4 9)")),
        Check("(string-append \"dial\" \"ect\")", .value("\"dialect\"")),
        // NumberKit's bignums.
        Check("(expt 2 64)", .value("18446744073709551616")),
        // Deep non-tail recursion, against watchOS's smaller stacks.
        Check("(let f ((n 100000)) (if (= n 0) 0 (+ 1 (f (- n 1)))))", .value("100000")),

        // MarkdownKit's named characters, which the MarkdownKit fork makes deterministic.
        Check("(string-encode-named-chars \"a<b&c'd\" #t)", .value("\"a&lt;b&amp;c&#39;d\"")),
        Check(
            "(list (char-name #\\&) (char-name #\\x00A0) (char-name #\\x00C5))",
            .value("(\"amp\" \"nbsp\" \"Aring\")")
        ),
        Check("(string-decode-named-chars \"&eacute;&amp;\")", .value("\"é&\"")),

        Check("(os-name)", .value("\"\(platform)\"")),
        Check("(list (device-battery-level) (device-battery-state))", .report),

        // SXML loads, taking the watchOS side of its `cond-expand` there.
        Check(
            "(cond-expand ((library (lispkit styled-text)) 'present) (else 'absent))",
            .value(platform == "watchOS" ? "absent" : "present")
        ),
        Check("(import (lispkit sxml))", .report),
        Check("(sxml->xml '(p \"a<b\"))", .value("\"<p>a&lt;b</p>\"")),
        // A vector reaches `styled-text?` before its own clause, so this needs the fallback on
        // watchOS.
        Check("(sxml->xml '(p #(#\\o #\\k)))", .value("\"<p>ok</p>\"")),
    ]

    #if os(watchOS)
        let thisDevice = "after-first-unlock-this-device-only"
        checks += [
            Check("(import (lispkit system keychain))", .report),
            Check("(define svc \"gy.metrolo.dialect.smoke\")", .report),

            // Storage round-trips.
            Check("(define kc (make-keychain svc))", .report),
            Check("(keychain-remove! kc \"key\")", .report),
            Check("(keychain-set! kc \"key\" '(1 \"two\" #\\3))", .report),
            Check("(keychain-ref kc \"key\")", .value("(1 \"two\" #\\3)")),
            Check("(keychain-exists? kc \"key\")", .value("#t")),
            Check("(keychain-remove! kc \"key\")", .report),
            Check("(keychain-exists? kc \"key\")", .value("#f")),

            // Upstream maps this-device-only to after-first-unlock, and takes synchronisation from
            // the accessibility argument, which would give #f, then #t.
            Check(
                "(keychain-accessibility (make-keychain svc #f '\(thisDevice)))", .value(thisDevice)
            ),
            Check("(keychain-synchronized? (make-keychain svc #f #f #t))", .value("#t")),
            Check(
                "(keychain-synchronized? (make-keychain svc #f 'when-unlocked #f))", .value("#f")),

            // The stored items carry what was asked for, whether the keychain or `keychain-set!`
            // asks.
            Check(
                "(define (attr k key n) (cdr (assq n (keychain-ref-attributes k key))))", .report),
            Check("(define kd (make-keychain svc #f '\(thisDevice) #f))", .report),
            Check("(define ks (make-keychain svc #f #f #t))", .report),
            Check("(keychain-set! kd \"device\" 1)", .report),
            Check("(attr kd \"device\" 'accessibility)", .value(thisDevice)),
            Check("(attr kd \"device\" 'synchronizable)", .value("#f")),
            Check("(keychain-set! kc \"set\" 2 #f #f '\(thisDevice))", .report),
            Check("(attr kc \"set\" 'accessibility)", .value(thisDevice)),
            Check("(keychain-set! kc \"synced\" 3 #f #f #f #t)", .report),
            Check("(attr kc \"synced\" 'synchronizable)", .value("#t")),
            Check("(keychain-remove! kd \"device\")", .report),
            Check("(keychain-remove! kc \"set\")", .report),
            Check("(keychain-remove! ks \"synced\")", .report),
            Check("(keychain-exists? ks \"synced\")", .value("#f")),

            // A prompt is accepted and ignored; a policy is refused.
            Check(
                "(keychain-accessibility (make-keychain svc #f '(\"Unlock\" when-unlocked)))",
                .value("when-unlocked")
            ),
            Check(
                "(make-keychain svc #f '(\"Unlock\" when-unlocked user-presence))",
                .error(containing: "authentication policies are not supported on watchOS")
            ),
            Check(
                "(make-password)", .error(containing: "passwords cannot be generated on watchOS")),
        ]
    #endif

    for check in checks {
        run(check)
    }
    note("checks run")

    // -- Library sweep ----------------------------------------------------------------------------

    // Loads every bundled library into an environment of its own. A library that needs a native
    // library the platform lacks fails here; that is reported, not counted as a failure, so that
    // the two platforms' lists can be compared.
    let libraries = resources.appendingPathComponent("Libraries", isDirectory: true)
    var names: [String] = []
    if let files = FileManager.default.enumerator(at: libraries, includingPropertiesForKeys: nil) {
        for case let file as URL in files where file.pathExtension == "sld" {
            let parts = file.deletingPathExtension().path
                .dropFirst(libraries.path.count + 1)
                .split(separator: "/")
            names.append("(" + parts.joined(separator: " ") + ")")
        }
    }
    names.sort()

    let sweepStart = Date()
    var unavailable: [String] = []
    for name in names {
        if case .error(let error) = evaluate("(environment '\(name))") {
            unavailable.append("\(name): \(error.message)")
        }
    }
    print(
        String(
            format: "libraries: %d of %d load, in %.2f s",
            names.count - unavailable.count,
            names.count,
            Date().timeIntervalSince(sweepStart)
        )
    )
    for line in unavailable {
        print("  unavailable \(line)")
    }
    note("every library loaded")
    if names.isEmpty {
        fail("no libraries found in \(libraries.path)")
    }

    // -- Memory -----------------------------------------------------------------------------------

    // What data costs: a list and a vector, each measured and then dropped. The list is as long as
    // the stack can drop (see Main); a vector is not freed recursively, so it can be longer.
    if case .error(let error) = evaluate("(import (lispkit debug))") {
        fail("(import (lispkit debug)): error \(error.message)")
    }
    for (name, elements, value) in [
        ("list", 50_000, "(iota 50000)"),
        ("vector", 1_000_000, "(make-vector 1000000 0)"),
    ] {
        let form = "(define big \(value))"
        _ = evaluate("(define big #f)")
        _ = evaluate("(gc)")
        let before = footprint()
        if case .error(let error) = evaluate(form) {
            fail("\(form): error \(error.message)")
            continue
        }
        let after = footprint()
        note("with a \(elements)-element \(name)")
        print(
            String(
                format: "memory: a %@ costs %.0f bytes an element",
                name,
                (after - before) * 1_048_576 / Double(elements)
            )
        )
    }
    _ = evaluate("(define big #f)")
    _ = evaluate("(gc)")
    note("both dropped, after (gc)")

    print("memory footprint:")
    for (stage, megabytes) in memory {
        print(String(format: "  %7.1f MB  %@", megabytes, stage))
    }

    print(failures == 0 ? "SMOKE: PASS" : "SMOKE: FAIL (\(failures) failed)")
    exit(failures == 0 ? 0 : 1)
}

// -- Main -----------------------------------------------------------------------------------------

// Everything runs on a thread of its own with a fixed stack, as Dialect's interpreter will, so that
// the Mac and the simulator run under the same limit. The stack bounds more than recursion: Swift
// frees a list one pair at a time, recursively, at about 160 bytes of stack a pair in a release
// build, so dropping a list of about 52 000 elements overflows an 8 MB stack. 12 MB is the stack
// upstream's REPL gives its interpreter thread.
let interpreter = Thread { smoke() }
interpreter.stackSize = 12 << 20
interpreter.start()
dispatchMain()
