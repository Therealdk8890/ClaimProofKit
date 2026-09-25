// Copyright 2026 Daniel Kissel
// SPDX-License-Identifier: Apache-2.0

import ClaimProofKit
import ClaimProofProvenance
import Foundation

struct InputDocument: Codable {
    let document: String
    let evidence: [EvidencePassage]
}

let arguments = CommandLine.arguments
do {
    switch parseCommand(Array(arguments.dropFirst())) {
    case let .verify(path, provenancePath):
        try runVerification(path: path, provenancePath: provenancePath)
    case let .benchmark(path, json, release):
        try runBenchmark(path: path, json: json, release: release)
    case let .annotationPrepare(candidatesPath, ledgerPath, outputDirectory, reviewerAliases):
        try runAnnotationPrepare(
            candidatesPath: candidatesPath,
            ledgerPath: ledgerPath,
            outputDirectory: outputDirectory,
            reviewerAliases: reviewerAliases
        )
    case let .annotationAudit(manifestPath, submissionPaths, json):
        try runAnnotationAudit(
            manifestPath: manifestPath,
            submissionPaths: submissionPaths,
            json: json
        )
    case let .annotationFinalize(
        manifestPath,
        primarySubmissionPaths,
        adjudicationPath,
        outputPath,
        origin,
        split
    ):
        try runAnnotationFinalize(
            manifestPath: manifestPath,
            primarySubmissionPaths: primarySubmissionPaths,
            adjudicationPath: adjudicationPath,
            outputPath: outputPath,
            origin: origin,
            split: split
        )
    case .help:
        printUsage()
        exit(0)
    case .usage:
        printUsage()
        exit(64)
    }
} catch {
    FileHandle.standardError.write(Data("claimproof: \(error)\n".utf8))
    exit(65)
}

enum Command {
    case verify(path: String, provenancePath: String?)
    case benchmark(path: String, json: Bool, release: Bool)
    case annotationPrepare(
        candidatesPath: String,
        ledgerPath: String,
        outputDirectory: String,
        reviewerAliases: [String]
    )
    case annotationAudit(manifestPath: String, submissionPaths: [String], json: Bool)
    case annotationFinalize(
        manifestPath: String,
        primarySubmissionPaths: [String],
        adjudicationPath: String,
        outputPath: String,
        origin: BenchmarkCorpusMetadata.Origin,
        split: BenchmarkCorpusMetadata.Split
    )
    case help
    case usage
}

func parseCommand(_ arguments: [String]) -> Command {
    if arguments.contains("--help") || arguments.contains("-h") {
        return .help
    }
    switch arguments.first {
    case "verify":
        var path: String?
        var provenancePath: String?
        var rest = arguments.dropFirst()
        while let argument = rest.first {
            rest = rest.dropFirst()
            if argument == "--provenance" {
                guard provenancePath == nil, let output = rest.first else { return .usage }
                provenancePath = output
                rest = rest.dropFirst()
            } else if path == nil {
                path = argument
            } else {
                return .usage
            }
        }
        guard let path else { return .usage }
        return .verify(path: path, provenancePath: provenancePath)
    case "benchmark":
        var path: String?
        var json = false
        var release = false
        for argument in arguments.dropFirst() {
            switch argument {
            case "--json" where !json:
                json = true
            case "--release" where !release:
                release = true
            case _ where path == nil && !argument.hasPrefix("--"):
                path = argument
            default:
                return .usage
            }
        }
        guard let path else { return .usage }
        return .benchmark(path: path, json: json, release: release)
    case "annotation":
        return parseAnnotationCommand(Array(arguments.dropFirst()))
    case let .some(path) where arguments.count == 1:
        // Backward compatibility: a lone path runs verification.
        return .verify(path: path, provenancePath: nil)
    default:
        return .usage
    }
}

