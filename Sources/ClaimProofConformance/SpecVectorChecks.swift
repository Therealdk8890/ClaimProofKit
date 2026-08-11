// Copyright 2026 Daniel Kissel
// SPDX-License-Identifier: BUSL-1.1
//
// Claim Proof Specification v1 vector checks — the portable core of the
// conformance harness. Everything here runs identically on native platforms
// and wasm32-wasi, so CI can byte-lock wasm behavior against the same frozen
// vectors the native harness enforces. The DProvenanceKit round-trip and
// vector regeneration stay in the native harness, which depends on packages
// (SQLite) that do not exist on wasm.

import ClaimProofKit
import ClaimProofProvenance
import Foundation

public enum SpecVectorChecks {

    /// The outcome of a section run: PASS/FAIL lines are printed as they are
    /// checked, and the caller aggregates the failure counts into an exit code.
    public struct SectionResult {
        public let failureCount: Int
    }

    // MARK: - Vector loading

    struct VectorError: Error, CustomStringConvertible {
        let description: String
    }

    static func loadVector<V: Decodable>(_ name: String, in directory: URL, as type: V.Type) throws -> V {
        let url = directory.appendingPathComponent(name)
        do {
            return try JSONDecoder().decode(V.self, from: Data(contentsOf: url))
        } catch {
            throw VectorError(description: "cannot load vector \(name) from \(url.path): \(error)")
        }
    }

    // MARK: - Shared construction (also used by the harness's --regenerate)

    public static func passages(_ wire: [VerdictSemanticsVector.Passage]) -> [EvidencePassage] {
        wire.map {
            EvidencePassage(
                id: $0.id,
                source: $0.source,
                sourceType: EvidencePassage.SourceType(rawValue: $0.sourceType) ?? .unknown,
                text: $0.text
            )
        }
    }

    public static func bridgePassages(_ wire: [ProvenanceBridgeVector.Passage]) -> [EvidencePassage] {
        wire.map {
            EvidencePassage(
                id: $0.id,
                source: $0.source,
                sourceType: EvidencePassage.SourceType(rawValue: $0.sourceType) ?? .unknown,
                text: $0.text
            )
        }
    }

    public static func reportVerdicts(_ wire: [ReportFingerprintVector.Verdict]) -> [ClaimVerdict] {
        wire.enumerated().map { index, verdict in
            ClaimVerdict(
                claim: Claim(id: "vector-\(index)", text: verdict.claimText),
                status: SupportStatus(rawValue: verdict.status) ?? .notVerifiable,
                confidence: 1,
                evidence: [],
                explanation: "conformance vector"
            )
        }
    }

    public static func bridgeTrace(
        document: String,
        evidence: [EvidencePassage],
        createdAt epochSeconds: Double
    ) throws -> (report: ProofReport, trace: ProvenanceTrace) {
        let claims = ClaimExtractor().extract(from: document)
        let verifier = ClaimVerifier()
        let report = ProofReport(
            createdAt: Date(timeIntervalSince1970: epochSeconds),
            verdicts: claims.map { verifier.verify(claim: $0, against: evidence) }
        )
        let trace = try ProvenanceExporter().trace(for: report, policy: VerificationPolicy())
        return (report, trace)
    }

    public static func edgeTriples(_ trace: ProvenanceTrace) -> [ProvenanceBridgeVector.Edge] {
        let sequenceByID = Dictionary(uniqueKeysWithValues: trace.events.map { ($0.id, $0.sequence) })
        return trace.edges.compactMap { edge in
            guard let source = sequenceByID[edge.sourceID], let target = sequenceByID[edge.targetID] else { return nil }
            return ProvenanceBridgeVector.Edge(sourceSequence: source, targetSequence: target, type: edge.type)
        }
    }

    // MARK: - Check plumbing

    private struct Section {
        var failureCount = 0

        mutating func check(_ name: String, _ passed: Bool, _ detail: @autoclosure () -> String = "") {
            if passed {
                print("  PASS \(name)")
            } else {
                failureCount += 1
                let extra = detail()
                print("  FAIL \(name)\(extra.isEmpty ? "" : " — \(extra)")")
            }
        }
    }

    // MARK: - Sections

    public static func checkClaimFingerprints(vectorsDirectory: URL) throws -> SectionResult {
        print("\n[1] claim fingerprint")
        let vector = try loadVector("claim_fingerprint.json", in: vectorsDirectory, as: ClaimFingerprintVector.self)
        var section = Section()
        section.check("spec version", vector.specVersion == ClaimProofSpec.version)
        for (index, testCase) in vector.cases.enumerated() {
            let got = Claim(id: "vector", text: testCase.text).fingerprint
            section.check("case \(index): \(testCase.description)", got == testCase.fingerprint, "expected \(testCase.fingerprint) got \(got)")
        }
        return SectionResult(failureCount: section.failureCount)
    }

