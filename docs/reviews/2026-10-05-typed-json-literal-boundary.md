# Typed JSON literal common-owner boundary

Base: `7e337afa9e5a64035c5925aca1d93ba0ef787aaf`. Branch:
`feat/common-typed-json-literals`. This is a common-contract dependency of the
generic GoogleSQL JSON surface and Graph Delta source acceptance. It is not
completion of the text entry or Graph Delta acceptance.

## Review requested from A and C

| Owner | Boundary | Required review |
| --- | --- | --- |
| A | `expression_syntax`, `expression_typing`, `lowering_relation`, `execution_relation`, `model_execution/restored_capture.mbt` | One typed literal leaf and existing evaluator; no scalar coercion of JSON null; complete-input preparation budgets; capture restoration uses explicit typed-wire mode |
| C | `value_admission`, `canonical_json`, `run_publication`, `managed_graph_storage`, `graph_snapshot_identity`, `bounded_graph_diff`, `local_sga/delta_input.mbt` | Common JSON domain/envelope, retained keys/strings and profile identities; Graph identities/Delta bodies explicitly use the checked payload rather than the cell envelope |

No A or C review is claimed by this document. The changes need those boundary
reviews before integration. No new compute, submission, storage or recovery
owner is introduced.

## Source and wire

Machine source example, using the existing derive expression:

```json
{"derive":{"j":{"typed_literal":{"type":"json","value":"null"}}}}
```

The checked output is non-null `json`. Its canonical typed-cell wire is
`{"$json":null}`. A nullable JSON cell holding SQL NULL remains `null`.
The same domain handles JSON number, string, boolean, object and array roots.
Existing `literal` scalar/null inference is unchanged; existing object/array
literal inference remains JSON and uses the same new wire. Raw authored data
does not decode a `$json` key as a type tag.

The wire contract is separately pinned within the common expression law.
Result serialization preimages now contain that wire contract CID and the
existing format version. Versions remain 0.1. Expression/source schemas,
registry, grammar/Program dependencies, Values wire law, dependent pins and
independent canonical/profile vectors change together. Old untagged JSON
typed cells are rejected in explicit wire mode, without fallback. Graph
identity/Delta semantic bodies keep their existing body format; checked JSON
property cells use the common envelope.

## Selected decoding profile

Reference: GoogleSQL `d82db99a923a46571f543a13899dc791a7b6f743`,
`ResolveJsonLiteral` / `JSONValue::ParseJSONString` with exact numeric parsing.
See [the design](../design/typed-json-literals.md) for official references.
Duplicate exact decoded keys retain the first value, while all input is parsed
and charged. Depth is at most 500 and additionally meets existing caller
ceilings. Data keys and string values retain CR/LF and Unicode scalar sequences.

The current common finite binary64 domain is an explicit numeric subset:
roundtrip decimal equality is required, so unsupported wide integers,
precision loss, overflow, underflow to zero and negative zero are rejected.
This does not claim the complete GoogleSQL signed/unsigned JSON integer domain.

## Evidence and remaining work

Independent fixed source/wire/profile preimages are in
`portability/corpus/typed-json-literals.json`. The expectation bytes are not
generated from the product. Existing Graph snapshot expectations remain intact.
The ordinary public-query harness includes two machine JSON successes (all
root domains plus SQL NULL, and an empty Result with full schema) and four
pre-admission refusals. The narrow selection is:

```sh
node scripts/test-packed-public-query.mjs --typed-json-literal-only
```

Focused JS checks cover parsing, Value admission and restoration, typing,
lowering, evaluation, Result delivery/profile identity, Values wire measurement
and Graph diff/apply. The latest affected-caller checks passed 54/54
(`run-n9LNQr`) and snapshot/encoding/closed-object JSON projection passed 14/14
(`run-88srQH`). Targeted Node contract/pin tests passed 23/23 (`run-wCXXsT`).
These logs are under `_build/local-checks/attempts/` in the branch worktree.
The changed storage fixture independently spells the JSON envelope; its
physical encoding is 43 bytes / 9 nodes rather than 33 bytes / 8 nodes.
Production ceilings are unchanged.

Three-target public-interface verification and changed-package formatting
passed (`run-TgiV5D`); this checks compilation and interfaces, not three-target
runtime execution. Read-only literal/vector, Workers/Node fixture, canonical,
owned-version and document-family validators passed. Exact-SHA packed results
and tarball digests belong in the PR validation record after execution.

Remaining: A/C reviews, final-SHA packed Local/HTTPS, Wasm/Native runtime
execution and CI. The separate Frontend branch must emit this structured leaf
and compare a complete independently authored Program. The Delta branch must
then execute valid authored JSON source through apply_graph_delta; its earlier
machine controls and refusal acceptance are separate evidence.
