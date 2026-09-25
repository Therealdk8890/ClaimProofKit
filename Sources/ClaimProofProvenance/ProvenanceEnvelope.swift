// Copyright 2026 Daniel Kissel
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Wire-compatible mirror of DProvenanceKit's `TraceEvent<AnyTraceableEvent>`.
///
/// Property names and types replicate the envelope exactly, so JSON produced
/// here decodes with `JSONDecoder().decode([TraceEvent<AnyTraceableEvent>].self, ...)`
/// in DProvenanceKit without adapters. This module deliberately does not depend
/// on DProvenanceKit — parity is enforced by the conformance harness, which
/// round-trips this encoding through the real package.
public struct ProvenanceEventEnvelope: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let runID: UUID
    public let contextID: String
    public let engineName: String
    public let schemaVersion: Int
    public let sequence: UInt64
    public let spanID: String?
    public let parentSpanID: String?
    public let payload: ErasedProvenancePayload
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        runID: UUID,
        contextID: String,
        engineName: String,
        schemaVersion: Int,
        sequence: UInt64,
        spanID: String? = nil,
        parentSpanID: String? = nil,
        payload: ErasedProvenancePayload,
        timestamp: Date
    ) {
        self.id = id
        self.runID = runID
        self.contextID = contextID
        self.engineName = engineName
        self.schemaVersion = schemaVersion
        self.sequence = sequence
        self.spanID = spanID
        self.parentSpanID = parentSpanID
        self.payload = payload
        self.timestamp = timestamp
    }
}

/// Wire-compatible mirror of DProvenanceKit's `AnyTraceableEvent`.
/// `rawJSON` holds the canonical (`.sortedKeys`, UTF-8) encoding of the payload,
/// per Trace Specification v1 §2.
public struct ErasedProvenancePayload: Codable, Equatable, Sendable {
    public let typeIdentifier: String
    public let priorityValue: Int
    public let rawJSON: String

    public init(typeIdentifier: String, priorityValue: Int, rawJSON: String) {
        self.typeIdentifier = typeIdentifier
        self.priorityValue = priorityValue
        self.rawJSON = rawJSON
    }

    /// Canonically encodes any payload (`.sortedKeys`, UTF-8 — Trace Spec v1 §2)
    /// into an erased wire payload. Public so hosts can attach their own custom
    /// event types alongside the built-in ClaimProof vocabulary.
    public static func erase(_ payload: some Codable, typeIdentifier: String, priority: ProvenancePriority) throws -> ErasedProvenancePayload {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        return ErasedProvenancePayload(
            typeIdentifier: typeIdentifier,
            priorityValue: priority.rawValue,
            rawJSON: String(decoding: data, as: UTF8.self)
        )
    }
}

/// Wire-compatible mirror of DProvenanceKit's `TraceEdge`. `type` carries a
/// `TraceEdgeType` raw value.
public struct ProvenanceEdge: Codable, Equatable, Sendable {
    /// The full `TraceEdgeType` vocabulary. `type` stays a plain `String` on the
    /// wire so future DProvenanceKit edge types pass through undisturbed.
    public enum EdgeType {
        public static let derivedFrom = "derivedFrom"
        public static let influencedBy = "influencedBy"
        public static let generatedFrom = "generatedFrom"
        public static let verifiedBy = "verifiedBy"
        public static let correctedBy = "correctedBy"
        public static let informed = "informed"
    }

    public let sourceID: UUID
    public let targetID: UUID
    public let type: String

    public init(sourceID: UUID, targetID: UUID, type: String) {
        self.sourceID = sourceID
        self.targetID = targetID
        self.type = type
    }
}
