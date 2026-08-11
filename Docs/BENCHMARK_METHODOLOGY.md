# Benchmark methodology

Benchmark v0.1 is an authored development corpus for evidence-bound legal verification. It is a regression baseline, not evidence of performance on real legal matters and not a universal truth-detection benchmark.

## Safety priority

An approved verdict is `directlySupported` or `supportedByInference`. A dangerous approval occurs when the verifier predicts either approved verdict for a case whose gold label is anything else. The v0.1 gate permits zero dangerous approvals.

The remaining thresholds prevent a verifier from appearing safe merely by rejecting everything:

- Verdict accuracy: at least 70%
- Contradiction recall: at least 80%
- Atomic-extraction precision: at least 80%
- Atomic-extraction recall: at least 80%

A corpus containing no unsafe-expected cases fails the gate outright: it cannot measure false approvals, so it must not pass vacuously.

## Regression gate vs ship criteria vs production release gate

The report carries two verdicts with different jobs:

- **`passesSafetyGate`** is the regression gate. It protects against getting worse and is what CI (and benchmark exit code 3) keys off.
- **`meetsShipCriteria`** is the feature go/no-go bar: supported-claim precision ≥ 95% and unsupported/contradicted recall ≥ 90%. Meeting it on this authored corpus is necessary but NOT sufficient — the same bar must be met on independently labeled, realistic documents before the verifier faces users, and no automatic export block should be enabled until real-world false-positive rates are known.
- **`passesProductionReleaseGate`** is the high-stakes release bar enforced by
  `claimproof benchmark <corpus> --release`. It requires a sealed,
  independently labeled realistic corpus, zero dangerous approvals, a one-sided
  95% false-green upper bound no greater than 1%, enough approval and rejection
  examples to prevent vacuous success, matter breadth, reviewer reliability,
  exact adjudicated evidence spans, and hard-negative challenge coverage. See
  [Realistic legal benchmark protocol](REALISTIC_BENCHMARK_PROTOCOL.md).

## Per-class metrics

Aggregate accuracy can flatter a lazy classifier (a verifier that approves everything scores whatever fraction of claims happen to be supported). The report therefore measures the binary safe/unsafe decision separately:

- **Supported-claim precision** — of claims the verifier approved, how many deserved approval ("verified means verified").
- **Unsupported/contradicted recall** — of unsafe claims, how many were caught rather than approved (complement of the false-supported rate).
- **Warning precision** — of flagged claims, how many deserved a flag. This is the alarm-fatigue number: a flag on a deserving claim counts as legitimate even when the exact status label differs.
- **Abstention precision/recall** — whether `notVerifiable`/`ambiguous` verdicts land where uncertainty genuinely exists, instead of the verifier inventing certainty.
- **Per-status precision/recall** and **per-category outcomes** — so a class the verifier cannot handle (for example, `reasonableInference` under the lexical baseline) is visible instead of averaged away.
- **Calibration** — confidence bucketed into five bins with per-bin accuracy and an expected calibration error. Until confidence semantics are made consistent, expect visible miscalibration here; the metric exists to keep that honest.

## Corpus coverage

The corpus contains claim-level cases for direct support, reasonable inference, partial support, contradiction, unsupported assertions, citation integrity, source authority, and non-verifiable content. Extraction cases cover simple statements, multiple sentences, compound clauses, questions, disclaimers, and short non-claim headings.

## Known limitations

- The examples are synthetic and authored by the project, not independently labeled.
- Extraction examples are intentionally small and linguistically simple.
- The baseline verifier is lexical and deterministic; it does not perform general semantic entailment.
- The corpus does not establish jurisdictional legal correctness or source currency.
- Exact accuracy is not comparable to unrelated benchmarks with different labels or evidence policies.

Before any production export gate is enabled, the corpus must add independently reviewed, de-identified examples from realistic workflows and report per-category confidence intervals and adjudicator agreement.

The production release gate now enforces the measurable portion of that
requirement. Building and independently labeling the realistic corpus remains a
separate human evidence-collection task; synthetic fixtures cannot satisfy the
gate by declaring themselves release-ready.

## Reproduce

```sh
swift run claimproof benchmark Fixtures/benchmark-v0.1.json
swift run claimproof benchmark Fixtures/benchmark-v0.1.json --json
swift run claimproof benchmark /path/to/sealed-corpus.json --release
bash scripts/check-benchmark-report.sh
```
