# Pre-JOIN range properties in CTE continuations

Base: main `040eed2b1a11a3d1f7bae81b68d956d1017fac05`.
Status: limited compiler/checker, fixture checks and clean-source normal-pack
Local/HTTPS acceptance pass. Submitted-HEAD CI and content review remain separate.

## Fixed counterexample

```sql
WITH lefts AS (SELECT id, payload FROM objects),
     rights AS (SELECT id, other FROM others)
FROM lefts AS l
|> WHERE ((l)).payload.score > 15
|> JOIN rights AS r ON l.id = r.id MAX_OUTPUT_ROWS 12
|> SELECT l.id, r.other.score
|> ORDER BY id
```

The dotted `l.payload.score` control lowers and checks. The parenthesized
receiver fails lowering at main: initial selection 1/2, guard `run-FJ5ip4`,
focused evidence `focused-test-IUDq9D`. This is a compiler counterexample, not
a claimed published Run failure. Ordinary field access/range binding already
has a shared implementation; no new syntax or expression semantics is needed.

The pre-JOIN WHERE is held in `JoinPart.pre_join_filter`, outside the query's
continuation-operation list. CTE specialization uses a property lowerer without
range-receiver binding there. `join_requires_group_scope` now detects this
shape using the existing static receiver decomposition and selects the existing
shared JOIN compiler. Its existing prefilter calls the ordinary range binder
before assigning the JOIN's private left slots. The detector only chooses a
path; actual value/range precedence, NULL, type and expression work remain with
the existing binder/checker. Same-named values are not rewritten as range values.

Product change: one applicability branch in `query_join_chain.mbt`.
No CTE scope, Source predicate, specialized JOIN filter, assert, Effect,
checker, planner, provider, capacity ceiling, contract pin or generated API is
modified. No acquisition fallback or test-side Program patch is introduced.
This is independent of #1169's SELECT/WHERE-after-JOIN/ORDER receiver repair;
that submitted branch remains unchanged. Both applicability branches must be
retained when the two independent main-targeted changes are integrated.

## Independent obligations

- Handwritten complete JSON Program: Values → nullable-property filter → JOIN
  with authored ceiling 1 → ordinary property → select/sort → Named Result.
  Independently typed input contains scores 10,20,NULL; peer duplicate ID 2 has
  scores 30 and 40. The expected filtered result is exactly `[{"id":1,"score":5}]`.
  Dropping the predicate yields extra rows and violates the tight JOIN ceiling.
- Source filter compares the original input, even if SELECT later replaces
  `payload` with the peer object whose score is 5. Expected value and column
  contracts are authored independently, not derived from compiler output.
- Quoted range/property names, parameter threshold 15 and explicit upper bound
  1 survive lowering. Inspect the actual predicate, parameter, JOIN keys and
  ceiling and run the normal checker with separately supplied parameter values.
- A same-named object/range contrast distinguishes `(payload).score` (20/10/NULL)
  from qualified `payload.score` (90). The latter yields four rows, including
  both peer matches for ID 2. A threshold 100 produces an empty typed Result.
- A future JOIN-right receiver and a scalar property receiver must be refused
  before durable admission or Source I/O with `ClientProgramInvalidInput`.
- The older unselected DISTINCT-order case pins the existing public
  `ClientProgramImplementationLimit` instead of the generic input-category set.
  This is the lowerer → admitted Check → preparation contract already documented
  in `2026-10-09-order-property-receiver-reuse.md` and #1169. It is not a product
  diagnostic change or a claim of finer invalid-order classification.
- Seven new positives (one JSON control) and two exact refusals join the existing
  normal corpus and narrow `--join-property-only` consumer. Total: 22 positives
  and 11 refusals per transport, three exact public-code refusals and eight
  older category checks. Existing positive sources/rows/types/guards are unchanged.

## Focused evidence

Pinned tools through existing bounded/nonzero wrappers:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js \
  src/query_program/join_prefilter_range_property_test.mbt \
  src/query_program/pipe_join_input_test.mbt \
  src/query_program/join_property_paths_test.mbt \
  src/query_program/source_range_property_test.mbt \
  src/query_program/pipe_range_property_test.mbt
node scripts/local-checks.mjs test node --timeout-seconds 120 -- \
  scripts/join-prefilter-property-source-input.test.mjs \
  scripts/public-query-profiles.test.mjs \
  scripts/analytic-offset-profiles.test.mjs
```

Initial repair selection 2/2: `run-Ff14kT`, `focused-test-S48qSH`.
Expanded JS selection 25/25: `run-a2U57h`, `focused-test-zXT3bM`.
Node selection 18/18: `run-mCg4Y0`, `focused-test-WYW2iP`.

## Public acceptance

Clean packed source: `936672de509791961a5c965cf138063f0d89076c`.
Original receipt: `worktrees/.codex-scratch/public-query-evidence-LD9m0O`.
The existing serialized heavy guard `run-NwBOCC` (1200 seconds) runs the normal
five-package producer, independent SHA/digest verification and unchanged narrow
public consumer:

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-join-prefilter-properties-936672de5-pack
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-join-prefilter-properties-936672de5-pack \
  node scripts/test-packed-public-query.mjs --join-property-only
```

Embedded Local and real HTTPS each finish **22 positives / 11 refusals**.
Both transports include all seven new positives and two new exact refusals.
Three refusals check exact public codes; eight older cases retain the existing
category assertions. Complete Named Result rows, describe type/nullability/
column order, hidden-column absence, same-Run resend/attach/lookup without extra
evaluation and admission/I/O zero on refusals pass through the shared consumer.
Source-free inputs do not establish external acquisition/sharing.

All ten receipt commands finish status 0 with complete output; the receipt is
passed/complete, source clean and its revision matches the producer manifest.
All five tarballs were independently rehashed against manifest and receipt.
There are no evidence errors. The temporary installation was removed and its
path is absent. Source fixtures are copied unchanged; no lowered Program is
edited by the consumer. The final evidence commit changes only this report;
public execution is attributed to the packed source above.

| Package | SHA-256 |
| --- | --- |
| client-wire | `ca7aaf03f3f1d78aff24c42a4ebe94ae2136ce29ba3fdf8ed81478e359e3df60` |
| sdk | `64eca760cdce9f0da1ea53542ede457ec9f5c80603d9b13721077d90c7b91c1e` |
| run-host-core | `f556604d2d56a7bdd76865289c621a4f69ec766af78e03d942f81666b1acfb54` |
| local-node | `2160abd10cf496c7cc846e5c6bc51f2152dbfe26f9b7a656686900547cb7c79c` |
| node | `a77756e97078c7df0ea0a318e5ccd74bd7aee2891caa148da2688f9c3eb2d9eb` |

## Remaining verification

Full Core, other execution targets, complete packed campaigns, CI and content
review remain separate. This unit is not completion of the whole frontend goal.
