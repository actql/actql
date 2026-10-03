# Source INFER: installed public acceptance

Baseline: `b18632b65570713e36c0a83e8afd0063bc37a5c3` (main).
The common connection is already in main at
`f9e6dbe36d263ef7baf4799646a1c53ebca47df9`. This unit adds authored public
source acceptance and corrects the historical dependency status. It does not
change a common owner, ModelTask contract, runtime, wire format or contract pin.

## Existing meaning and independent expectations

[INFER KEEP/AS](../spec/query-text.md#infer-keep-source-projection) lowers to the
ordinary infer step, retained-input join and object projection. The existing
[independent complete Programs](../../spec/frontend/fixtures/infer-keep/)
are compared by `scripts/query-program.test.mjs`; they are not regenerated in
this unit. The earlier two-row/refusal expectations in that directory retain
their own `not_run` status; the corpus below does not relabel them as executed.

The new source is authored independently in
`scripts/fixtures/infer-source-expectation.mjs`:

```aql
SELECT DISTINCT 'ticket-1' AS id
|> EXTEND 'urgent' AS text
|> INFER `model-task:packed-risk.v1`
     ITEM KEY (id) INPUT (text = text)
     KEEP (id, text AS note) AS assessment
|> WHERE assessment.outcome = 'ok'
     AND assessment.value.risk = 'high'
```

The independent row is:

```json
[{"id":"ticket-1","note":"urgent","assessment":{"input_key":{"id":"ticket-1"},"outcome":"ok","value":{"reason":null,"risk":"high"}}}]
```

Only `text` is sent to the installed test ModelTask. DISTINCT proves the id
candidate key; ITEM KEY does not manufacture that proof. The model uses the
existing typed registration and request preflight operations. Its successful
value is a non-null closed object with nullable `reason`; non-success is a
typed null object, with the existing outcome enumeration. No paid model or
external service is called.

| Authored positive | Independent obligation |
|---|---|
| Minimal, omitted KEEP | Only assessment is visible; one Model call |
| KEEP/AS | Columns id, note, assessment in that order; one Model call |
| KEEP and nested WHERE | Ordinary nullable property expressions preserve the row |
| Nullable retained input | note is typed NULL; model receives JSON null |
| Empty input | Full declared schema, no rows and zero Model calls |
| Provider returns no response | failed:provider_error with typed NULL value |
| Failed nullable object projection | outcome remains failed:provider_error; risk is typed NULL |

`Result.describe()` is compared against fully authored contracts, including
closed-object shape, column order and nullability. Reading `rows()` must reach
`complete` on both empty and nonempty inputs. Re-reading, attaching and the same
request resubmission must retain the original Run and add no Model call.

Four separate refusals cover a dropped input, the removed pre-INFER alias, an
unproven ITEM KEY and a KEEP/result-name collision. Each checks a typed input
error, zero admitted Runs, zero Model calls and `lookupRequest: not_found`.
The older no-ModelTask Host corpus remains a missing-installation refusal,
rather than claiming that valid INFER syntax is inherently non-executable.

## Capture and replay

Each transport first exits its process at the existing `infer_capture_committed`
fault boundary, after exactly one physical Model call and before publication.
A fresh process restores that exact request, waits for its Named Result, and
compares the row and description again. It must make zero provider calls.
Every case owns fresh durable state. Earlier uncertain requests are not reused
or retried. The harness calls no replay-specific substitute executor.

## Verification scope

Selected diagnostics reused the immutable five-package installation produced
from `aa24b3f0c36fb643efafcc1a0e3206202db030be`, after checking its package
digests. Those runtime sources and the common connection are in this baseline.
These are old-source installed-runtime diagnostics, not a clean pack or CI
result for the new acceptance commit:

- Minimal source: Local and HTTPS Named Results, types, attach and resubmission.
- Abrupt capture and fresh-process replay: both transports, zero replay calls.
- Six positives and four refusals per transport through the selected matrix.
- Six further cases (minimal, empty and failed nullable projection in each
  transport) verify stream completion and the NULL property result. One bounded
  Node wrapper passed, approximately 15 seconds. Three earlier bounded wrappers
  passed the minimal, replay and remaining matrix boundaries.

An initial diagnostic incorrectly tried to obtain `schema_invalid` by returning
a malformed object through `clientProgramModelResponse`. That operation returns
only an admitted typed response or no response; the malformed object exercised
the latter path. The current fixture explicitly returns no response, and its
expected provider_error comes from the existing contract. This is a corrected
fixture stimulus, not a runtime patch or a schema-invalid acceptance claim.
The failed diagnostic and its state are preserved independently.

No full local Core, Client, native or proof suite was repeated. Syntax checks
and selected document-link checks supplement the diagnostics. These earlier
diagnostics are not relabelled as the subsequent exact-source CI result.

## Completed hosted acceptance

[PR #261](https://github.com/actql/actql/pull/261) submitted source
`1ba6c06670f991594a8404d7f61a28ab5bdb5789` passed
[automatic CI 37119634895](https://github.com/actql/actql/actions/runs/37119634895).
All required jobs succeeded; optional performance/probe jobs were skipped.
Its CI test-merge tree, `d7aa461e3a664fb2bce9680a36df935e2cbb2777`, is
identical to the submitted tree. The main merge is
`b7aa6cf21e45a086f32bcb6a480d8dfdde79d24f`.

The [packed Client job](https://github.com/actql/actql/actions/runs/37119634895/job/111193553513)
passed the seven positives and four typed refusals above on both installed
Local and HTTPS Hosts, including full descriptions, stream completion and
committed-capture recovery in a fresh process with zero Model redispatch.
The normally produced package artifact is `11271524947`, named
`actql-client-packages-37119634895-1-d7aa461e3a664fb2bce9680a36df935e2cbb2777`,
with digest
`sha256:6a1461f50b4366c07ba73b041ed0469e1a838d44f3ad37dd308f0bfcbdb2ec33`.
This is the selected source-free acceptance evidence; it is not a claim that
subsequent source changes, acquired-input text or all INFER outcomes passed.

## Reproduction and hosted registration

```sh
node scripts/test-packed-public-query.mjs --infer-source-only
```

Use a committed clean source and the existing pinned dependencies. Normal pack
builds the five public packages, or hosted CI verifies and consumes its immutable
same-source package artifact. The application runs outside the checkout with
no runtime MoonBit toolchain. The command keeps standard evidence and reclaims
its own installation; `--keep-artifacts` retains it for investigation.

Default `test-packed-public-query.mjs` includes this corpus using its existing
installation, TLS setup and command/tarball evidence. There is no new CI job,
second package producer or duplicate install for these cases. Existing narrow
selections exclude this corpus unless `--infer-source-only` is selected.

This closes only the selected source-free INFER/KEEP/AS acceptance obligations.
Acquired-input text INFER, all classified failure
outcomes, broader multirow combinations, real model services, Cloud and the full
new-Frontend migration remain separate evidence obligations. The remaining
Graph, Effect, VecA and TEA language migration is not declared complete here.