func parseAnnotationCommand(_ arguments: [String]) -> Command {
    guard let action = arguments.first else { return .usage }
    switch action {
    case "prepare":
        let rest = Array(arguments.dropFirst())
        guard rest.count >= 3 else { return .usage }
        let candidatesPath = rest[0]
        let ledgerPath = rest[1]
        let outputDirectory = rest[2]
        var reviewers: [String] = []
        var index = 3
        while index < rest.count {
            guard rest[index] == "--reviewer", index + 1 < rest.count else { return .usage }
            reviewers.append(rest[index + 1])
            index += 2
        }
        return .annotationPrepare(
            candidatesPath: candidatesPath,
            ledgerPath: ledgerPath,
            outputDirectory: outputDirectory,
            reviewerAliases: reviewers
        )
    case "audit":
        var paths: [String] = []
        var json = false
        for argument in arguments.dropFirst() {
            if argument == "--json", !json {
                json = true
            } else if !argument.hasPrefix("--") {
                paths.append(argument)
            } else {
                return .usage
            }
        }
        guard paths.count == 3 else { return .usage }
        return .annotationAudit(
            manifestPath: paths[0],
            submissionPaths: Array(paths[1...2]),
            json: json
        )
    case "finalize":
        var paths: [String] = []
        var origin = BenchmarkCorpusMetadata.Origin.publicRecord
        var split = BenchmarkCorpusMetadata.Split.validation
        var rest = Array(arguments.dropFirst())
        while let argument = rest.first {
            rest.removeFirst()
            if argument == "--origin" {
                guard let value = rest.first,
                      let parsed = BenchmarkCorpusMetadata.Origin(rawValue: value)
                else { return .usage }
                origin = parsed
                rest.removeFirst()
            } else if argument == "--split" {
                guard let value = rest.first,
                      let parsed = BenchmarkCorpusMetadata.Split(rawValue: value)
                else { return .usage }
                split = parsed
                rest.removeFirst()
            } else if !argument.hasPrefix("--") {
                paths.append(argument)
            } else {
                return .usage
            }
        }
        guard paths.count == 5 else { return .usage }
        return .annotationFinalize(
            manifestPath: paths[0],
            primarySubmissionPaths: Array(paths[1...2]),
            adjudicationPath: paths[3],
            outputPath: paths[4],
            origin: origin,
            split: split
        )
    default:
        return .usage
    }
}

