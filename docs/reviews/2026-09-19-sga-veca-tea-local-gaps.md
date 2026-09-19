# SGA, VecA, and TEA Local execution gaps

Baseline: `0886df5ab75ff77edcd68291470f487346fc1cc4`.

This is a live implementation ledger, not a completion claim. The machine
readable coverage manifest is authoritative for individual operation status.

## Shared blockers

| Area | Baseline state | Required closure |
|---|---|---|
| Canonical AoA | Five normative operations are absent and several arities disagree with the language contract | Reconcile operation IDs, Carrier signatures, ordered inputs, parameters, obligations, laws, CIDs, and pins |
| Lowering | SGA, VecA, TEA, Bridge, and vector scalar expressions are rejected as unimplemented | Produce complete checked typed AoA without frontend rediscovery |
| DAG inputs | Task inputs are limited to ports zero and one | Use ordered typed edges through planning, dispatch, cancellation, and cleanup |
| Completion | Managed output is Relation-shaped | One Carrier-aware lifecycle with typed Carrier views |
| Runtime material | Only relation sequences and tables are accepted | Add managed Carrier views and registered providers without forced copies |
| Progress | Local kernels are synchronous | Add bounded MoonBit start/resume state and real environment yield |
| Cancellation | Pre-start and surrounding asynchronous cancellation exist, but synchronous kernels cannot receive cancellation | Connect delivery, polling, stop confirmation, and cleanup |
| Packaging | Local execution kernels are assembled together | Produce and inspect family-selective artifacts |
| Publication | Existing Effect-free path accepts ordered Relations | Connect every new Relation result and Carrier projection through that path |

## Normative contract mismatches

The language maps the following canonical operations, but the pinned pipeline
registry does not contain them:

- `SGA.subgraph`
- `SGA.equal`
- `SGA.mean_structural`
- `TEA.time_series`
- `TEA.join.interval`

The baseline registry also has incompatible fixed arities for these formal
source shapes:

- graph traversal with an optional selector Relation
- shortest path with up to two selector Relations
- reciprocal-rank fusion with a nonempty finite Relation list

The canonical lowering text still describes `union_graphs` as a generated
binary fold. The accepted design instead retains the authored finite list as
one typed occurrence and allows a physical fold only when it preserves the
registered order, failure, numeric, identity, and accounting laws. Resolve
this normative conflict before implementing either path.

## Family execution gaps

### SGA

All 17 author-visible operations are accepted by frontend typing but lack the
portable Local lowering, Carrier provider, managed execution, two-consumer
connection, and publication connection required by this milestone. Graph
projection already defines evidence laws; execution must consume rather than
recreate them.

### VecA

All five operations lack portable Local execution. `vector_score` and
`vector_concat` are accepted by expression typing but rejected by shared
lowering and have no evaluator implementation. The prescribed binary32 and
binary64 operation sequence needs a portable conforming kernel and independent
vectors before optimized implementations can be selected.

### TEA

All eight operations lack portable Local execution. Runtime work must preserve
finite event-time observation semantics across transport page splits and bind
checkpoint advancement to the existing successful commit boundary. No
long-lived streaming state is required by TEA 0.1.

## Current verification boundary

The baseline passed Linux CI run `35414883771`. That proves the accepted RelA
baseline only. It is not evidence for any missing family execution path.

Each entry moves from missing to partial to complete only when its manifest
evidence names existing fixtures, suites, targets, and recorded results. A
passing inventory count alone cannot complete a layer.
