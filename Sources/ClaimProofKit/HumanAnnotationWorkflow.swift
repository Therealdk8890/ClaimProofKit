// Copyright 2026 Daniel Kissel
// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum EvidenceAuthorizationBasis: String, Codable, Sendable {
    case publicRecordReusePermitted
    case deidentifiedWithAuthorization
}

public enum DeidentificationReviewStatus: String, Codable, Sendable {
    case notRequired
    case pending
    case reviewedBySecondPerson
}

/// Private provenance for one collected source. The source ledger should not be
/// committed with the public benchmark: it may contain URLs or other provenance
/// that intentionally does not appear in reviewer packets.
public struct EvidenceSourceRecord: Codable, Sendable {
    public let id: String
    public let matterID: String
    public let title: String
    public let canonicalURL: String?
    public let sourceType: EvidencePassage.SourceType
    public let jurisdiction: String
    public let retrievedAt: String
    public let authorizationBasis: EvidenceAuthorizationBasis
    public let licenseOrTerms: String
    public let redistributionPermitted: Bool
    public let contentSHA256: String
    public let deidentificationReview: DeidentificationReviewStatus
    public let containsDirectPersonalIdentifiers: Bool
    public let containsRestrictedMaterial: Bool

    public init(
        id: String,
        matterID: String,
        title: String,
        canonicalURL: String? = nil,
        sourceType: EvidencePassage.SourceType,
        jurisdiction: String,
        retrievedAt: String,
        authorizationBasis: EvidenceAuthorizationBasis,
        licenseOrTerms: String,
        redistributionPermitted: Bool,
        contentSHA256: String,
        deidentificationReview: DeidentificationReviewStatus,
        containsDirectPersonalIdentifiers: Bool,
        containsRestrictedMaterial: Bool
    ) {
        self.id = id
        self.matterID = matterID
        self.title = title
        self.canonicalURL = canonicalURL
        self.sourceType = sourceType
        self.jurisdiction = jurisdiction
        self.retrievedAt = retrievedAt
        self.authorizationBasis = authorizationBasis
        self.licenseOrTerms = licenseOrTerms
        self.redistributionPermitted = redistributionPermitted
        self.contentSHA256 = contentSHA256
        self.deidentificationReview = deidentificationReview
        self.containsDirectPersonalIdentifiers = containsDirectPersonalIdentifiers
        self.containsRestrictedMaterial = containsRestrictedMaterial
    }
}

public struct EvidenceSourceLedger: Codable, Sendable {
    public let version: String
    public let sources: [EvidenceSourceRecord]

    public init(version: String, sources: [EvidenceSourceRecord]) {
        self.version = version
        self.sources = sources
    }
}

/// Unlabeled coordinator input. It deliberately has no expected status,
/// rationale, gold span, model prediction, or benchmark category to leak into
/// the independent review packets.
public struct AnnotationCandidate: Codable, Sendable {
    public let id: String
    public let matterID: String
    public let claimText: String
    public let claimType: Claim.ClaimType
    public let evidence: [EvidencePassage]
    public let challengeTags: [String]
    /// Exact passage-ID to private source-ledger record mapping. This remains
    /// in the coordinator manifest and is omitted from reviewer packets.
    public let evidenceSourceRecordIDs: [String: String]

    public init(
        id: String,
        matterID: String,
        claimText: String,
        claimType: Claim.ClaimType,
        evidence: [EvidencePassage],
        challengeTags: [String] = [],
        evidenceSourceRecordIDs: [String: String]
    ) {
        self.id = id
        self.matterID = matterID
        self.claimText = claimText
        self.claimType = claimType
        self.evidence = evidence
        self.challengeTags = challengeTags
        self.evidenceSourceRecordIDs = evidenceSourceRecordIDs
    }
}

public struct AnnotationCandidateCorpus: Codable, Sendable {
    public let version: String
    public let name: String
    public let sourceLedgerVersion: String
    public let annotationPolicyVersion: String
    public let candidates: [AnnotationCandidate]

