# Claim Proof Specification v1

This document freezes the identity algorithms, canonical encodings, and
DProvenanceKit interchange contract of ClaimProofKit. Every rule below is
locked by a golden vector under `ConformanceHarness/vectors/` and enforced in
CI; the harness also proves the interchange against the real DProvenanceKit
package. The structure deliberately mirrors DProvenanceKit's Trace
Specification v1 so the two kits stay in lockstep.

Version: `ClaimProofSpec.version = "1.0"` · Verifier: `cpk-lexical` v1.0

## §1 Claim fingerprint

FNV-1a 64-bit over the UTF-8 bytes of the **lowercased** claim text
(offset basis `14695981039346656037`, prime `1099511628211`), rendered as
**unpadded** lowercase hex. Material edits to a claim change its fingerprint
and invalidate any prior proof.

Known property: case-only edits do **not** change the fingerprint (input is
case-folded). Evidence identity (§5) is byte-exact by contrast.

Locked by `claim_fingerprint.json`.

## §2 Canonical payload encoding

Identical to DProvenanceKit Trace Specification v1 §2: JSON with **sorted
keys**, UTF-8. Payloads carry no timestamps — the envelope owns time.
Floating-point values use Foundation's shortest round-trip rendering; the
bridge vector includes a non-terminating binary value (`2/3`) to lock that
formatting.

Locked by the `rawJSON` strings in `provenance_bridge.json`.

## §3 Report fingerprint

SHA-256 (lowercase hex) over the domain-separated string:

```
"cpk:v1:report:" + concat( claim.fingerprint + ":" + status.rawValue + "|"  per verdict, in report order )
```

Two reports share a fingerprint exactly when they verify the same claim
wording (case-folded, per §1) to the same verdicts in the same order.
Timestamps, confidence values, and evidence excerpts do not participate.

Locked by `report_fingerprint.json`.

## §4 Policy fingerprint

SHA-256 (lowercase hex) over a frozen newline-delimited listing, in exactly
this order and with default Swift number interpolation:

```
specVersion:1.0
verifier:cpk-lexical
verifierVersion:1.0
supportedThreshold:<Double>
ambiguousThreshold:<Double>
contradictionThreshold:<Double>
maximumEvidenceMatches:<Int>
```

Locked by `policy_fingerprint.json`.

## §5 Evidence content fingerprint

SHA-256 (lowercase hex) over the **exact** UTF-8 bytes of the passage text.
No normalization: any byte-level edit changes the identity.

Exercised via `evidenceFingerprints` in `provenance_bridge.json`.

## §6 Verdict semantics

The verdicts of the baseline lexical verifier under the default policy are
part of the locked surface: eight canonical cases pin direct support,
polarity contradiction, unsupported assertion, partial support,
non-verifiable recommendations, source-authority rejection, speculative
evidence rejection, and structured-value contradiction. Evidence ranking
ties break deterministically by ascending passage id under Swift `String`
ordering (lexicographic over Unicode canonical form, so `"p10" < "p2"`);
passage ids are assumed unique within a verification.

Locked by `verdict_semantics.json`.

## §7 DProvenanceKit interchange (bridge)

`ClaimProofProvenance` emits envelopes wire-compatible with DProvenanceKit's
`TraceEvent<AnyTraceableEvent>`, without depending on DProvenanceKit. Parity
is enforced by the conformance harness round-trip against the published
package.

**Vocabulary** (stable `typeIdentifier`s, never renamed):

| Event | Priority | Payload keys |
| --- | --- | --- |
| `cpk_claim_extracted` | structural (2) | `claimID`, `claimType`, `fingerprint`, `text` |
| `cpk_claim_verified` | critical (3) | `claimFingerprint`, `status`, `confidence`, `evidenceFingerprints` |
| `cpk_report_finalized` | critical (3) | `reportFingerprint`, `policyFingerprint`, `specVersion`, `safeToPublish`, `statusCounts` |

**Order:** per claim in report order, `cpk_claim_extracted` then
`cpk_claim_verified`; a single `cpk_report_finalized` terminates the run.

**Edges:** `extracted --verifiedBy--> verified` per claim and
`verified --derivedFrom--> report_finalized`. When attaching a verification
to an existing host run, record the ClaimProof events with
`record(_:derivedFrom:type:)` using `.verifiedBy` from the event being
verified. (Note: DProvenanceKit's `explain()` narrates `informed`/
`derivedFrom` edges only; `verifiedBy` edges appear in `lineage`/`impact`.)

**Run fingerprint:** Trace Specification v1 §5 — SHA-1 (lowercase hex) over
`concat( typeIdentifier + ":" + engineName + "|" per event in commit order )`.
The bridge computes it eagerly; recording the same payload sequence through a
DProvenanceKit store reproduces it exactly (proved in CI).

Locked by `provenance_bridge.json`.

## Versioning rules

- Any change to §1–§7 behavior requires bumping `ClaimProofSpec.version`
  (or `verifierVersion` for §6-only changes), regenerating vectors with
  `ConformanceHarness/regenerate-vectors.sh`, and reviewing the diff.
- `typeIdentifier` strings are append-only: new event types may be added;
  existing ones are never renamed or repurposed.
- The bridge tracks DProvenanceKit's published interchange surface
  (`TraceEvent`, `AnyTraceableEvent`, `TraceEdge` — stable since 0.3.0). If
  DProvenanceKit ships Trace Specification v2, the bridge gains a new
  emission mode rather than mutating v1 output.
