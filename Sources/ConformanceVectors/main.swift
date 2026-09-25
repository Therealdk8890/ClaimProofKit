// Copyright 2026 Daniel Kissel
// SPDX-License-Identifier: Apache-2.0
//
// Portable runner for the Claim Proof Specification v1 vector checks. Built as
// a wasm32-wasi command module and executed under a wasm runtime in CI, it
// byte-locks the wasm build's identity algorithms and verdict semantics to the
// same frozen vectors the native harness enforces — the code paths that differ
// off Apple platforms (swift-crypto SHA-256, the hand-rolled UTF-16 scanner)
// are exactly the ones this run pins. It also runs natively:
//
//   swift run ConformanceVectors ConformanceHarness/vectors
//
// The wasm runtime must preopen the vectors directory, e.g.:
//
//   wasmtime run --dir ConformanceHarness/vectors::/vectors \
//     ConformanceVectors.wasm /vectors

import ClaimProofConformance
import ClaimProofKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    print("usage: ConformanceVectors <vectors-directory>")
    exit(64)
}
let vectorsDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)

print("Claim Proof Specification v\(ClaimProofSpec.version) vector conformance")
do {
    let (failureCount, _) = try SpecVectorChecks.runAll(vectorsDirectory: vectorsDirectory)
    if failureCount > 0 {
        print("\n\(failureCount) conformance failure(s)")
        exit(1)
    }
    print("\nAll spec vector checks passed.")
} catch {
    print("error: \(error)")
    exit(1)
}
