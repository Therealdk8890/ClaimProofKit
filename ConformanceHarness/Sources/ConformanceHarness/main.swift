// Copyright 2026 Daniel Kissel
// SPDX-License-Identifier: Apache-2.0
//
// Claim Proof Specification v1 conformance harness.
//
// Verifies the live ClaimProofKit implementation against the frozen golden
// vectors in ../vectors, then round-trips the provenance bridge output through
// the REAL DProvenanceKit package (fetched from its published tag) to prove
// interchange parity. Run with --regenerate to re-lock the vectors from the
// current implementation after an intentional, spec-version-bumping change.
//
// The vector checks themselves (sections [1]–[5]) live in the main package's
// ClaimProofConformance target so the ConformanceVectors runner executes the
// same code under a wasm runtime in CI; this harness adds vector regeneration
// and the live DProvenanceKit round-trip, which need native-only dependencies.

import ClaimProofConformance
import ClaimProofKit
import ClaimProofProvenance
import DProvenanceKit
import Foundation
import SQLite3

#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

// MARK: - Infrastructure

let vectorsDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("vectors")

// The harness is strictly sequential; this counter is only touched from top-level code.
nonisolated(unsafe) var failureCount = 0

func check(_ name: String, _ passed: Bool, _ detail: @autoclosure () -> String = "") {
    if passed {
        print("  PASS \(name)")
    } else {
        failureCount += 1
        let extra = detail()
        print("  FAIL \(name)\(extra.isEmpty ? "" : " — \(extra)")")
    }
}

func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

let vectorEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return encoder
}()

func writeVector(_ name: String, _ vector: some Encodable) throws {
    let url = vectorsDirectory.appendingPathComponent(name)
    try vectorEncoder.encode(vector).write(to: url)
    print("  wrote \(name)")
}

// MARK: - Seeds (used only by --regenerate; verification is vector-driven)

let claimFingerprintSeeds: [(String, String)] = [
    ("Simple factual claim", "The court granted the motion."),
    ("Case-folded twin of the simple claim (same fingerprint by design)", "THE COURT GRANTED THE MOTION."),
    ("Single-character difference from the simple claim", "The court granted the motions."),
    ("Unicode and emoji content", "Ünïcode – emoji 🧾 claim"),
    ("Minimal one-letter claim", "a"),
    // FNV-1a of this text has a zero top nibble, so the vector locks the
    // UNPADDED-hex property (shorter than 16 chars) that zero-padding would break.
    ("Fingerprint shorter than 16 hex digits (locks unpadded rendering)", "The tenant paid rent in June.")
]

let policyFingerprintSeeds: [(String, VerificationPolicy)] = [
    ("Default policy", VerificationPolicy()),
    ("Raised support threshold", VerificationPolicy(supportedThreshold: 0.9)),
    ("Wider evidence window", VerificationPolicy(maximumEvidenceMatches: 5)),
    ("Fully custom policy", VerificationPolicy(supportedThreshold: 0.72, ambiguousThreshold: 0.35, contradictionThreshold: 0.5, maximumEvidenceMatches: 2))
]

let reportFingerprintSeeds: [(String, [(String, SupportStatus)])] = [
    ("Empty report", []),
    ("Single supported claim", [("The court granted the motion.", .directlySupported)]),
    ("Two claims in original order", [
        ("The court granted the motion.", .directlySupported),
        ("The tenant paid rent in March.", .contradicted)
    ]),
    ("Same two claims reversed (order participates in identity)", [
        ("The tenant paid rent in March.", .contradicted),
        ("The court granted the motion.", .directlySupported)
    ])
]

