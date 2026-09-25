// Copyright 2026 Daniel Kissel
// SPDX-License-Identifier: Apache-2.0

import ClaimProofKit
import Foundation
import Testing
@testable import ClaimProofProvenance

@Suite("Provenance export")
struct ProvenanceExportTests {
    private let evidence = [
        EvidencePassage(
            id: "order-1",
            source: "Scheduling Order",
            sourceType: .courtRecord,
            text: "The court denied the request for an extension."
        )
    ]

    private func makeReport() -> ProofReport {
        let claims = [
            Claim(id: "1", text: "The court denied the request for an extension.", type: .factual),
            Claim(id: "2", text: "The court granted the request for an extension.", type: .factual)
        ]
        return ProofReport(
            createdAt: Date(timeIntervalSince1970: 1_760_000_000),
            verdicts: claims.map { ClaimVerifier().verify(claim: $0, against: evidence) }
        )
    }

    @Test("A report exports interleaved claim events terminated by the report event")
    func eventVocabularyAndOrder() throws {
        let trace = try ProvenanceExporter().trace(for: makeReport(), policy: VerificationPolicy())
        let types = trace.events.map(\.payload.typeIdentifier)
        #expect(types == [
            "cpk_claim_extracted", "cpk_claim_verified",
            "cpk_claim_extracted", "cpk_claim_verified",
            "cpk_report_finalized"
        ])
        #expect(trace.events.map(\.sequence) == [0, 1, 2, 3, 4])
        #expect(trace.events.allSatisfy { $0.engineName == "ClaimProofKit" })
        #expect(trace.events.allSatisfy { $0.contextID == "claimproof" })
        let runIDs = Set(trace.events.map(\.runID))
        #expect(runIDs.count == 1)
    }

    @Test("Run fingerprint is deterministic and sensitive to engine and order")
    func runFingerprint() throws {
        let report = makeReport()
        let first = try ProvenanceExporter().trace(for: report, policy: VerificationPolicy(), runID: UUID())
        let second = try ProvenanceExporter().trace(for: report, policy: VerificationPolicy(), runID: UUID())
        #expect(first.runFingerprint == second.runFingerprint)
        #expect(first.runFingerprint.count == 40)

        let otherEngine = try ProvenanceExporter(engineName: "Custom").trace(for: report, policy: VerificationPolicy())
        #expect(otherEngine.runFingerprint != first.runFingerprint)
    }

    @Test("Edges link extraction to verdict and verdicts to the report")
    func edgeTopology() throws {
        let trace = try ProvenanceExporter().trace(for: makeReport(), policy: VerificationPolicy())
        let verifiedBy = trace.edges.filter { $0.type == "verifiedBy" }
        let derivedFrom = trace.edges.filter { $0.type == "derivedFrom" }
        #expect(verifiedBy.count == 2)
        #expect(derivedFrom.count == 2)

        let reportEventID = trace.events.last?.id
        #expect(derivedFrom.allSatisfy { $0.targetID == reportEventID })

        let eventIDs = Set(trace.events.map(\.id))
        for edge in trace.edges {
            #expect(eventIDs.contains(edge.sourceID))
            #expect(eventIDs.contains(edge.targetID))
            #expect(edge.sourceID != edge.targetID)
        }
    }

    @Test("Payload rawJSON is canonical: sorted keys, decodable, no envelope duplication")
    func canonicalPayloads() throws {
        let trace = try ProvenanceExporter().trace(for: makeReport(), policy: VerificationPolicy())
        for event in trace.events {
            let object = try JSONSerialization.jsonObject(with: Data(event.payload.rawJSON.utf8))
            let dictionary = try #require(object as? [String: Any])
            #expect(!dictionary.keys.contains("timestamp"))
            #expect(!dictionary.keys.contains("typeIdentifier"))

            // The top-level keys must appear in sorted order in the raw bytes —
            // JSONSerialization discards order, so scan the string itself.
            let positions = dictionary.keys.compactMap { key -> (String, String.Index)? in
                guard let range = event.payload.rawJSON.range(of: "\"\(key)\":") else { return nil }
                return (key, range.lowerBound)
            }
            #expect(positions.count == dictionary.keys.count)
            let keysInByteOrder = positions.sorted { $0.1 < $1.1 }.map(\.0)
            #expect(keysInByteOrder == keysInByteOrder.sorted(), "unsorted keys in \(event.payload.rawJSON)")
        }
        let verified = try #require(trace.events.first { $0.payload.typeIdentifier == "cpk_claim_verified" })
        let payload = try JSONDecoder().decode(ClaimVerifiedPayload.self, from: Data(verified.payload.rawJSON.utf8))
        #expect(payload.status == "directlySupported")
        #expect(payload.evidenceFingerprints.count == 1)
    }

    @Test("An empty report exports a lone finalization event with no edges")
    func emptyReport() throws {
        let report = ProofReport(createdAt: Date(timeIntervalSince1970: 0), verdicts: [])
        let trace = try ProvenanceExporter().trace(for: report, policy: VerificationPolicy())
        #expect(trace.events.map(\.payload.typeIdentifier) == ["cpk_report_finalized"])
        #expect(trace.edges.isEmpty)
        #expect(trace.reportFingerprint == report.fingerprint)
        #expect(trace.runFingerprint.count == 40)
    }

    @Test("Events JSON round-trips through the envelope mirror with default coding")
    func envelopeRoundTrip() throws {
        let trace = try ProvenanceExporter().trace(for: makeReport(), policy: VerificationPolicy())
        let decoded = try JSONDecoder().decode([ProvenanceEventEnvelope].self, from: trace.eventsJSONData())
        #expect(decoded == trace.events)

        let manifest = try JSONDecoder().decode(ProvenanceManifest.self, from: trace.manifestJSONData())
        #expect(manifest.runFingerprint == trace.runFingerprint)
        #expect(manifest.reportFingerprint == trace.reportFingerprint)
        #expect(manifest.specVersion == ClaimProofSpec.version)
        #expect(manifest.events == trace.events)
    }

    @Test("Report fingerprint in the terminal payload matches the report")
    func terminalPayload() throws {
        let report = makeReport()
        let trace = try ProvenanceExporter().trace(for: report, policy: VerificationPolicy())
        let terminal = try #require(trace.events.last)
        let payload = try JSONDecoder().decode(ReportFinalizedPayload.self, from: Data(terminal.payload.rawJSON.utf8))
        #expect(payload.reportFingerprint == report.fingerprint)
        #expect(payload.policyFingerprint == VerificationPolicy().fingerprint)
        #expect(payload.safeToPublish == report.isSafeToPublish)
        #expect(payload.statusCounts.values.reduce(0, +) == report.verdicts.count)
    }
}
