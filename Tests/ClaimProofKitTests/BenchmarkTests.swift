// Copyright 2026 Daniel Kissel
// SPDX-License-Identifier: BUSL-1.1

import Foundation
import Testing
@testable import ClaimProofKit

@Suite("Benchmark v0.1")
struct BenchmarkTests {
    @Test("Versioned corpus is substantial and decodes")
    func corpusDecodes() throws {
        let corpus = try loadCorpus()
        #expect(corpus.version == "v0.1")
        #expect(corpus.claimCases.count == 34)
        #expect(corpus.extractionCases.count == 10)
        #expect(Set(corpus.claimCases.map(\.id)).count == corpus.claimCases.count)
        #expect(Set(corpus.extractionCases.map(\.id)).count == corpus.extractionCases.count)
    }

    @Test("Realistic collection template decodes but cannot pass as a release holdout")
    func realisticTemplateDecodes() throws {
        let corpus = try loadCorpus(relativePath: "Docs/realistic-benchmark-template.json")
        #expect(corpus.metadata?.split == .development)
        let report = BenchmarkRunner().run(corpus)
        #expect(!report.passesProductionReleaseGate)
        #expect(report.productionReleaseGateFailures.contains {
            $0.contains("sealedHoldout is required")
        })
    }

    @Test("Baseline meets the safety regression gate")
    func safetyGate() throws {
        let report = BenchmarkRunner().run(try loadCorpus())
        #expect(report.falseSupportedRate == 0)
        #expect(report.passesSafetyGate)
    }

    @Test("Baseline reports per-class metrics, calibration, and ship criteria")
    func perClassMetrics() throws {
        let report = BenchmarkRunner().run(try loadCorpus())
        // Zero dangerous approvals ⇒ every approval deserved and every unsafe claim caught.
        #expect(report.supportedPrecision == 1)
        #expect(report.unsupportedRecall == 1)
        #expect(report.meetsShipCriteria)
        // The two permanently-failing inference cases are illegitimate warnings,
        // so warning precision must be below 1 — the aggregate can't hide them.
        #expect(report.warningPrecision < 1)
        #expect(report.statusMetrics["contradicted"]?.recall == 1)
        #expect(report.categoryBreakdown["reasonableInference"]?.exactMatchRate == 0)
        #expect(report.calibration.bins.reduce(0) { $0 + $1.caseCount } == report.claimResults.count)
        #expect(report.calibration.expectedCalibrationError >= 0)
        #expect(report.calibration.expectedCalibrationError <= 1)
        // The synthetic corpus remains a useful regression gate, but it is far
        // too small and lacks independent/sealed metadata for a release claim.
        #expect(report.unsafeCaseCount == 24)
        #expect(report.falseSupportedUpperBound95 > 0.11)
        #expect(!report.passesProductionReleaseGate)
        #expect(report.productionReleaseGateFailures.contains("realistic-corpus metadata is missing"))
    }

    @Test("A statistically powered, independently labeled sealed corpus can pass the release gate")
    func productionReleaseGatePasses() {
        let report = BenchmarkRunner().run(releaseCorpus())
        #expect(report.passesProductionReleaseGate)
        #expect(report.productionReleaseGateFailures.isEmpty)
        #expect(report.dangerousApprovalCount == 0)
        #expect(report.falseSupportedUpperBound95 <= 0.01)
        #expect(report.approvalRecall == 1)
        #expect(report.matterCount == 50)
    }

    @Test("One false green fails the production release gate unconditionally")
    func productionReleaseGateRejectsFalseGreen() {
        let report = BenchmarkRunner().run(releaseCorpus(includeFalseGreen: true))
        #expect(!report.passesProductionReleaseGate)
        #expect(report.dangerousApprovalCount == 1)
        #expect(report.productionReleaseGateFailures.contains { $0.hasPrefix("dangerous approval count 1") })
    }

    @Test("A fabricated gold quote cannot satisfy the release gate")
    func productionReleaseGateRejectsInvalidGoldSpan() {
        let report = BenchmarkRunner().run(releaseCorpus(includeInvalidGoldSpan: true))
        #expect(!report.passesProductionReleaseGate)
        #expect(report.productionReleaseGateFailures.contains {
            $0.contains("lack valid exact gold evidence spans")
        })
    }

    @Test("A canonically equivalent but byte-different gold quote is rejected")
    func productionReleaseGateRequiresByteExactGoldSpan() {
        let report = BenchmarkRunner().run(releaseCorpus(includeNormalizedGoldSpan: true))
        #expect(!report.passesProductionReleaseGate)
        #expect(report.productionReleaseGateFailures.contains {
            $0.contains("lack valid exact gold evidence spans")
        })
    }

    @Test("A lazily approving verifier fails the ship criteria, not just accuracy")
    func lazyApprovalCanary() {
        // Full lexical overlap with a different meaning: the baseline verifier
        // approves this, the gold label says it must not.
        let falseApproval = ClaimBenchmarkCase(
            id: "canary-1",
            category: .partialSupport,
            claimText: "The tenant paid rent in March.",
            claimType: .factual,
            evidence: [EvidencePassage(
                id: "ledger",
                source: "Ledger",
                sourceType: .evidence,
                text: "The tenant paid rent in March into escrow rather than to the landlord."
            )],
            expectedStatus: .partiallySupported,
            rationale: "Payment happened but not as the claim implies."
        )
        let trueApproval = ClaimBenchmarkCase(
            id: "canary-2",
            category: .directSupport,
            claimText: "The court denied the request for an extension.",
            claimType: .factual,
            evidence: [EvidencePassage(
                id: "order",
                source: "Order",
                sourceType: .courtRecord,
                text: "The court denied the request for an extension."
            )],
            expectedStatus: .directlySupported,
            rationale: "Verbatim support."
        )
        let corpus = BenchmarkCorpus(
            version: "canary",
            name: "lazy approval canary",
            claimCases: [falseApproval, trueApproval],
            extractionCases: []
        )
        let report = BenchmarkRunner().run(corpus)
        #expect(report.supportedPrecision == 0.5)
        #expect(report.unsupportedRecall == 0)
        #expect(!report.meetsShipCriteria)
        #expect(!report.passesSafetyGate)
    }

    @Test("Structured values cannot be silently approved")
    func structuredValueConflict() {
        let evidence = EvidencePassage(
            id: "rule",
            source: "Court rule",
            sourceType: .courtRule,
            text: "The response period is 14 days."
        )
        let claim = Claim(
            id: "deadline",
            text: "The response period is 30 days.",
            type: .legalRule
        )
        #expect(ClaimVerifier().verify(claim: claim, against: [evidence]).status == .contradicted)
    }

    private func loadCorpus() throws -> BenchmarkCorpus {
        try loadCorpus(relativePath: "Fixtures/benchmark-v0.1.json")
    }

    private func loadCorpus(relativePath: String) throws -> BenchmarkCorpus {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent(relativePath)
        return try JSONDecoder().decode(BenchmarkCorpus.self, from: Data(contentsOf: url))
    }

    /// Generated in-memory so the repository does not pretend synthetic data is
    /// the real corpus. This only locks the release-gate mechanics and boundary.
    private func releaseCorpus(
        includeFalseGreen: Bool = false,
        includeInvalidGoldSpan: Bool = false,
        includeNormalizedGoldSpan: Bool = false
    ) -> BenchmarkCorpus {
        let tags = [
            "actor", "amount", "compoundClaim", "date", "modality",
            "negation", "quotation", "sourceAuthority",
        ]
        var claimCases: [ClaimBenchmarkCase] = []

        for index in 0..<300 {
            let isCanary = includeFalseGreen && index == 0
            let evidence = EvidencePassage(
                id: "rule-\(index)",
                source: "Court Rule 6",
                sourceType: .courtRule,
                text: isCanary
                    ? "The response period was 30 days."
                    : "The response period was 14 days."
            )
            claimCases.append(ClaimBenchmarkCase(
                id: "unsafe-\(index)",
                category: isCanary ? .unsupported : .contradiction,
                claimText: "The response period was 30 days.",
                claimType: .legalRule,
                evidence: [evidence],
                expectedStatus: isCanary ? .unsupported : .contradicted,
                rationale: isCanary
                    ? "The canary gold label refuses approval despite lexical identity."
                    : "The controlling rule states a different deadline.",
                matterID: "matter-\(index % 50)",
                challengeTags: tags,
                goldEvidenceSpans: isCanary ? nil : [GoldEvidenceSpan(
                    evidenceID: evidence.id,
                    exactQuote: evidence.text
                )]
            ))
        }

        for index in 0..<100 {
            let invalidGoldSpan = includeInvalidGoldSpan && index == 0
            let normalizedGoldSpan = includeNormalizedGoldSpan && index == 0
            let evidence = EvidencePassage(
                id: "order-\(index)",
                source: "Court order",
                sourceType: .courtRecord,
                text: normalizedGoldSpan
                    ? "The café court denied the extension request."
                    : "The court denied the extension request."
            )
            claimCases.append(ClaimBenchmarkCase(
                id: "supported-\(index)",
                category: .directSupport,
                claimText: evidence.text,
                claimType: .factual,
                evidence: [evidence],
                expectedStatus: .directlySupported,
                rationale: "The order states the proposition verbatim.",
                matterID: "matter-\(index % 50)",
                challengeTags: tags,
                goldEvidenceSpans: [GoldEvidenceSpan(
                    evidenceID: evidence.id,
                    exactQuote: invalidGoldSpan
                        ? "The court granted the extension request."
                        : normalizedGoldSpan
                            ? evidence.text.decomposedStringWithCanonicalMapping
                            : evidence.text
                )]
            ))
        }

        let extractionCases = (0..<50).map { index in
            ExtractionBenchmarkCase(
                id: "extract-\(index)",
                document: "The court denied the extension request.",
                expectedClaims: ["The court denied the extension request."]
            )
        }
        return BenchmarkCorpus(
            version: "release-gate-test",
            name: "Production release gate mechanics",
            metadata: BenchmarkCorpusMetadata(
                origin: .publicRecord,
                split: .sealedHoldout,
                independentlyLabeled: true,
                annotatorsPerClaim: 2,
                binaryLabelAgreement: 0.90,
                annotationPolicyVersion: "legal-annotation/1"
            ),
            claimCases: claimCases,
            extractionCases: extractionCases
        )
    }
}
