// Copyright 2026 Daniel Kissel
// SPDX-License-Identifier: Apache-2.0
//
// Wire formats for the frozen golden vectors under ConformanceHarness/vectors.
// Shared by the native conformance harness (which also regenerates vectors and
// round-trips through the real DProvenanceKit) and the wasm vector runner
// (which proves the same identity and verdict behavior under wasm32-wasi).

public struct ClaimFingerprintVector: Codable {
    public struct Case: Codable {
        public let description: String
        public let text: String
        public let fingerprint: String

        public init(description: String, text: String, fingerprint: String) {
            self.description = description
            self.text = text
            self.fingerprint = fingerprint
        }
    }

    public let specVersion: String
    public let algorithm: String
    public let cases: [Case]

    public init(specVersion: String, algorithm: String, cases: [Case]) {
        self.specVersion = specVersion
        self.algorithm = algorithm
        self.cases = cases
    }
}

public struct PolicyFingerprintVector: Codable {
    public struct Case: Codable {
        public let description: String
        public let supportedThreshold: Double
        public let ambiguousThreshold: Double
        public let contradictionThreshold: Double
        public let maximumEvidenceMatches: Int
        public let fingerprint: String

        public init(
            description: String,
            supportedThreshold: Double,
            ambiguousThreshold: Double,
            contradictionThreshold: Double,
            maximumEvidenceMatches: Int,
            fingerprint: String
        ) {
            self.description = description
            self.supportedThreshold = supportedThreshold
            self.ambiguousThreshold = ambiguousThreshold
            self.contradictionThreshold = contradictionThreshold
            self.maximumEvidenceMatches = maximumEvidenceMatches
            self.fingerprint = fingerprint
        }
    }

    public let specVersion: String
    public let algorithm: String
    public let cases: [Case]

    public init(specVersion: String, algorithm: String, cases: [Case]) {
        self.specVersion = specVersion
        self.algorithm = algorithm
        self.cases = cases
    }
}

public struct ReportFingerprintVector: Codable {
    public struct Verdict: Codable {
        public let claimText: String
        public let status: String

        public init(claimText: String, status: String) {
            self.claimText = claimText
            self.status = status
        }
    }

    public struct Case: Codable {
        public let description: String
        public let verdicts: [Verdict]
        public let fingerprint: String

        public init(description: String, verdicts: [Verdict], fingerprint: String) {
            self.description = description
            self.verdicts = verdicts
            self.fingerprint = fingerprint
        }
    }

    public let specVersion: String
    public let algorithm: String
    public let cases: [Case]

    public init(specVersion: String, algorithm: String, cases: [Case]) {
        self.specVersion = specVersion
        self.algorithm = algorithm
        self.cases = cases
    }
}

public struct VerdictSemanticsVector: Codable {
    public struct Passage: Codable {
        public let id: String
        public let source: String
        public let sourceType: String
        public let text: String

        public init(id: String, source: String, sourceType: String, text: String) {
            self.id = id
            self.source = source
            self.sourceType = sourceType
            self.text = text
        }
    }

    public struct Case: Codable {
        public let description: String
        public let claimText: String
        public let claimType: String
        public let evidence: [Passage]
        public let expectedStatus: String

        public init(description: String, claimText: String, claimType: String, evidence: [Passage], expectedStatus: String) {
            self.description = description
            self.claimText = claimText
            self.claimType = claimType
            self.evidence = evidence
            self.expectedStatus = expectedStatus
        }
    }

    public let specVersion: String
    public let description: String
    public let cases: [Case]

    public init(specVersion: String, description: String, cases: [Case]) {
        self.specVersion = specVersion
        self.description = description
        self.cases = cases
    }
}

public struct ProvenanceBridgeVector: Codable {
    public struct Passage: Codable {
        public let id: String
        public let source: String
        public let sourceType: String
        public let text: String

        public init(id: String, source: String, sourceType: String, text: String) {
            self.id = id
            self.source = source
            self.sourceType = sourceType
            self.text = text
        }
    }

    public struct Event: Codable {
        public let typeIdentifier: String
        public let priorityValue: Int
        public let rawJSON: String

        public init(typeIdentifier: String, priorityValue: Int, rawJSON: String) {
            self.typeIdentifier = typeIdentifier
            self.priorityValue = priorityValue
            self.rawJSON = rawJSON
        }
    }

    public struct Edge: Codable {
        public let sourceSequence: UInt64
        public let targetSequence: UInt64
        public let type: String

        public init(sourceSequence: UInt64, targetSequence: UInt64, type: String) {
            self.sourceSequence = sourceSequence
            self.targetSequence = targetSequence
            self.type = type
        }
    }

    public let specVersion: String
    public let description: String
    public let document: String
    public let evidence: [Passage]
    public let createdAtEpochSeconds: Double
    public let reportFingerprint: String
    public let policyFingerprint: String
    public let runFingerprint: String
    public let events: [Event]
    public let edges: [Edge]

    public init(
        specVersion: String,
        description: String,
        document: String,
        evidence: [Passage],
        createdAtEpochSeconds: Double,
        reportFingerprint: String,
        policyFingerprint: String,
        runFingerprint: String,
        events: [Event],
        edges: [Edge]
    ) {
        self.specVersion = specVersion
        self.description = description
        self.document = document
        self.evidence = evidence
        self.createdAtEpochSeconds = createdAtEpochSeconds
        self.reportFingerprint = reportFingerprint
        self.policyFingerprint = policyFingerprint
        self.runFingerprint = runFingerprint
        self.events = events
        self.edges = edges
    }
}
