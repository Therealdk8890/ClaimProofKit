// Copyright 2026 Daniel Kissel
// SPDX-License-Identifier: Apache-2.0

import ClaimProofKit
import ClaimProofProvenance
import Foundation

/// A JSON-in/JSON-out boundary over the verification pipeline, for hosts that
/// cannot bind Swift types directly — a wasm module driven from JavaScript, an
/// FFI caller, or a subprocess. Synchronous by design: the baseline pipeline is
/// deterministic and offline, and single-threaded wasm cannot block on async.
///
/// The provenance manifest is returned as the exact JSON string produced by
/// `ProvenanceTrace.manifestJSONData()` — embedded verbatim, never re-encoded,
/// per Trace Specification v1 §2.
public enum ClaimProofBridge {
    public struct Request: Codable, Sendable {
        public var document: String
        public var evidence: [EvidencePassage]
        public var policy: PolicyOverrides?
        public var includeMarkdown: Bool?
        public var includeProvenance: Bool?
        /// Optional UUID string stamped as the trace's `runID`. This pins only
        /// that field: envelope event IDs and timestamps are freshly generated
        /// per run, so two runs with the same `runID` still differ byte-wise.
        public var runID: String?

        public init(
            document: String,
            evidence: [EvidencePassage],
            policy: PolicyOverrides? = nil,
            includeMarkdown: Bool? = nil,
            includeProvenance: Bool? = nil,
            runID: String? = nil
        ) {
            self.document = document
            self.evidence = evidence
            self.policy = policy
            self.includeMarkdown = includeMarkdown
            self.includeProvenance = includeProvenance
            self.runID = runID
        }
    }

    public struct PolicyOverrides: Codable, Sendable {
        public var supportedThreshold: Double?
        public var ambiguousThreshold: Double?
        public var contradictionThreshold: Double?
        public var maximumEvidenceMatches: Int?

        public init(
            supportedThreshold: Double? = nil,
            ambiguousThreshold: Double? = nil,
            contradictionThreshold: Double? = nil,
            maximumEvidenceMatches: Int? = nil
        ) {
            self.supportedThreshold = supportedThreshold
            self.ambiguousThreshold = ambiguousThreshold
            self.contradictionThreshold = contradictionThreshold
            self.maximumEvidenceMatches = maximumEvidenceMatches
        }

        func applied(to policy: inout VerificationPolicy) {
            if let supportedThreshold { policy.supportedThreshold = supportedThreshold }
            if let ambiguousThreshold { policy.ambiguousThreshold = ambiguousThreshold }
            if let contradictionThreshold { policy.contradictionThreshold = contradictionThreshold }
            if let maximumEvidenceMatches { policy.maximumEvidenceMatches = maximumEvidenceMatches }
        }
    }

    public struct Response: Codable, Sendable {
        public let specVersion: String
        public let report: ProofReport
        public let decision: ProofDecision
        public let reportFingerprint: String
        public let policyFingerprint: String
        public let markdown: String?
        /// Canonical manifest JSON from `manifestJSONData()`, verbatim.
        public let provenanceManifest: String?
    }

    public struct ErrorResponse: Codable, Sendable {
        public struct Failure: Codable, Sendable {
            public let code: String
            public let message: String
        }

        public let error: Failure
    }

    /// Runs the baseline deterministic verification over a JSON request and
    /// returns a JSON response; on any failure returns an `ErrorResponse`
    /// JSON object instead of throwing across the boundary.
    public static func verify(requestJSON: String) -> String {
        let request: Request
        do {
            request = try JSONDecoder().decode(Request.self, from: Data(requestJSON.utf8))
        } catch {
            return errorJSON(code: "invalidRequest", message: String(describing: error))
        }

        if let maximum = request.policy?.maximumEvidenceMatches, maximum < 0 {
            // Reject rather than clamp: the policy fingerprint embeds this
            // value, and clamping would fingerprint a policy the caller never
            // requested. Negative values trap inside ClaimVerifier.
            return errorJSON(code: "invalidRequest", message: "maximumEvidenceMatches must be non-negative: \(maximum)")
        }

        var policy = VerificationPolicy()
        request.policy?.applied(to: &policy)

        let report = ClaimVerifier(policy: policy).verify(document: request.document, against: request.evidence)
        let decision = ConservativeProofPolicy().evaluate(report)

        var manifest: String?
        if request.includeProvenance == true {
            let runID: UUID
            if let raw = request.runID {
                guard let parsed = UUID(uuidString: raw) else {
                    return errorJSON(code: "invalidRequest", message: "runID is not a valid UUID: \(raw)")
                }
                runID = parsed
            } else {
                runID = UUID()
            }
            do {
                let trace = try ProvenanceExporter().trace(for: report, policy: policy, runID: runID)
                manifest = try String(decoding: trace.manifestJSONData(), as: UTF8.self)
            } catch {
                return errorJSON(code: "provenanceFailed", message: String(describing: error))
            }
        }

        let response = Response(
            specVersion: ClaimProofSpec.version,
            report: report,
            decision: decision,
            reportFingerprint: report.fingerprint,
            policyFingerprint: policy.fingerprint,
            markdown: request.includeMarkdown == true ? ReportRenderer().markdown(report) : nil,
            provenanceManifest: manifest
        )
        do {
            return try String(decoding: Self.encoder.encode(response), as: UTF8.self)
        } catch {
            return errorJSON(code: "encodingFailed", message: String(describing: error))
        }
    }

    /// Spec §5 evidence identity: SHA-256 (lowercase hex) over the exact UTF-8
    /// bytes of `text`, no normalization.
    public static func passageFingerprint(text: String) -> String {
        EvidencePassage(id: "", source: "", text: text).contentFingerprint
    }

    /// Spec §1 claim identity: case-folded FNV-1a 64-bit, lowercase hex.
    public static func claimFingerprint(text: String) -> String {
        Claim(id: "", text: text).fingerprint
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func errorJSON(code: String, message: String) -> String {
        let payload = ErrorResponse(error: .init(code: code, message: message))
        if let data = try? Self.encoder.encode(payload) {
            return String(decoding: data, as: UTF8.self)
        }
        return #"{"error":{"code":"encodingFailed","message":"could not encode error"}}"#
    }
}
