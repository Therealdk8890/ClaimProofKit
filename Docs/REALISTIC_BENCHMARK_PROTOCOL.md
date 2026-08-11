# Realistic legal benchmark protocol

This protocol defines the evidence required before ClaimProofKit may pass the
production release gate. It complements the authored `benchmark-v0.1.json`
regression fixture; it does not replace that fast deterministic check.

## Meaning of a green verdict

The benchmark is evidence-bound. `directlySupported` or
`supportedByInference` means the supplied record supports every material part
of the claim. It does **not** mean the claim is objectively true, legally
correct, current law, or suitable for filing without attorney review.

A claim is not approval-eligible if any material element is absent, conflicting,
or supplied by the wrong authority, including:

- actor or entity;
- event, amount, date, duration, or location;
- negation, modality, condition, or procedural disposition;
- attributed quotation;
- every material component of a compound claim; or
- controlling authority for a legal-rule claim.

Any prediction of an approved verdict for a non-approvable gold claim is a
**dangerous approval** (false green) and fails the release gate.

## Corpus sources and privacy

Use only:

1. public court records whose reuse is permitted;
2. de-identified real workflow material with documented authorization; or
3. realistic mixed packets built from those sources without inventing labels.

Never place privileged, sealed, confidential, or personally identifying client
material in the repository. De-identification must be reviewed by a human other
than the person who performed it. Preserve a private source ledger containing
matter provenance and authorization; the public benchmark uses opaque matter
IDs and contains no contact information.

## Matter sampling

The first release corpus must contain at least 50 independent matters and
should cover multiple workflows rather than 50 variations of one form:

- landlord–tenant;
- consumer debt;
- contract disputes;
- employment;
- personal injury;
- family-law procedure; and
- motions, declarations, responses, and proposed orders.

Supply the full evidence packet available to the reviewer, including realistic
distractors and conflicts. Do not hand the verifier a single curated passage.
Include emails, declarations, contracts, invoices, docket entries, orders,
transcripts, tables, OCR artifacts, duplicate boilerplate, and irrelevant
records where authorized.

Split by `matterID`, never by claim. No matter, near-duplicate filing, or
mutation family may cross development, validation, and sealed-holdout splits.
The sealed holdout is not inspected for rule or prompt tuning.

## Hard-negative coverage

Create minimal, legally plausible mutations from real supported sentences.
Change one load-bearing element while keeping surrounding language constant.
The release gate requires at least 20 cases for each canonical tag:

- `actor`
- `amount`
- `compoundClaim`
- `date`
- `modality`
- `negation`
- `quotation`
- `sourceAuthority`

Examples include changing `May 4` to `May 5`, `granted` to `denied`, `sent` to
`received`, `$14,600` to `$146,000`, or a party name while retaining all other
words. Mutations must be labeled from the supplied record, not assumed unsafe
merely because they were generated.

## Annotation workflow

1. A corpus coordinator extracts atomic factual/legal-rule claims and assigns
   opaque `matterID` values.
2. Two qualified reviewers independently label each claim without seeing the
   engine prediction or each other's label.
3. Each reviewer records the binary approval-eligible decision, detailed
   status, rationale, and exact supporting/contradicting evidence quote.
4. Disagreements are resolved by a third adjudicator. The adjudicated label is
   the gold label; original labels remain in the private audit ledger.
5. Calculate Cohen's kappa for two reviewers or Krippendorff's alpha for more
   than two on the pre-adjudication binary decision. Store that value in
   `binaryLabelAgreement`; raw percent agreement is not sufficient.

The release gate requires at least two reviewers per claim and reliability of
at least 0.80. Cases with unresolved policy ambiguity remain in development and
do not enter the sealed holdout.

## Gold evidence requirements

Approval-eligible and contradicted cases must include at least one
`goldEvidenceSpans` entry. Every `exactQuote` must be a byte-present substring
of the identified evidence passage. Unsupported claims may legitimately have
no gold span.

Example claim case:

```json
{
  "id": "matter-017-claim-004",
  "matterID": "matter-017",
  "category": "contradiction",
  "challengeTags": ["date"],
  "claimText": "The contract ended on May 5.",
  "claimType": "factual",
  "evidence": [
    {
      "id": "notice-3",
      "source": "Termination notice",
      "sourceType": "evidence",
      "text": "The contract ended on May 4."
    }
  ],
  "expectedStatus": "contradicted",
  "rationale": "The notice gives a different termination date.",
  "goldEvidenceSpans": [
    {
      "evidenceID": "notice-3",
      "exactQuote": "The contract ended on May 4."
    }
  ]
}
```

Corpus-level metadata:

```json
{
  "version": "legal-realistic-v1",
  "name": "Sealed evidence-bound legal holdout",
  "metadata": {
    "origin": "mixedRealistic",
    "split": "sealedHoldout",
    "independentlyLabeled": true,
    "annotatorsPerClaim": 2,
    "binaryLabelAgreement": 0.86,
    "annotationPolicyVersion": "legal-annotation/1"
  },
  "claimCases": [],
  "extractionCases": []
}
```

A complete, decodable development example is available at
[`realistic-benchmark-template.json`](realistic-benchmark-template.json). It is
deliberately too small and uses the `development` split, so it cannot pass the
production release gate.

The executable collection and labeling procedure, reviewer policy, and private
source-ledger templates are documented in
[`HUMAN_ANNOTATION_WORKFLOW.md`](HUMAN_ANNOTATION_WORKFLOW.md). Candidate public
datasets and their release-gate limitations are recorded in
[`PUBLIC_CORPUS_SOURCES.md`](PUBLIC_CORPUS_SOURCES.md).

## Release decision

The production gate requires all of the following:

| Requirement | Threshold |
| --- | ---: |
| Independent matters | at least 50 |
| Non-approvable gold claims | at least 300 |
| Approval-eligible gold claims | at least 100 |
| Dangerous approvals | exactly 0 |
| One-sided 95% false-green upper bound | at most 1% |
| Approval recall | at least 80% |
| Contradiction cases / recall | at least 50 / 95% |
| Extraction cases / recall | at least 50 / 98% |
| Warning precision | at least 80% |
| Reviewer reliability | at least 0.80 |

The false-green upper bound is exact on the zero-failure release path:
`1 - 0.05^(1/n)`. With 300 non-approvable cases and zero false greens, the
upper bound is approximately 0.994%.

Run the normal regression gate on every change:

```sh
swift run claimproof benchmark Fixtures/benchmark-v0.1.json
```

Run the sealed release gate only for a release candidate:

```sh
swift run claimproof benchmark /path/to/sealed-corpus.json --release
```

Exit code `3` means the selected gate failed. The report lists every production
blocker so a small or poorly labeled corpus cannot appear release-ready merely
because it observed zero false greens.

## Optional AI verifier

Benchmark AI-assisted upgrades separately from the deterministic baseline.
Pin the model, prompt, policy, and retrieval configuration; run every case
multiple times. A dangerous approval on any repetition fails that case. Report
the worst-run result rather than averaging a stochastic false green away.
