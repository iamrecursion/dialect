// swift-tools-version:6.0

// A command-line smoke test of the LispKit fork, run on the Mac or spawned in a watch simulator by
// `lispkit-smoke.sh`. It depends on the fork by path, so the fork carries no test scaffolding.

import PackageDescription

let package = Package(
    name: "LispKitSmoke",
    platforms: [
        .macOS(.v14),
        .watchOS(.v10),
    ],
    dependencies: [
        .package(path: "../../External/swift-lispkit")
    ],
    targets: [
        .executableTarget(
            name: "LispKitSmoke",
            dependencies: [
                .product(name: "LispKit", package: "swift-lispkit")
            ]
        )
    ],
    // Swift 5 mode: the checks share top-level state with the interpreter thread they run on, which
    // is safe here, as the main thread only waits, but which Swift 6's checking cannot see.
    swiftLanguageModes: [.v5]
)
