// swift-tools-version: 6.0
// Copyright 2026 Daniel Kissel
// SPDX-License-Identifier: BUSL-1.1

import PackageDescription

let package = Package(
    name: "ConformanceHarness",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: ".."),
        // The real DProvenanceKit, held to the 0.8.x interchange surface the
        // bridge was verified against (patch releases only — a minor bump gets
        // an explicit re-verification here). The harness proves — against the
        // actual package, not a mirror — that ClaimProofProvenance output
        // ingests seamlessly, and that a ClaimProof report can be bound into a
        // signed proof pack that verifies role-bound and renders a certificate.
        //
        // Re-verified 0.5.0 → 0.8.0: sections [1]–[6] passed unchanged; section
        // [7] was added because proof packs did not exist before 0.6.
        .package(url: "https://github.com/Therealdk8890/DProvenanceKit.git", .upToNextMinor(from: "0.8.0"))
    ],
    targets: [
        .executableTarget(
            name: "ConformanceHarness",
            dependencies: [
                .product(name: "ClaimProofKit", package: "ClaimProofKit"),
                .product(name: "ClaimProofProvenance", package: "ClaimProofKit"),
                // The portable vector checks (sections [1]–[5]) live in the
                // main package so the wasm runner executes the same code.
                .product(name: "ClaimProofConformance", package: "ClaimProofKit"),
                .product(name: "DProvenanceKit", package: "DProvenanceKit")
            ]
        )
    ]
)