let verdictSemanticsSeeds: [(String, String, Claim.ClaimType, [(String, String, EvidencePassage.SourceType, String)])] = [
    (
        "Directly grounded legal rule",
        "A response must be filed within 14 days after service of the motion.",
        .legalRule,
        [("rule-5", "Local Rule 5", .courtRule, "A response must be filed within 14 days after service of the motion.")]
    ),
    (
        "Polarity reversal is contradicted",
        "The court did not deny the request for an extension.",
        .factual,
        [("order-1", "Scheduling Order", .courtRecord, "The court denied the request for an extension.")]
    ),
    (
        "Invented fact is unsupported",
        "The plaintiff filed a second amended complaint.",
        .factual,
        [("order-1", "Scheduling Order", .courtRecord, "The court denied the request for an extension.")]
    ),
    (
        "Related but incomplete evidence is partial support",
        "The landlord returned the deposit after inspection.",
        .factual,
        [("letter-2", "Move-out Letter", .evidence, "The landlord completed the inspection and returned the keys.")]
    ),
    (
        "Recommendations are not verifiable",
        "We recommend filing a motion to compel discovery.",
        .recommendation,
        [("order-1", "Scheduling Order", .courtRecord, "The court denied the request for an extension.")]
    ),
    (
        "A legal rule cannot rest on a court record (source authority)",
        "A response must be filed within 14 days after service of the motion.",
        .legalRule,
        [("order-1", "Scheduling Order", .courtRecord, "A response must be filed within 14 days after service of the motion.")]
    ),
    (
        "A speculative passage cannot prove an occurrence",
        "The city approved the zoning variance.",
        .factual,
        [("minutes-3", "Council Minutes", .evidence, "The city is considering a proposed zoning variance.")]
    ),
    (
        "Conflicting structured values are contradicted",
        "The response deadline is 14 days.",
        .factual,
        [("rule-6", "Local Rule 6", .unknown, "The response deadline is 30 days.")]
    )
]

// The fourth sentence yields confidence 2/3 — a non-terminating binary Double —
// so the locked rawJSON also pins Foundation's shortest-round-trip formatting.
let bridgeSeedDocument = "The court denied the request for an extension. The tenant paid rent on March 1. The court granted the motion for sanctions. The mediator scheduled a conference."
let bridgeSeedEvidence: [(String, String, EvidencePassage.SourceType, String)] = [
    ("order-1", "Scheduling Order", .courtRecord, "The court denied the request for an extension."),
    ("ledger-1", "Rent Ledger", .evidence, "The tenant paid rent on March 1."),
    ("conf-1", "Case Notes", .evidence, "The mediator canceled the conference.")
]
let bridgeSeedEpochSeconds: Double = 1_760_000_000

// MARK: - Regeneration

func regenerate() throws {
    print("[regenerate] re-locking vectors from the live implementation")

    try writeVector("claim_fingerprint.json", ClaimFingerprintVector(
        specVersion: ClaimProofSpec.version,
        algorithm: "FNV-1a 64-bit over lowercased UTF-8 claim text, unpadded lowercase hex",
        cases: claimFingerprintSeeds.map { description, text in
            ClaimFingerprintVector.Case(
                description: description,
                text: text,
                fingerprint: Claim(id: "seed", text: text).fingerprint
            )
        }
    ))

    try writeVector("policy_fingerprint.json", PolicyFingerprintVector(
        specVersion: ClaimProofSpec.version,
        algorithm: "sha256 of frozen newline-delimited key:value listing (see PROOF_SPEC_V1.md §4)",
        cases: policyFingerprintSeeds.map { description, policy in
            PolicyFingerprintVector.Case(
                description: description,
                supportedThreshold: policy.supportedThreshold,
                ambiguousThreshold: policy.ambiguousThreshold,
                contradictionThreshold: policy.contradictionThreshold,
                maximumEvidenceMatches: policy.maximumEvidenceMatches,
                fingerprint: policy.fingerprint
            )
        }
    ))

    try writeVector("report_fingerprint.json", ReportFingerprintVector(
        specVersion: ClaimProofSpec.version,
        algorithm: "sha256( \"cpk:v1:report:\" + concat( claimFingerprint + ':' + status + '|' per verdict in order ) )",
        cases: reportFingerprintSeeds.map { description, verdicts in
            let wire = verdicts.map { ReportFingerprintVector.Verdict(claimText: $0.0, status: $0.1.rawValue) }
            return ReportFingerprintVector.Case(
                description: description,
                verdicts: wire,
                fingerprint: ProofReport(verdicts: SpecVectorChecks.reportVerdicts(wire)).fingerprint
            )
        }
    ))

    try writeVector("verdict_semantics.json", VerdictSemanticsVector(
        specVersion: ClaimProofSpec.version,
        description: "Baseline lexical verifier verdicts under the default policy.",
        cases: verdictSemanticsSeeds.map { description, claimText, claimType, evidence in
            let wire = evidence.map {
                VerdictSemanticsVector.Passage(id: $0.0, source: $0.1, sourceType: $0.2.rawValue, text: $0.3)
            }
            let verdict = ClaimVerifier().verify(
                claim: Claim(id: "seed", text: claimText, type: claimType),
                against: SpecVectorChecks.passages(wire)
            )
            return VerdictSemanticsVector.Case(
                description: description,
                claimText: claimText,
                claimType: claimType.rawValue,
                evidence: wire,
                expectedStatus: verdict.status.rawValue
            )
        }
    ))

    let wireEvidence = bridgeSeedEvidence.map {
        ProvenanceBridgeVector.Passage(id: $0.0, source: $0.1, sourceType: $0.2.rawValue, text: $0.3)
    }
    let (report, trace) = try SpecVectorChecks.bridgeTrace(
        document: bridgeSeedDocument,
        evidence: SpecVectorChecks.bridgePassages(wireEvidence),
        createdAt: bridgeSeedEpochSeconds
    )
    try writeVector("provenance_bridge.json", ProvenanceBridgeVector(
        specVersion: ClaimProofSpec.version,
        description: "End-to-end lock of the DProvenanceKit interchange: event vocabulary, canonical payload bytes (Trace Specification v1 §2), run fingerprint (§5), and lineage edges.",
        document: bridgeSeedDocument,
        evidence: wireEvidence,
        createdAtEpochSeconds: bridgeSeedEpochSeconds,
        reportFingerprint: report.fingerprint,
        policyFingerprint: VerificationPolicy().fingerprint,
        runFingerprint: trace.runFingerprint,
        events: trace.events.map {
            ProvenanceBridgeVector.Event(
                typeIdentifier: $0.payload.typeIdentifier,
                priorityValue: $0.payload.priorityValue,
                rawJSON: $0.payload.rawJSON
            )
        },
        edges: SpecVectorChecks.edgeTriples(trace)
    ))

    print("[regenerate] done — commit the vectors with a spec-version review")
}

