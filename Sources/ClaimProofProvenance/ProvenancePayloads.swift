// Copyright 2026 Daniel Kissel
// SPDX-License-Identifier: Apache-2.0

import ClaimProofKit
import Foundation

/// Stable event-type identifiers for the ClaimProof provenance vocabulary.
///
/// These strings are part of Claim Proof Specification v1 and are locked by the
/// `provenance_bridge.json` conformance vector. They MUST never change: queries,
/// diffs, and alignment in DProvenanceKit key off them.
public enum ClaimProofEventType {
    public static let claimExtracted = "cpk_claim_extracted"
    public static let claimVerified = "cpk_claim_verified"
    public static let reportFinalized = "cpk_report_finalized"
}

/// Mirror of DProvenanceKit's `TracePriority` raw values (Trace Specification v1).
/// Kept as a local type so this module stays dependency-free.
public enum ProvenancePriority: Int, Codable, Sendable {
    case telemetry = 0
    case diagnostic = 1
    case structural = 2
    case critical = 3
}

/// Payload recorded when a claim is identified in a document.
public struct ClaimExtractedPayload: Codable, Equatable, Sendable {
    public let claimID: String
    public let fingerprint: String
    public let claimType: String
    public let text: String

    public init(claim: Claim) {
        self.claimID = claim.id
        self.fingerprint = claim.fingerprint
        self.claimType = claim.type.rawValue
        self.text = claim.text
    }

    public var typeIdentifier: String { ClaimProofEventType.claimExtracted }
    public var priority: ProvenancePriority { .structural }
}

/// Payload recorded for each claim verdict. Evidence passages are referenced by
/// content fingerprint rather than embedded, keeping trace rows compact.
public struct ClaimVerifiedPayload: Codable, Equatable, Sendable {
    public let claimFingerprint: String
    public let status: String
    public let confidence: Double
    public let evidenceFingerprints: [String]

    public init(verdict: ClaimVerdict) {
        self.claimFingerprint = verdict.claim.fingerprint
        self.status = verdict.status.rawValue
        self.confidence = verdict.confidence
        self.evidenceFingerprints = verdict.evidence.map(\.passage.contentFingerprint)
    }

    public var typeIdentifier: String { ClaimProofEventType.claimVerified }
    public var priority: ProvenancePriority { .critical }

    /// Equivalence key in the style of DProvenanceKit adapters, so alignment
    /// treats verdicts with the same claim and status as semantically comparable.
    /// Computed at runtime for equivalence evaluators; deliberately NOT part of
    /// the serialized payload (it is derivable from the encoded fields).
    public var semanticKey: String { "\(typeIdentifier):\(claimFingerprint):\(status)" }
}

/// Terminal payload carrying the report-level identity and outcome.
public struct ReportFinalizedPayload: Codable, Equatable, Sendable {
    public let reportFingerprint: String
    public let policyFingerprint: String
    public let specVersion: String
    public let safeToPublish: Bool
    public let statusCounts: [String: Int]

    public init(report: ProofReport, policy: VerificationPolicy) {
        self.reportFingerprint = report.fingerprint
        self.policyFingerprint = policy.fingerprint
        self.specVersion = ClaimProofSpec.version
        self.safeToPublish = report.isSafeToPublish
        var counts: [String: Int] = [:]
        for verdict in report.verdicts {
            counts[verdict.status.rawValue, default: 0] += 1
        }
        self.statusCounts = counts
    }

    public var typeIdentifier: String { ClaimProofEventType.reportFinalized }
    public var priority: ProvenancePriority { .critical }
}
