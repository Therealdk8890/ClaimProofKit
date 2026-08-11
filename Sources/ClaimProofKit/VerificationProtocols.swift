// Copyright 2026 Daniel Kissel
// SPDX-License-Identifier: BUSL-1.1

import Foundation

public protocol AtomicClaimExtracting: Sendable {
    func extract(from document: String) -> [Claim]
}

extension ClaimExtractor: AtomicClaimExtracting {}

public protocol EvidenceRetrieving: Sendable {
    func retrieve(
        for claim: Claim,
        from corpus: [EvidencePassage],
        limit: Int
    ) async throws -> [EvidencePassage]
}

public protocol ClaimEntailmentVerifying: Sendable {
    func verify(
        claim: Claim,
        against evidence: [EvidencePassage]
    ) async throws -> ClaimVerdict
}

public protocol ProofPolicyEvaluating: Sendable {
    func evaluate(_ report: ProofReport) -> ProofDecision
}

public protocol TrustReportGenerating: Sendable {
    func generate(from verdicts: [ClaimVerdict]) -> ProofReport
}

public struct ProofDecision: Codable, Equatable, Sendable {
    public enum Disposition: String, Codable, Sendable {
        case allow
        case requireReview
        case block
    }

    public let disposition: Disposition
    public let blockingClaimIDs: [String]
    public let reviewClaimIDs: [String]

    public init(
        disposition: Disposition,
        blockingClaimIDs: [String] = [],
        reviewClaimIDs: [String] = []
    ) {
        self.disposition = disposition
        self.blockingClaimIDs = blockingClaimIDs
        self.reviewClaimIDs = reviewClaimIDs
    }
}

public struct PipelineResult: Codable, Sendable {
    public let report: ProofReport
    public let decision: ProofDecision

    public init(report: ProofReport, decision: ProofDecision) {
        self.report = report
        self.decision = decision
    }
}
