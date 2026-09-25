// Copyright 2026 Daniel Kissel
// SPDX-License-Identifier: Apache-2.0

import Foundation

public struct EvidencePassage: Codable, Hashable, Sendable {
    public enum SourceType: String, Codable, CaseIterable, Sendable {
        case evidence
        case declaration
        case courtRecord
        case statute
        case regulation
        case courtRule
        case caseLaw
        case calculationInput
        case unknown
    }

    public let id: String
    public let source: String
    public let sourceType: SourceType
    public let text: String

    public init(id: String, source: String, sourceType: SourceType = .unknown, text: String) {
        self.id = id
        self.source = source
        self.sourceType = sourceType
        self.text = text
    }

    /// A missing `sourceType` key decodes as `.unknown`, mirroring the
    /// initializer's default, so minimal JSON from non-Swift callers works.
    /// Unrecognized values still fail: a typo must not silently widen the
    /// source-eligibility rules a verdict was gated by.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.source = try container.decode(String.self, forKey: .source)
        self.sourceType = try container.decodeIfPresent(SourceType.self, forKey: .sourceType) ?? .unknown
        self.text = try container.decode(String.self, forKey: .text)
    }
}

public struct Claim: Codable, Hashable, Sendable {
    public enum ClaimType: String, Codable, CaseIterable, Sendable {
        case factual
        case legalRule
        case legalConclusion
        case calculation
        case recommendation
        case quotation
        case unknown
    }

    public let id: String
    public let text: String
    public let type: ClaimType
    public let parentText: String?
    public let fingerprint: String
    public let range: Range<Int>?

    public init(
        id: String,
        text: String,
        type: ClaimType = .unknown,
        parentText: String? = nil,
        fingerprint: String? = nil,
        range: Range<Int>? = nil
    ) {
        self.id = id
        self.text = text
        self.type = type
        self.parentText = parentText
        self.fingerprint = fingerprint ?? Self.makeFingerprint(text)
        self.range = range
    }

    private static func makeFingerprint(_ text: String) -> String {
        // Stable FNV-1a identifier: material edits invalidate the old verification.
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.lowercased().utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

public enum SupportStatus: String, Codable, CaseIterable, Sendable {
    case directlySupported
    case supportedByInference
    case partiallySupported
    case contradicted
    case ambiguous
    case unsupported
    case notVerifiable
}

public struct EvidenceMatch: Codable, Hashable, Sendable {
    public let passage: EvidencePassage
    public let score: Double
    public let matchedTerms: [String]

    public init(passage: EvidencePassage, score: Double, matchedTerms: [String]) {
        self.passage = passage
        self.score = score
        self.matchedTerms = matchedTerms
    }
}

public struct ClaimVerdict: Codable, Hashable, Sendable {
    public let claim: Claim
    public let status: SupportStatus
    public let confidence: Double
    public let evidence: [EvidenceMatch]
    public let explanation: String

    public init(
        claim: Claim,
        status: SupportStatus,
        confidence: Double,
        evidence: [EvidenceMatch],
        explanation: String
    ) {
        self.claim = claim
        self.status = status
        self.confidence = confidence
        self.evidence = evidence
        self.explanation = explanation
    }
}

public struct ProofReport: Codable, Sendable {
    public let version: Int
    public let createdAt: Date
    public let verdicts: [ClaimVerdict]

    public init(version: Int = 1, createdAt: Date = Date(), verdicts: [ClaimVerdict]) {
        self.version = version
        self.createdAt = createdAt
        self.verdicts = verdicts
    }

    public var isSafeToPublish: Bool {
        verdicts.allSatisfy { $0.status == .directlySupported || $0.status == .supportedByInference }
    }

    public var supportRate: Double {
        guard !verdicts.isEmpty else { return 1 }
        let supported = verdicts.filter {
            $0.status == .directlySupported || $0.status == .supportedByInference
        }.count
        return Double(supported) / Double(verdicts.count)
    }
}

public struct VerificationPolicy: Sendable {
    public var supportedThreshold: Double
    public var ambiguousThreshold: Double
    public var contradictionThreshold: Double
    public var maximumEvidenceMatches: Int

    public init(
        supportedThreshold: Double = 0.80,
        ambiguousThreshold: Double = 0.40,
        contradictionThreshold: Double = 0.55,
        maximumEvidenceMatches: Int = 3
    ) {
        self.supportedThreshold = supportedThreshold
        self.ambiguousThreshold = ambiguousThreshold
        self.contradictionThreshold = contradictionThreshold
        self.maximumEvidenceMatches = maximumEvidenceMatches
    }
}
