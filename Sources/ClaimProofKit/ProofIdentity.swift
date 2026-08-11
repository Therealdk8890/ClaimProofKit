// Copyright 2026 Daniel Kissel
// SPDX-License-Identifier: BUSL-1.1

#if canImport(CryptoKit)
import CryptoKit
#elseif canImport(Crypto)
import Crypto
#else
#error("No crypto module available: add this platform to the swift-crypto dependency condition in Package.swift.")
#endif
import Foundation

/// Claim Proof Specification v1 constants.
///
/// The specification pins the identity algorithms in this file plus the verdict
/// semantics of the baseline verifier. Every algorithm here is locked by golden
/// vectors under `ConformanceHarness/vectors/`; changing behavior requires a new
/// spec version and regenerated vectors.
public enum ClaimProofSpec {
    /// Version of the identity + verdict-semantics contract, mirrored in every
    /// conformance vector's `specVersion` field.
    public static let version = "1.0"

    /// Identifier of the built-in deterministic lexical verifier.
    public static let verifierIdentifier = "cpk-lexical"

    /// Version of the built-in verifier's rule set (lexicons, stemmer, thresholds' meaning).
    public static let verifierVersion = "1.0"

    static func sha256Hex(_ input: String) -> String {
        HexEncoding.lowercase(SHA256.hash(data: Data(input.utf8)))
    }
}

/// Lowercase-hex rendering without `String(format:)`, which is unavailable in
/// FoundationEssentials-only environments (e.g. the wasm32-wasi SDK).
package enum HexEncoding {
    package static func lowercase(_ bytes: some Sequence<UInt8>) -> String {
        var out: [UInt8] = []
        out.reserveCapacity(64)
        for byte in bytes {
            out.append(digit(byte >> 4))
            out.append(digit(byte & 0x0F))
        }
        return String(decoding: out, as: UTF8.self)
    }

    private static func digit(_ nibble: UInt8) -> UInt8 {
        nibble < 10 ? 0x30 + nibble : 0x61 + (nibble - 10)
    }
}

public extension EvidencePassage {
    /// SHA-256 over the exact UTF-8 bytes of `text`, lowercase hex.
    /// No normalization: any byte-level edit to the passage changes its identity.
    var contentFingerprint: String {
        ClaimProofSpec.sha256Hex(text)
    }
}

public extension ProofReport {
    /// Stable identity of the verification outcome: SHA-256 (lowercase hex) over
    /// `"cpk:v1:report:"` followed by `"\(claim.fingerprint):\(status.rawValue)|"`
    /// for each verdict in report order.
    ///
    /// Two reports share a fingerprint exactly when they verify the same claim
    /// wording (case-folded, since claim fingerprints fold case — see spec §1)
    /// to the same verdicts in the same order. Timestamps, confidence, and
    /// evidence excerpts do not participate.
    var fingerprint: String {
        let signature = verdicts.map { "\($0.claim.fingerprint):\($0.status.rawValue)|" }.joined()
        return ClaimProofSpec.sha256Hex("cpk:v1:report:" + signature)
    }
}

public extension VerificationPolicy {
    /// Identity of the policy under which a report was produced: SHA-256
    /// (lowercase hex) over a frozen, newline-delimited key:value listing.
    ///
    /// The listing order and formatting are part of Claim Proof Specification v1
    /// and must not change without a spec version bump. The verifier identity is
    /// part of the hash because the same thresholds mean different things to
    /// different verifiers; custom `ClaimEntailmentVerifying` implementations
    /// pass their own identifier and version.
    func fingerprint(
        verifier: String = ClaimProofSpec.verifierIdentifier,
        verifierVersion: String = ClaimProofSpec.verifierVersion
    ) -> String {
        let canonical = """
        specVersion:\(ClaimProofSpec.version)
        verifier:\(verifier)
        verifierVersion:\(verifierVersion)
        supportedThreshold:\(supportedThreshold)
        ambiguousThreshold:\(ambiguousThreshold)
        contradictionThreshold:\(contradictionThreshold)
        maximumEvidenceMatches:\(maximumEvidenceMatches)
        """
        return ClaimProofSpec.sha256Hex(canonical)
    }

    /// Convenience for the built-in baseline lexical verifier.
    var fingerprint: String {
        fingerprint()
    }
}
