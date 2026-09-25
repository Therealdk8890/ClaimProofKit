import XCTest
@testable import ClaimProofKit

final class GovernanceVerificationSignalTests: XCTestCase {
    func testPipelineResultMapsToControllerNeutralSignal() throws {
        let claim = Claim(id: "claim-1", text: "The contract was signed.", type: .factual)
        let passage = EvidencePassage(id: "evidence-1", source: "contract.pdf", text: "The contract was signed.")
        let verdict = ClaimVerdict(
            claim: claim,
            status: .directlySupported,
            confidence: 1,
            evidence: [EvidenceMatch(passage: passage, score: 1, matchedTerms: ["contract", "signed"])],
            explanation: "Direct support."
        )
        let report = ProofReport(verdicts: [verdict])
        let result = PipelineResult(
            report: report,
            decision: ProofDecision(disposition: .allow)
        )

        let signal = GovernanceVerificationSignal(
            result: result,
            policyFingerprint: "policy-123",
            traceID: "trace-1",
            runID: "run-1",
            actionID: "action-1"
        )

        XCTAssertEqual(signal.version, 1)
        XCTAssertEqual(signal.disposition, .allow)
        XCTAssertEqual(signal.reportFingerprint, report.fingerprint)
        XCTAssertEqual(signal.policyFingerprint, "policy-123")
        XCTAssertEqual(signal.supportedClaimCount, 1)
        XCTAssertEqual(signal.totalClaimCount, 1)
        XCTAssertEqual(signal.traceID, "trace-1")
        XCTAssertEqual(signal.runID, "run-1")
        XCTAssertEqual(signal.actionID, "action-1")
    }

    func testBlockedVerificationCarriesBlockingClaims() throws {
        let claim = Claim(id: "claim-unsafe", text: "The evidence proves X.", type: .factual)
        let verdict = ClaimVerdict(
            claim: claim,
            status: .unsupported,
            confidence: 0,
            evidence: [],
            explanation: "No supporting evidence."
        )
        let report = ProofReport(verdicts: [verdict])
        let result = PipelineResult(
            report: report,
            decision: ProofDecision(
                disposition: .block,
                blockingClaimIDs: ["claim-unsafe"]
            )
        )

        let signal = GovernanceVerificationSignal(
            result: result,
            policyFingerprint: "policy-123"
        )

        XCTAssertEqual(signal.disposition, .block)
        XCTAssertEqual(signal.blockingClaimIDs, ["claim-unsafe"])
        XCTAssertEqual(signal.supportedClaimCount, 0)
        XCTAssertEqual(signal.totalClaimCount, 1)
    }

    func testSignalSerializesWithoutControllerDependency() throws {
        let signal = GovernanceVerificationSignal(
            disposition: .requireReview,
            reportFingerprint: "report-123",
            policyFingerprint: "policy-123",
            reviewClaimIDs: ["claim-1"],
            supportedClaimCount: 2,
            totalClaimCount: 3
        )

        let data = try signal.jsonData()
        let decoded = try JSONDecoder().decode(GovernanceVerificationSignal.self, from: data)
        XCTAssertEqual(decoded, signal)
    }
}


    func testSharedV1FixtureMatchesWireContract() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "governance-verification-signal-v1", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let signal = try JSONDecoder().decode(GovernanceVerificationSignal.self, from: data)

        XCTAssertEqual(signal.version, 1)
        XCTAssertEqual(signal.disposition, .block)
        XCTAssertEqual(signal.reportFingerprint, "report-123")
        XCTAssertEqual(signal.policyFingerprint, "policy-123")
        XCTAssertEqual(signal.blockingClaimIDs, ["claim-unsafe"])
        XCTAssertEqual(signal.reviewClaimIDs, [])
        XCTAssertEqual(signal.supportedClaimCount, 0)
        XCTAssertEqual(signal.totalClaimCount, 1)
        XCTAssertEqual(signal.traceID, "trace-1")
        XCTAssertEqual(signal.runID, "run-1")
        XCTAssertEqual(signal.actionID, "action-1")
    }
}
