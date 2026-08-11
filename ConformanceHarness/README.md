# Claim Proof Specification conformance harness

This package proves that the live ClaimProofKit implementation matches the
frozen golden vectors in `vectors/`, and that the `ClaimProofProvenance`
bridge output ingests seamlessly into the **real DProvenanceKit package**
(fetched from its published tag, not a local mirror).

The design mirrors DProvenanceKit's own `ConformanceHarness`: golden vectors
lock the behavior, and CI fails on any drift. ClaimProofKit is the reference
implementation of Claim Proof Specification v1, so vectors are generated here
rather than vendored from another repository. The Python implementation
(`ClaimProofKitPython`) vendors these files via its `conformance/sync-vectors.sh`
and proves byte-exact parity against them in its own CI — after regenerating
vectors here, re-sync them there.

## What the vectors lock

| Vector | Locks |
| --- | --- |
| `claim_fingerprint.json` | FNV-1a 64-bit claim fingerprint (case-folded input, unpadded lowercase hex) |
| `policy_fingerprint.json` | SHA-256 policy identity over the frozen key:value listing |
| `report_fingerprint.json` | SHA-256 report identity (`cpk:v1:report:` domain, verdict order-sensitive) |
| `verdict_semantics.json` | Baseline lexical verifier verdicts under the default policy |
| `provenance_bridge.json` | DProvenanceKit interchange: event vocabulary, canonical payload bytes (Trace Spec v1 §2), run fingerprint (§5), lineage edges |

## Run

```sh
cd ConformanceHarness
swift run ConformanceHarness            # verify (exit 0 pass, 1 fail)
./regenerate-vectors.sh                 # intentionally re-lock after a spec change
```

The live round-trip additionally proves, against the actual DProvenanceKit
package: bridge JSON decodes as `[TraceEvent<AnyTraceableEvent>]`, recording
those payloads through a real `SQLiteTraceStore` reproduces the bridge's run
fingerprint byte-for-byte, and edges/sequences read back intact from a store.

## WebAssembly

The vector checks (sections [1]–[5]) live in the main package's
`ClaimProofConformance` library; this harness and the `ConformanceVectors`
runner both execute that same code, so the two cannot drift. CI additionally
builds the runner for `wasm32-wasip1` and executes it under WasmKit against
these vectors, byte-locking wasm behavior — the swift-crypto hashing and
hand-rolled scanner paths that never run on a macOS host. From the repository
root:

```sh
swift build -c release --swift-sdk <wasm-sdk-id> --product ConformanceVectors
wasmkit run --dir "$PWD/ConformanceHarness/vectors" \
  .build/wasm32-unknown-wasip1/release/ConformanceVectors.wasm \
  "$PWD/ConformanceHarness/vectors"
```

The DProvenanceKit round-trip stays native-only (SQLite does not exist on
wasm); interchange parity is host-independent wire format, proven once here.

## Changing locked behavior

Any intentional change to fingerprints, canonical encoding, verifier verdict
semantics, or the bridge vocabulary requires bumping the spec or verifier
version in `ClaimProofSpec` (see `Docs/PROOF_SPEC_V1.md`), regenerating, and
reviewing the vector diff in the commit.
