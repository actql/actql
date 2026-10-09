# INNER correlated UNNEST connection

## Contract and fixed counterexample

Audited from main `d0c38e7b4e38cfbfc561e259907502b2efbc1e96`.
The adopted GoogleSQL profile permits correlated INNER array flattening, with
or without ON. See the official [array guide](https://docs.cloud.google.com/bigquery/docs/arrays)
and [query syntax](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax).
A conditional INNER join retains only expanded pairs whose predicate is true.
Empty/NULL arrays have no children; duplicates and NULL children are preserved
unless the predicate excludes them. OFFSET remains the original element index.

```sql
SELECT p.id, element, position
FROM parents p
INNER JOIN UNNEST(p.items) element WITH OFFSET position
  ON element = p.id
ORDER BY p.id, position
```

Independent input: `(2,[2,NULL,2]), (1,[1]), (3,[]), (4,NULL)`.
Expected ordered rows:
`[{"id":1,"element":1,"position":0},{"id":2,"element":2,"position":0},{"id":2,"element":2,"position":2}]`.
Dropping ON incorrectly retains the NULL child at position 1. Deduplicating the
array incorrectly loses the second match. The complete independent Program
in `src/query_program/inner_correlated_unnest_test.mbt` passes the ordinary
checker; the SQL and Pipe source forms failed parsing before this change.

## Implementation

`query_syntax/query.mbt` dispatches explicit INNER/bare JOIN UNNEST through the
existing correlated expansion. The optional ON expression becomes an ordinary
Where operation immediately after expansion. Both SQL and Pipe reuse normal
expression parsing, scope resolution, nullable properties, budgets and lowering.
An ordinary JOIN continuation binds this filtered producer before joining; it
does not move ON behind another JOIN. No common owner or execution path changes.

The EBNF and query-text coverage describe this selected connection. LEFT
correlation, comma/implicit array expansion and correlated USING remain separate
coverage gaps. Correlation inherits the checked ARRAY bound and Host ceilings;
no MAX_OUTPUT_ROWS is silently accepted or discarded for expansion.

## Independent public obligations

The existing normal correlated-UNNEST packed cohort includes the new cases.
The independent JSON control explicitly inserts the equality filter after
UNNEST. Source forms are not patched after lowering. New positives cover SQL,
Pipe, omitted ON, quoted names, false/NULL predicates, empty input, immutable
parent aliases after SET, DATA, set multiplicity, nullable object fields,
ordinary JOIN continuation with bound 10, and acquired Source read-once.
Four new typed pre-admission refusals cover an unresolved receiver, a projected
away alias, USING and an unsupported expansion bound. Existing acceptance
checks retain column order/type/nullability, hidden-column absence, row values,
request replay, Result rereading, admission and provider counters.

## Grammar and existing identity fixture repair

The grammar manifest changes from
`sha256:27ebfa9f22860ffcf7d16c15199c95cd41952579720e27b16b715fa5d5b0f18c`
to `sha256:6c736875bc97084060934856c845f467405e231cdd8971494e8d0934c043b18b`.
Program wire, value contracts and logical operation semantics do not change.
Grammar-bound invocation, executable/compiled Plan and Run identities change;
old saved Runs are not relabeled. The preceding complete grammar and independently
assembled Values Run preimages are retained in
`scripts/fixtures/pre-inner-unnest-grammar.json`.

Before updating the grammar, the current main-derived independent Values vector
already failed 2/9 tests (`run-rahFII`, `focused-test-X7OqTo`). Its installed
contract closure derives Unit `c92e4312...`, while consuming fixtures retained
`144ed737...`. The local Values body is identical; the CheckEnvironment contract closure pin
changed from `d896f22c...` to `ff717ce1...` in main's contract repair. The original
Run vector `c722ca18...` is preserved under its historical dependency pins.
The repaired main grammar independently derives Run `1b7df752...`; the new
INNER grammar independently derives `4dcc3bab...`. Expectations follow the
hand-assembled normative oracle/preimages, never a product failure output.
Current Unit, proof, ResultPlan and Run fixtures are aligned. Common contract
bodies, checker/owner implementation and historical expectations are preserved.

Existing compilation-manifest, document-metadata, spec-family and canonical
vector generators update reviewed dependent outputs; generated sources are not
hand edited.

## Executed evidence before packaging

- Original counterexample: `run-j80AdC`, `focused-test-irFcnw`: 1 passed, 2 failed.
- First connected control: `run-bvT9YJ`, `focused-test-90uBfk`: 3/3 passed.
- Expansion/continuation callers: `run-xJZzbt`, `focused-test-6zsu5g`: 25/25.
- Final selected JS callers plus Values publication identities:
  `run-76cHWG`, `focused-test-T32Q83`: 27/27.
- Fixtures and independent manifest/Run vectors: `run-unYjsp`,
  `focused-test-euH8oE`: 21/21. Earlier correction attempt `run-4bLb93`
  failed one newly authored historical assertion; that assertion used the
  wrong pre-pivot closure and was corrected without changing product behavior.
- Fixture/document/import checks: `run-ueYUHG`, `focused-test-QsiWhB`: 20/20.
- `run-EEVar7`: selected JS/Wasm/Native package checks and all four read-only
  generators passed. The wrapper then failed because `check:docs` is not a
  current npm script. The actual document/import checks above passed; this
  entire wrapper is not reported as successful.
- MoonBit formatting and `git diff --check` passed.

Focused commands use pinned Node 22.22.0, MoonBit `0.10.12+1634b282e` and the
existing bounded/nonzero-test wrappers. The MoonBit selection names the new
inner test, existing correlated/continuation/set/UNNEST tests, and the two
`run_publication_host` Values identity consumers. The Node selection names
`correlated-unnest-source-input`, `compilation-manifests`,
`sga-query-call-contract`, `client-values-run-materials-vector`,
`document-validation` and `spec-family-imports` tests.

## Public execution and remaining coverage

Fresh normal five-package Local/HTTPS execution is the next verification step.
The new fixture count is 15 positive cases and four pre-admission refusals;
those are obligations until the actual consumer finishes. No public success,
CI completion, full Core campaign, backend runtime conformance, LEFT correlation
or broader GoogleSQL conformance is claimed by parser/checker success.

The first fresh pack at `1a9baf0d1c971bf4305fd46968a9219c651a3c31`
failed at the new immutable-parent fixture, after 23 Local positives. Receipt:
`public-query-evidence-SDnxB1`, command `010.stderr.log`; wrapper `run-HuSIkJ`.
Its source selected original `p.id` but expected current `id=99`. The correction
selects the current `id`, keeps the ON/ORDER references to original `p.id`,
and retains expected rows. A separate hand-authored JSON control preserves
`original_id` before SET, filters on it, and publishes the current `id`. This
is a fixture authoring correction, not evidence of a product alias defect.
The failed installation/Store and original logs are retained. That run did
not reach later Local cases, refusals or the HTTPS cohort.

The main integration `1a9baf0d1c971bf4305fd46968a9219c651a3c31` normally
merges `727520c8d02e4f3836471a8851e5d735c2cd3f02` without conflicts.
Its selected JS callers passed 27/27 (`run-wceC2Y`, `focused-test-FS5VQ7`).

The second clean pack at `f0e899e1117e8302dd3e37f7b4724061af6960b9`
failed at the newly added immutable JSON control (`public-query-evidence-SQSlAU`,
`010.stderr.log`, wrapper `run-3R4DYb`), again after 23 Local positives.
The ordinary bridge diagnostic identifies `InputCollision("id")` at
`stages[0].steps[5].derive.id`: derive adds columns and cannot overwrite one.
Changing numeric literal representation alone did not fix that collision
(`run-8NDyXq`: 1/2 passed). The independent control now derives a fresh
`current_id` literal and projects it as `id`; original_id remains the predicate
and order receiver. Rows, contracts, bounds and product code are unchanged.
The corrected control passes the ordinary checker; its paired refusal and
fixture checks pass 7/7 (`run-BHTNux`, `focused-test-1qvGpP`). The diagnostic
source is retained at `/private/tmp/actql-b-inner-control-diagnostic.test.mjs`.
The prior fixture/vector checks passed 15/15 with the first fixture correction
in an uncommitted working tree (`run-0BGaIJ`, `focused-test-8tjwJA`); that result
is not attributed to the subsequent corrected immutable control.
