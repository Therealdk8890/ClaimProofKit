// Copyright 2026 Daniel Kissel
// SPDX-License-Identifier: BUSL-1.1

import ClaimProofKit
#if canImport(CryptoKit)
import CryptoKit
#elseif canImport(Crypto)
import Crypto
#else
#error("No crypto module available: add this platform to the swift-crypto dependency condition in Package.swift.")
#endif
import Foundation

/// Maps a `ProofReport` into a DProvenanceKit-compatible trace.
///
/// The exported run tells the full verification story: one `cpk_claim_extracted`
/// and one `cpk_claim_verified` event per claim (in report order), terminated by
/// `cpk_report_finalized`. Extracted claims connect to their verdicts with
/// `verifiedBy` edges; verdicts connect to the final report with `derivedFrom`.
public struct ProvenanceExporter: Sendable {
    /// Version of the bridge encoding itself, independent of the spec version.
    public static let bridgeVersion = "1.0"

    public let engineName: String
    public let contextID: String
    public let schemaVersion: Int

    public init(
        engineName: String = "ClaimProofKit",
        contextID: String = "claimproof",
        schemaVersion: Int = 1
    ) {
        self.engineName = engineName
        self.contextID = contextID
        self.schemaVersion = schemaVersion
    }

    /// Builds the trace for a report. Every event carries the report's creation
    /// instant: per Trace Specification v1, the envelope owns time and `sequence`
    /// is the authoritative clock, so a post-hoc export uses a single timestamp.
    ///
    /// `policy` is deliberately explicit: `ProofReport` does not carry the policy
    /// it was produced under, so the caller must pass the one actually used — a
    /// defaulted value here would silently stamp the wrong policy fingerprint
    /// into the trace.
    public func trace(
        for report: ProofReport,
        policy: VerificationPolicy,
        runID: UUID = UUID()
    ) throws -> ProvenanceTrace {
        var events: [ProvenanceEventEnvelope] = []
        var edges: [ProvenanceEdge] = []
        var sequence: UInt64 = 0

        func append(_ erased: ErasedProvenancePayload) -> UUID {
            let envelope = ProvenanceEventEnvelope(
                runID: runID,
                contextID: contextID,
                engineName: engineName,
                schemaVersion: schemaVersion,
                sequence: sequence,
                payload: erased,
                timestamp: report.createdAt
            )
            events.append(envelope)
            sequence += 1
            return envelope.id
        }

        var verdictEventIDs: [UUID] = []
        for verdict in report.verdicts {
            let extracted = ClaimExtractedPayload(claim: verdict.claim)
            let extractedID = append(try .erase(
                extracted, typeIdentifier: extracted.typeIdentifier, priority: extracted.priority
            ))

            let verified = ClaimVerifiedPayload(verdict: verdict)
            let verifiedID = append(try .erase(
                verified, typeIdentifier: verified.typeIdentifier, priority: verified.priority
            ))

            edges.append(ProvenanceEdge(
                sourceID: extractedID, targetID: verifiedID, type: ProvenanceEdge.EdgeType.verifiedBy
            ))
            verdictEventIDs.append(verifiedID)
        }

        let finalized = ReportFinalizedPayload(report: report, policy: policy)
        let reportEventID = append(try .erase(
            finalized, typeIdentifier: finalized.typeIdentifier, priority: finalized.priority
        ))
        for verdictEventID in verdictEventIDs {
            edges.append(ProvenanceEdge(
                sourceID: verdictEventID, targetID: reportEventID, type: ProvenanceEdge.EdgeType.derivedFrom
            ))
        }

        return ProvenanceTrace(
            events: events,
            edges: edges,
            runFingerprint: Self.runFingerprint(of: events),
            reportFingerprint: report.fingerprint,
            policyFingerprint: policy.fingerprint,
            engineName: engineName,
            contextID: contextID
        )
    }

    /// Trace Specification v1 §5 run fingerprint: SHA-1 (lowercase hex) over the
    /// concatenation of `"\(type):\(engine)|"` per event in commit order. This is
    /// the same structural identity DProvenanceKit computes when it stores a run.
    public static func runFingerprint(of events: [ProvenanceEventEnvelope]) -> String {
        var hasher = Insecure.SHA1()
        for event in events {
            let signature = "\(event.payload.typeIdentifier):\(event.engineName)|"
            hasher.update(data: Data(signature.utf8))
        }
        return HexEncoding.lowercase(hasher.finalize())
    }
}

/// A completed export: DProvenanceKit-compatible envelopes, the lineage edges
/// between them, and the identities that lock the run to its report and policy.
public struct ProvenanceTrace: Codable, Equatable, Sendable {
    public let events: [ProvenanceEventEnvelope]
    public let edges: [ProvenanceEdge]
    public let runFingerprint: String
    public let reportFingerprint: String
    public let policyFingerprint: String
    public let engineName: String
    public let contextID: String

    /// Bare JSON array of envelopes. Decodes in DProvenanceKit as
    /// `[TraceEvent<AnyTraceableEvent>]` with a default `JSONDecoder`.
    public func eventsJSONData() throws -> Data {
        try Self.encoder.encode(events)
    }

    /// Full manifest: bridge/spec versions, fingerprints, events, and edges.
    public func manifestJSONData() throws -> Data {
        try Self.encoder.encode(ProvenanceManifest(trace: self))
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

/// On-disk manifest shape written by `claimproof verify --provenance`.
public struct ProvenanceManifest: Codable, Equatable, Sendable {
    public let bridgeVersion: String
    public let specVersion: String
    public let engineName: String
    public let contextID: String
    public let runFingerprint: String
    public let reportFingerprint: String
    public let policyFingerprint: String
    public let events: [ProvenanceEventEnvelope]
    public let edges: [ProvenanceEdge]

    public init(trace: ProvenanceTrace) {
        self.bridgeVersion = ProvenanceExporter.bridgeVersion
        self.specVersion = ClaimProofSpec.version
        self.engineName = trace.engineName
        self.contextID = trace.contextID
        self.runFingerprint = trace.runFingerprint
        self.reportFingerprint = trace.reportFingerprint
        self.policyFingerprint = trace.policyFingerprint
        self.events = trace.events
        self.edges = trace.edges
    }
}
