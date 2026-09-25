// Copyright 2026 Daniel Kissel
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import ClaimProofKit

@Suite("Human evidence and independent annotation workflow")
struct HumanAnnotationWorkflowTests {
    @Test("Preparation validates provenance and emits separately keyed blind packets")
    func preparesBlindPackets() throws {
        let preparation = try preparedWorkflow()
        #expect(preparation.packets.count == 3)
        #expect(preparation.manifest.intakeValidationPassed)

        let assignmentIDs = preparation.packets.flatMap { $0.items.map(\.assignmentID) }
        #expect(Set(assignmentIDs).count == assignmentIDs.count)
        #expect(preparation.packets.allSatisfy { $0.items.count == 4 })

        let encodedPacket = try JSONEncoder().encode(preparation.packets[0])
        let packetText = String(decoding: encodedPacket, as: UTF8.self)
        #expect(!packetText.contains("candidate-0"))
        #expect(!packetText.contains("source-record-0"))
        #expect(!packetText.contains("challengeTags"))
        #expect(!packetText.contains("expectedStatus"))

        let encodedTemplate = try JSONEncoder().encode(preparation.responseTemplates[0])
        let templateObject = try #require(
            JSONSerialization.jsonObject(with: encodedTemplate) as? [String: Any]
        )
        let responses = try #require(templateObject["responses"] as? [[String: Any]])
        #expect(responses[0].keys.contains("approvalEligible"))
        #expect(responses[0]["approvalEligible"] is NSNull)
        #expect(responses[0]["status"] is NSNull)
        #expect(responses[0]["rationale"] is NSNull)
        #expect(responses[0]["evidenceSpans"] is NSNull)
    }

    @Test("Two complete independent reviews produce Cohen's kappa and a gold corpus")
    func auditsAndFinalizes() throws {
        let preparation = try preparedWorkflow()
        let first = submission(alias: "reviewer-a", preparation: preparation)
        let second = submission(alias: "reviewer-b", preparation: preparation)
        let report = HumanAnnotationWorkflow().audit(
            manifest: preparation.manifest,
            primarySubmissions: [first, second]
        )

        #expect(report.issues.isEmpty)
        #expect(report.binaryLabelAgreement == 1)
        #expect(report.passesReliabilityGate)
        #expect(report.detailedDisagreementCandidateIDs.isEmpty)

        let adjudication = AnnotationSubmission(
            corpusVersion: preparation.manifest.candidateCorpus.version,
            reviewerAlias: "adjudicator",
            annotationPolicyVersion: preparation.manifest.candidateCorpus.annotationPolicyVersion,
            responses: []
        )
        let corpus = try HumanAnnotationWorkflow().finalize(
            manifest: preparation.manifest,
            primarySubmissions: [first, second],
            adjudicationSubmission: adjudication,
            origin: .publicRecord,
            split: .validation
        )
        #expect(corpus.metadata?.independentlyLabeled == true)
        #expect(corpus.metadata?.binaryLabelAgreement == 1)
        #expect(corpus.metadata?.split == .validation)
        #expect(corpus.claimCases.count == 4)
        #expect(corpus.claimCases.filter { $0.expectedStatus == .directlySupported }.count == 2)
        #expect(corpus.claimCases.filter { $0.expectedStatus == .unsupported }.count == 2)
    }

    @Test("Fabricated evidence quotes are rejected before agreement is calculated")
    func rejectsFabricatedEvidence() throws {
        let preparation = try preparedWorkflow()
        let valid = submission(alias: "reviewer-a", preparation: preparation)
        var labels = submission(alias: "reviewer-b", preparation: preparation).responses
        let original = labels[0]
        labels[0] = AnnotationLabel(
            assignmentID: original.assignmentID,
            approvalEligible: original.approvalEligible,
            status: original.status,
            rationale: original.rationale,
            evidenceSpans: original.approvalEligible
                ? [GoldEvidenceSpan(evidenceID: "evidence-0", exactQuote: "Fabricated quote")]
                : original.evidenceSpans
        )
        let invalid = AnnotationSubmission(
            corpusVersion: preparation.manifest.candidateCorpus.version,
            reviewerAlias: "reviewer-b",
            annotationPolicyVersion: preparation.manifest.candidateCorpus.annotationPolicyVersion,
            responses: labels
        )
        let report = HumanAnnotationWorkflow().audit(
            manifest: preparation.manifest,
            primarySubmissions: [valid, invalid]
        )
        #expect(!report.passesReliabilityGate)
        #expect(report.binaryLabelAgreement == nil)
        #expect(report.issues.contains { $0.contains("non-byte-present evidence quote") })
    }

    @Test("Canonically equivalent but byte-different evidence quotes are rejected")
    func rejectsNormalizedEvidenceQuote() throws {
        let preparation = try preparedWorkflow()
        let valid = submission(alias: "reviewer-a", preparation: preparation)
        var labels = submission(alias: "reviewer-b", preparation: preparation).responses
        let original = labels[0]
        let assignment = try #require(preparation.manifest.assignments.first {
            $0.assignmentID == original.assignmentID
        })
        let candidate = try #require(preparation.manifest.candidateCorpus.candidates.first {
            $0.id == assignment.candidateID
        })
        let byteDifferentQuote = candidate.evidence[0].text.decomposedStringWithCanonicalMapping
        labels[0] = AnnotationLabel(
            assignmentID: original.assignmentID,
            approvalEligible: original.approvalEligible,
            status: original.status,
            rationale: original.rationale,
            evidenceSpans: original.approvalEligible
                ? [GoldEvidenceSpan(
                    evidenceID: candidate.evidence[0].id,
                    exactQuote: byteDifferentQuote
                )]
                : original.evidenceSpans
        )
        let invalid = AnnotationSubmission(
            corpusVersion: preparation.manifest.candidateCorpus.version,
            reviewerAlias: "reviewer-b",
            annotationPolicyVersion: preparation.manifest.candidateCorpus.annotationPolicyVersion,
            responses: labels
        )
        let report = HumanAnnotationWorkflow().audit(
            manifest: preparation.manifest,
            primarySubmissions: [valid, invalid]
        )
        #expect(report.issues.contains { $0.contains("non-byte-present evidence quote") })
    }

    @Test("De-identified real material requires second-person review")
    func requiresSecondPersonDeidentificationReview() {
        let corpus = candidateCorpus()
        let ledger = sourceLedger(deidentificationReview: .pending)
        let issues = HumanAnnotationWorkflow().validateIntake(corpus: corpus, ledger: ledger)
        #expect(issues.contains { $0.contains("pending de-identification review") })
        #expect(issues.contains { $0.contains("needs second-person de-identification review") })
    }

    @Test("Duplicate source IDs report an issue instead of trapping")
    func duplicateSourceIDsAreSafe() {
        let valid = sourceLedger()
        let duplicate = EvidenceSourceLedger(
            version: valid.version,
            sources: [valid.sources[0], valid.sources[0]]
        )
        let issues = HumanAnnotationWorkflow().validateIntake(
            corpus: candidateCorpus(),
            ledger: duplicate
        )
        #expect(issues.contains("source ledger contains duplicate source IDs"))
    }

    private func preparedWorkflow() throws -> AnnotationPreparation {
        try HumanAnnotationWorkflow().prepare(
            corpus: candidateCorpus(),
            ledger: sourceLedger(),
            reviewerAliases: ["reviewer-a", "reviewer-b", "adjudicator"]
        )
    }

    private func candidateCorpus() -> AnnotationCandidateCorpus {
        AnnotationCandidateCorpus(
            version: "human-pilot-v1",
            name: "Human annotation pilot",
            sourceLedgerVersion: "source-ledger-v1",
            annotationPolicyVersion: "legal-annotation/1",
            candidates: (0..<4).map { index in
                AnnotationCandidate(
                    id: "candidate-\(index)",
                    matterID: "matter-\(index)",
                    claimText: index.isMultiple(of: 2)
                        ? "The café court denied the extension request."
                        : "The court granted the extension request.",
                    claimType: .factual,
                    evidence: [EvidencePassage(
                        id: "evidence-\(index)",
                        source: "Order",
                        sourceType: .courtRecord,
                        text: "The café court denied the extension request."
                    )],
                    challengeTags: ["modality"],
                    evidenceSourceRecordIDs: ["evidence-\(index)": "source-record-\(index)"]
                )
            }
        )
    }

    private func sourceLedger(
        deidentificationReview: DeidentificationReviewStatus = .reviewedBySecondPerson
    ) -> EvidenceSourceLedger {
        EvidenceSourceLedger(
            version: "source-ledger-v1",
            sources: (0..<4).map { index in
                EvidenceSourceRecord(
                    id: "source-record-\(index)",
                    matterID: "matter-\(index)",
                    title: "De-identified order",
                    sourceType: .courtRecord,
                    jurisdiction: "Test jurisdiction",
                    retrievedAt: "2026-07-15",
                    authorizationBasis: .deidentifiedWithAuthorization,
                    licenseOrTerms: "Test authorization on file",
                    redistributionPermitted: true,
                    contentSHA256: String(repeating: "a", count: 64),
                    deidentificationReview: deidentificationReview,
                    containsDirectPersonalIdentifiers: false,
                    containsRestrictedMaterial: false
                )
            }
        )
    }

    private func submission(
        alias: String,
        preparation: AnnotationPreparation
    ) -> AnnotationSubmission {
        let candidateByID = Dictionary(
            uniqueKeysWithValues: preparation.manifest.candidateCorpus.candidates.map { ($0.id, $0) }
        )
        let responses = preparation.manifest.assignments.compactMap { assignment -> AnnotationLabel? in
            guard assignment.reviewerAlias == alias,
                  let candidate = candidateByID[assignment.candidateID],
                  let index = Int(candidate.id.replacingOccurrences(of: "candidate-", with: ""))
            else { return nil }
            let approved = index.isMultiple(of: 2)
            return AnnotationLabel(
                assignmentID: assignment.assignmentID,
                approvalEligible: approved,
                status: approved ? .directlySupported : .unsupported,
                rationale: approved
                    ? "The order states the claim exactly."
                    : "The supplied order does not support that disposition.",
                evidenceSpans: approved
                    ? [GoldEvidenceSpan(
                        evidenceID: candidate.evidence[0].id,
                        exactQuote: candidate.evidence[0].text
                    )]
                    : []
            )
        }
        return AnnotationSubmission(
            corpusVersion: preparation.manifest.candidateCorpus.version,
            reviewerAlias: alias,
            annotationPolicyVersion: preparation.manifest.candidateCorpus.annotationPolicyVersion,
            responses: responses
        )
    }
}
