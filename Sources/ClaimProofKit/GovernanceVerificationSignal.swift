// Copyright 2026 Daniel Kissel
// SPDX-License-Identifier: BUSL-1.1

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
        precondition(!reportFingerprint.isEmpty, "reportFingerprint must be non-empty")
        precondition(!policyFingerprint.isEmpty, "policyFingerprint must be non-empty")
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

    /// A compact JSON representation suitable for a message bus, webhook, or
    /// controller event attribute. ClaimProofKit remains independent of the
    /// controller that consumes it.
    public func jsonData() throws -> Data {
        try JSONEncoder().encode(self)
    }
}
