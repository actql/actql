# Property Graph Delta application handoff

C owns the common Graph and Relation boundary. This unit connects an authored
complete-record Delta to the existing checked Program, mixed-input task,
managed Graph execution, retained Graph snapshot and Relation Store. B can use
the JSON operation below for text lowering; D can use the independent public
fixture for composition. This is application support, not full SGA completion.

## Public Program boundary

The application step uses existing bindings:

```json
{"from":"g","apply_graph_delta":{"with":"changes","field":"delta"},"as":"applied"}
```

`g` is the checked Property Graph input. `changes` is an exactly bound Relation
with one row and a Required, non-nullable JSON column named `delta`. The checked
Graph contract is retained in the Plan. Runtime admission still verifies the
Graph contract, base snapshot, complete before records and target snapshot;
passing Check does not turn received JSON into reference or execution authority.

The maintained minimal executable Program is constructed from
[`property-graph-presence.program.json`](../../scripts/fixtures/property-graph-presence.program.json)
by [`deltaApplicationScenario`](../../scripts/fixtures/property-graph-delta-application.mjs).
It uses synthetic Values, two node definitions, composite numeric/text keys,
parallel edges and an independently authored snapshot oracle. For an existing
authorized public Client, the call shape is:

```js
import {readFile} from 'node:fs/promises';
import {canonicalText} from './scripts/check-canonical-json.mjs';
import {deltaApplicationScenario} from './scripts/fixtures/property-graph-delta-application.mjs';

const fixture = JSON.parse(await readFile(
  './scripts/fixtures/property-graph-presence.program.json', 'utf8'));
const {document, expected} = deltaApplicationScenario(fixture, 'node_rows');
const run = await client.aql(canonicalText(document), {format:'json'});
const state = await run.wait();
// Require state.status === 'succeeded' before comparing to independent expected.
const result = run.result('answer');
const schema = await result.describe();
const rows = await result.all();
```

Use `edge_rows` for the second projection. The fixture changes N1.p from 7 to 8
and removes only E11; E10 keeps its independent identity and the same endpoints.
The M node still lacks p, while N2 still has explicit NULL. The row projection
publishes only guaranteed fields. Internal typed access checks optional fields
before and after real Relation Store reload; public rows never disguise absence
as NULL. Public comparisons use the independently expected canonical row order,
not sorted copies of observed results.

## Delta and snapshot identity

Delta remains `actql-graph-delta/0.1`. Node complete records are `{id,key,props}`;
edge complete records are `{dst,id,key,props,src}`. Identity retains domain,
definition and typed key components. Key column metadata remains in the saved
Property Graph contract. Edges are not identified by their endpoint tuple.

Both base and target CIDs use the formal five-element
`actql-property-graph-snapshot/0.1` preimage, including the saved definitions.
The obsolete four-element tuple preimage and old record shapes are not accepted
as an alternative format. Application shares the existing snapshot, record
validation and storage owners. It checks the exact base, ordered unique actions,
full before equality and target CID before exposing a completed Graph.

Malformed envelopes, wrong base/target, foreign input binding, wrong row count,
missing installed limits and capacity arithmetic overflow reject. Partial
application is not published. No old Graph fallback, parallel journal or second
execution owner is introduced.

## Execution and resource boundary

The formal mixed-input task binds Graph on port 0 and Relation on port 1.
Conversion, one-use handoff, application and completion share one bounded work
owner. The Graph and Relation reads remain borrowed; cancelling or cleaning the
application does not reclaim its input owners. Repeated cleanup does not restart
Compute or change cumulative work.

The private installed policy uses 2,000,000 logical workspace slots, a 64 MiB
execution reservation, and the existing bounded value/snapshot limits. These
are admission limits and reservations, not a count law or total physical-heap
theorem. The exact/one-short workspace fixture independently calculates 71,951
slots for its declared small input, including simultaneous conversion, snapshot
indexes, body/before admission, provisional Storage and staged output. This
fixture is not the size of every admitted Graph.

