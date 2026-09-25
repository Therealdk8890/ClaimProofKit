// swift-tools-version: 6.0
// Copyright 2026 Daniel Kissel
// SPDX-License-Identifier: BUSL-1.1

import PackageDescription

// On Apple platforms the identity algorithms use the system CryptoKit; everywhere
// else (Linux, wasm32-wasi, Windows, ...) swift-crypto provides the same API under
// `import Crypto`. The condition keeps Apple builds free of the extra link.
let cryptoOnNonDarwin: Target.Dependency = .product(
    name: "Crypto",
    package: "swift-crypto",
    condition: .when(platforms: [.linux, .android, .windows, .wasi, .openbsd])
)

let package = Package(
    name: "ClaimProofKit",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "ClaimProofKit", targets: ["ClaimProofKit"]),
        .library(name: "ClaimProofProvenance", targets: ["ClaimProofProvenance"]),
        .library(name: "ClaimProofBridge", targets: ["ClaimProofBridge"]),
        // Portable core of the spec conformance checks: vector formats plus the
        // identity/verdict sections that run on both native and wasm32-wasi.
        // The native harness layers regeneration and the DProvenanceKit
        // round-trip on top; the ConformanceVectors runner executes the same
        // sections under a wasm runtime in CI.
        .library(name: "ClaimProofConformance", targets: ["ClaimProofConformance"]),
        // C-ABI WebAssembly reactor over the bridge. Built with the wasm SDK in
        // reactor exec-model; on native platforms it is a stub that keeps the
        // package building and testing cleanly.
        .executable(name: "ClaimProofWasm", targets: ["ClaimProofWasm"]),
        .executable(name: "ConformanceVectors", targets: ["ConformanceVectors"]),
        .executable(name: "claimproof", targets: ["claimproof"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0")
    ],
    targets: [
        .target(name: "ClaimProofKit", dependencies: [cryptoOnNonDarwin]),
        // Bridge: emits DProvenanceKit-compatible traces without taking a
        // dependency on DProvenanceKit. Wire parity is locked by the
        // conformance harness, which round-trips through the real package.
        .target(name: "ClaimProofProvenance", dependencies: ["ClaimProofKit", cryptoOnNonDarwin]),
        // Integration adapter: a JSON-in/JSON-out boundary over the pipeline so
        // non-Swift hosts (a wasm webview, an FFI caller) can drive verification
        // without binding Swift types. Carries no ClaimProofCloud-only features.
        .target(name: "ClaimProofBridge", dependencies: ["ClaimProofKit", "ClaimProofProvenance"]),
        // Pointer+length C-ABI exports (cpk_verify, cpk_malloc/free) over the
        // bridge, for a wasm host with no companion process. Boundary-safe
        // integration adapter; the wasm-specific exports are #if arch(wasm32).
        .executableTarget(name: "ClaimProofWasm", dependencies: ["ClaimProofBridge"]),
        // Spec vector checks shared by the native conformance harness and the
        // wasm runner, so the two can never drift apart.
        .target(name: "ClaimProofConformance", dependencies: ["ClaimProofKit", "ClaimProofProvenance"]),
        // Command-model executable (native and wasm32-wasi) that runs the
        // vector checks against a directory passed as its single argument.
        .executableTarget(name: "ConformanceVectors", dependencies: ["ClaimProofConformance", "ClaimProofKit"]),
        .executableTarget(name: "claimproof", dependencies: ["ClaimProofKit", "ClaimProofProvenance"]),
        .testTarget(name: "ClaimProofKitTests", dependencies: ["ClaimProofKit"], resources: [.process("../Fixtures")]),
        .testTarget(name: "ClaimProofProvenanceTests", dependencies: ["ClaimProofProvenance", "ClaimProofKit"]),
        .testTarget(name: "ClaimProofBridgeTests", dependencies: ["ClaimProofBridge", "ClaimProofKit"])
    ],
    swiftLanguageModes: [.v6]
)
