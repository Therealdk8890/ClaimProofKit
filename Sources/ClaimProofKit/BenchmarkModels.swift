// Copyright 2026 Daniel Kissel
// SPDX-License-Identifier: BUSL-1.1

import Foundation

public struct BenchmarkCorpus: Codable, Sendable {
    public let version: String
    public let name: String
    /// Required by the production release gate. Kept optional so historical
    /// synthetic regression corpora continue to decode unchanged.
    public let metadata: BenchmarkCorpusMetadata?
    public let claimCases: [ClaimBenchmarkCase]
    public let extractionCases: [ExtractionBenchmarkCase]

    public init(
        version: String,
        name: String,
        metadata: BenchmarkCorpusMetadata? = nil,
        claimCases: [ClaimBenchmarkCase],
        extractionCases: [ExtractionBenchmarkCase]
    ) {
        self.version = version
        self.name = name
        self.metadata = metadata
        self.claimCases = claimCases
        self.extractionCases = extractionCases
    }
}

/// Provenance and annotation facts that distinguish a realistic, sealed legal
/// benchmark from an authored development fixture. These fields are assertions
/// about the corpus-building process, not model outputs.
public struct BenchmarkCorpusMetadata: Codable, Sendable {
    public enum Origin: String, Codable, Sendable {
        case authoredSynthetic
        case deidentifiedReal
        case publicRecord
        case mixedRealistic
    }

    public enum Split: String, Codable, Sendable {
        case development
        case validation
        case sealedHoldout
    }

    public let origin: Origin
    public let split: Split
    public let independentlyLabeled: Bool
    public let annotatorsPerClaim: Int
    /// Agreement on the load-bearing binary decision: approval-eligible or not.
    public let binaryLabelAgreement: Double
    public let annotationPolicyVersion: String

    public init(
        origin: Origin,
        split: Split,
        independentlyLabeled: Bool,
        annotatorsPerClaim: Int,
        binaryLabelAgreement: Double,
        annotationPolicyVersion: String
    ) {
        self.origin = origin
        self.split = split
        self.independentlyLabeled = independentlyLabeled
        self.annotatorsPerClaim = annotatorsPerClaim
        self.binaryLabelAgreement = binaryLabelAgreement
        self.annotationPolicyVersion = annotationPolicyVersion
    }
}

/// Exact adjudicated evidence attached to a gold label. A green or contradicted
/// release-gate case without a byte-exact span is not defensible and is refused.
public struct GoldEvidenceSpan: Codable, Sendable {
    public let evidenceID: String
    public let exactQuote: String
    public let startUTF16: Int?
    public let endUTF16: Int?

    public init(
        evidenceID: String,
        exactQuote: String,
        startUTF16: Int? = nil,
        endUTF16: Int? = nil
    ) {
        self.evidenceID = evidenceID
        self.exactQuote = exactQuote
        self.startUTF16 = startUTF16
        self.endUTF16 = endUTF16
    }
}

public struct ClaimBenchmarkCase: Codable, Sendable {
    public enum Category: String, Codable, CaseIterable, Sendable {
        case directSupport
        case reasonableInference
        case partialSupport
        case contradiction
        case unsupported
        case citationIntegrity
        case sourceAuthority
        case notVerifiable
    }

    public let id: String
    public let category: Category
    public let claimText: String
    public let claimType: Claim.ClaimType
    public let evidence: [EvidencePassage]
    public let expectedStatus: SupportStatus
    public let rationale: String
    /// Matter-level grouping prevents claim leakage across corpus splits and
    /// lets the release gate enforce breadth across independent legal matters.
    public let matterID: String?
    /// Structured hard-negative coverage, e.g. date, amount, negation, actor.
    public let challengeTags: [String]?
    /// Required for approval-eligible and contradicted production cases.
    public let goldEvidenceSpans: [GoldEvidenceSpan]?

    public init(
        id: String,
        category: Category,
        claimText: String,
        claimType: Claim.ClaimType,
        evidence: [EvidencePassage],
        expectedStatus: SupportStatus,
        rationale: String,
        matterID: String? = nil,
        challengeTags: [String]? = nil,
        goldEvidenceSpans: [GoldEvidenceSpan]? = nil
    ) {
        self.id = id
        self.category = category
        self.claimText = claimText
        self.claimType = claimType
        self.evidence = evidence
        self.expectedStatus = expectedStatus
        self.rationale = rationale
        self.matterID = matterID
        self.challengeTags = challengeTags
        self.goldEvidenceSpans = goldEvidenceSpans
    }
}

