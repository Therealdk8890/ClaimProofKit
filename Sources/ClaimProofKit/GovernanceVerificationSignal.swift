// Copyright 2026 Daniel Kissel
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Provider-neutral result emitted by ClaimProofKit for an external governance
/// controller. The signal describes verification; it does not authorize,
/// contain, or recover an agent.
public struct GovernanceVerificationSignal: Codable, Equatable, Sendable {
    public enum Disposition: String, Codable, Sendable {
        case allow
        case requireReview
        case block
    }

    public let version: Int
    public let disposition: Disposition
    public let reportFingerprint: String
    public let policyFingerprint: String
    public let blockingClaimIDs: [String]
    public let reviewClaimIDs: [String]
    public let supportedClaimCount: Int
    public let totalClaimCount: Int
    public let traceID: String?
    public let runID: String?
    public let actionID: String?

    public init(
        disposition: Disposition,
        reportFingerprint: String,
        policyFingerprint: String,
        blockingClaimIDs: [String] = [],
        reviewClaimIDs: [String] = [],
        supportedClaimCount: Int,
        totalClaimCount: Int,
        traceID: String? = nil,
        runID: String? = nil,
        actionID: String? = nil,
        version: Int = 1
    ) {
        precondition(version >= 1, "version must be positive")
        precondition(!reportFingerprint.isEmpty, "reportFingerprint must be non-empty")
        precondition(!policyFingerprint.isEmpty, "policyFingerprint must be non-empty")
        precondition(blockingClaimIDs.allSatisfy { !$0.isEmpty }, "blockingClaimIDs entries must be non-empty")
        precondition(reviewClaimIDs.allSatisfy { !$0.isEmpty }, "reviewClaimIDs entries must be non-empty")
        precondition(traceID == nil || !traceID!.isEmpty, "traceID must be non-empty when present")
        precondition(runID == nil || !runID!.isEmpty, "runID must be non-empty when present")
        precondition(actionID == nil || !actionID!.isEmpty, "actionID must be non-empty when present")
        precondition(supportedClaimCount >= 0, "supportedClaimCount must be non-negative")
        precondition(totalClaimCount >= 0, "totalClaimCount must be non-negative")
        precondition(supportedClaimCount <= totalClaimCount, "supportedClaimCount cannot exceed totalClaimCount")
        self.version = version
        self.disposition = disposition
        self.reportFingerprint = reportFingerprint
        self.policyFingerprint = policyFingerprint
        self.blockingClaimIDs = blockingClaimIDs
        self.reviewClaimIDs = reviewClaimIDs
        self.supportedClaimCount = supportedClaimCount
        self.totalClaimCount = totalClaimCount
        self.traceID = traceID
        self.runID = runID
        self.actionID = actionID
    }

    /// Build a governance signal from a completed verification pipeline.
    public init(
        result: PipelineResult,
        policyFingerprint: String,
        traceID: String? = nil,
        runID: String? = nil,
        actionID: String? = nil
    ) {
        let disposition: Disposition
        switch result.decision.disposition {
        case .allow:
            disposition = .allow
        case .requireReview:
            disposition = .requireReview
        case .block:
            disposition = .block
        }

        let supported = result.report.verdicts.filter {
            $0.status == .directlySupported || $0.status == .supportedByInference
        }.count

        self.init(
            disposition: disposition,
            reportFingerprint: result.report.fingerprint,
            policyFingerprint: policyFingerprint,
            blockingClaimIDs: result.decision.blockingClaimIDs,
            reviewClaimIDs: result.decision.reviewClaimIDs,
            supportedClaimCount: supported,
            totalClaimCount: result.report.verdicts.count,
            traceID: traceID,
            runID: runID,
            actionID: actionID
        )
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case disposition
        case reportFingerprint
        case policyFingerprint
        case blockingClaimIDs
        case reviewClaimIDs
        case supportedClaimCount
        case totalClaimCount
        case traceID
        case runID
        case actionID
    }

    /// Decode untrusted transport data through the same contract validation as
    /// programmatic construction. This prevents Codable from bypassing the
    /// invariants enforced by the public initializer.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .version)
        let disposition = try container.decode(Disposition.self, forKey: .disposition)
        let reportFingerprint = try container.decode(String.self, forKey: .reportFingerprint)
        let policyFingerprint = try container.decode(String.self, forKey: .policyFingerprint)
        let blockingClaimIDs = try container.decode([String].self, forKey: .blockingClaimIDs)
        let reviewClaimIDs = try container.decode([String].self, forKey: .reviewClaimIDs)
        let supportedClaimCount = try container.decode(Int.self, forKey: .supportedClaimCount)
        let totalClaimCount = try container.decode(Int.self, forKey: .totalClaimCount)
        let traceID = try container.decodeIfPresent(String.self, forKey: .traceID)
        let runID = try container.decodeIfPresent(String.self, forKey: .runID)
        let actionID = try container.decodeIfPresent(String.self, forKey: .actionID)

        func invalid(_ field: String, _ reason: String) -> DecodingError {
            DecodingError.dataCorruptedError(forKey: CodingKeys(stringValue: field)!, in: container, debugDescription: reason)
        }

        guard version >= 1 else { throw invalid("version", "version must be positive") }
        guard !reportFingerprint.isEmpty else { throw invalid("reportFingerprint", "must be non-empty") }
        guard !policyFingerprint.isEmpty else { throw invalid("policyFingerprint", "must be non-empty") }
        guard supportedClaimCount >= 0 else { throw invalid("supportedClaimCount", "must be non-negative") }
        guard totalClaimCount >= 0 else { throw invalid("totalClaimCount", "must be non-negative") }
        guard supportedClaimCount <= totalClaimCount else { throw invalid("supportedClaimCount", "cannot exceed totalClaimCount") }
        guard blockingClaimIDs.allSatisfy({ !$0.isEmpty }) else { throw invalid("blockingClaimIDs", "entries must be non-empty") }
        guard reviewClaimIDs.allSatisfy({ !$0.isEmpty }) else { throw invalid("reviewClaimIDs", "entries must be non-empty") }
        guard traceID == nil || traceID!.isEmpty == false else { throw invalid("traceID", "must be non-empty when present") }
        guard runID == nil || runID!.isEmpty == false else { throw invalid("runID", "must be non-empty when present") }
        guard actionID == nil || actionID!.isEmpty == false else { throw invalid("actionID", "must be non-empty when present") }

        self.init(
            disposition: disposition,
            reportFingerprint: reportFingerprint,
            policyFingerprint: policyFingerprint,
            blockingClaimIDs: blockingClaimIDs,
            reviewClaimIDs: reviewClaimIDs,
            supportedClaimCount: supportedClaimCount,
            totalClaimCount: totalClaimCount,
            traceID: traceID,
            runID: runID,
            actionID: actionID,
            version: version
        )
    }

    /// A compact JSON representation suitable for a message bus, webhook, or
    /// controller event attribute. ClaimProofKit remains independent of the
    /// controller that consumes it.
    public func jsonData() throws -> Data {
        try JSONEncoder().encode(self)
    }
}
