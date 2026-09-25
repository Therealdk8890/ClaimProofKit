// Copyright 2026 Daniel Kissel
// SPDX-License-Identifier: Apache-2.0

import Testing
@testable import ClaimProofKit

@Suite("Verification pipeline")
struct VerificationPipelineTests {
    @Test("Default pipeline blocks unsupported claims")
    func blocksUnsupportedClaim() async throws {
        let evidence = EvidencePassage(
            id: "docket",
            source: "Court docket",
            sourceType: .courtRecord,
            text: "The complaint was filed on Monday."
        )
        let result = try await VerificationPipeline().verify(
            document: "The plaintiff received 10000 dollars in damages.",
            evidence: [evidence]
        )

        #expect(result.report.verdicts.count == 1)
        #expect(result.decision.disposition == .block)
        #expect(result.decision.blockingClaimIDs == result.report.verdicts.map(\.claim.id))
    }

    @Test("A custom entailment verifier plugs into the public contract")
    func customVerifier() async throws {
        let result = try await VerificationPipeline(
            verifier: AlwaysInferenceVerifier()
        ).verify(
            document: "The tenant received the notice.",
            evidence: []
        )

        #expect(result.report.verdicts.first?.status == .supportedByInference)
        #expect(result.decision.disposition == .allow)
    }

    @Test("Reviewable uncertainty does not silently pass")
    func requiresReview() {
        let claim = Claim(id: "claim", text: "The payment was late.", type: .factual)
        let verdict = ClaimVerdict(
            claim: claim,
            status: .partiallySupported,
            confidence: 0.6,
            evidence: [],
            explanation: "Only the payment date was supplied."
        )
        let decision = ConservativeProofPolicy().evaluate(ProofReport(verdicts: [verdict]))

        #expect(decision.disposition == .requireReview)
        #expect(decision.reviewClaimIDs == ["claim"])
    }
}

private struct AlwaysInferenceVerifier: ClaimEntailmentVerifying {
    func verify(
        claim: Claim,
        against evidence: [EvidencePassage]
    ) async throws -> ClaimVerdict {
        ClaimVerdict(
            claim: claim,
            status: .supportedByInference,
            confidence: 0.8,
            evidence: [],
            explanation: "Test verifier"
        )
    }
}
