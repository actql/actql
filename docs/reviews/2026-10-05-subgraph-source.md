# Subgraph source connection

## Baseline and selected contract

Base main: `4a63d0e699674df519c9d35a990080026000e560`. Branch:
`feat/frontend-subgraph-selection`. This unit has no unmerged dependency and
does not change #420 or the execution-blocked aggregate work in #381.

The adopted named `subgraph(nodes: ..., edges: ...)` surface is an ActQL
extension, already parsed under the [SGA surface](../design/frontend-sga-surface.md)
and [query text contract](../spec/query-text.md#named-logical-sga-calls).
Its [common contract](../spec/language.md#subgraph) selects node identities,
deduplicates them, retains exactly the original edges with both endpoints
selected, then applies the optional edge predicate. Graph identities, labels,
properties, schema, policy, scope and resource obligations are retained.
This is pure Graph computation, with no implicit acquisition, Result,
materialization, persistence or execution placement.

Common main supports explicit IDs and a Relation selector. `nodes.where` is
an adopted but unimplemented common selector form; keep its authored predicate
and existing typed pre-admission refusal. Do not approximate it with a private
Frontend filter or declare it a permanent language restriction. Data-dependent
identity membership is checked during execution, before a complete Graph or
Result can be published.

## Counterexample and repair

The baseline selection executed two tests: the independent machine Program
passed the ordinary checker, while this authored source failed lowering:

```aql
DATA n = SELECT 1 AS node_key, 7 AS p;
DATA g = PROPERTY GRAPH (
  NODE TABLES (n AS N KEY (node_key) LABEL Person PROPERTIES (p))
);
DATA selected = FROM g |> node_rows() |> SELECT id;
DATA slice = FROM g |> subgraph(nodes: {from: selected, id: 'id'});
FROM slice |> node_rows() |> SELECT p, node_key
```

Receipt: `run-08eNt2`, `focused-test-AI6RMF`, **1/2**. This distinguishes
common Program support from missing text routing, without using product output
as an expectation.

The private module `subgraph_script_program.mbt` reuses the existing typed SGA
argument builder and DATA producer resolution. It emits the authored Subgraph
body at the original call position. Both the Graph-preserving and Graph-to-rows
routes use it, including the prefix of a keyed MATCH. Only earlier emitted
Relation producers are accepted as selector references; external capture and
sharing remain with their existing owners. The original constructor metadata is
retained because the common Subgraph output retains that admitted Graph contract.
No presence, uniqueness, identity, NULL or authority guarantee is invented here.

The independent complete expected Program fixes the actual selector producer,
Graph input, projection fields and output order. Common refusals retain unknown
arguments, malformed selectors and edge predicates. Unknown/forward/wrong-Carrier
producer references and a Graph call after the Relation transition remain typed
Frontend refusals. There are no common Owner, Host, protocol, numeric-law,
grammar, schema, pin, stored identity or version changes.

## Independent public obligations

The [authored fixture](../../scripts/fixtures/subgraph-source-input.mjs) contains
**13 positive cases, 17 preparation refusals and one execution failure**.
Two complete JSON controls use direct Values; the source uses ordinary
SELECT/UNION producers. Structures and CIDs may differ, while the independently
specified meaning must agree. No harness modifies a lowered Program.

- Nodes 1/2/3 have properties 10/20/NULL. Selection of 1/2 returns the first
  two; selection of 2/3 preserves NULL and its declared nullable type.
- Edges 10/11 are distinct parallel 1-to-2 edges; edge 12 is 2-to-3; edge 13
  is a 2-to-2 loop. Selecting 1/2 retains 10/11/13, preserving multiplicity
  and excluding 12. Filtering by weight greater than 10 retains 11/13 without
  removing either endpoint.
- Empty Relation selectors produce typed empty nodes and edges. Repeated
  selector identities do not duplicate graph elements. Quoted DATA bindings,
  normalization, subsequent row operations and static-label MATCH retain scope.
- Edge-predicate parameters use the existing declarations and value binding.
  A valid explicit ID has a separately authored constructor/producer preimage;
  the fixture uses an independent canonical hash, not sampled product identities.
- Invalid bodies and unadapted `nodes.where` reject before Run admission and
  provider I/O. A missing explicit identity is a runtime membership failure:
  no rows or Result description are published, and attach/resend do not rerun.

An initial test incorrectly expected scalar `ids: [1]` to fail the static
checker. The common identity contract admits JSON and membership depends on
the input Graph, so this is now an execution-failure obligation. No product
rule was changed to match that mistaken test.

The existing packed harness compares independent rows, complete ordered
`Result.describe()` contracts, stream termination and same-request/attach reuse
on Embedded Local and HTTPS. Cases are registered in its default corpus, with
`--subgraph-only` for focused acceptance. The 512 MiB budget is unchanged.

## Executed and pending verification

- Final focused MoonBit JS: **30/30**, `run-XLXcxi`,
  `focused-test-Y5P46X`, including Subgraph, existing Graph rows, keyed MATCH,
  equality, diagnostics and node traversal. The previous 13/14 run exposed
  the mistaken static membership expectation above; it is not a product pass.
- Targeted existing public fixture identity/collision Node checks: **2/2**,
  `run-GVk4mw`, `focused-test-FTKeRf`.
- Changed MoonBit formatting, JavaScript syntax and `git diff --check` pass.
- Public selection to run from a clean committed source:
  `node scripts/test-packed-public-query.mjs --subgraph-only --keep-artifacts`
  through the existing bounded serial guard. Fresh Local/HTTPS execution is
  **not established by the focused tests above**; record the actual receipt,
  source SHA and normally packed tarball digests below when it finishes.
- Required submitted-HEAD CI is separate. Do not manually rerun it during
  the billing outage or claim local success as CI success. Full Core,
  Wasm/native, all packed, proof and performance campaigns are not local
  requirements for this connection unit. No merge is performed.

## Authored control correction before execution acceptance

The first clean `16e301aa7b7bc97589211e3aa5c283de2b4d71d2` campaign
(`run-G8TuuS`, `public-query-evidence-vwYiWk`) passed the README/control
smokes, then refused the first independent JSON before execution. Two focused
ordinary checker controls (`run-k6MImL`, `focused-test-RrjlyU`, **0/2**)
identified `Projection(OutputCollision(Unqualified("node_key")))`.

This is consistent with the existing [Graph row contract](../spec/language.md)
`graph-rows.collisions-and-unknown-evidence`: a property must not collide with
a retained key alias in this Bridge. Constructing key-valued properties and
projecting every Graph column are distinct contracts. This finding is not a
new Subgraph or Frontend defect, and the common collision rule is not relaxed.

The Subgraph controls now expose `p`/`w` properties alongside the original
`node_key`/`edge_key` components. Rows, parallel edge keys, predicate values,
NULLs, selected elements and their expected order remain unchanged. The keyed
MATCH case exposes its selected `p` property with independently expected values
10/20; numeric key projection remains covered through the row Bridge cases.
The valid explicit identity preimage is coordinated with the authored property
selection, never copied from a product identity. The original complete
[colliding JSON](../../scripts/fixtures/subgraph-property-key-collision.repro.program.json)
is retained separately, and the same collision is a public preparation refusal.
It is not silently reclassified as a successful control.

The corrected independent JSON controls pass the ordinary checker **2/2**
(`run-JEzyeD`, `focused-test-p4WngX`). Their expected result rows/contracts
remain independently authored. This is preparation evidence, not a packed
execution pass; the clean committed-source acceptance below is still required.

## First public execution and task-profile boundary

Clean source `324ed9f24c4172047cfde10469ab3598378d952f` was normally packed
under `run-qMFKkY`, receipt `public-query-evidence-825Vuv`. Both independent
JSON controls passed Embedded Local through Named Result rows and full ordered
description contracts. The first text case refused during preparation with
`ClientProgramRejected`. Later text cases and Subgraph HTTPS were not reached.
This is an incomplete campaign, not source execution acceptance.

A one-case logging-only diagnostic reused that retained installation under
`run-wKF5yB`. The preparation cause was
`Preparation(Graph(TaskLimit))`, not a checker, Subgraph kernel or Result
failure. The disposable preparation adapter was restored byte-for-byte in
`finally`; its original digest and diagnostic logs are retained beside the
receipt. This overlay is diagnosis, not a pristine packed pass.

The unchanged [larger source](../../scripts/fixtures/subgraph-task-limit.repro.aql)
passes ordinary semantic checking (**1/1**, `run-h1lfiA`,
`focused-test-cphBZk`). Its [generated diagnostic Program](../../scripts/fixtures/subgraph-task-limit-generated.repro.program.json)
contains 37 pipeline steps and is **not an expectation or oracle**. The standard
Host selects `max_tasks: 32`; task admission therefore remains a distinct
obligation. No limit is raised and no common physical strategy is changed.
The original input is retained as a preparation-refusal case.

The new independently bounded sources use two nodes and three edges for
parallel-edge, loop, predicate and projection cases. The expected selected
rows remain 1/2 and 10/11/13. A separate induction case selects only node 2
and expects only loop 13, detecting failure to exclude either missing endpoint.
The nullable case uses nodes 2/3 and still expects 20/NULL with a nullable
contract. Duplicate-selector coverage uses two parallel edges and requires
both once. These inputs are deliberately chosen within the existing task
profile; they do not establish execution of the retained larger input or
permit changing a submitted query to fit a budget. Fresh execution of the
bounded cases remains pending until recorded below.

## Main integration and opaque-literal correction

Main `3d21f2c8ccbe055aa792bdffdaab2b85770cf0c4` (#421) was normally merged
without conflicts in `e14685a4bee3b04b567ac9b76593fc599092ac5f`. Its Graph
normal cases and precise refusals are retained; this branch does not restore
obsolete equality/components unsupported expectations or change nearest/Events
input ports. Integrated focused JS checks passed **20/20** (`run-UMKUjT`,
`focused-test-fJxOCL`), and the existing public corpus checks passed **2/2**
(`run-piqW6K`, `focused-test-ng88CO`).

The fresh e14685 campaign (`run-OXm8k5`, `public-query-evidence-lpQhpI`)
passed both JSON controls and eight text cases through Local Named Results:
subset, induced parallel edges, quoted DATA/normalization/edge predicate,
nullable property, static-label MATCH, typed empty nodes/edges and endpoint
exclusion. It then refused the parameter case before admission; later cases
and Subgraph HTTPS were not reached.

One retained-installation diagnostic (`run-rTZfap`) identified the normal
checker refusal at `steps/24/subgraph/edges/gt/1`, expecting an author-orderable
scalar. The original fixture incorrectly authored `{literal: @minimum}`.
Common expression literals are opaque: lowering correctly preserved the
object `{"literal":{"$param":"minimum"}}`, not a scalar parameter read.
This is an authored-input error, not a common owner or Frontend defect.
The positive source now uses `gt: [{field: "w"}, @minimum]`, lowering to the
existing expression parameter reference directly. Expected rows/contracts are
unchanged. The original object-literal form is retained as a preparation
refusal with the same declaration/value, rather than changing literal semantics.
The logging-only disposable adapter was again restored byte-for-byte; the
diagnostic is not a pristine execution pass.

Clean source `331e450afa5ae982eaba02207f6f46e12e26aaae` was normally packed
under `run-zIws1o`, receipt `public-query-evidence-QeG8oP`. Local reached
**12/13 positives**, including the corrected parameter predicate and duplicate
selector identities. The last explicit-identity source refused with
`ClientProgramInvalidInput`. Remaining refusals, runtime membership failure and
Subgraph HTTPS were not reached. The six focused Subgraph source tests also
passed before this commit (`run-dTkF15`, `focused-test-iaEX8P`); that receipt
records the uncommitted test/fixture changes and is not a clean 331e450 run.

The retained-installation diagnostic `run-3WPneA` fixed the refusal as
`QuerySyntax(Expected identifier)` at byte 162. The fixture had embedded
`JSON.stringify(identity)` into a named-call object: JSON String keys are not
query identifiers. The corrected source explicitly spells `definition`,
`domain`, `key` and `key_types` as identifiers while preserving the independently
derived identity value. The original JSON-quoted-key text remains a syntax
refusal. No grammar is widened or independent identity copied from runtime.

## Completed scoped packed acceptance

Verified clean source: **`dba3119c00470a47026f32f086ddd8df29ca00d8`**, including
main #421. Command:

```sh
node scripts/test-packed-public-query.mjs --subgraph-only --keep-artifacts
```

The existing serial local guard selected `heavy: true`, a 1200-second budget
and five-second TERM grace, with the pinned repository toolchain. Receipt
`public-query-evidence-8Nh8WA`, guard `run-rpOdJ9`: **passed, complete,
clean source, no evidence errors**. The normal prepack hooks built the runtime;
there was no logging overlay, edited generated Program, skipped prepack,
replacement checker, custom Graph executor or budget change.

On **each** Embedded Local and public HTTPS path:

- **13 positive inputs** (two independent JSON controls and 11 authored text
  inputs) reached Named Results with independently expected rows, complete
  ordered columns/types/nullability, stream completion and same-request/read
  reuse. Parallel edges, induction, edge predicates/parameters, duplicate
  selectors, NULL, empty schemas, static labels, quoted DATA/normalization
  and independently derived explicit typed identity all passed.
- **17 preparation refusals** returned existing typed input codes with
  unchanged Run admission/provider-I/O counters. The retained task-bound,
  key/property collision, opaque object literal and JSON-quoted-key examples
  remain refusals for their distinct reasons, rather than successful coverage.
- **One data-dependent missing-identity execution failure** exposed no Named
  Result rows or description. Reattach/resend did not restart execution.

README Local/HTTPS, the public check boundaries and deliberate missing-generated-
asset refusal also passed as harness prerequisites. This is a selected Subgraph
campaign, not all Graph operations, snapshots, INFER or full integration CI.

Normally packed artifacts (SHA-256):

| Package | Digest |
|---|---|
| `@actql/client-wire` | `a8d1f2a63ed08d3378765fbee905fb72233d19e66e8ce77d6f1398ae45dbe8b7` |
| `@actql/sdk` | `a42baf2456b366d3a761f01cce27292ae1dcee13c8ce6113a3b70896bedd4e97` |
| `@actql/run-host-core` | `cf74b3bf1a686c7acef26dd1d820e0802c815deb3b1bd984d7444d36336527a8` |
| `@actql/local-node` | `e9009a1db698e00056bcbb3db124f6a854d51e4f4d5098b90ae6c65013062d3d` |
| `@actql/node` | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |

The following evidence-only commit changes this report; it does not rename the
verified source or claim an additional campaign at a newer HEAD. Seven focused
source tests passed with the final test changes before commit (`run-FohbbU`,
`focused-test-4L5JtN`); that receipt retains its actual dirty-source state.
Full Core, Wasm/native, proof, performance and full packed campaigns are not
rerun locally. Exact submitted-HEAD automatic CI and content review remain
separate obligations. Keep the PR Draft; no manual CI rerun or merge.