// MARK: - Live DProvenanceKit round-trip

func readStoredFingerprint(_ path: String) -> String? {
    var database: OpaquePointer?
    guard sqlite3_open(path, &database) == SQLITE_OK else { return nil }
    defer { sqlite3_close(database) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, "SELECT fingerprint FROM runs LIMIT 1", -1, &statement, nil) == SQLITE_OK else { return nil }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else { return nil }
    return String(cString: text)
}

func checkDProvenanceKitRoundTrip(_ trace: ProvenanceTrace) async {
    print("\n[6] DProvenanceKit round-trip (live package)")

    // 6a. Our bare events JSON must decode as DProvenanceKit's own envelope type.
    do {
        let decoded = try JSONDecoder().decode([TraceEvent<AnyTraceableEvent>].self, from: trace.eventsJSONData())
        check("decodes as [TraceEvent<AnyTraceableEvent>]", decoded.count == trace.events.count)
        for (index, pair) in zip(decoded, trace.events).enumerated() {
            let (theirs, ours) = pair
            check("event \(index) fields survive", theirs.payload.typeIdentifier == ours.payload.typeIdentifier
                && theirs.payload.priorityValue == ours.payload.priorityValue
                && theirs.payload.rawJSON == ours.payload.rawJSON
                && theirs.sequence == ours.sequence
                && theirs.engineName == ours.engineName
                && theirs.contextID == ours.contextID
                && theirs.runID == ours.runID
                && theirs.id == ours.id)
        }

        // 6b. Recording those payloads through a real DProvenanceKit store must
        // reproduce our run fingerprint (Trace Specification v1 §5).
        let path = NSTemporaryDirectory() + "cpk_roundtrip_\(UUID().uuidString).sqlite"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = try SQLiteTraceStore<AnyTraceableEvent>(fileURL: URL(fileURLWithPath: path))
        let run = DProvenanceKit<AnyTraceableEvent>.ActiveTraceRun(contextID: trace.contextID, store: store)
        for event in decoded {
            run.record(event.payload, engineName: event.engineName)
        }
        try await store.flush()
        let stored = readStoredFingerprint(path) ?? "<none>"
        check("store fingerprint matches bridge fingerprint", stored == trace.runFingerprint, "expected \(trace.runFingerprint) got \(stored)")

        // 6c. Edges ingest through the run API and the run reads back intact.
        let memory = InMemoryTraceStore<AnyTraceableEvent>()
        let memoryRun = DProvenanceKit<AnyTraceableEvent>.ActiveTraceRun(contextID: trace.contextID, store: memory)
        var recordedIDs: [UUID: UUID] = [:]
        for event in decoded {
            recordedIDs[event.id] = memoryRun.record(event.payload, engineName: event.engineName)
        }
        for edge in trace.edges {
            if let source = recordedIDs[edge.sourceID], let target = recordedIDs[edge.targetID],
               let type = TraceEdgeType(rawValue: edge.type) {
                memoryRun.link(source: source, target: target, type: type)
            }
        }
        try await memory.flush()
        let fetched = try await memory.getRun(id: memoryRun.runID)
        check("run reads back from InMemoryTraceStore", fetched?.events.count == trace.events.count,
              "expected \(trace.events.count) got \(fetched?.events.count ?? -1)")
        // DProvenanceKit assigns its own sequences on record, so comparing raw
        // sequence values would be tautological; the real claim is that commit
        // ORDER survives the store round-trip.
        check("commit order preserved",
              fetched?.events.map(\.payload.typeIdentifier) == trace.events.map(\.payload.typeIdentifier))
    } catch {
        check("round-trip", false, "error \(error)")
    }
}

