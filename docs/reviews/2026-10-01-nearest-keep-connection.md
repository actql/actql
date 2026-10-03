# NEAREST KEEP / AS source connection

The baseline-specific common gaps below are historical. The
[current public connection report](2026-10-03-nearest-public-connection-boundary.md)
separates the resolved object/property boundary, ordinary VecA preparation and
official Plan issuance from the remaining installed Host profile and public
execution obligations. It does not claim packed NEAREST execution.

## Baseline and boundary

Base: `c26a4ea4bf0a8ba55a7639ac1bdcf6653427b1f6` (`origin/main`).
Branch: `feat/frontend-nearest-keep-as`.
INFER acceptance remains independently preserved at
`0996714dfa283c428d9feb1e77f869ab94f9cd98`; this work does not adopt A's
development commits or edit its common execution files.

This unit constructs ordinary Programs from the adopted NEAREST Pipe form.
It changes no provider, physical strategy, Run owner, model execution, storage
format, public Client method or SDK dependency. JSON/YAML Program remains a
public machine input. Owned contracts remain at 0.1.

## Independent connection probe

[Fixture directory](../../spec/frontend/fixtures/nearest-keep/kept.aql) contains
independently authored input rows, a Program, expected rows and expected column
contracts. The query has one ID (`q1`) and two candidates. Candidate `b` occurs
before `a` in the input; dot scores are independently 0 and 1. Both matches
repeat the nullable query note. Neither row index nor concatenated ID is used.

The [minimal JSON Program](../../spec/frontend/fixtures/nearest-keep/common-minimal.program.json)
was written before source lowering. It uses common nearest, many-to-one
join-back on each retained input, and ordinary named object projection.
`nearest_shared_test.mbt` checks it through the normal Program checker. Its
separate probes identify the exact common gaps; they do not implement a model,
KNN evaluator or alternative typed owner.

Expected rows are acceptance targets, not executed row evidence. Compare their
pair IDs, values, nullability and ranks independently. The ordered source adds
an explicit `ORDER BY neighbor.rank`; no sort is implicitly added to the plain
KEEP form, and a join's incidental iteration order is not publication evidence.

| Boundary | Existing owner / operation | Observation |
| --- | --- | --- |
| Singleton input identity and vector roles | `vector_typing.check`, `to_vectors` | Normal checker accepts both explicit sides |
| Exact nearest and score/rank rules | `relation_evidence.check_nearest_sources`, existing VecA provider | Reused; no new evaluator |
| Output key evidence | `relation_evidence.nearest_keys` | One witness covers query_id **and** candidate_id, never query_id alone |
| KEEP correspondence | Common inner join, many_to_one | Nullable query values can repeat over several matches |
| Named key/result object type | Common object expression typing | Accepted; empty Values retains the complete type |
| Object/property execution | `lowering_relation.lower_expression` | Object construction rejects with `ExpressionNotImplemented("object")` on the base |
| Composite Program identity bridge | `vector_typing.check` ToVectors branch | An ID array rejects as `Vector(Decode(WrongType))` |
| Nested output key witness | Common projection transfer | Dropping flat roles removes that witness; the frontend fabricates none |

## Implemented frontend scope

- Mandatory candidate alias, both KEY/VECTOR roles, METRIC/K and result AS.
- Optional KEEP references, aliases and known-schema wildcards in authored order.
- Linear Relation Pipe with singleton non-null IDs, checked by common owners.
- Reuse of each named producer, including a shared query/corpus source. A query
  predicate cannot shrink the explicitly named corpus through capture reuse.
- Computed VECTOR expressions lower once into ordinary derived slots.
- A new output scope contains only KEEP and the result object; old aliases and
  omitted columns are inaccessible. Private slots are projected out.
- Original source spans, parsing work/node bounds and construction limits.