public struct ExtractionBenchmarkCase: Codable, Sendable {
    public let id: String
    public let document: String
    public let expectedClaims: [String]

    public init(id: String, document: String, expectedClaims: [String]) {
        self.id = id
        self.document = document
        self.expectedClaims = expectedClaims
    }
}

public struct BenchmarkCaseResult: Codable, Sendable {
    public let id: String
    public let category: ClaimBenchmarkCase.Category
    public let expected: SupportStatus
    public let predicted: SupportStatus
    public let confidence: Double
    public let passed: Bool
    public let dangerouslyApproved: Bool
}

public struct ExtractionCaseResult: Codable, Sendable {
    public let id: String
    public let expected: [String]
    public let predicted: [String]
    public let truePositiveCount: Int
    public let falsePositiveCount: Int
    public let falseNegativeCount: Int
}

public struct BenchmarkThresholds: Codable, Sendable {
    public let minimumVerdictAccuracy: Double
    public let maximumFalseSupportedRate: Double
    public let minimumContradictionRecall: Double
    public let minimumExtractionPrecision: Double
    public let minimumExtractionRecall: Double
    /// Ship criteria (feature go/no-go), evaluated separately from the
    /// regression gate: an "approved" verdict must be right at least this often.
    public let minimumSupportedPrecision: Double
    /// Ship criteria: unsafe (unsupported/contradicted/etc.) claims must be
    /// caught — not approved — at least this often.
    public let minimumUnsupportedRecall: Double

    public init(
        minimumVerdictAccuracy: Double = 0.70,
        maximumFalseSupportedRate: Double = 0,
        minimumContradictionRecall: Double = 0.80,
        minimumExtractionPrecision: Double = 0.80,
        minimumExtractionRecall: Double = 0.80,
        minimumSupportedPrecision: Double = 0.95,
        minimumUnsupportedRecall: Double = 0.90
    ) {
        self.minimumVerdictAccuracy = minimumVerdictAccuracy
        self.maximumFalseSupportedRate = maximumFalseSupportedRate
        self.minimumContradictionRecall = minimumContradictionRecall
        self.minimumExtractionPrecision = minimumExtractionPrecision
        self.minimumExtractionRecall = minimumExtractionRecall
        self.minimumSupportedPrecision = minimumSupportedPrecision
        self.minimumUnsupportedRecall = minimumUnsupportedRecall
    }
}

/// High-stakes release requirements. This is intentionally separate from the
/// fast synthetic regression gate: `claimproof benchmark --release` applies
/// these only to a sealed, independently labeled realistic corpus.
public struct BenchmarkReleaseThresholds: Codable, Sendable {
    public let minimumUnsafeCaseCount: Int
    public let minimumApprovalEligibleCaseCount: Int
    public let maximumFalseSupportedUpperBound95: Double
    public let minimumApprovalRecall: Double
    public let minimumContradictionRecall: Double
    public let minimumContradictionCaseCount: Int
    public let minimumExtractionRecall: Double
    public let minimumExtractionCaseCount: Int
    public let minimumWarningPrecision: Double
    public let minimumMatterCount: Int
    public let minimumAnnotatorsPerClaim: Int
    public let minimumBinaryLabelAgreement: Double
    public let requiredChallengeTags: [String]
    public let minimumCasesPerChallengeTag: Int

    public init(
        minimumUnsafeCaseCount: Int = 300,
        minimumApprovalEligibleCaseCount: Int = 100,
        maximumFalseSupportedUpperBound95: Double = 0.01,
        minimumApprovalRecall: Double = 0.80,
        minimumContradictionRecall: Double = 0.95,
        minimumContradictionCaseCount: Int = 50,
        minimumExtractionRecall: Double = 0.98,
        minimumExtractionCaseCount: Int = 50,
        minimumWarningPrecision: Double = 0.80,
        minimumMatterCount: Int = 50,
        minimumAnnotatorsPerClaim: Int = 2,
        minimumBinaryLabelAgreement: Double = 0.80,
        requiredChallengeTags: [String] = [
            "actor", "amount", "compoundClaim", "date", "modality",
            "negation", "quotation", "sourceAuthority",
        ],
        minimumCasesPerChallengeTag: Int = 20
    ) {
        self.minimumUnsafeCaseCount = minimumUnsafeCaseCount
        self.minimumApprovalEligibleCaseCount = minimumApprovalEligibleCaseCount
        self.maximumFalseSupportedUpperBound95 = maximumFalseSupportedUpperBound95
        self.minimumApprovalRecall = minimumApprovalRecall
        self.minimumContradictionRecall = minimumContradictionRecall
        self.minimumContradictionCaseCount = minimumContradictionCaseCount
        self.minimumExtractionRecall = minimumExtractionRecall
        self.minimumExtractionCaseCount = minimumExtractionCaseCount
        self.minimumWarningPrecision = minimumWarningPrecision
        self.minimumMatterCount = minimumMatterCount
        self.minimumAnnotatorsPerClaim = minimumAnnotatorsPerClaim
        self.minimumBinaryLabelAgreement = minimumBinaryLabelAgreement
        self.requiredChallengeTags = requiredChallengeTags
        self.minimumCasesPerChallengeTag = minimumCasesPerChallengeTag
    }
}