    public init(
        version: String,
        name: String,
        sourceLedgerVersion: String,
        annotationPolicyVersion: String,
        candidates: [AnnotationCandidate]
    ) {
        self.version = version
        self.name = name
        self.sourceLedgerVersion = sourceLedgerVersion
        self.annotationPolicyVersion = annotationPolicyVersion
        self.candidates = candidates
    }
}

public struct AnnotationPacketItem: Codable, Sendable {
    public let assignmentID: String
    public let matterID: String
    public let claimText: String
    public let claimType: Claim.ClaimType
    public let evidence: [EvidencePassage]

    public init(
        assignmentID: String,
        matterID: String,
        claimText: String,
        claimType: Claim.ClaimType,
        evidence: [EvidencePassage]
    ) {
        self.assignmentID = assignmentID
        self.matterID = matterID
        self.claimText = claimText
        self.claimType = claimType
        self.evidence = evidence
    }
}

public struct AnnotationPacket: Codable, Sendable {
    public let schemaVersion: String
    public let corpusVersion: String
    public let reviewerAlias: String
    public let annotationPolicyVersion: String
    public let items: [AnnotationPacketItem]

    public init(
        schemaVersion: String = "claimproof-annotation-packet/1",
        corpusVersion: String,
        reviewerAlias: String,
        annotationPolicyVersion: String,
        items: [AnnotationPacketItem]
    ) {
        self.schemaVersion = schemaVersion
        self.corpusVersion = corpusVersion
        self.reviewerAlias = reviewerAlias
        self.annotationPolicyVersion = annotationPolicyVersion
        self.items = items
    }
}

public struct AnnotationAssignment: Codable, Sendable {
    public let assignmentID: String
    public let reviewerAlias: String
    public let candidateID: String

    public init(assignmentID: String, reviewerAlias: String, candidateID: String) {
        self.assignmentID = assignmentID
        self.reviewerAlias = reviewerAlias
        self.candidateID = candidateID
    }
}

/// Private coordinator state. Keep it separate from packets so reviewers cannot
/// recover source IDs, challenge tags, or stable candidate IDs.
public struct AnnotationCoordinatorManifest: Codable, Sendable {
    public let schemaVersion: String
    public let candidateCorpus: AnnotationCandidateCorpus
    public let assignments: [AnnotationAssignment]
    public let intakeValidationPassed: Bool

    public init(
        schemaVersion: String = "claimproof-annotation-manifest/1",
        candidateCorpus: AnnotationCandidateCorpus,
        assignments: [AnnotationAssignment],
        intakeValidationPassed: Bool
    ) {
        self.schemaVersion = schemaVersion
        self.candidateCorpus = candidateCorpus
        self.assignments = assignments
        self.intakeValidationPassed = intakeValidationPassed
    }
}

public struct AnnotationResponseTemplate: Codable, Sendable {
    public struct Response: Codable, Sendable {
        public let assignmentID: String
        public let approvalEligible: Bool?
        public let status: SupportStatus?
        public let rationale: String?
        public let evidenceSpans: [GoldEvidenceSpan]?

        public init(
            assignmentID: String,
            approvalEligible: Bool? = nil,
            status: SupportStatus? = nil,
            rationale: String? = nil,
            evidenceSpans: [GoldEvidenceSpan]? = nil
        ) {
            self.assignmentID = assignmentID
            self.approvalEligible = approvalEligible
            self.status = status
            self.rationale = rationale
            self.evidenceSpans = evidenceSpans
        }

        private enum CodingKeys: String, CodingKey {
            case assignmentID
            case approvalEligible
            case status
            case rationale
            case evidenceSpans
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(assignmentID, forKey: .assignmentID)
            if let approvalEligible {
                try container.encode(approvalEligible, forKey: .approvalEligible)
            } else {
                try container.encodeNil(forKey: .approvalEligible)
            }
            if let status {
                try container.encode(status, forKey: .status)
            } else {
                try container.encodeNil(forKey: .status)
            }
            if let rationale {
                try container.encode(rationale, forKey: .rationale)
            } else {
                try container.encodeNil(forKey: .rationale)
            }
            if let evidenceSpans {
                try container.encode(evidenceSpans, forKey: .evidenceSpans)
            } else {
                try container.encodeNil(forKey: .evidenceSpans)
            }
        }
    }