Composite-key syntax is recognized but lowering explicitly reports
`UnsupportedNearest`; it does not emit an invalid common Program. Combining
NEAREST with existing CTE/set/JOIN assembly remains pending. These are recorded
implementation gaps, not changes to the adopted target semantics.

## Handoff to A

1. Adoptable object/property execution is needed for the ordinary projection
   in `common-minimal.program.json`. A's development object work was read but
   not adopted. Supply a fixed complete SHA and the existing Host registration
   example; B will first run one input query through packed Local/HTTP.
2. The [composite bridge probe](../../spec/frontend/fixtures/nearest-keep/composite-bridge.program.json)
   is rejected by `vector_typing/check.mbt::check`, which reads one `id` role
   and calls `carrier.vectors(..., ids=[id], max_identity_fields=1)`.
   Existing Vectors and nearest support intrinsic typed tuples; the missing
   boundary is an ordinary Program producer for that tuple. Coordinate the
   common contract and owner, rather than inventing a frontend synthetic ID.
3. If a subsequent consumer needs a key witness on the nested result, it must
   come from existing common identity/projection evidence. Retaining typed key
   values is not permission to declare arbitrary objects KeyComparable.

Reproduce the common gaps with:

```sh
moon test --target js src/query_program/nearest_shared_test.mbt
```

Frontend and ordinary-checker regression:

```sh
moon test --target js src/query_syntax src/query_program
```

Packed NEAREST Local/HTTP, Result.describe consistency, actual rows and
re-read/re-submit execution counts remain **not run** pending common execution.
The same independent expected rows will be used after adoption, without
rewriting them from product output. INFER's one-row acceptance takes priority
when A's adoptable SHA arrives.

## Identity and validation

The query grammar and rules alter Grammar Manifest CID and therefore dependent
Executable Plan / Bound Invocation Template identities. Program identity is
determined by the generated ordinary Program. Schema/registry semantics and
the contract version are unchanged. Manifest and compiler pins are generated
from source, not edited directly. No runtime bundle is committed.

Fixed-SHA results are recorded after the source commit. Source construction,
checker success, shared-gap probes and packed execution are separate evidence.

### Local verification

Implementation and generated-artifact SHA:
`a829178608c05fdc246797c27cd47d5715bf5121`.

| Source SHA | Command / boundary | Result |
| --- | --- | --- |
| `d636da9dd` | `local-checks.mjs run core --target js` | Check and independent Run vector passed; 7,148/7,148 tests passed |
| `d636da9dd` | `local-checks.mjs run lint` | Passed, including three-target API agreement and no-DuckDB module isolation |
| `45edf6a35` | `local-checks.mjs run spec` | Passed through contracts, links, examples, documentation, Unicode and encoding; stopped at stale canonical fixture |
| `a82917860` | Remaining `check:spec` commands from `check:canonical` through `check:events`, read directly from `package.json` | All passed after regeneration |
| `a82917860` | `moon check --target js/wasm/native --deny-warn` (separate commands) | All passed |
| `a82917860` | `moon test --target js src/query_syntax src/query_program src/canonical_json` | 577/577 passed |

The full final-SHA local spec aggregate was not repeated after the canonical
fixture-only correction. Its complete CI execution is a separate result;
staged checks above must not be presented as that aggregate's exit-code success.
Local full Wasm/native test suites and packed runtime acceptance were not run.
Logs are retained under `_build/nearest-keep-evidence/` and are not shipped.

Generation order for the grammar dependency closure:

```sh
node scripts/compilation-manifests.mjs --write
node scripts/update-document-metadata.mjs --write
node scripts/check-actql-spec-family.mjs --write
npm run generate:canonical
```

An existing INFER frontend follow-up was also identified: `infer_join_field`
emits a `join_field` object, while the common join selection used by the
independent probe accepts `left.field` / `right.field` strings. B must reconcile
that emitter with the adopted common join contract when resuming INFER
acceptance. It is not an additional common execution-owner request, and this
NEAREST unit does not modify the preserved INFER acceptance SHA.