/// Precision/recall for one verdict status, derived from the confusion matrix.
public struct StatusMetric: Codable, Sendable {
    public let expectedCount: Int
    public let predictedCount: Int
    public let matchCount: Int
    public let precision: Double
    public let recall: Double
}

/// Outcome quality within one authored corpus category.
public struct CategoryMetric: Codable, Sendable {
    public let caseCount: Int
    public let exactMatchCount: Int
    public let dangerousApprovalCount: Int
    public let exactMatchRate: Double
}

/// One fixed-width confidence bucket. `exactMatchRate` close to
/// `averageConfidence` means the confidence field is well calibrated.
public struct CalibrationBin: Codable, Sendable {
    public let lowerBound: Double
    public let upperBound: Double
    public let caseCount: Int
    public let averageConfidence: Double
    public let exactMatchRate: Double
}

public struct CalibrationSummary: Codable, Sendable {
    public let bins: [CalibrationBin]
    /// Expected calibration error: case-weighted mean |accuracy − confidence|
    /// across non-empty bins. Lower is better; 0 is perfectly calibrated.
    public let expectedCalibrationError: Double
}

public struct BenchmarkReport: Codable, Sendable {
    public let corpusVersion: String
    public let corpusName: String
    public let corpusMetadata: BenchmarkCorpusMetadata?
    public let thresholds: BenchmarkThresholds
    public let releaseThresholds: BenchmarkReleaseThresholds
    public let claimResults: [BenchmarkCaseResult]
    public let extractionResults: [ExtractionCaseResult]
    public let verdictAccuracy: Double
    public let falseSupportedRate: Double
    public let falseSupportedUpperBound95: Double
    public let unsafeCaseCount: Int
    public let approvalEligibleCaseCount: Int
    public let dangerousApprovalCount: Int
    public let contradictionRecall: Double
    public let extractionPrecision: Double
    public let extractionRecall: Double
    /// Of claims the verifier approved, how many deserved approval.
    /// This is the "verified really means verified" number.
    public let supportedPrecision: Double
    /// Of approval-eligible gold claims, how many the verifier approved. This
    /// prevents a reject-everything system from passing on false-green safety.
    public let approvalRecall: Double
    /// Of expected-unsafe claims, how many were caught (not approved).
    /// Complement of `falseSupportedRate`; the "dangerous claims caught" number.
    public let unsupportedRecall: Double
    /// Of claims the verifier flagged (any non-approved verdict), how many
    /// deserved flagging. Low values mean warning fatigue.
    public let warningPrecision: Double
    /// Precision/recall of the abstaining verdicts (notVerifiable, ambiguous):
    /// does the verifier admit uncertainty in the right places?
    public let abstentionPrecision: Double
    public let abstentionRecall: Double
    /// Per-status precision/recall for every verdict status.
    public let statusMetrics: [String: StatusMetric]
    /// Outcome quality per authored corpus category.
    public let categoryBreakdown: [String: CategoryMetric]
    public let calibration: CalibrationSummary
    public let confusionMatrix: [String: [String: Int]]
    public let matterCount: Int
    public let challengeTagCounts: [String: Int]
    /// Regression gate: protects against getting worse. CI keys off this.
    public let passesSafetyGate: Bool
    /// Ship criteria: the feature go/no-go bar (supported precision and
    /// unsupported recall thresholds). Meeting it on an authored development
    /// corpus is necessary, NOT sufficient — the bar must also be met on
    /// independently labeled, realistic documents.
    public let meetsShipCriteria: Bool
    /// High-stakes release gate. It requires a sealed, independently labeled,
    /// realistic corpus with enough statistical power and coverage.
    public let passesProductionReleaseGate: Bool
    /// Stable, human-readable reasons make a failed release gate actionable.
    public let productionReleaseGateFailures: [String]
}