    public let schemaVersion: String
    public let corpusVersion: String
    public let reviewerAlias: String
    public let annotationPolicyVersion: String
    public let responses: [Response]

    public init(packet: AnnotationPacket) {
        self.schemaVersion = "claimproof-annotation-submission/1"
        self.corpusVersion = packet.corpusVersion
        self.reviewerAlias = packet.reviewerAlias
        self.annotationPolicyVersion = packet.annotationPolicyVersion
        self.responses = packet.items.map { Response(assignmentID: $0.assignmentID) }
    }
}

public struct AnnotationLabel: Codable, Sendable {
    public let assignmentID: String
    public let approvalEligible: Bool
    public let status: SupportStatus
    public let rationale: String
    public let evidenceSpans: [GoldEvidenceSpan]

    public init(
        assignmentID: String,
        approvalEligible: Bool,
        status: SupportStatus,
        rationale: String,
        evidenceSpans: [GoldEvidenceSpan] = []
    ) {
        self.assignmentID = assignmentID
        self.approvalEligible = approvalEligible
        self.status = status
        self.rationale = rationale
        self.evidenceSpans = evidenceSpans
    }
}

public struct AnnotationSubmission: Codable, Sendable {
    public let schemaVersion: String
    public let corpusVersion: String
    public let reviewerAlias: String
    public let annotationPolicyVersion: String
    public let responses: [AnnotationLabel]

    public init(
        schemaVersion: String = "claimproof-annotation-submission/1",
        corpusVersion: String,
        reviewerAlias: String,
        annotationPolicyVersion: String,
        responses: [AnnotationLabel]
    ) {
        self.schemaVersion = schemaVersion
        self.corpusVersion = corpusVersion
        self.reviewerAlias = reviewerAlias
        self.annotationPolicyVersion = annotationPolicyVersion
        self.responses = responses
    }
}

public struct AnnotationPreparation: Sendable {
    public let manifest: AnnotationCoordinatorManifest
    public let packets: [AnnotationPacket]
    public let responseTemplates: [AnnotationResponseTemplate]
}

public struct AnnotationAuditReport: Codable, Sendable {
    public let corpusVersion: String
    public let reviewerAliases: [String]
    public let candidateCount: Int
    public let binaryAgreementCount: Int
    public let binaryDisagreementCount: Int
    public let detailedDisagreementCandidateIDs: [String]
    public let adjudicatorAlias: String?
    public let adjudicationAssignmentIDs: [String]
    public let binaryLabelAgreement: Double?
    public let issues: [String]

    public var passesReliabilityGate: Bool {
        issues.isEmpty && (binaryLabelAgreement ?? -1) >= 0.80
    }
}

public enum AnnotationWorkflowError: Error, CustomStringConvertible, Sendable {
    case invalidIntake([String])
    case invalidReviewers(String)
    case invalidSubmissions([String])

    public var description: String {
        switch self {
        case let .invalidIntake(issues):
            return "annotation intake is invalid: \(issues.joined(separator: "; "))"
        case let .invalidReviewers(message):
            return "reviewer configuration is invalid: \(message)"
        case let .invalidSubmissions(issues):
            return "annotation submissions are invalid: \(issues.joined(separator: "; "))"
        }
    }
}

public struct HumanAnnotationWorkflow: Sendable {
    public init() {}