func runVerification(path: String, provenancePath: String?) throws -> Never {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let input = try JSONDecoder().decode(InputDocument.self, from: data)
    let policy = VerificationPolicy()
    let report = ClaimVerifier(policy: policy).verify(document: input.document, against: input.evidence)
    // The report is always emitted, even if the trace write fails afterwards; a
    // trace-write failure gets its own exit code (EX_CANTCREAT) so callers can
    // distinguish it from bad input (65) and from a blocked report (2).
    print(ReportRenderer().markdown(report))
    if let provenancePath {
        do {
            let trace = try ProvenanceExporter().trace(for: report, policy: policy)
            try trace.manifestJSONData().write(to: URL(fileURLWithPath: provenancePath))
            FileHandle.standardError.write(Data("provenance trace written to \(provenancePath) (run fingerprint \(trace.runFingerprint))\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("claimproof: failed to write provenance trace to \(provenancePath): \(error)\n".utf8))
            exit(73)
        }
    }
    exit(report.isSafeToPublish ? 0 : 2)
}

func runBenchmark(path: String, json: Bool, release: Bool) throws -> Never {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let corpus = try JSONDecoder().decode(BenchmarkCorpus.self, from: data)
    let report = BenchmarkRunner().run(corpus)
    if json {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        print(String(decoding: try encoder.encode(report), as: UTF8.self))
    } else {
        print(BenchmarkReportRenderer().markdown(report))
    }
    let passed = release ? report.passesProductionReleaseGate : report.passesSafetyGate
    exit(passed ? 0 : 3)
}

func runAnnotationPrepare(
    candidatesPath: String,
    ledgerPath: String,
    outputDirectory: String,
    reviewerAliases: [String]
) throws -> Never {
    let decoder = JSONDecoder()
    let candidates = try decoder.decode(
        AnnotationCandidateCorpus.self,
        from: Data(contentsOf: URL(fileURLWithPath: candidatesPath))
    )
    let ledger = try decoder.decode(
        EvidenceSourceLedger.self,
        from: Data(contentsOf: URL(fileURLWithPath: ledgerPath))
    )
    let preparation = try HumanAnnotationWorkflow().prepare(
        corpus: candidates,
        ledger: ledger,
        reviewerAliases: reviewerAliases
    )
    let outputURL = URL(fileURLWithPath: outputDirectory, isDirectory: true)
    if FileManager.default.fileExists(atPath: outputURL.path),
       !(try FileManager.default.contentsOfDirectory(atPath: outputURL.path)).isEmpty
    {
        throw AnnotationWorkflowError.invalidIntake([
            "annotation output directory is not empty; use a new directory to preserve the audit trail",
        ])
    }
    let slugs = preparation.packets.map { safeFilename($0.reviewerAlias) }
    if Set(slugs).count != slugs.count {
        throw AnnotationWorkflowError.invalidReviewers(
            "reviewer aliases collide when converted to packet filenames"
        )
    }
    try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
    try writeJSON(
        preparation.manifest,
        to: outputURL.appendingPathComponent("coordinator-manifest.json")
    )
    for (packet, template) in zip(preparation.packets, preparation.responseTemplates) {
        let slug = safeFilename(packet.reviewerAlias)
        try writeJSON(packet, to: outputURL.appendingPathComponent("\(slug)-packet.json"))
        try writeJSON(template, to: outputURL.appendingPathComponent("\(slug)-submission.json"))
    }
    print("Prepared two blinded review packets and one sealed adjudicator packet in \(outputDirectory).")
    print("Keep coordinator-manifest.json and the source ledger private; do not give them to reviewers.")
    exit(0)
}

func runAnnotationAudit(
    manifestPath: String,
    submissionPaths: [String],
    json: Bool
) throws -> Never {
    let decoder = JSONDecoder()
    let manifest = try decoder.decode(
        AnnotationCoordinatorManifest.self,
        from: Data(contentsOf: URL(fileURLWithPath: manifestPath))
    )
    let submissions = try submissionPaths.map { path in
        try decoder.decode(
            AnnotationSubmission.self,
            from: Data(contentsOf: URL(fileURLWithPath: path))
        )
    }
    let report = HumanAnnotationWorkflow().audit(
        manifest: manifest,
        primarySubmissions: submissions
    )
    if json {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        print(String(decoding: try encoder.encode(report), as: UTF8.self))
    } else {
        print("# Independent annotation audit")
        print("")
        print("- Claims: \(report.candidateCount)")
        print("- Binary agreements: \(report.binaryAgreementCount)")
        print("- Binary disagreements: \(report.binaryDisagreementCount)")
        print("- Detailed disagreements requiring adjudication: \(report.detailedDisagreementCandidateIDs.count)")
        if let adjudicator = report.adjudicatorAlias {
            print("- Sealed adjudicator: \(adjudicator)")
        }
        if let kappa = report.binaryLabelAgreement {
            print(String(format: "- Cohen's kappa: %.3f", kappa))
        } else {
            print("- Cohen's kappa: undefined")
        }
        print("- Reliability gate: \(report.passesReliabilityGate ? "PASS" : "FAIL")")
        if !report.issues.isEmpty {
            print("")
            print("## Issues")
            for issue in report.issues { print("- \(issue)") }
        }
        if !report.detailedDisagreementCandidateIDs.isEmpty {
            print("")
            print("## Assignment IDs the adjudicator must complete")
            for id in report.adjudicationAssignmentIDs { print("- \(id)") }
        }
    }
    exit(report.passesReliabilityGate ? 0 : 3)
}

func runAnnotationFinalize(
    manifestPath: String,
    primarySubmissionPaths: [String],
    adjudicationPath: String,
    outputPath: String,
    origin: BenchmarkCorpusMetadata.Origin,
    split: BenchmarkCorpusMetadata.Split
) throws -> Never {
    let decoder = JSONDecoder()
    let manifest = try decoder.decode(
        AnnotationCoordinatorManifest.self,
        from: Data(contentsOf: URL(fileURLWithPath: manifestPath))
    )
    let primaries = try primarySubmissionPaths.map { path in
        try decoder.decode(
            AnnotationSubmission.self,
            from: Data(contentsOf: URL(fileURLWithPath: path))
        )
    }
    let adjudication = try decoder.decode(
        AnnotationSubmission.self,
        from: Data(contentsOf: URL(fileURLWithPath: adjudicationPath))
    )
    let corpus = try HumanAnnotationWorkflow().finalize(
        manifest: manifest,
        primarySubmissions: primaries,
        adjudicationSubmission: adjudication,
        origin: origin,
        split: split
    )
    let outputURL = URL(fileURLWithPath: outputPath)
    if FileManager.default.fileExists(atPath: outputURL.path) {
        throw AnnotationWorkflowError.invalidIntake([
            "finalized corpus already exists; refusing to overwrite the audit artifact",
        ])
    }
    try writeJSON(corpus, to: outputURL)
    print("Wrote independently labeled \(split.rawValue) corpus to \(outputPath).")
    exit(0)
}

func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(value).write(to: url, options: .atomic)
}

func safeFilename(_ value: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    let mapped = value.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
    let result = String(mapped)
    return result.isEmpty ? "reviewer" : result
}

func printUsage() {
    let usage = """
    Usage:
      claimproof verify <input.json> [--provenance <trace.json>]
      claimproof benchmark <corpus.json> [--json] [--release]
      claimproof annotation prepare <candidates.json> <source-ledger.json> <output-dir>
        --reviewer <reviewer-a> --reviewer <reviewer-b> --reviewer <adjudicator>
      claimproof annotation audit <manifest.json> <review-a.json> <review-b.json> [--json]
      claimproof annotation finalize <manifest.json> <review-a.json> <review-b.json>
        <adjudication.json> <output-corpus.json> [--origin <origin>] [--split <split>]

    --provenance writes a DProvenanceKit-compatible trace manifest of the
    verification run alongside the report.

    --release enforces the statistically powered production gate instead of
    the fast synthetic regression gate.

    Annotation packets exclude candidate IDs, source-ledger records, expected
    labels, model predictions, rationales, and benchmark categories. Finalize
    defaults to the validation split; sealedHoldout must be selected explicitly.

    Exit codes: 0 published, 2 blocked, 3 benchmark gate failed,
    64 usage, 65 unreadable input, 73 provenance trace write failed.

    Backward compatibility: claimproof <input.json> runs verification.
    """
    FileHandle.standardError.write(Data("\(usage)\n".utf8))
}
