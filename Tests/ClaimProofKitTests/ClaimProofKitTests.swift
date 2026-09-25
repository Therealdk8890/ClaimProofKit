// Copyright 2026 Daniel Kissel
// SPDX-License-Identifier: Apache-2.0

import Testing
@testable import ClaimProofKit

@Suite("ClaimProofKit")
struct ClaimProofKitTests {
    private let evidence = [
        EvidencePassage(
            id: "rule-5",
            source: "Local Rule 5",
            sourceType: .courtRule,
            text: "A response must be filed within 14 days after service of the motion."
        ),
        EvidencePassage(
            id: "order-1",
            source: "Scheduling Order",
            sourceType: .courtRecord,
            text: "The court denied the request for an extension."
        )
    ]

    @Test("A directly grounded claim is supported")
    func supportedClaim() {
        let claim = Claim(id: "1", text: "The response must be filed within 14 days after service of the motion.", type: .legalRule)
        let result = ClaimVerifier().verify(claim: claim, against: evidence)
        #expect(result.status == .directlySupported)
        #expect(result.evidence.first?.passage.id == "rule-5")
    }

    @Test("A polarity reversal is contradicted")
    func contradictedClaim() {
        let claim = Claim(id: "2", text: "The court did not deny the request for an extension.", type: .factual)
        let result = ClaimVerifier().verify(claim: claim, against: evidence)
        #expect(result.status == .contradicted)
    }

    @Test("An invented fact is unsupported")
    func unsupportedClaim() {
        let claim = Claim(id: "3", text: "The plaintiff received ten thousand dollars in damages.", type: .factual)
        let result = ClaimVerifier().verify(claim: claim, against: evidence)
        #expect(result.status == .unsupported)
    }

    @Test("A mixed document blocks publication")
    func reportGate() {
        let document = """
        The response must be filed within 14 days after service of the motion.
        The plaintiff received ten thousand dollars in damages.
        """
        let report = ClaimVerifier().verify(document: document, against: evidence)
        #expect(report.verdicts.count == 2)
        #expect(report.isSafeToPublish == false)
        #expect(report.supportRate == 0.5)
    }

    @Test("A compound sentence becomes independently reviewable claims")
    func atomicDecomposition() {
        let claims = ClaimExtractor().extract(
            from: "The defendant received notice on March 3 and failed to respond within 30 days."
        )
        #expect(claims.count == 2)
        #expect(claims.allSatisfy { $0.parentText != nil })
    }

    @Test("A recommendation is not represented as factual verification")
    func nonVerifiableRecommendation() {
        let claim = Claim(id: "4", text: "The attorney recommends filing a response.", type: .recommendation)
        let result = ClaimVerifier().verify(claim: claim, against: evidence)
        #expect(result.status == .notVerifiable)
    }
}