    public func validateIntake(
        corpus: AnnotationCandidateCorpus,
        ledger: EvidenceSourceLedger
    ) -> [String] {
        var issues: [String] = []
        if corpus.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("candidate corpus version is empty")
        }
        if corpus.annotationPolicyVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("annotation policy version is empty")
        }
        if corpus.sourceLedgerVersion != ledger.version {
            issues.append("candidate corpus sourceLedgerVersion does not match the ledger")
        }
        if corpus.candidates.isEmpty {
            issues.append("candidate corpus contains no claims")
        }

        let sourceIDs = ledger.sources.map(\.id)
        if Set(sourceIDs).count != sourceIDs.count {
            issues.append("source ledger contains duplicate source IDs")
        }
        let candidateIDs = corpus.candidates.map(\.id)
        if Set(candidateIDs).count != candidateIDs.count {
            issues.append("candidate corpus contains duplicate candidate IDs")
        }
        let sourcesByID = firstValues(ledger.sources, keyedBy: \.id)

        for source in ledger.sources {
            let prefix = "source \(source.id)"
            if source.matterID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append("\(prefix) has no matterID")
            }
            if source.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append("\(prefix) has no title")
            }
            if source.jurisdiction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append("\(prefix) has no jurisdiction")
            }
            if source.retrievedAt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append("\(prefix) has no retrieval date")
            }
            if source.authorizationBasis == .publicRecordReusePermitted,
               source.canonicalURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
            {
                issues.append("\(prefix) has no canonical public-record URL")
            }
            if source.licenseOrTerms.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append("\(prefix) has no license or terms record")
            }
            if !source.redistributionPermitted {
                issues.append("\(prefix) is not cleared for benchmark redistribution")
            }
            if source.containsRestrictedMaterial {
                issues.append("\(prefix) contains privileged, sealed, confidential, or restricted material")
            }
            if source.containsDirectPersonalIdentifiers {
                issues.append("\(prefix) still contains direct personal identifiers")
            }
            if source.deidentificationReview == .pending {
                issues.append("\(prefix) has a pending de-identification review")
            }
            if source.authorizationBasis == .deidentifiedWithAuthorization &&
                source.deidentificationReview != .reviewedBySecondPerson
            {
                issues.append("\(prefix) needs second-person de-identification review")
            }
            if !isSHA256(source.contentSHA256) {
                issues.append("\(prefix) has an invalid SHA-256 digest")
            }
        }

        for candidate in corpus.candidates {
            let prefix = "candidate \(candidate.id)"
            if candidate.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append("a candidate has an empty ID")
            }
            if candidate.matterID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append("\(prefix) has no matterID")
            }
            if candidate.claimText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append("\(prefix) has empty claim text")
            }
            if candidate.evidence.isEmpty {
                issues.append("\(prefix) has no evidence packet")
            }
            let evidenceIDs = candidate.evidence.map(\.id)
            if Set(evidenceIDs).count != evidenceIDs.count {
                issues.append("\(prefix) contains duplicate evidence IDs")
            }
            let mappedEvidenceIDs = Set(candidate.evidenceSourceRecordIDs.keys)
            let expectedEvidenceIDs = Set(evidenceIDs)
            if mappedEvidenceIDs != expectedEvidenceIDs {
                issues.append("\(prefix) does not map every evidence passage to exactly one source record")
            }
            for evidence in candidate.evidence {
                guard let sourceID = candidate.evidenceSourceRecordIDs[evidence.id] else { continue }
                guard let source = sourcesByID[sourceID] else {
                    issues.append("\(prefix) references unknown source \(sourceID)")
                    continue
                }
                if source.matterID != candidate.matterID {
                    issues.append("\(prefix) references source \(sourceID) from another matter")
                }
                if source.sourceType != evidence.sourceType {
                    issues.append("\(prefix) passage \(evidence.id) has a source type that disagrees with \(sourceID)")
                }
            }
        }
        return issues
    }

    /// Produces three separately keyed, independently ordered packets. The third
    /// packet remains sealed until the first two submissions have been audited;
    /// it is then used only for detailed disagreements.
    public func prepare(
        corpus: AnnotationCandidateCorpus,
        ledger: EvidenceSourceLedger,
        reviewerAliases: [String]
    ) throws -> AnnotationPreparation {
        let normalizedReviewers = reviewerAliases.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard normalizedReviewers.count == 3 else {
            throw AnnotationWorkflowError.invalidReviewers(
                "exactly two primary reviewers and one adjudicator are required"
            )
        }
        guard normalizedReviewers.allSatisfy({ !$0.isEmpty }),
              Set(normalizedReviewers).count == normalizedReviewers.count
        else {
            throw AnnotationWorkflowError.invalidReviewers("reviewer aliases must be non-empty and unique")
        }

        let issues = validateIntake(corpus: corpus, ledger: ledger)
        guard issues.isEmpty else {
            throw AnnotationWorkflowError.invalidIntake(issues)
        }

        var assignments: [AnnotationAssignment] = []
        var packets: [AnnotationPacket] = []
        for reviewer in normalizedReviewers {
            var items: [AnnotationPacketItem] = []
            for candidate in corpus.candidates {
                let assignmentID = "assignment-\(UUID().uuidString.lowercased())"
                assignments.append(AnnotationAssignment(
                    assignmentID: assignmentID,
                    reviewerAlias: reviewer,
                    candidateID: candidate.id
                ))
                items.append(AnnotationPacketItem(
                    assignmentID: assignmentID,
                    matterID: candidate.matterID,
                    claimText: candidate.claimText,
                    claimType: candidate.claimType,
                    evidence: candidate.evidence
                ))
            }
            packets.append(AnnotationPacket(
                corpusVersion: corpus.version,
                reviewerAlias: reviewer,
                annotationPolicyVersion: corpus.annotationPolicyVersion,
                items: items.shuffled()
            ))
        }

        let manifest = AnnotationCoordinatorManifest(
            candidateCorpus: corpus,
            assignments: assignments,
            intakeValidationPassed: true
        )
        return AnnotationPreparation(
            manifest: manifest,
            packets: packets,
            responseTemplates: packets.map(AnnotationResponseTemplate.init(packet:))
        )
    }

    /// Audits the two pre-adjudication submissions and calculates Cohen's kappa
    /// on the load-bearing binary approval decision. Model outputs never enter
    /// this calculation.
    public func audit(
        manifest: AnnotationCoordinatorManifest,
        primarySubmissions: [AnnotationSubmission]
    ) -> AnnotationAuditReport {
        var issues: [String] = []
        guard primarySubmissions.count == 2 else {
            return AnnotationAuditReport(
                corpusVersion: manifest.candidateCorpus.version,
                reviewerAliases: primarySubmissions.map(\.reviewerAlias),
                candidateCount: manifest.candidateCorpus.candidates.count,
                binaryAgreementCount: 0,
                binaryDisagreementCount: 0,
                detailedDisagreementCandidateIDs: [],
                adjudicatorAlias: nil,
                adjudicationAssignmentIDs: [],
                binaryLabelAgreement: nil,
                issues: ["exactly two primary submissions are required"]
            )
        }

        if !manifest.intakeValidationPassed {
            issues.append("coordinator manifest was not created from a validated intake")
        }
        let aliases = primarySubmissions.map(\.reviewerAlias)
        if Set(aliases).count != 2 {
            issues.append("primary submissions do not have two distinct reviewer aliases")
        }

        let candidatesByID = firstValues(manifest.candidateCorpus.candidates, keyedBy: \.id)
        let assignmentIDs = manifest.assignments.map(\.assignmentID)
        if Set(assignmentIDs).count != assignmentIDs.count {
            issues.append("coordinator manifest contains duplicate assignment IDs")
        }
        let assignmentsByID = firstValues(manifest.assignments, keyedBy: \.assignmentID)
        var labelsByReviewerAndCandidate: [String: [String: AnnotationLabel]] = [:]

        for submission in primarySubmissions {
            let prefix = "submission \(submission.reviewerAlias)"
            if submission.corpusVersion != manifest.candidateCorpus.version {
                issues.append("\(prefix) has the wrong corpus version")
            }
            if submission.annotationPolicyVersion != manifest.candidateCorpus.annotationPolicyVersion {
                issues.append("\(prefix) has the wrong annotation policy version")
            }
            let responseIDs = submission.responses.map(\.assignmentID)
            if Set(responseIDs).count != responseIDs.count {
                issues.append("\(prefix) contains duplicate assignment IDs")
            }
            let expectedAssignments = Set(manifest.assignments.compactMap {
                $0.reviewerAlias == submission.reviewerAlias ? $0.assignmentID : nil
            })
            let submittedAssignments = Set(responseIDs)
            let missing = expectedAssignments.subtracting(submittedAssignments)
            let unexpected = submittedAssignments.subtracting(expectedAssignments)
            if !missing.isEmpty {
                issues.append("\(prefix) is missing \(missing.count) assignments")
            }
            if !unexpected.isEmpty {
                issues.append("\(prefix) contains \(unexpected.count) unexpected assignments")
            }

            for label in submission.responses {
                guard let assignment = assignmentsByID[label.assignmentID],
                      assignment.reviewerAlias == submission.reviewerAlias,
                      let candidate = candidatesByID[assignment.candidateID]
                else { continue }
                issues.append(contentsOf: validate(
                    label: label,
                    candidate: candidate,
                    reviewerAlias: submission.reviewerAlias
                ))
                labelsByReviewerAndCandidate[submission.reviewerAlias, default: [:]][candidate.id] = label
            }
        }

        var binaryPairs: [(Bool, Bool)] = []
        var detailedDisagreements: [String] = []
        for candidate in manifest.candidateCorpus.candidates {
            guard let first = labelsByReviewerAndCandidate[aliases[0]]?[candidate.id],
                  let second = labelsByReviewerAndCandidate[aliases[1]]?[candidate.id]
            else { continue }
            binaryPairs.append((first.approvalEligible, second.approvalEligible))
            if first.status != second.status || first.approvalEligible != second.approvalEligible {
                detailedDisagreements.append(candidate.id)
            }
        }

        let binaryAgreementCount = binaryPairs.filter { $0.0 == $0.1 }.count
        let binaryDisagreementCount = binaryPairs.count - binaryAgreementCount
        let kappa = issues.isEmpty && binaryPairs.count == manifest.candidateCorpus.candidates.count
            ? cohensKappa(binaryPairs)
            : nil
        if issues.isEmpty && kappa == nil {
            issues.append("Cohen's kappa is undefined because both reviewers used only one binary class")
        }
        let primaryAliasSet = Set(aliases)
        let adjudicatorAliases = Set(manifest.assignments.map(\.reviewerAlias))
            .subtracting(primaryAliasSet)
        let adjudicatorAlias = adjudicatorAliases.count == 1 ? adjudicatorAliases.first : nil
        if adjudicatorAlias == nil {
            issues.append("manifest does not identify exactly one distinct adjudicator")
        }
        let disagreementSet = Set(detailedDisagreements)
        let adjudicationAssignmentIDs = manifest.assignments.compactMap { assignment -> String? in
            guard assignment.reviewerAlias == adjudicatorAlias,
                  disagreementSet.contains(assignment.candidateID)
            else { return nil }
            return assignment.assignmentID
        }.sorted()

        return AnnotationAuditReport(
            corpusVersion: manifest.candidateCorpus.version,
            reviewerAliases: aliases,
            candidateCount: manifest.candidateCorpus.candidates.count,
            binaryAgreementCount: binaryAgreementCount,
            binaryDisagreementCount: binaryDisagreementCount,
            detailedDisagreementCandidateIDs: detailedDisagreements.sorted(),
            adjudicatorAlias: adjudicatorAlias,
            adjudicationAssignmentIDs: adjudicationAssignmentIDs,
            binaryLabelAgreement: kappa,
            issues: issues
        )
    }

    /// Resolves detailed disagreements with a third, previously sealed reviewer
    /// submission and emits gold labels without copying the private audit trail
    /// into the public benchmark corpus.
    public func finalize(
        manifest: AnnotationCoordinatorManifest,
        primarySubmissions: [AnnotationSubmission],
        adjudicationSubmission: AnnotationSubmission,
        origin: BenchmarkCorpusMetadata.Origin,
        split: BenchmarkCorpusMetadata.Split
    ) throws -> BenchmarkCorpus {
        let audit = audit(manifest: manifest, primarySubmissions: primarySubmissions)
        guard audit.issues.isEmpty, let kappa = audit.binaryLabelAgreement else {
            throw AnnotationWorkflowError.invalidSubmissions(audit.issues)
        }
        guard kappa >= 0.80 else {
            throw AnnotationWorkflowError.invalidSubmissions([
                "pre-adjudication Cohen's kappa \(kappa) is below 0.80",
            ])
        }
        let primaryAliases = Set(primarySubmissions.map(\.reviewerAlias))
        guard !primaryAliases.contains(adjudicationSubmission.reviewerAlias) else {
            throw AnnotationWorkflowError.invalidReviewers("adjudicator must be distinct from primary reviewers")
        }
        guard adjudicationSubmission.corpusVersion == manifest.candidateCorpus.version,
              adjudicationSubmission.annotationPolicyVersion == manifest.candidateCorpus.annotationPolicyVersion
        else {
            throw AnnotationWorkflowError.invalidSubmissions([
                "adjudication submission has the wrong corpus or annotation policy version",
            ])
        }

        let candidatesByID = firstValues(manifest.candidateCorpus.candidates, keyedBy: \.id)
        let assignmentsByID = firstValues(manifest.assignments, keyedBy: \.assignmentID)
        var primaryLabels: [String: [AnnotationLabel]] = [:]
        for submission in primarySubmissions {
            for label in submission.responses {
                guard let assignment = assignmentsByID[label.assignmentID] else { continue }
                primaryLabels[assignment.candidateID, default: []].append(label)
            }
        }

        let disagreementIDs = Set(audit.detailedDisagreementCandidateIDs)
        var adjudicatedLabels: [String: AnnotationLabel] = [:]
        var adjudicationIssues: [String] = []
        for label in adjudicationSubmission.responses {
            guard let assignment = assignmentsByID[label.assignmentID],
                  assignment.reviewerAlias == adjudicationSubmission.reviewerAlias,
                  let candidate = candidatesByID[assignment.candidateID]
            else {
                adjudicationIssues.append("adjudication contains an unknown assignment")
                continue
            }
            guard disagreementIDs.contains(candidate.id) else {
                adjudicationIssues.append("adjudication includes non-disputed candidate \(candidate.id)")
                continue
            }
            adjudicationIssues.append(contentsOf: validate(
                label: label,
                candidate: candidate,
                reviewerAlias: adjudicationSubmission.reviewerAlias
            ))
            if adjudicatedLabels[candidate.id] != nil {
                adjudicationIssues.append("adjudication contains duplicate response for \(candidate.id)")
            }
            adjudicatedLabels[candidate.id] = label
        }
        let missingAdjudications = disagreementIDs.subtracting(adjudicatedLabels.keys)
        if !missingAdjudications.isEmpty {
            adjudicationIssues.append("adjudication is missing \(missingAdjudications.count) disputed candidates")
        }
        guard adjudicationIssues.isEmpty else {
            throw AnnotationWorkflowError.invalidSubmissions(adjudicationIssues)
        }

        let claimCases = try manifest.candidateCorpus.candidates.map { candidate in
            let label: AnnotationLabel
            if disagreementIDs.contains(candidate.id) {
                guard let adjudicated = adjudicatedLabels[candidate.id] else {
                    throw AnnotationWorkflowError.invalidSubmissions([
                        "missing adjudicated label for \(candidate.id)",
                    ])
                }
                label = adjudicated
            } else {
                guard let agreed = primaryLabels[candidate.id]?.first else {
                    throw AnnotationWorkflowError.invalidSubmissions([
                        "missing primary label for \(candidate.id)",
                    ])
                }
                label = agreed
            }
            return ClaimBenchmarkCase(
                id: candidate.id,
                category: category(for: label.status),
                claimText: candidate.claimText,
                claimType: candidate.claimType,
                evidence: candidate.evidence,
                expectedStatus: label.status,
                rationale: label.rationale,
                matterID: candidate.matterID,
                challengeTags: candidate.challengeTags,
                goldEvidenceSpans: label.evidenceSpans.isEmpty ? nil : label.evidenceSpans
            )
        }

        return BenchmarkCorpus(
            version: manifest.candidateCorpus.version,
            name: manifest.candidateCorpus.name,
            metadata: BenchmarkCorpusMetadata(
                origin: origin,
                split: split,
                independentlyLabeled: true,
                annotatorsPerClaim: 2,
                binaryLabelAgreement: kappa,
                annotationPolicyVersion: manifest.candidateCorpus.annotationPolicyVersion
            ),
            claimCases: claimCases,
            extractionCases: []
        )
    }

    private func validate(
        label: AnnotationLabel,
        candidate: AnnotationCandidate,
        reviewerAlias: String
    ) -> [String] {
        let prefix = "reviewer \(reviewerAlias), candidate \(candidate.id)"
        var issues: [String] = []
        let shouldApprove = label.status == .directlySupported || label.status == .supportedByInference
        if label.approvalEligible != shouldApprove {
            issues.append("\(prefix) has an approval/status mismatch")
        }
        if label.rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("\(prefix) has no rationale")
        }
        let requiresGoldEvidence = shouldApprove || label.status == .contradicted
        if requiresGoldEvidence && label.evidenceSpans.isEmpty {
            issues.append("\(prefix) requires at least one exact evidence span")
        }
        let evidenceByID = firstValues(candidate.evidence, keyedBy: \.id)
        for span in label.evidenceSpans {
            guard let passage = evidenceByID[span.evidenceID] else {
                issues.append("\(prefix) cites unknown evidence \(span.evidenceID)")
                continue
            }
            if span.exactQuote.isEmpty || !containsExactUTF8(text: passage.text, quote: span.exactQuote) {
                issues.append("\(prefix) contains a non-byte-present evidence quote")
            }
            if (span.startUTF16 == nil) != (span.endUTF16 == nil) {
                issues.append("\(prefix) provides only one UTF-16 span boundary")
            } else if let start = span.startUTF16, let end = span.endUTF16,
                      !matchesUTF16Span(text: passage.text, quote: span.exactQuote, start: start, end: end)
            {
                issues.append("\(prefix) has incorrect UTF-16 evidence boundaries")
            }
        }
        return issues
    }

    private func cohensKappa(_ pairs: [(Bool, Bool)]) -> Double? {
        guard !pairs.isEmpty else { return nil }
        let count = Double(pairs.count)
        let observed = Double(pairs.filter { $0.0 == $0.1 }.count) / count
        let firstApproval = Double(pairs.filter(\.0).count) / count
        let secondApproval = Double(pairs.filter(\.1).count) / count
        let expected = firstApproval * secondApproval +
            (1 - firstApproval) * (1 - secondApproval)
        guard expected < 1 else { return nil }
        return (observed - expected) / (1 - expected)
    }

    private func matchesUTF16Span(
        text: String,
        quote: String,
        start: Int,
        end: Int
    ) -> Bool {
        guard start >= 0, end >= start else { return false }
        let units = Array(text.utf16)
        guard end <= units.count else { return false }
        return Array(units[start..<end]) == Array(quote.utf16)
    }

    private func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
        }
    }

    private func containsExactUTF8(text: String, quote: String) -> Bool {
        guard !quote.isEmpty else { return false }
        return Data(text.utf8).range(of: Data(quote.utf8)) != nil
    }

    private func firstValues<Value>(
        _ values: [Value],
        keyedBy keyPath: KeyPath<Value, String>
    ) -> [String: Value] {
        var result: [String: Value] = [:]
        for value in values where result[value[keyPath: keyPath]] == nil {
            result[value[keyPath: keyPath]] = value
        }
        return result
    }

    private func category(for status: SupportStatus) -> ClaimBenchmarkCase.Category {
        switch status {
        case .directlySupported:
            return .directSupport
        case .supportedByInference:
            return .reasonableInference
        case .partiallySupported:
            return .partialSupport
        case .contradicted:
            return .contradiction
        case .ambiguous, .notVerifiable:
            return .notVerifiable
        case .unsupported:
            return .unsupported
        }
    }
}