Current portable tests exercise work exhaustion, handoff cancellation, input
revocation, invalid envelopes, bounds and repeated cleanup. Real installed Host
tests deliver timer cancellation after positive conversion work and after
positive application progress. They require no completed Delta/row task, stopped
execution and zero held/reserved bytes after cleanup. They do not test SDK
cancel-response loss or physical cleanup I/O failure.

## Verification by source revision

### Follow-up ordinary Relation composition

`deltaRelationCompositionScenario(fixture, operation)` in the same independent
fixture module extends the application Program without replacing the execution
path. It uses existing main's presence-aware derive, DISTINCT and GROUP owners.
The four maintained operations are:

| Operation | Meaning after Delta | Independent public result |
| --- | --- | --- |
| `keyed-distinct` | Derive Required `bucket = 1`, then `distinct: [bucket]` | One `{bucket:1}` row |
| `whole-distinct` | Derive the same bucket, then `distinct: true` | Three typed node identities, each with bucket 1 |
| `group` | Group on the Required bucket; count all rows and max the bucket | `{bucket:1,m:1,n:3}` |
| `edge-group` | Group remaining edges on tenant_key; max edge_key and count | `{tenant_key:"a",m:10,n:1}` |

The original graph has two independent parallel edges. Its authored Delta
removes E11, so edge aggregation must count one edge, not the original two. The
node inputs keep p absent, NULL and updated to 8. Node Store assertions inspect
the bridge rows, derived sparse rows, and the consumer's complete retained
output after source-read denial and verified reload. Whole-row DISTINCT retains
these different complete rows rather than treating the common bucket as its key.
Keyed DISTINCT projects away unspecified columns; GROUP emits only its declared
keys/aggregates with count non-nullable and max nullable.

The public test checks Local/HTTPS ordered initial read, reattach, metadata,
Graph snapshot reload, Relation Store reload and temporary cleanup. A dead-branch
reference to Conditional p in GROUP must still reject before Run admission or
physical work. This is not INFER/Effect acceptance or additional kernel coverage.
It also applies an independently authored removal of every node and edge, then
checks empty node/edge GROUP streams after the same Store reload boundaries.
The empty target retains the constructor's contract/domain and declaration-derived
column names/types/nullability; it does not infer schema from observed rows.
Select only this follow-up with `--delta-relation-only` on the existing packed
Property Graph runner; the clean-source/package-manifest checks still apply.

At `28b8653fdf266b5b775d78d8c64383bbe87eea9d`, the focused command below passed
16/16 on each of JS, Wasm and native, sequentially on macOS with the pinned
MoonBit toolchain. This does not establish Linux or whole-Core acceptance.

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 120 -- --target js src/query_integration --filter '*Delta*'
```

The corresponding retained attempt directories are `run-BwNiea`, `run-JwM4ok`
and `run-bwZrAf` under `_build/local-checks/attempts/`. Resource and inventory
tests passed 195/195 on the bytes subsequently committed at that SHA. The first
192/195 run remains in `run-vp0qo3`: two stale summary-count expectations and one
incorrect expected diagnostic were corrected, without weakening the validator.

Parent `f5e403e0e767e4ba0b4ee67d68802eb4c17e7829` separately passed fresh packed
Local/HTTPS Delta acceptance 2/2 (`run-Tmn7TO`), installed Host/source public
tests 4/4 (`run-1d1nIr`), and actual Git foundation validation. Its five tarballs
and manifest identify that exact clean revision. These results are not relabelled
as a later HEAD. Successful packed temporary installations were removed after
child termination; the package manifest/digests and bounded command logs remain.

The branch then normally merged main `312a5fc38e61c24d3f90e017d9a0983f949e2e93`.
Final submitted SHA, fresh package identities, execution results and automatic
PR CI belong in the PR body. Hosted CI and content review remain separate.

## Remaining scope

Graph diff has typed checking but is not completed by this managed application
unit. This PR does not add structural merge/subtract/union, full SGA execution,
Graph catalog persistence, conditional-column refinement or a naming migration.
The registered route assurance covers logical work/workspace and the named
lifecycle tests. Source/physical-resource assurance and broader failure modes
remain recorded in the existing resource ledger; full boundary completion is
not asserted. Keep those limits when using this unit in a larger composition.
