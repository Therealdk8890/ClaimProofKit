// Copyright 2026 Daniel Kissel
// SPDX-License-Identifier: Apache-2.0

import Foundation

public struct VerificationPipeline: Sendable {
    private let extractor: any AtomicClaimExtracting
    private let retriever: any EvidenceRetrieving
    private let verifier: any ClaimEntailmentVerifying
    private let policy: any ProofPolicyEvaluating
    private let reportGenerator: any TrustReportGenerating
    private let evidenceLimit: Int

    public init(
        extractor: any AtomicClaimExtracting = ClaimExtractor(),
        retriever: any EvidenceRetrieving = PassthroughEvidenceRetriever(),
        verifier: any ClaimEntailmentVerifying = LexicalEntailmentVerifier(),
        policy: any ProofPolicyEvaluating = ConservativeProofPolicy(),
        reportGenerator: any TrustReportGenerating = DefaultTrustReportGenerator(),
        evidenceLimit: Int = 20
    ) {
        self.extractor = extractor
        self.retriever = retriever
        self.verifier = verifier
        self.policy = policy
        self.reportGenerator = reportGenerator
        self.evidenceLimit = max(1, evidenceLimit)
    }

    public func verify(document: String, evidence corpus: [EvidencePassage]) async throws -> PipelineResult {
        let claims = extractor.extract(from: document)
        var verdicts: [ClaimVerdict] = []
        verdicts.reserveCapacity(claims.count)

        for claim in claims {
            let evidence = try await retriever.retrieve(
                for: claim,
                from: corpus,
                limit: evidenceLimit
            )
            verdicts.append(try await verifier.verify(claim: claim, against: evidence))
        }

        let report = reportGenerator.generate(from: verdicts)
        return PipelineResult(report: report, decision: policy.evaluate(report))
    }
}

public struct PassthroughEvidenceRetriever: EvidenceRetrieving {
    public init() {}

    public func retrieve(
        for claim: Claim,
        from corpus: [EvidencePassage],
        limit: Int
    ) async throws -> [EvidencePassage] {
        Array(corpus.prefix(max(1, limit)))
    }
}

public struct LexicalEntailmentVerifier: ClaimEntailmentVerifying {
    private let verifier: ClaimVerifier

    public init(verifier: ClaimVerifier = ClaimVerifier()) {
        self.verifier = verifier
    }

    public func verify(
        claim: Claim,
        against evidence: [EvidencePassage]
    ) async throws -> ClaimVerdict {
        verifier.verify(claim: claim, against: evidence)
    }
}

public struct DefaultTrustReportGenerator: TrustReportGenerating {
    public init() {}

    public func generate(from verdicts: [ClaimVerdict]) -> ProofReport {
        ProofReport(verdicts: verdicts)
    }
}

public struct ConservativeProofPolicy: ProofPolicyEvaluating {
    public init() {}

    public func evaluate(_ report: ProofReport) -> ProofDecision {
        let blocking = report.verdicts.filter {
            $0.status == .contradicted || $0.status == .unsupported
        }.map(\.claim.id)
        let review = report.verdicts.filter {
            $0.status == .partiallySupported
                || $0.status == .ambiguous
                || $0.status == .notVerifiable
        }.map(\.claim.id)

        if !blocking.isEmpty {
            return ProofDecision(
                disposition: .block,
                blockingClaimIDs: blocking,
                reviewClaimIDs: review
            )
        }
        if !review.isEmpty {
            return ProofDecision(disposition: .requireReview, reviewClaimIDs: review)
        }
        return ProofDecision(disposition: .allow)
    }
}
