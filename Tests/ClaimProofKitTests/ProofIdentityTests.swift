// Copyright 2026 Daniel Kissel
// SPDX-License-Identifier: BUSL-1.1

import Foundation
import Testing
@testable import ClaimProofKit

@Suite("Proof identity")
struct ProofIdentityTests {
    private func verdict(_ text: String, _ status: SupportStatus) -> ClaimVerdict {
        ClaimVerdict(
            claim: Claim(id: "c-\(text.count)", text: text),
            status: status,
            confidence: 1,
            evidence: [],
            explanation: "test"
        )
    }

    @Test("Report fingerprint is stable across timestamps and metadata")
    func reportFingerprintStability() {
        let verdicts = [verdict("The court granted the motion.", .directlySupported)]
        let first = ProofReport(createdAt: Date(timeIntervalSince1970: 0), verdicts: verdicts)
        let second = ProofReport(createdAt: Date(timeIntervalSince1970: 1_000_000), verdicts: verdicts)
        #expect(first.fingerprint == second.fingerprint)
        #expect(first.fingerprint.count == 64)
    }

    @Test("Report fingerprint changes with verdict status, wording, and order")
    func reportFingerprintSensitivity() {
        let supported = verdict("The court granted the motion.", .directlySupported)
        let contradicted = verdict("The court granted the motion.", .contradicted)
        let other = verdict("The tenant paid rent in March.", .directlySupported)

        let base = ProofReport(verdicts: [supported, other]).fingerprint
        #expect(ProofReport(verdicts: [contradicted, other]).fingerprint != base)
        #expect(ProofReport(verdicts: [other, supported]).fingerprint != base)
        #expect(ProofReport(verdicts: [verdict("The court granted the request.", .directlySupported), other]).fingerprint != base)
    }

    @Test("Policy fingerprint pins spec version and every threshold")
    func policyFingerprint() {
        let base = VerificationPolicy().fingerprint
        #expect(base.count == 64)
        #expect(VerificationPolicy().fingerprint == base)
        #expect(VerificationPolicy(supportedThreshold: 0.9).fingerprint != base)
        #expect(VerificationPolicy(maximumEvidenceMatches: 4).fingerprint != base)
    }

    @Test("Evidence content fingerprint is byte-exact")
    func evidenceFingerprint() {
        let passage = EvidencePassage(id: "e1", source: "s", text: "The rent was paid.")
        let edited = EvidencePassage(id: "e1", source: "s", text: "The rent was paid. ")
        #expect(passage.contentFingerprint != edited.contentFingerprint)
        // Case changes must alter the identity even though claim fingerprints fold case.
        let upper = EvidencePassage(id: "e1", source: "s", text: "THE RENT WAS PAID.")
        #expect(passage.contentFingerprint != upper.contentFingerprint)
    }
}