// MARK: - Proof pack + certificate (live package)

/// The shape a proof-pack binding event must actually have: `role` and `sha256` as real JSON
/// object keys in the signed payload. Contrast `AnyTraceableEvent`, which the bridge produces
/// and whose `Codable` nests the domain JSON inside a `rawJSON` string, where the verifier's
/// object-graph walk cannot reach it.
struct ArtifactEmitted: TraceableEvent {
    struct Entry: Codable, Sendable, Equatable {
        let role: String
        let sha256: String
    }

    let artifacts: [Entry]

    var typeIdentifier: String { "artifact-emitted" }
    var priority: TracePriority { TracePriority(rawValue: 3) ?? .telemetry }
}

/// Sections [1]–[6] prove the bridge's *events* survive into DProvenanceKit. They say nothing
/// about the artifact a downstream reader is actually handed, which is where the product claim
/// lives. This section closes that gap end to end: a real ClaimProof report is bound into a
/// signed proof pack, verified against the live package, and rendered as the certificate a
/// non-technical reader receives.
func checkProofPackAndCertificate(_ trace: ProvenanceTrace) async {
    print("\n[7] proof pack + certificate (live package)")

    do {
        // A genuine ClaimProof artifact — the frozen report vector, not a synthetic stand-in.
        let reportBytes = try Data(
            contentsOf: vectorsDirectory.appendingPathComponent("report_fingerprint.json")
        )
        let digest = sha256Hex(reportBytes)
        let role = "claim-proof-report"

        // Ingest the bridge output into a real DProvenanceKit run, then emit the
        // artifact-emitted event that co-locates `role` with `sha256`. That co-location is
        // exactly what a v2 pack signs over: without it the role is producer-asserted and the
        // pack can only reach valuePresenceOnly.
        let decoded = try JSONDecoder().decode(
            [TraceEvent<AnyTraceableEvent>].self, from: trace.eventsJSONData()
        )
        let store = InMemoryTraceStore<AnyTraceableEvent>()
        let active = DProvenanceKit<AnyTraceableEvent>.ActiveTraceRun(
            contextID: trace.contextID, store: store
        )
        for event in decoded {
            active.record(event.payload, engineName: event.engineName)
        }
        let bindingJSON = "{\"artifacts\":[{\"role\":\"\(role)\",\"sha256\":\"\(digest)\"}],"
            + "\"priority\":3,\"typeIdentifier\":\"artifact-emitted\"}"
        active.record(
            AnyTraceableEvent(typeIdentifier: "artifact-emitted", priorityValue: 3, rawJSON: bindingJSON),
            engineName: "ClaimProof"
        )
        try await store.flush()

        guard let run = try await store.getRun(id: active.runID) else {
            check("run reads back for signing", false)
            return
        }

        // Sign the trace and bind the report into a pack, as an integrator would.
        let signed = try TraceAttestationDocument.signed(run: run, using: SoftwareTraceAttestationKey())
        let artifact = ProofPackArtifact(
            role: role,
            mediaType: "application/json",
            encoding: .utf8,
            content: String(decoding: reportBytes, as: UTF8.self),
            sha256: digest
        )
        let pack = ProofPackDocument(attestation: signed, artifacts: [artifact])

        // 7a. The bridge-erased path CANNOT bind, and pinning that is the point of this
        // section. ClaimProofProvenance's events arrive as `AnyTraceableEvent`, whose Codable
        // nests the domain JSON inside a `rawJSON` string. The verifier walks the *parsed*
        // payload object graph, so a `role`/`sha256` pair sitting inside that string literal
        // is invisible to it: v2 role binding finds no co-located pair, and even v1 digest
        // presence finds no matching string leaf. Asserting the exact failure keeps this
        // honest — if a future DProvenanceKit or bridge change makes erased payloads
        // transparent, this check fails loudly and the limitation gets revisited on purpose.
        let erased = pack.verify()
        check("bridge-erased payloads do not bind (known limitation)", !erased.isValid)
        check("and the reason is specifically an unbound artifact",
              erased.failure == .artifactNotBound(index: 0),
              "got \(String(describing: erased.failure))")

        // 7b. Recorded natively as a typed event, the same ClaimProof report binds. This is
        // the shape an integrator has to emit for a pack to be worth anything.
        let typedStore = InMemoryTraceStore<ArtifactEmitted>()
        let typedRun = DProvenanceKit<ArtifactEmitted>.ActiveTraceRun(
            contextID: trace.contextID, store: typedStore
        )
        typedRun.record(
            ArtifactEmitted(artifacts: [.init(role: role, sha256: digest)]),
            engineName: "ClaimProof"
        )
        try await typedStore.flush()
        guard let typedTrace = try await typedStore.getRun(id: typedRun.runID) else {
            check("typed run reads back for signing", false)
            return
        }
        let typedSigned = try TraceAttestationDocument.signed(
            run: typedTrace, using: SoftwareTraceAttestationKey()
        )
        let typedPack = ProofPackDocument(attestation: typedSigned, artifacts: [artifact])
        let verification = typedPack.verify()

        check("typed binding pack verifies", verification.isValid,
              "failure \(String(describing: verification.failure))")
        check("binds exactly the one artifact", verification.bindings.count == 1)
        check("binding is role-bound, not value-presence-only",
              verification.bindingStrength == .roleBound,
              "got \(String(describing: verification.bindingStrength))")
        check("binding anchors to the artifact-emitted event",
              verification.bindings.first?.eventTypeIdentifier == "artifact-emitted")

        // 7c. It survives the JSON form a customer would actually be sent.
        let roundTripped = try ProofPackDocument.decodeJSON(typedPack.jsonData())
        check("pack survives JSON round-trip", roundTripped == typedPack)
        check("round-tripped pack still verifies", roundTripped.verify().isValid)

        // 7d. The certificate a downstream reader receives.
        let certificate = ProofPackCertificate.plainText(
            verification, pack: typedPack, issuedAt: Date(),
            toolVersion: DProvenanceKitVersion.current
        )
        check("certificate reports VERIFIED", certificate.contains("RESULT: VERIFIED"))
        check("certificate names the ClaimProof role", certificate.contains(role))
        check("certificate names the tool version that produced it",
              certificate.contains(DProvenanceKitVersion.current))
        check("certificate discloses what it does not attest",
              certificate.lowercased().contains("does not"))

        // 7e. A substituted report must not verify. This is the claim the whole artifact
        // exists to support, so it is asserted rather than assumed.
        var tamperedBytes = reportBytes
        tamperedBytes.append(0x20)
        let tampered = ProofPackDocument(attestation: typedSigned, artifacts: [
            ProofPackArtifact(
                role: role,
                mediaType: "application/json",
                encoding: .utf8,
                content: String(decoding: tamperedBytes, as: UTF8.self),
                sha256: sha256Hex(tamperedBytes)
            )
        ])
        check("a substituted report fails verification", !tampered.verify().isValid)

        // 7f. Relabelling the artifact after signing must fail — the property that
        // separates v2 from v1.
        let relabelled = ProofPackDocument(attestation: typedSigned, artifacts: [
            ProofPackArtifact(
                role: "court-filing",
                mediaType: "application/json",
                encoding: .utf8,
                content: String(decoding: reportBytes, as: UTF8.self),
                sha256: digest
            )
        ])
        check("a relabelled artifact fails verification", !relabelled.verify().isValid)
    } catch {
        check("proof pack", false, "error \(error)")
    }
}

// MARK: - Entry

if CommandLine.arguments.contains("--regenerate") {
    try regenerate()
    exit(0)
}

print("Claim Proof Specification v\(ClaimProofSpec.version) conformance")
let (vectorFailures, trace) = try SpecVectorChecks.runAll(vectorsDirectory: vectorsDirectory)
failureCount += vectorFailures
await checkDProvenanceKitRoundTrip(trace)
await checkProofPackAndCertificate(trace)

if failureCount > 0 {
    print("\n\(failureCount) conformance failure(s)")
    exit(1)
}
print("\nAll conformance checks passed.")
