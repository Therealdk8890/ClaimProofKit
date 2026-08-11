// Copyright 2026 Daniel Kissel
// SPDX-License-Identifier: BUSL-1.1

import Foundation
import Testing
import ClaimProofKit
@testable import ClaimProofBridge

@Suite("ClaimProofBridge")
struct ClaimProofBridgeTests {
    private let document = "The response was filed within the fourteen day deadline. The court granted the extension request."
    private let evidence = [
        EvidencePassage(
            id: "pass-0001",
            source: "Docket entry 12",
            sourceType: .courtRecord,
            text: "The response was filed within the fourteen day deadline."
        ),
        EvidencePassage(
            id: "pass-0002",
            source: "Docket entry 14",
            sourceType: .courtRecord,
            text: "The court denied the extension request."
        ),
    ]

    private func requestJSON(includeMarkdown: Bool = false, includeProvenance: Bool = false) throws -> String {
        let request = ClaimProofBridge.Request(
            document: document,
            evidence: evidence,
            includeMarkdown: includeMarkdown,
            includeProvenance: includeProvenance,
            runID: "00000000-0000-0000-0000-000000000042"
        )
        return try String(decoding: JSONEncoder().encode(request), as: UTF8.self)
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601 // matches the bridge's encoder
        return decoder
    }

    private func respond(_ json: String) throws -> ClaimProofBridge.Response {
        let raw = ClaimProofBridge.verify(requestJSON: json)
        return try Self.decoder.decode(ClaimProofBridge.Response.self, from: Data(raw.utf8))
    }

    @Test("response matches a direct ClaimVerifier run")
    func matchesDirectRun() throws {
        let response = try respond(requestJSON())
        let direct = ClaimVerifier().verify(document: document, against: evidence)

        #expect(response.specVersion == ClaimProofSpec.version)
        #expect(response.reportFingerprint == direct.fingerprint)
        #expect(response.policyFingerprint == VerificationPolicy().fingerprint)
        #expect(response.report.verdicts.map(\.claim) == direct.verdicts.map(\.claim))
        #expect(response.report.verdicts.map(\.status) == direct.verdicts.map(\.status))
        // Contradicted second claim: the conservative policy must block.
        #expect(response.decision.disposition == .block)
        #expect(!response.decision.blockingClaimIDs.isEmpty)
        #expect(response.markdown == nil)
        #expect(response.provenanceManifest == nil)
    }

    @Test("markdown and provenance are included on request")
    func optionalArtifacts() throws {
        let response = try respond(requestJSON(includeMarkdown: true, includeProvenance: true))
        #expect(response.markdown?.isEmpty == false)

        let manifestJSON = try #require(response.provenanceManifest)
        let manifest = try JSONDecoder().decode(
            BridgeManifestProbe.self, from: Data(manifestJSON.utf8)
        )
        #expect(manifest.reportFingerprint == response.reportFingerprint)
        #expect(manifest.policyFingerprint == response.policyFingerprint)
        #expect(manifest.runFingerprint.count == 40) // SHA-1 lowercase hex
        #expect(manifest.specVersion == ClaimProofSpec.version)
    }

    @Test("identical requests produce identical responses")
    func deterministicResponses() throws {
        let json = try requestJSON(includeMarkdown: true, includeProvenance: true)
        let first = ClaimProofBridge.verify(requestJSON: json)
        let second = ClaimProofBridge.verify(requestJSON: json)
        // createdAt differs per run; compare everything identity-bearing instead.
        let a = try Self.decoder.decode(ClaimProofBridge.Response.self, from: Data(first.utf8))
        let b = try Self.decoder.decode(ClaimProofBridge.Response.self, from: Data(second.utf8))
        #expect(a.reportFingerprint == b.reportFingerprint)
        #expect(a.policyFingerprint == b.policyFingerprint)
        #expect(a.report.verdicts.map(\.claim.fingerprint) == b.report.verdicts.map(\.claim.fingerprint))
    }

    @Test("policy overrides change the policy fingerprint")
    func policyOverrides() throws {
        var request = ClaimProofBridge.Request(document: document, evidence: evidence)
        request.policy = .init(supportedThreshold: 0.9)
        let json = try String(decoding: JSONEncoder().encode(request), as: UTF8.self)
        let response = try respond(json)

        var expected = VerificationPolicy()
        expected.supportedThreshold = 0.9
        #expect(response.policyFingerprint == expected.fingerprint)
        #expect(response.policyFingerprint != VerificationPolicy().fingerprint)
    }

    @Test("malformed JSON returns a structured error, not a crash")
    func malformedRequest() throws {
        let raw = ClaimProofBridge.verify(requestJSON: "{not json")
        let error = try JSONDecoder().decode(ClaimProofBridge.ErrorResponse.self, from: Data(raw.utf8))
        #expect(error.error.code == "invalidRequest")
    }

    @Test("negative maximumEvidenceMatches returns a structured error, not a trap")
    func negativeMaximumEvidenceMatches() throws {
        var request = ClaimProofBridge.Request(document: document, evidence: evidence)
        request.policy = .init(maximumEvidenceMatches: -1)
        let json = try String(decoding: JSONEncoder().encode(request), as: UTF8.self)
        let raw = ClaimProofBridge.verify(requestJSON: json)
        let error = try JSONDecoder().decode(ClaimProofBridge.ErrorResponse.self, from: Data(raw.utf8))
        #expect(error.error.code == "invalidRequest")
        #expect(error.error.message.contains("-1"))
    }

    @Test("evidence without sourceType decodes as .unknown")
    func minimalEvidenceJSON() throws {
        let json = """
        {"document": "\(document)", "evidence": [{"id": "p1", "source": "s", "text": "The response was filed within the fourteen day deadline."}]}
        """
        let response = try respond(json)
        #expect(!response.report.verdicts.isEmpty)
    }

    @Test("invalid runID returns a structured error")
    func invalidRunID() throws {
        let request = ClaimProofBridge.Request(
            document: document, evidence: evidence, includeProvenance: true, runID: "not-a-uuid"
        )
        let json = try String(decoding: JSONEncoder().encode(request), as: UTF8.self)
        let raw = ClaimProofBridge.verify(requestJSON: json)
        let error = try JSONDecoder().decode(ClaimProofBridge.ErrorResponse.self, from: Data(raw.utf8))
        #expect(error.error.code == "invalidRequest")
        #expect(error.error.message.contains("not-a-uuid"))
    }

    @Test("fingerprint helpers match the spec implementations")
    func fingerprintHelpers() {
        let passage = evidence[0]
        #expect(ClaimProofBridge.passageFingerprint(text: passage.text) == passage.contentFingerprint)
        let claim = Claim(id: "x", text: "The Response was FILED.")
        #expect(ClaimProofBridge.claimFingerprint(text: "The Response was FILED.") == claim.fingerprint)
    }
}

/// Just the manifest fields the tests assert on.
private struct BridgeManifestProbe: Decodable {
    let specVersion: String
    let runFingerprint: String
    let reportFingerprint: String
    let policyFingerprint: String
}
