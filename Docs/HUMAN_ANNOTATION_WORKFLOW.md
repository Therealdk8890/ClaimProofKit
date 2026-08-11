# Human evidence collection and independent labeling

ClaimProofKit can enforce an independent human workflow; it cannot turn an AI
or one operator into two independent human reviewers. This workflow keeps the
human boundary explicit and auditable.

## 1. Collect and clear evidence

Start from
[`evidence-source-ledger-template.json`](evidence-source-ledger-template.json)
and [`annotation-candidates-template.json`](annotation-candidates-template.json).
Keep the completed source ledger private.

For every source:

1. record the canonical source and retrieval date;
2. preserve a SHA-256 digest of the exact collected artifact;
3. document the legal/authorization basis for use and redistribution;
4. reject privileged, sealed, confidential, or restricted material;
5. remove direct personal identifiers from reviewer-visible text; and
6. obtain second-person de-identification review for authorized real workflow
   material.

On macOS, calculate an artifact digest with:

```sh
shasum -a 256 /path/to/source-file
```

Use opaque matter, source, passage, and candidate IDs. Each candidate contains
the full realistic evidence packet, including relevant conflicts and
distractors, rather than a single hand-selected sentence. Map every evidence
passage ID to exactly one private source-ledger record with
`evidenceSourceRecordIDs`; source type and matter ID must agree.

## 2. Prepare blinded packets

Use two primary reviewer aliases and one distinct adjudicator alias. Aliases
should not contain names or email addresses.

```sh
swift run claimproof annotation prepare \
  /private/path/annotation-candidates.json \
  /private/path/evidence-source-ledger.json \
  /private/path/annotation-run \
  --reviewer reviewer-a \
  --reviewer reviewer-b \
  --reviewer adjudicator
```

The command refuses invalid source provenance, pending de-identification,
personal identifiers, restricted material, duplicate IDs, missing evidence,
or uncleared redistribution. It writes:

- a private `coordinator-manifest.json`;
- one independently ordered packet per reviewer; and
- one response template per reviewer.

Give each primary reviewer only their packet, their response template, and
[`LEGAL_ANNOTATION_POLICY_V1.md`](LEGAL_ANNOTATION_POLICY_V1.md). Do not expose
the source ledger, coordinator manifest, other packets, expected labels, model
predictions, challenge tags, or benchmark categories. Keep the adjudicator
packet sealed.

## 3. Collect primary labels

Each reviewer replaces every `null` in their submission template with:

- the binary `approvalEligible` decision;
- one detailed `status`;
- a short, load-bearing `rationale`; and
- exact evidence spans when the policy requires them.

Do not transform submissions with an AI. Store the two original files before
running any comparison.

## 4. Audit pre-adjudication agreement

```sh
swift run claimproof annotation audit \
  /private/path/annotation-run/coordinator-manifest.json \
  /private/path/annotation-run/reviewer-a-submission.json \
  /private/path/annotation-run/reviewer-b-submission.json
```

The audit fails on incomplete assignments, reviewer reuse, policy/version
drift, approval/status mismatch, fabricated quotes, invalid offsets, or Cohen's
kappa below 0.80. Its disagreement section lists only the assignment IDs the
sealed adjudicator must complete.

## 5. Adjudicate and finalize

Give the third reviewer their sealed packet and a submission file containing
only the assignment IDs listed by the audit. Do not show either primary label
or an engine result. Then finalize to `validation` (the safe default):

```sh
swift run claimproof annotation finalize \
  /private/path/annotation-run/coordinator-manifest.json \
  /private/path/annotation-run/reviewer-a-submission.json \
  /private/path/annotation-run/reviewer-b-submission.json \
  /private/path/annotation-run/adjudicator-submission.json \
  /private/path/legal-validation-v1.json
```

The emitted corpus contains adjudicated gold labels and Cohen's kappa, but not
reviewer aliases, source URLs, or original submissions. Select
`--split sealedHoldout` only for a genuinely sealed, matter-disjoint corpus
that has never been used for rule, prompt, or threshold tuning.

Finally run:

```sh
swift run claimproof benchmark /private/path/legal-validation-v1.json
swift run claimproof benchmark /private/path/legal-holdout-v1.json --release
```

The current workflow finalizes claim-verdict cases. Extraction cases still
require a separate two-reviewer span/claim audit before they may count toward
the release gate.
