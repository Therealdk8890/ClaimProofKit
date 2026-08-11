# ClaimProofKit

ClaimProofKit is a local-first Swift library that checks whether material claims in a generated document are supported by supplied evidence passages.

ClaimProofKit is source-available under the [Business Source License 1.1](LICENSE). Non-production evaluation, development, testing, and personal study are permitted. Production use requires a separate commercial license until the Change Date, when that version converts to Apache 2.0. See [Commercial licensing](COMMERCIAL_LICENSING.md) and the [product boundary](PRODUCT_BOUNDARY.md). Hosted, enterprise, governance, and managed-service implementations are developed separately in ClaimProofCloud.

This first vertical slice deliberately uses a deterministic lexical verifier. It is inspectable, runs without an API key, and establishes the report contract that future semantic and domain-specific verifiers can implement. It is not yet suitable as the sole accuracy gate for legal, medical, or financial content.

## Run the proof gate

```sh
swift test
swift run claimproof Fixtures/legal-demo.json
swift run claimproof benchmark Fixtures/benchmark-v0.1.json
```

The CLI exits with status `0` only when every extracted claim is supported. A blocked report exits with status `2`, which makes it usable as a CI gate.

The benchmark command exits with status `0` when the versioned regression thresholds pass and `3` when they fail. Add `--json` for a machine-readable report. Benchmark v0.1 measures verdict accuracy, false-supported rate, contradiction recall, and atomic-extraction precision and recall. The safety gate permits no falsely approved unsafe claims.

The current reproducible baseline and its limitations are documented in [Benchmark v0.1](Docs/BENCHMARK_V0.1.md) and [Benchmark methodology](Docs/BENCHMARK_METHODOLOGY.md). These are development-corpus results, not claims of accuracy on real legal matters.

Production release candidates use a separate, opt-in statistical gate over a
sealed, independently labeled realistic corpus. The collection, annotation,
privacy, hard-negative, and reviewer-reliability requirements are defined in
[the realistic legal benchmark protocol](Docs/REALISTIC_BENCHMARK_PROTOCOL.md):

```sh
swift run claimproof benchmark /path/to/sealed-corpus.json --release
```

The repository also provides an executable human-labeling workflow. It validates
the private evidence-source ledger, creates separately keyed blind packets for
two primary reviewers and a third adjudicator, verifies exact evidence quotes,
calculates pre-adjudication Cohen's kappa, and emits the adjudicated benchmark
corpus:

```sh
swift run claimproof annotation prepare candidates.json source-ledger.json annotation-run \
  --reviewer reviewer-a --reviewer reviewer-b --reviewer adjudicator
swift run claimproof annotation audit annotation-run/coordinator-manifest.json \
  annotation-run/reviewer-a-submission.json annotation-run/reviewer-b-submission.json
```

See [Human evidence collection and independent labeling](Docs/HUMAN_ANNOTATION_WORKFLOW.md)
and [Legal evidence annotation policy v1](Docs/LEGAL_ANNOTATION_POLICY_V1.md).

## Locked parity: Claim Proof Specification v1

Every identity algorithm and the baseline verifier's verdict semantics are frozen by [Claim Proof Specification v1](Docs/PROOF_SPEC_V1.md) and locked by golden vectors under `ConformanceHarness/vectors/`, in the same style as DProvenanceKit's conformance harness. Claims carry FNV-1a fingerprints, evidence passages carry byte-exact SHA-256 content fingerprints, and every report and policy has a stable SHA-256 identity. CI fails on any drift:

```sh
cd ConformanceHarness
swift run ConformanceHarness
```

## Working with DProvenanceKit

`ClaimProofProvenance` exports a verification run as a [DProvenanceKit](https://github.com/Therealdk8890/DProvenanceKit)-compatible trace — claim extraction and verdict events with `verifiedBy`/`derivedFrom` lineage, terminated by a report event carrying the report and policy fingerprints:

```sh
swift run claimproof verify Fixtures/legal-demo.json --provenance trace.json
```

```swift
import ClaimProofProvenance

let trace = try ProvenanceExporter().trace(for: report, policy: policy)
try trace.eventsJSONData()   // decodes as [TraceEvent<AnyTraceableEvent>] in DProvenanceKit
```

The CLI writes the full manifest (versions, fingerprints, events, edges); its
`events` field is the array that decodes directly in DProvenanceKit.

The bridge takes no dependency on DProvenanceKit; wire parity is proved in CI by round-tripping through the real package — the emitted JSON decodes natively, and DProvenanceKit's own store reproduces the bridge's Trace Specification v1 §5 run fingerprint byte-for-byte.

## Initial architecture

- `ClaimExtractor` identifies reviewable statements, decomposes simple compound sentences, classifies claim type, and preserves source ranges.
- `ClaimVerifier` applies claim-aware source rules and returns direct support, inferred support, partial support, contradiction, ambiguity, unsupported, or not-verifiable.
- `VerificationPipeline` composes public extraction, retrieval, entailment, proof-policy, and TrustReport protocols so local or external verifiers can be substituted without changing the report contract.
- `BM25TopKRetriever` ranks large evidence corpora per claim with deterministic tie-breaking, replacing the passthrough retriever for real records.
- `ProofReport` is the stable machine-readable artifact.
- `ReportRenderer` creates a human-reviewable Markdown report with exact evidence passages.
- `ClaimProofBridge` is a JSON-in/JSON-out boundary over the pipeline for hosts that cannot bind Swift types (a wasm module driven from JavaScript, an FFI caller).
- `ClaimProofWasm` exposes the bridge as a C-ABI WebAssembly reactor: `cpk_verify`, `cpk_passage_fingerprint`, `cpk_claim_fingerprint` (so hosts never reimplement a frozen identity algorithm), and `cpk_malloc`/`cpk_free` for buffer ownership. `cpk_abi_version` versions the contract — hosts should check it at load time and refuse a module they do not recognize.

The library targets build for WebAssembly (`wasm32-wasi`), and CI executes the conformance vectors inside a wasm module under [WasmKit](https://github.com/swiftwasm/WasmKit) — wasm behavior is byte-locked, not just compiled: identity hashing falls back from CryptoKit to [swift-crypto](https://github.com/apple/swift-crypto) off Apple platforms, and extraction uses a hand-rolled UTF-16 scanner whose ICU parity is locked by differential tests and the conformance vectors.

Material edits change a claim fingerprint, invalidating any proof attached to the previous wording. The current extractor and lexical verifier are intentionally conservative baselines; they are not presented as complete legal-language understanding or semantic entailment.

## Next accuracy milestone

Replace the lexical verifier with a pluggable verification pipeline combining deterministic checks, retrieval, semantic entailment, citations, and calibrated human review. Every verifier must be measured against a versioned legal claim/evidence corpus before it can participate in the publish gate.
