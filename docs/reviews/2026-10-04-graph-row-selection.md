# Graph row selectors from public text

## Boundary and dependencies

This Frontend unit uses the existing named-argument syntax:

```aql
FROM g |> node_rows(definition: "N") |> SELECT key, p
FROM g |> node_rows(label: "Person") |> SELECT key, p
FROM g |> edge_rows(label: "R") |> SELECT part, edge_key
```

`g` is an earlier DATA Property Graph producer. Selectors are string values,
not producer references, physical table names or predicates. There is no new
parser grammar, execution owner, acquisition or materialization boundary.

Initial fixed integration `40fcd7b7f` combines main
`b6c69a7e5bdbf25dc3bc5cf5224b980536efb3ec`, B's #303
`bd05a93a5729b9ac6d24c949b72f7066f259c896`, and C's #307
`be4d39a6380685150b09847a6bc769f9eae36778`. The latter depends on #299
`16742aaa3e56982561122a7fe02d0674ced98182`. These are development dependencies,
not declarations that all dependency CI or public acceptance is complete.

| Text | Existing Program body | Ownership |
|---|---|---|
| `node_rows()` | `node_rows: true` | Existing no-selection Bridge |
| `node_rows(definition: "N")` | `node_rows: {definition: "N"}` | C's same-kind definition selector |
| `edge_rows(label: "R")` | `edge_rows: {label: "R"}` | C's same-kind label selector |

The Frontend enumerates visible names from the selected declared definitions
using the common Graph name identity. It emits the selector unchanged and
adds no type, presence, uniqueness or order evidence. The common checker
still derives the finite schema and validates Graph key/label/property rules.
Label selection includes every matching definition and properties declared
under any of those definitions' labels. Conditional presence is distinct
from nullable value; `IS NOT NULL` cannot manufacture presence. Guaranteed
projection precedes ordinary filtering when other columns remain Conditional.
Raw key columns retain their names; typed element identity remains the
Bridge's separate contract. No row sample determines an empty Result schema.

## Independent obligations

The complete definition-selected Program in
`src/query_program/graph_row_selection_test.mbt` is authored independently.
The existing packed corpus in
`scripts/fixtures/property-graph-row-source-input.mjs` now includes:

- Independent JSON and text controls for definition-selected nullable nodes.
- Independent JSON and text controls for label-selected heterogeneous
  definitions, guaranteed projection, filtering and explicit ordering.
- Independently keyed parallel edges with composite raw keys, using both
  definition and label selection and quoted DATA names.
- A selected empty definition while another definition is nonempty; declared
  nullable type and selected column order remain available.
- Unknown/wrong-kind selectors, both selectors, non-string values, Conditional
  projection and Conditional `IS NOT NULL` rejection.

JSON controls use independently authored Values and existing Program
operations. No compiler output creates an expectation, and no lowered Program
is patched by the test. The standard packed application checks full ordered
Result descriptions, rows, stream completion and same-request Run reuse;
refusal checks retain zero durable admission and zero provider I/O.

## Executed evidence and unverified boundaries

Pre-integration focused JS on the working implementation: Graph Program/checker tests 9/9.
Independent Node grammar/Run preimage vectors 3/3. Read-only compilation
manifest, normative metadata, canonical corpus (367 identities), Workers
fixture and Node fixture freshness checks pass. Both integration parents'
independent vectors remain pinned; the normative query-rule update changes
the grammar CID and dependent compilation/Plan/Run identities, not the Graph
identity model or contract version 0.1.

An initial attempt stopped with ENOSPC and left corrupt compiler output.
Those attempts are failures, not product refusals or successful coverage.
Only the newly generated JS compiler output was rebuilt; evidence logs were
retained. No full Core, all-target, proof or performance campaign was added.

Public Local/HTTP execution of the new selectors remains unverified until
this branch's normal packed automatic CI finishes. The existing 5 no-selection
positives and 4 unchanged refusals remain in the corpus; 8 new positives and
7 new refusals exercise selectors. Syntax/checker success is not public Host
execution evidence. C's own JSON acceptance and #303's earlier public run
are dependency evidence, not acceptance of these new authored sources.

D's CTE predicate repair remains separate. This unit changes no CTE,
assertion, Effect, shared capacity derivation, provider or remote protocol.

## Submitted integration boundary

Current integration source is
`0e15166777886e5441c54fed615348df2138db6e`, retaining normal merge parents:

- Current main `d5f0802c93e2863b092aa8f1a9e9a7cc97b12c5b`, including #287
  and #299 as completed integrated units.
- B's no-selection text dependency #303
  `7bc0367339711cc85c80ce82a387a11e3f189ce3`.
- C's label-selection dependency #307
  `51764ed8846a0f3913d498d434154576d4b976dc`.

The next submitted commit also adds direct text-to-common-checker edge selector
regressions and this evidence record. Normal merge conflict resolution keeps
both parents' independent preimages, then regenerates metadata and pins from
combined normative source. In particular the #303 definition-only grammar/Run
vector remains a predecessor; it is not rebound to the label-enabled contract.
This Frontend unit remains Draft pending its new source's public packed
Local/HTTP acceptance and required automatic CI. No dependency success is
claimed as this source's execution result.

Focused JS at submitted source
`c4c2d9b2f7a6b5425cbc14c9fe40ec64b10960bd` passed 10/10 Graph tests.
Its automatic [CI run](https://github.com/actql/actql/actions/runs/37172067735)
stopped in history preflight before product jobs ran: the two normal dependency
merges `5fa4bc547a44198777c02ed1ed21411dadfcffe8` and
`0e15166777886e5441c54fed615348df2138db6e` lacked their protected
`package.json` resolution records. Each merge has two actual maximal bases;
both parents changed that path relative to one base even though the parent
and result blobs agree. New source-bound declarations retain all bases,
ordered parents, blob digests and ancestral declaration groups. Existing
records and the validator are unchanged. This repairs provenance, not a
product execution failure, and does not establish public selector acceptance.