    public static func checkPolicyFingerprints(vectorsDirectory: URL) throws -> SectionResult {
        print("\n[2] policy fingerprint")
        let vector = try loadVector("policy_fingerprint.json", in: vectorsDirectory, as: PolicyFingerprintVector.self)
        var section = Section()
        section.check("spec version", vector.specVersion == ClaimProofSpec.version)
        for (index, testCase) in vector.cases.enumerated() {
            let policy = VerificationPolicy(
                supportedThreshold: testCase.supportedThreshold,
                ambiguousThreshold: testCase.ambiguousThreshold,
                contradictionThreshold: testCase.contradictionThreshold,
                maximumEvidenceMatches: testCase.maximumEvidenceMatches
            )
            section.check("case \(index): \(testCase.description)", policy.fingerprint == testCase.fingerprint, "expected \(testCase.fingerprint) got \(policy.fingerprint)")
        }
        return SectionResult(failureCount: section.failureCount)
    }

    public static func checkReportFingerprints(vectorsDirectory: URL) throws -> SectionResult {
        print("\n[3] report fingerprint")
        let vector = try loadVector("report_fingerprint.json", in: vectorsDirectory, as: ReportFingerprintVector.self)
        var section = Section()
        section.check("spec version", vector.specVersion == ClaimProofSpec.version)
        for (index, testCase) in vector.cases.enumerated() {
            let got = ProofReport(verdicts: reportVerdicts(testCase.verdicts)).fingerprint
            section.check("case \(index): \(testCase.description)", got == testCase.fingerprint, "expected \(testCase.fingerprint) got \(got)")
        }
        return SectionResult(failureCount: section.failureCount)
    }

    public static func checkVerdictSemantics(vectorsDirectory: URL) throws -> SectionResult {
        print("\n[4] verdict semantics")
        let vector = try loadVector("verdict_semantics.json", in: vectorsDirectory, as: VerdictSemanticsVector.self)
        var section = Section()
        section.check("spec version", vector.specVersion == ClaimProofSpec.version)
        for (index, testCase) in vector.cases.enumerated() {
            let claim = Claim(
                id: "vector",
                text: testCase.claimText,
                type: Claim.ClaimType(rawValue: testCase.claimType) ?? .unknown
            )
            let verdict = ClaimVerifier().verify(claim: claim, against: passages(testCase.evidence))
            section.check(
                "case \(index): \(testCase.description)",
                verdict.status.rawValue == testCase.expectedStatus,
                "expected \(testCase.expectedStatus) got \(verdict.status.rawValue)"
            )
        }
        return SectionResult(failureCount: section.failureCount)
    }

    public static func checkProvenanceBridge(vectorsDirectory: URL) throws -> (result: SectionResult, trace: ProvenanceTrace) {
        print("\n[5] provenance bridge (vector)")
        let vector = try loadVector("provenance_bridge.json", in: vectorsDirectory, as: ProvenanceBridgeVector.self)
        var section = Section()
        section.check("spec version", vector.specVersion == ClaimProofSpec.version)

        let (report, trace) = try bridgeTrace(
            document: vector.document,
            evidence: bridgePassages(vector.evidence),
            createdAt: vector.createdAtEpochSeconds
        )
        section.check("report fingerprint", report.fingerprint == vector.reportFingerprint, "expected \(vector.reportFingerprint) got \(report.fingerprint)")
        section.check("policy fingerprint", VerificationPolicy().fingerprint == vector.policyFingerprint)
        section.check("run fingerprint", trace.runFingerprint == vector.runFingerprint, "expected \(vector.runFingerprint) got \(trace.runFingerprint)")
        section.check("event count", trace.events.count == vector.events.count, "expected \(vector.events.count) got \(trace.events.count)")

        for (index, pair) in zip(trace.events, vector.events).enumerated() {
            let (event, expected) = pair
            section.check("event \(index) type", event.payload.typeIdentifier == expected.typeIdentifier, "expected \(expected.typeIdentifier) got \(event.payload.typeIdentifier)")
            section.check("event \(index) priority", event.payload.priorityValue == expected.priorityValue)
            section.check("event \(index) canonical payload", event.payload.rawJSON == expected.rawJSON, "expected \(expected.rawJSON) got \(event.payload.rawJSON)")
        }

        let gotEdges = edgeTriples(trace)
        let expectedEdges = vector.edges
        let edgesMatch = gotEdges.count == expectedEdges.count && zip(gotEdges, expectedEdges).allSatisfy {
            $0.sourceSequence == $1.sourceSequence && $0.targetSequence == $1.targetSequence && $0.type == $1.type
        }
        section.check("edges", edgesMatch, "expected \(expectedEdges.count) matching edges")
        return (SectionResult(failureCount: section.failureCount), trace)
    }

    /// Runs sections [1]–[5] and returns the total failure count plus the
    /// section-[5] trace (the native harness feeds it to the DProvenanceKit
    /// round-trip; the wasm runner ignores it).
    public static func runAll(vectorsDirectory: URL) throws -> (failureCount: Int, trace: ProvenanceTrace) {
        var failures = 0
        failures += try checkClaimFingerprints(vectorsDirectory: vectorsDirectory).failureCount
        failures += try checkPolicyFingerprints(vectorsDirectory: vectorsDirectory).failureCount
        failures += try checkReportFingerprints(vectorsDirectory: vectorsDirectory).failureCount
        failures += try checkVerdictSemantics(vectorsDirectory: vectorsDirectory).failureCount
        let (bridge, trace) = try checkProvenanceBridge(vectorsDirectory: vectorsDirectory)
        failures += bridge.failureCount
        return (failures, trace)
    }
}
