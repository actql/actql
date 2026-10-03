# Definition-keyed Property Graph: initial vertical

## Current authority and completion boundary

### Acquired-INFER main integration (2026-10-03)

Clean source `34c1f5f82b7474f0c302d6ac7ba50597a1bf9909` completes both
the full Salesforce job and the full packed Client job. These include the
277 Salesforce tests, actual Effect recovery and all public/lower-level Store
crash boundaries, public SQL/Pipe and two-source custody/recovery, the shared
Graph snapshot and unsupported-consumer matrix, native Graph Named Results,
and packed Result descriptions. Logs:
`/private/tmp/property-graph-client-{salesforce,packed}-34c1f5f82-20261003.log`.
The clean public-query artifact is
`worktrees/.codex-scratch/public-query-evidence-6YwRFc`. This is local evidence
for that source, not a final Linux CI result.

Main subsequently advances to `c26adeb078fd54327cc9263544f4c57420f6e3c2`
(acquired-INFER #223). The current integration is conflict-free and retains
both the existing Graph checks and main's new acquired-INFER packed check.
No Graph scope, identity or unsupported-consumer policy is expanded. Before
committing the integration, the complete `pipeline_check_context` package
passes **278/278 on each of JS, Wasm and native**, public interfaces match
across the three targets, and Node/Workers generated assemblies are fresh.
Logs: `/private/tmp/property-graph-mainc26-construction-{js,wasm,native}-20261003.log`
and `/private/tmp/property-graph-mainc26-{api,node-freshness,workers-freshness}-20261003.log`.
These are integrated working-tree checks; clean-source aggregate validation,
normal fresh packed snapshot acceptance and final pushed-SHA CI are still
required before adoption. The previous source's successes do not substitute
for that integration's acceptance.

The first integrated lint run at
`6e553eeb8e75c122ae96798c51cdb734b2962de7` fails before the dependency-free
Node execution step: the Node Host fixture copy is stale relative to the
current Workers fixture. The existing `node-host-fixtures.mjs --write`
projection removes 1,134 lines of retired tuple fixture helpers and adds the
same 58 current lines already owned by the Workers fixture. No generator,
semantic oracle, dependency guard or expected result is changed. The actual
DuckDB-free standard-entry regression then passes **62/62**, with one explicitly
conditional source-only RelA check skipped in the isolated JS installation.
Formatting passes. Logs remain separate:
`/private/tmp/property-graph-lint-6e553eeb8-20261003.log` and
`/private/tmp/property-graph-node-fixture-fixed-no-duckdb-20261003.log`.
The failed lint aggregate is not reported as passing; a clean-source rerun is
required after committing this generated copy.

### Three-target Core and current-main integration (2026-10-03)

Clean source `73c58a1e1c17a09b96e5c5822fbb514aeb4e961a` passes the actual
`scripts/local-checks.mjs run core --target <target>` jobs: JS **7,287/7,287**,
Wasm **7,283/7,283**, and native **7,370/7,370**. Each job also passes common
Core checking with `--deny-warn` and the independent Run-vector tests **2/2**.
Logs: `/private/tmp/property-graph-core-{js,wasm,native}-73c58a1e1-20261003.log`.
Native uses the existing `test-native-core.mjs` owner with
`ACTQL_TEST_NATIVE_SQLITE_LIBRARY=/usr/lib/libsqlite3.dylib`; its separate
trusted-clock test is **1/1**, and the successful full-run namespace is removed
only after the child exits (84 files, 1.9 MiB before removal). This macOS result
does not replace the final submitted SHA's Linux CI.

Main `4f6feed519170e46c0065d1491c40287e6d34f1a` is integrated at
`aca1d3f6a4130f6be5054f2428eb9f2718448d60`. The only textual conflict is
`package.json`: the Graph surface/public/fresh-packed acceptance and SDK
cancellation tests stay registered exactly once, while main's redundant
immediate runtime-builder checks are removed. Historical foundation records
and validators are unchanged; the explicit merge resolution records both
parents and all applicable declaration inputs. No independent edit is added
to `carrier_tasks.mbt`; main's implementation is adopted unchanged.

Before committing that integration, constructor/fused shared-input tests
**21/21** and main's multi-root Relation tests **2/2** pass on each of JS,
Wasm and native, and formatting passes. Logs:
`/private/tmp/property-graph-main4f-{construction,data-set}-{js,wasm,native}-20261003.log`.
These are integrated working-tree diagnostics matching the committed merge
tree, not new full Core results. Current-source API/spec, fresh packed public
snapshot acceptance and final fixed-SHA CI remain to be recorded. No all-SGA
completion, B adoption GO, public branch replacement or merge is claimed.

The first actual composed-history check rejects the previously undeclared
`b2180c826a0115b0f2a611efb77d25dc2cdb39ad` package registration merge. Log:
`/private/tmp/property-graph-main4f-history-20261003.log`. This is separate
from the 84/84 composer unit tests: it is a missing production declaration,
not a weakened-validator workaround or a product Graph failure. Both that
merge and the later `aca1d3f6a4130f6be5054f2428eb9f2718448d60` now receive
exact-parent/digest/rationale resolutions, including the earlier resolution
among the later merge's inputs. The unsubmitted pre-correction commit
`cba8da271de88ad42b93259567cd2caf6cac371e` is retained at local ref
`archive/pr164-cba8da271-pre-foundation-fix-20261003`; its declaration commit
is amended before publication, without changing either merge's source tree.

### Earlier integrated implementation checkpoint (2026-10-03)

The current implementation checkpoint is
`5cae69a164b7bc26ee66bff0b14eb2284b6c4674`, including main
`a32d8c94404c3f6be52d1fcfb73aab21cbf7093c`. The complete CI-equivalent
local spec job passes at that clean SHA: `check:spec`, strict resource
completion, independent execution-authorization vectors, non-writing metadata
verification and the final tracked-diff check. Resource regressions are
**176/176**. The scope remains **52 executable routes plus 17 typed
pre-execution refusals**, not complete SGA. Log:
`/private/tmp/property-graph-spec-5cae69a16-20261003.log`.

The sole current representation reaches constructor, scoped MATCH, TRAIL and
bounded snapshot persistence/reload through the existing owners. Tuple
construction, readers, storage/profile branches, unsupported algorithm kernels
and execution fallbacks are removed. Supported generic capacity, ownership,
delivered cancellation and cleanup obligations have current positive fixtures;
unsupported algorithm-specific guarantees are withdrawn, not reported as
execution success. The guarantee ledger's current table maps these separately.
The real Host matrix and its selected Relation guarantee migration are
recorded below, including the initial failures and their corrections.

Final-source three-target Core/API, fresh packed public snapshot acceptance and
same-submitted-SHA required CI remain mandatory. The older packed successes
below are not substitutes. Published #164 is still the old Draft HEAD; no B
adoption GO or main merge is claimed.

Both original source histories are now preserved remotely at
`archive/pr164-published-125a186-20261002` (full SHA
`125a186ae9396fbfc7865641922e8e8a4ffc87d9`) and
`archive/pr164-pre-reconstruction-b88d27bb3-20261002` (full SHA
`b88d27bb30b4d38bd046ce5912bdf29e6b78d418`). Replacing the PR branch remains
a separate, explicitly announced lease-protected operation.

## Earlier checkpoints (results belong to their recorded source)

### Clean public checkpoint and compilation pin refresh (2026-10-03)

Clean source `0deb69e70885f9f51e400f4d8131f3b2ff514d85` passes fresh packed
Local/HTTPS **2/2**, including the shared refusal matrix (all 17 classified
consumers, with and without external input). Normal prepack builds all five
packages; the consumer PATH contains no checkout toolchain. The independent
fixture verifies physical snapshot save, original source revocation, verified
reload, typed composite keys, independent parallel edges, labels and exact
snapshot bytes/CID through public MATCH/TRAIL Named Results. Evidence and all
five tarball digests are retained in
`/Users/t14i/workspace/20260822/worktrees/.codex-scratch/property-graph-package-rvQDA4/acceptance.json`.
Log: `/private/tmp/property-graph-packed-0deb69e70-20261003.log`.

The subsequent aggregate spec run passes the shared dispatch boundary,
resource gate and its mutation regressions, then stops at the stale grammar
manifest. The current query-text rules replace property-inferred labels and
tuple edge identity with the agreed definition-owned labels and typed keys;
their source hash must therefore change. The existing manifest generator
refreshes the grammar JSON and compiled pin together, without modifying its
checker or the historical foundation. The query-rules digest becomes
`63cf6ff9f71feba9b5c882a4b0bef83f9c14bdb61e24e46a8bd16239e34dbf32`, and the
grammar manifest CID becomes
`sha256:2bf8ef0846b81f91fec96548d10dddd8c7e5a82b7db05444b38eefa316779c11`.
Canonical manifest/freshness regressions pass **5/5**; the complete common
check-environment package passes **224/224 on each target**. Logs:
`/private/tmp/property-graph-manifest-{js,wasm,native}-20261003.log`.
The packed run predates this pin refresh and is not claimed as final acceptance
for the later submitted SHA. Aggregate spec log:
`/private/tmp/property-graph-spec-0deb69e70-20261003.log`; checks after the stale
manifest failure did not run. Full final-source acceptance remains mandatory.

### Snapshot composition boundary correction (2026-10-03)

At `155bb335183e28f462614db3aa1c01618b1ff30f`, aggregate `check:spec` fails
in `connector-dispatch-boundary.test.mjs`: shared client dispatch constructs
the concrete `local` configuration key for snapshot storage. This is a current
snapshot connection defect, not an unsupported SGA operation or a reason to
relax the guard. The concrete Embedded adapter now creates the configuration
map; shared dispatch forwards that map without selecting a Connector identity.
Current acquired-input authorization remains supplied by the dispatch owner.

The regression requires an opaque installed provider configuration to arrive
unchanged at publication dispatch. It fails before the change and passes after
it. The focused dispatch custody and common-boundary tests pass **22/22**.
The unfiltered test also imports two-source public acceptance: seven failures
there are caused by the borrowed stale `@actql/client-wire` lacking
`validCheckOutcome`, before public execution; the missing subsequent reports
are consequences, not successful crash/recovery checks. A negative-lookahead
test-name selection still selected nested public tests and reproduced that
environment failure; the final focused selection names the relevant unit tests
explicitly. Borrowed dependencies and acceptance expectations were not changed.
Retained failure areas are `_build/two-source-public-4QL6T2` and
`_build/two-source-public-h3xlgO`. Full public acceptance still requires fresh
packages on the final source. Aggregate spec did not reach its later checks in
the initial run and is not reported as successful.

### Initial-scope resource gate checkpoint (2026-10-03)

On top of `caa5932bce615c1b6d46f392575033c24e71500f`, the existing resource
gate uses the existing current-profile family classification as its only scope
authority. It maps 52 executable routes and 17 typed pre-execution refusals;
refusals are not execution success. One shared public fixture checks every
refused operation in source-free and external-input Programs, before Run
admission, acquisition I/O or physical dispatch. No per-operator refusal
fixture, parallel capability list, additional gate or legacy conversion is
introduced. Executable non-Graph obligations and common resource-owner checks
remain strict.

The initial constructor/MATCH/TRAIL boundary records now point to current
definition-keyed regressions, not retired tuple fixtures. Six resource files
pass **26/26 on each of JS, Wasm and native**, with exact/one-short work and
workspace, private-stop custody, repeated typed selectors and long text/key
handling. The MATCH predicate oracle independently counts expression transitions
and binary-frame/binding workspace. The edge oracle charges each authored label
entry, including repeated case-insensitive labels. The path oracle distinguishes
physical adjacency scans from once-per-self-loop candidates and verifies empty
hop filters, zero-hop output and every private stop for walk/trail/acyclic in
both stored and viewed paths. This does not cover every nonempty-hop predicate
variant or certify unimplemented SGA consumers.

The installed Host matrix passes **15/15 on Node**: literal and typed-property
node/edge MATCH plus explicit TRAIL, each with success, prefix cancellation and
following Relation cancellation. Two downstream consumers, no later consumer
start after cancellation, repeated close and all four retained/reserved capacity
counters returning to zero are verified. Existing snapshot failure/cancellation
and resource-owner tests are not replaced by unsupported refusals.

The existing strict resource gate and coverage summary check pass. Their own
mutation regressions pass **184/184**, no skips. The first resource-gate test run
had seven obsolete assertions: six still treated retired node/edge projection
routes as executable and one used the historical summary count. These assertions
were replaced by the inventory-driven refusal obligation/current summary;
supported MATCH/TRAIL and non-Graph proof-removal checks remained strict.
The complete touched Node surface/driver suite also passes **22/22**, including
snapshot handoff success, cleanup retry, snapshot cancellation and constructor
in-flight cancellation. Formatting, JavaScript syntax and diff checks pass.

Logs: `/private/tmp/property-graph-resource-subset-{js,wasm,native}-20261003.log`
and `/private/tmp/property-graph-resource-gate-tests-20261003.log`. These are
working-tree checkpoint results, not pushed-SHA acceptance. Remaining obsolete
Node Host fixtures still require guarantee-preserving migration. Final-source
public snapshot, fresh packed acceptance, aggregate Core/spec/API and required
CI remain open. The four initial operations remain partial and the other Graph
operations remain blocked. No all-SGA completion or broader mechanized guarantee
follows from this checkpoint.

The superseding decision is ActQL-only. `smoothhq/aoa` and its PR #2 are not
used: no external package, checkout, build, authentication or CI success is a
completion dependency. The normative law body is owned here as
`spec/dependencies/actql-property-graph-laws.json` with identifier
`actql-property-graph-laws/0.1`. It retains the agreed constructor semantics
and explicitly states graph-wide property type and shared-label consistency.
The existing ActQL pipeline owner consumes that body; historical `aoa` names
in unrelated local IR contracts do not import an external implementation.

The original dependency-integration checkpoint combined main
`16d93c2bf7c9c7aa0c485416a7ea1436fd8a060a` with the prior #164 source at
`dfb1c51318a7faa306548c213bf1888d92ff7fce`. Local
registration, canonical preimage and spec-family checks pass. The independent
complete snapshot fixture is
`portability/corpus/property-graph-owned-snapshot.json`; its records are not
derived from a Graph encoder or runtime output. A law ownership change has new
law, contract and snapshot CIDs; historical fixture identities stay frozen.

This is not final acceptance. The common Graph requires definition-scoped
metadata; the retired tuple constructor cannot issue a second Graph profile.
The latest checkpoint below connects public snapshot save/reload through the
existing bounded owners and passes fresh packed acceptance. Remaining obsolete
consumers, positive fixtures and coverage inventories still need source
migration. Complete Core/spec and final-SHA required CI remain mandatory. No
success from an earlier checkpoint is reused for that decision.

### Latest verified integration and remaining blockers

Clean source `d1d7c9abf57ef1ac08817279ac0dd161890e88ac` integrates main
`5bb95908901ba57ae4a83ff119d9d9a3f68cf154` and the public snapshot connection.
Fresh packages built by normal prepack pass **2/2 Local/HTTPS** through the
actual public Program -> Host -> Named Result path. The driver physically
saves the independently expected snapshot, revokes the source generation,
completes verified reading before reload, and executes MATCH/TRAIL on the
restored generation. Composite typed node/edge keys, independent parallel
edges, label sets, exact snapshot CID/bytes and physical temporary-body
reclamation are checked. Result reattach is a separate assertion, not the
roundtrip evidence. There is no new public Graph catalog or SDK save API.

Packed evidence is retained at
`/Users/t14i/workspace/20260822/worktrees/.codex-scratch/property-graph-package-UkPcwp`:
`acceptance.json` records the clean full source SHA and all five public package
digests; pack/install/test logs and Host state are preserved. The command used
Node 24.21.0 with the pinned MoonBit toolchain for packing, not for the external
consumer. Source-level focused common regressions passed **34/34 on each target**
and Node driver/surface/cleanup regressions passed **49/49** before this clean
checkpoint. Official tracked API verification passed after main integration.

The complete Core JS run at that same clean source is still red:
**7,584 total, 7,170 passed, 414 failed**, exit 2. Log:
`/private/tmp/property-graph-core-js-d1d7c9abf-20261002.log`.
The previous INFER and Graph lifecycle failures are absent. Remaining groups
are query_integration (173), local_sga (58), pipeline_typing (45), program_check
(39), lowering_relation (35), pipeline_check_context (20),
capacity_graph_preflight (17), capacity_program_step (12), query_program (7),
managed_graph_storage (5) and bounded_graph_diff (3). These are not all declared
obsolete or repaired, and no aggregate success follows from focused tests.

The subsequent Storage/diff migration removes 1,500+ lines of unreachable
endpoint-tuple execution rather than enabling an old profile. Storage's five
regressions remain executable with current definition-keyed inputs; parallel
edge retention, indexed lookup/revocation, refusal of endpoint synthesis,
atomic capacity/work/cancellation and independent UTF-8 byte counting are
retained. Node construction requires a definition and key, and duplicate
content cannot restore tuple-style collapse. Old tuple delta completion tests
are archived as inert text; current tests require explicit unsupported refusal
without consuming parallel edges and retain pure limit validation. Complete
Storage and diff packages pass **12/12 and 3/3 respectively on each of JS,
Wasm and native**. Official API verification passes. The expanded diff fixture
initially supplied a zero field ceiling for its one-key definition and failed
before execution; the ceiling was corrected without changing admission.
Log: `/private/tmp/property-graph-storage-diff-retirement-final-20261002.log`.
This source update has not had another aggregate Core or fresh packed run.

The subsequent lowering fixture migration retains the supported constructor,
MATCH and TRAIL as current executable regressions. The constructor has one
canonical `BRIDGE.rows.to_property_graph` occurrence, separate ordered producer
roles, an independent edge key, both shared endpoint bindings and finite
preparation. MATCH retains projection order, typed identity repetitions,
definition/label bindings and exact/one-short name and entry budgets. TRAIL
retains ordered hops, repeated typed start IDs and Relation selector ports;
unconnected definition-free predicates are explicitly rejected. The mixed
Vectors projection remains an unchanged positive obligation. Thirteen
unconnected Graph operations and two projections must fail with the exact
typed unsupported issue and operation path. Twenty old positive algorithm
tests are archived, not claimed as implemented; eleven original files are
verified byte-identical to `ff364752f462185fb1c41d32cb82b2f438a9e10e`.

The complete lowering package passes **207/207 on each of JS, Wasm and native**
with the pinned toolchain. Native log:
`/private/tmp/property-graph-lowering-native-20261002.log`.
Initial fixtures failed before execution because shortest/reach selectors,
the mean generator alias and constructor label/property shapes were not the
registered input forms. They were corrected to the existing contracts, not
accepted by weakening refusal checks. A `-f` invocation matched no test names
and ran 0 tests; it is not counted. File-path selections and then the complete
package ran the stated regressions. Formatting and `git diff --check` pass.
This checkpoint changes test inputs and preserves the withdrawn tests as inert
evidence; it has not had a new aggregate Core, spec or fresh packed run.

Four mixed upper-pipeline fixtures are subsequently migrated without dropping
their non-Graph cases. Produced Graphs retain the exact checked producer owner
and separate node/edge upper bounds through current MATCH; row counts are not
substituted for Graph measures. Scoped MATCH expressions and literal TRAIL
retain source correspondence, exact/one-short collector work and slot bounds,
without manufacturing predicates for unsupported operations. The TRAIL output
guard is distinct from its hop ceiling and retains exact owner/source and
finite collection limits. Time-series parameter slots remain positive; current
parameterized Graph bounds/components are explicitly refused before slots.
The four files pass **18/18 on each target**; native log:
`/private/tmp/property-graph-pipeline-custody-native-20261002.log`.
All four originals are byte-identical inert archives. Initial fixture failures
were a missing required generator alias and missing node-MATCH selector, fixed
to the registered input shape. This is focused validation, not full pipeline
or aggregate Core success.

At clean source `1ef8f0edd1e43741e551300a386c1491382a8b75`, complete Core JS
is **7,566 total, 7,199 passed, 367 failed**, exit 2. Log:
`/private/tmp/property-graph-core-js-1ef8f0edd-20261002.log`.
Lowering, Storage and diff have no remaining failures in this run. Failure
groups are query_integration (173), local_sga (58), pipeline_typing (41),
program_check (39), pipeline_check_context (20), capacity_graph_preflight (17),
capacity_program_step (12) and query_program (7). Unsupported old positive
tests, mixed ownership/capacity fixtures and Frontend-owned inputs still need
individual classification; none is silently skipped or declared harmless.
Main was fetched again and remains
`5bb95908901ba57ae4a83ff119d9d9a3f68cf154`. No main integration or source
edits overlapped this gate. The latest focused results do not discharge spec,
fresh packed or final-SHA required CI.

At source `d5e2b5b491d0e14b70c8dc8ca41cde13a24805ec`, four additional
upper-pipeline files retain ordered/repeated constructor operands, MATCH
identity rows, shared preflight budgets and TRAIL selector custody. The empty
selector's exact zero bound is derived from empty VALUES -> current constructor
-> MATCH; its nonnullable JSON identity field is verified. Supported TRAIL
paths retain the physical checked selector, source locations, copied indexed
reads and exact/one-short budgets. Traversed-node output, shortest, subgraph
and union must issue explicit typed refusals rather than legacy obligations.
Aggregate call provenance and every non-Graph case remain executable. The four
original files are byte-identical inert archives from
`6d137b83ad7459d142f44e4acc98ebad95f8b92d`.

Focused regressions pass **12/12 on each JS, Wasm and native**. Native log:
`/private/tmp/property-graph-pipeline-constructor-custody-native-20261002.log`.
Initial authored fixtures failed on invalid label configuration, prohibited
JSON VALUES, empty MATCH IDs, zero TAKE and a property/binding collision.
The final fixtures use the existing constructor/MATCH contracts; none of those
admission rules was relaxed. A one-short limit can propagate a nested owner
budget issue rather than only the pipeline's outer issue; the original
requirement remains exact-limit acceptance and one-short rejection.

The complete pipeline package at the clean committed source above remains red:
**343 total, 308 passed, 35 failed**, exit 2. Log:
`/private/tmp/property-graph-pipeline-d5e2b5b49-20261002.log`.
The prior 41 pipeline failures are reduced by six migrations, not skipped.
Remaining files still require individual treatment of supported MATCH/TRAIL,
generic ownership evidence and withdrawn algorithm-positive fixtures. This
checkpoint does not claim aggregate Core, spec, fresh packed or final-SHA CI
success. Main was fetched again and remains `5bb95908901ba57ae4a83ff119d9d9a3f68cf154`.

Main's new foundation composition validator rejects eight reachable historical
#164 commits that changed the immutable #148 reuse baseline. Restoring current
bytes cannot change those ancestors. The old global current-foundation record
is preserved as inert historical text, and main's frozen records/validator are
unchanged. Log:
`/private/tmp/property-graph-current-foundation-predeclaration-20261002.log`.
The user has approved preserving the old branch and reconstructing changes
and independent declarations on current main. Before replacing the published
branch, the exact preservation ref, old/new SHAs and force-with-lease condition
will be announced. No history rewrite, force-push, guard relaxation or reuse
of earlier CI success has occurred. The historical integration test also needs
migration to the new declaration contract; it is not a current guarantee.

The published PR remains a separate older checkpoint, Draft and not GO.
Full Core/spec migration, provenance reconstruction and required CI on the
submitted source remain open. No external AoA work or Graph Frontend edits
are part of these checkpoints.

The remaining sections record the initial additive vertical and its historical
verification. Their legacy-preservation promises are superseded: the new
Property Graph is the sole implementation target, without an old-format reader,
fallback or conversion that collapses parallel edges. Historical records are
evidence, not a compatibility implementation.

## ActQL-only consumer migration checkpoint

Normal Program admission rejects the retired constructor and old Graph port
serialization has no fallback. SourceView Graph schemas now use the owned
Property Graph law and the new definition-scoped contract. The shared Catalog
law resolver selects `PropertyGraphLaw`, not a legacy SGA identity law.

An independent SourceView fixture checks the entire schema envelope, view,
Catalog and Environment CID chain, including the distinct canonical ordering
rules. Its Environment CID is
`sha256:daa21d77bc5c20b691c71098c493813e7e63f838be76326fc20d687337d49e63`.
Expected bytes and identities are authored and hashed independently, not
copied from a compiler or runtime.

Current-source focused regression evidence (not final acceptance):

- Owned-law/registration, complete snapshot fixture and SourceView CID oracle:
  Node **10/10**.
- Graph schema and Environment admission: **209/209 on each of JS, Wasm and
  native**. Structural JSON
  nodes and type/label comparison work are separate bounds; the same enclosing
  admission owner debits comparison work once. Exact limits, one-short limits
  and a second unused schema exercise the accounting boundary.
- SourceView Graph MATCH capacity and imported producer ownership: JS **4/4**.
- Effect closure/physical Result target migration: JS **9/9**.
- Host Effect consumer migration: Node **3/3**, including independently held
  Result ports and exact early/final/imported physical producer bindings.
- Repeated constructor operands and node/edge MATCH through Result imports:
  JS **1/1**, covering empty inputs and repeated versus distinct producer visits.
- Current provider/construction/internal-snapshot/Plan vertical: **25/25 on
  each of JS, Wasm and native**, after withdrawing unused legacy provider
  start/kernel/cleanup branches. The refusal probe fails at the pre-correction
  integration checkpoint (1/2), then passes after correction (2/2). The Plan
  contract literal is independently hashed from the normative machine body.
- Fresh public packages: **2/2 Local/HTTPS** constructor, MATCH, independent
  TRAIL and Named Result acceptance, with Node v22.22.0 and no MoonBit lookup
  path in the repository-external consumer. Evidence, package digests and Host
  state are retained at
  `/Users/t14i/workspace/20260822/worktrees/.codex-scratch/property-graph-package-v7gUOq`.
  This is an uncommitted-source checkpoint, not final-SHA CI and not public
  snapshot save/reload. An earlier packed attempt was deliberately interrupted
  (exit 130) because the formatting check was still active; it is not counted
  as a successful run or a product failure.

The former `graph -> normalize_graph -> node_rows` consumer is replaced by
`property_graph -> match_nodes`. One fewer physical operation is expected;
ownership and retained Result inventory assertions are not weakened. Graph
node bounds count declared nodes rather than invented endpoint nodes.

The initial full current-source Program test run had **298/347** passes and
**49** failures, mostly positive assertions for the withdrawn tuple Graph
path. Subsequent full runs reached **307/347** with **40** and then **310/347**
with **37** old-profile failures. The latter is recorded in
`/private/tmp/property-graph-program-check-after-provider-retirement.log`.
There has been no aggregate green run. These failures are not reported as successful final
verification or worked around by restoring legacy execution.

The current spec run passed engine accounting (1,063 tests), source generators
and Connector/Host boundary checks, then was stopped during resource-audit
mutation tests. A separate non-writing production-route check completed with
exit 1 and specifically detected the withdrawn legacy dispatch markers.
Current-profile unsupported operations and historical assurance scope must be
registered explicitly; there is no successful full spec run. The resource
gate is not removed and historical assurances are not reused as new-profile
support. `moon fmt --check` and `git diff --check` pass at this checkpoint.

The next narrow public-admission regression covers all 16 currently unsupported
legacy SGA/projection spellings after an admitted Property Graph constructor,
even with the old SGA profile claimed. It fails before the correction (0/1),
then passes alongside both supported public Program cases (3/3 on each of JS,
Wasm and native). The static integration boundary now returns the existing
typed `UnsupportedStaticPath` rather than deferring to a legacy selection or
conversion. This is an implementation subset, not a new restriction on the
adopted language's operation grammar. The packed run above precedes this latest
admission change and must not be represented as its final verification.

## Frontend handoff

The common machine constructor is `property_graph`, selected explicitly with
`version: "actql-property-graph-constructor/0.1"`. Its output is the separately
admitted `actql-property-graph-contract/0.1` Graph, not a legacy simple Graph.
The complete runnable input is
[`property-graph-parallel.program.json`](../../scripts/fixtures/property-graph-parallel.program.json).
It constructs two independently keyed parallel self-loop edges, performs a
definition-scoped MATCH and exposes the keys through a public Named Result.

The constructor contains ordered `nodes` and `edges` definitions. Each has a
definition `name`, resolved producer `from`, and nonempty ordered `key` column
list. Edge `source`/`target` identify a node definition and ordered endpoint
columns. Static label entries select declared properties independently of
label membership. See the normative
[constructor contract](../spec/language.md#property-graph-construction).

The common checker owns definition-domain issuance. Frontends must not invent
a domain, use a current input Artifact CID as provenance, or repeat Graph
validation. The initial vertical uses retained VALUES producer definitions;
an external schema/name alone is rejected as missing definition provenance.
Frontend syntax and name resolution are a separate responsibility.

Within one admitted domain, identity contains the definition, semantic key
types and complete key tuple. Properties, labels and endpoints are content,
not replacement identities. NULL element keys exclude elements. Duplicate
non-null keys reject even when their payloads match; duplicate edge keys are
checked before missing-endpoint exclusion. Missing or NULL endpoints exclude
an edge without inventing nodes. Independent edge keys preserve parallel edges.

MATCH requires the selected `definition`, optionally a static `label`, and
uses the existing predicates/projection. Optional identity/source/target
bindings retain complete typed identities. TRAIL uses `path_mode: "trail"`
and `emit: "paths"`; it tracks edge identities, not endpoint tuples. Other
unimplemented new-profile SGA operations fail closed.

## Snapshot and compatibility boundary

The existing bounded storage, traversal, snapshot, stop and cleanup owners are
reused. No new task-graph checker, Run state machine or capacity ledger is
introduced. Snapshot framing is separately identified as
`actql-property-graph-snapshot/0.1`; reload validates the full admitted
contract, typed identities, endpoint correspondence and content identity.
Constructor exclusions do not repair an invalid stored snapshot.

Historical constructor bodies, snapshot framing and tuple edge identities
remain immutable evidence only. They are not a promise of an executable
compatibility path. Explicit installed profile selection is required; a legacy
module claim is insufficient. No implicit migration or cross-domain mapping is
provided. Public Local/HTTPS Result publication was tested after MATCH/TRAIL;
that is not evidence of a durable Store Graph snapshot catalog.

Review correction: the adopted **public** snapshot roundtrip acceptance remains
incomplete. Internal save uses `bounded_graph_snapshot.prepare_property` and
`take_property_output`; internal reload uses
`local_bridge.start_property_snapshot_reload`, with full typed identity/domain,
label and content admission before handoff. Its callers outside the bridge are
whitebox tests. The public Graph provider currently connects constructor and
MATCH/TRAIL but not saved-snapshot input admission. The SDK exports no Graph
save/reload operation; Run Host `CapturedResultSnapshot` covers Result
publication, not Graph restoration. Public Result reattach is not a snapshot
roundtrip. The Frontend handoff is therefore limited to the tested constructor,
MATCH/TRAIL and Named Result paths. No new catalog, implicit conversion or
constructor re-execution is introduced to stand in for this missing boundary.

### Owner-bound snapshot connection checkpoint

The common Material now supports a lazy, generation-bound snapshot operation.
It is not a second storage or accounting owner. A foreign factory is refused
before acquisition; even a defective trusted factory returning a foreign
operation leaves that operation's cleanup handle under the original Material.
A claim is once-only across repeated references. Failed preparation cannot
start another allocation. Cleanup failure or an incomplete cleanup result
keeps custody for retry, including after the source reference is revoked.
Local dispatch's retention-release and cleanup-refresh checks use this pending
custody, not source availability alone.

The Graph family adapter reuses `PropertySnapshotHandoff`, the sole bounded
snapshot encoder and the existing reload admission. It captures the checked
owner/port before any received bytes. Exact bytes/CID must be finalized before
source release; restoration is a distinct completion generation and cannot
silently keep the old material. Total/frame byte refusal is latched and cannot
be resumed into a successful save. Terminal stop/failure reports preserve
actual cumulative work for the driver; diagnostic text is separate from the
typed common issue. No cleanup work is invented.

Focused current-source evidence is **10/10** common Material/lifecycle tests
and **14/14** snapshot-selected integration tests on **each of JS, Wasm and
native**. The latter includes the
independent canonical fixture, early release, wrong CID, source revocation,
one-time restored transfer, byte refusal, cancellation and late identity
failure. Earlier raw handoff tests passed **8/8 on each target**, before this
latest Material connection. The current logs are
`/private/tmp/property-graph-material-custody-{js,wasm,native}-20261002.log`
and `/private/tmp/property-graph-material-snapshot-{js,wasm,native}-20261002.log`.
These are uncommitted-source tests, not final-SHA CI. Initial adapter compilation errors
(Debug rendering and Result propagation syntax) were corrected, without
changing any expected snapshot bytes or weakening assertions.
The three changed common-package interfaces were regenerated with
`moon info --target js,wasm,native`; no backend divergence was reported.
Focused formatting and `git diff --check` also pass. This does not replace the
full repository API/freshness or final CI gates.

**Still unconnected:** selected provider capacity reservation, driver charging
and restored-port installation, the Node Store lease/write/seal/verified-read
path, and actual public Local/HTTPS snapshot acceptance. The family adapter
tests move bytes in memory; they are not public persistence evidence. Fresh
packed packages and final-SHA CI must be run after that connection and the
remaining profile migration/gate work.

The process Store boundary needs explicit physical cleanup verification:
`process-client.close()` revokes local rights, but is not a report that the
control-side `process-service` has reclaimed its sealed body. Do not equate
local `reservedBytes == 0` with physical file deletion or parent Store capacity
release. The connection must keep the existing parent body's cleanup owner
through verified read completion and reclamation; a failed or uncertain seal
must not discard its original lease responsibility.

The first physical connection supplies explicit `release-sealed` on the
existing process Store, separate from ordinary lease close. The request names
the exact sealed body and immutable physical report under the installed
session/Run capability. The parent invokes that body's existing cleanup owner
and returns a typed reclamation report only after checking its pending state.
Active reader custody blocks deletion and capacity reuse. Lost/invalid replies
keep local pending custody and retry the same parent body; released names are
bounded tombstones under the existing entry ceiling, not new generations.
Published Result holdings are not implicitly revoked by ordinary lease close.

The three new physical Store cases failed **0/3 before** this connection.
The first implementation exposed an incorrect assumption that cleanup retry
returned a status record (it returns a completion boolean); the active-reader
regression caught the premature ACK, and the adapter now reads the existing
cleanup owner's status after retry. The initial correction passed **9/9**
including existing binary and real-process Store tests. Expanded lost/invalid
ACK, seal-response loss and parallel-release regressions passed **26/26** with
the existing service and delegated process suites. This is physical Store evidence,
not yet public Graph snapshot acceptance.

## Executed regression evidence

Implementation checkpoint: `dc111614df6aadca1d58ae6eaef4893dc7fca421`.

- Constructor, domain, formal Plan, snapshot save/reload, Graph port and legacy
  Result regression sweep: **38/38 each on JS, Wasm and native**.
- Source Node surface, actual Local/HTTPS public SDK and legacy RelA boundary:
  **7/7**, Node 22.23.2. The Host cancellation test observes positive constructor
  work before a real timer abort, no partial Graph completion, and repeated
  close with no pending custody.
- Exact constructor control-work/workspace is independently counted as **45**;
  45 succeeds and 44 refuses under quanta 1 and 7. Cleanup cannot restart work.
- Repository-external packed Local/HTTPS acceptance: **2/2** before that
  checkpoint. Five packages were produced through normal prepack; the child
  resolves installed packages without a checkout or MoonBit lookup path.
  This is not final-SHA CI evidence.
- New-profile resource evidence cannot borrow legacy construction or Host
  cancellation evidence. Removing the dedicated cases/assurances or replacing
  the dispatch marker is required to fail the gate.

Initial verification failures are retained, not hidden: missing exact local
dependencies and an insecure endpoint were corrected with pinned dependencies
and real synthetic-CA HTTPS, not relaxed policies. A stale route-count negative
fixture was updated for the additive route. Full spec then passed its Local
coverage/resource checks but stopped at the required `MOON_HOME` environment
check. The pinned rerun exposed a generated Program-schema pin and a legacy
coverage-set assertion that had not distinguished the additive constructor;
both are corrected without changing the frozen legacy profile.

The new normative grammar/classification roots propagate through the Values
fixture's local Unit contract closure, proof, publication limits, Result Plan
and Run identity. `scripts/client-values-dependency-oracle.mjs` independently
authors these preimages from normative role bodies and the synthetic input;
it imports no compiler or issuer. Historical vectors retain their original
pins and literal CIDs. The new Run fixture is independently derived as
`sha256:f171d251195c262096577393afc6d51390ca7b4b7b63bda8b17c74a13a6d54f6`.
This global dependency impact does not change legacy Graph contract bodies,
tuple identities or snapshot framing. Final complete gates and Linux CI must
be reported against the submitted SHA in the PR.

## Single executable Graph contract checkpoint

The common `Graph` requires an admitted Property Graph definition. The retired
endpoint-tuple constructor returns `UnsupportedGraphProfile`; it cannot issue
a second executable profile. Contract admission, canonical serialization,
snapshot preparation and identity encoding now have only the definition-keyed
representation. MATCH and TRAIL use typed element identities and label sets;
the common rows-to-Graph entry delegates to the existing Property Graph owner.
No parallel kernel or lossy endpoint-tuple conversion is introduced.

Reach, shortest-path, structural operations and diff that have not been
connected to the new semantics return `UnsupportedGraphOperation`. This is an
explicit current implementation gap, not a language restriction or a claim that
the legacy implementation provides the new semantics. Historical raw fixtures
remain negative inputs; they do not reconstruct a legacy executable Graph.
Some obsolete symbols, unreachable implementations and historical positive
test inventories still require retirement or migration before full acceptance.

The focused common-contract, admission, MATCH, snapshot, storage and provider
regressions passed **98/98 on each of JS, Wasm and native**. An additional real
Property Graph diff refusal test passed **1/1 on each target** and checks that
refusal does not consume or alter the source material. The initial focused
runs exposed outdated positive expectations and an opaque-Graph admission hole;
these were corrected to test the actual current contract and distinguish
incomplete Graph input from an unsupported operation. No relaxed legacy
fallback was used to pass them.

Three-target interface generation and the official tracked-interface check
passed after commit `172ec7378`. Shared Graph interfaces do not diverge.
The current Relation pipeline foundation
explicitly records the integrated `dfb1c51318a7faa306548c213bf1888d92ff7fce`
source and its added Graph acceptance commands. The immutable historical #148
baseline and its oracle digests are restored byte-for-byte. The first foundation
check exposed a prior #164 edit of the historical baseline; that edit is removed
rather than updating the historical expectation or bypassing the guard. The
rerun passed **28/28**, including all mutation/refusal tests and the actual
repository reference. This provenance update does not
extend the conditional Relation theorem to Property Graph providers.

Full Core, spec, fresh packed public snapshot acceptance and required CI have
not yet been established at this checkpoint. In particular, internal snapshot
roundtrip and physical Store release tests do not prove the public save/reload
route. The PR remains incomplete until that route and the remaining consumer
migration are validated on one submitted SHA.

## Current consumer and key-evidence corrections

The first full JS Core run at `843d95bada7a41e8c0eb25dd983902ac2d47e1c3`
reported **7,356 total, 6,860 passed, 496 failed**. Its original log remains at
`/private/tmp/property-graph-core-js-retirement-20261002.log`. The failure count
is not classified wholesale as obsolete: it includes real current-consumer
connections and dependency-vector corrections as well as retired positive
fixtures. The aggregate is still not green.

Definition-free scope and tuple row projection can no longer manufacture a
Graph schema from opaque input. Complete current Graphs receive an explicit
unsupported-operation refusal at these unconnected entries; incomplete Graphs
receive an incomplete-input refusal. Definition-scoped MATCH retains its actual
typed scope. The SourceView corpus is regenerated from the current independent
`empty-property-graph` input, rather than retaining the retired tuple fixture.
The existing #133 wrong-carrier work-custody regression now uses an actual
current Graph material; rejection still preserves child/parent work and cannot
start its successor.

The independent Values oracle selects the owned Property Graph law for the
current Catalog closure. The historical Check Environment role is frozen to
its normative predecessor bytes, independently hashing to
`sha256:50a14e0c2454d439df53fc4be570d6e008299ba1005cc442838a985337cb3dd8`.
This repairs a missing historical role pin, not a historical CID expectation.
Every predecessor golden CID remains unchanged. Current preimages are authored
without importing a compiler, issuer or runtime and independently yield:

- Unit: `sha256:bd1d8948bb65f17b94e971ec556f43add62bec77e59fdb3723f588cfe7b76810`.
- Proof: `sha256:b71c7850a144cc4c855e3093c1c198fdcddec92ee8547480e689b74f6e36d563`.
- Result Plan: `sha256:457f27fe1a1f226e1ebab73824370e2242c003886619e37e4f18ed866c897d3f`.
- Run: `sha256:838a90f1bb3ee17c4e8a25db56d1756c5201897f7a1128498832796ff8c18a90`.

The scoped SourceView/projection/admission/constructor/Plan/Values/#133
corrections passed **200/200 on Wasm and native**. JS passed the same selected
groups as **173/173 plus 27/27**. The independent Node Values oracle passed
**2/2**. These are focused results, not complete Core or final packed evidence.

A further current MATCH connection defect was independently reproduced before
the correction: **3 of 4** new regressions failed. The checked identity binding
was dropped, while historical row aliases could fabricate an endpoint/property
tuple key. MATCH key evidence now uses only the checked definition's complete
typed identity binding. It retains the original CheckedMatch producer and its
validation obligation. Endpoints, properties and labels never replace an
independent edge key. Projection aliases preserve that witness; dropping the
last identity projection loses it. Generic JSON scalar-key/order eligibility
is unchanged, and inherited MATCH Result order is retained independently.
The corrected evidence package and current Result consumers passed **27/27 on
each of JS, Wasm and native**. Retired degree, reach, structural operations and
row bridges are tested as typed refusals, not silently skipped or redirected.

The remaining Result-order fixtures now use current MATCH and explicit TRAIL,
including composite typed starting identities, retained sequence after take,
nullable business properties, authored primary order with retained-sequence
ties, aliasing and identity removal. Copying only the output shape cannot
manufacture the producer sequence. Unsupported diff/equality cannot issue
singleton publication evidence. The full `src/relation_results` package passed
**103/103 on each of JS, Wasm and native**. The initial migrated JS test run was
102/103 because a test authored `direction` instead of the specified `dir`;
the fixture spelling was corrected, without changing parser or expectations.

Pipeline key/bridge audit migration passed **8/8 on each target**. The current
MATCH identity and alias budget checks retain their exact/one-short limits;
TRAIL enumeration does not invent a Relation key. Retired tuple projections
refuse even with historical role aliases. The cross-family audit still checks
Events/Vectors success, wrong-carrier origin, body validation and explicit input
selection. Current Graph refusal preserves the operation path and span.

Remaining work includes other legacy-positive consumer inventories, the real
configured-Store public snapshot save/reload route, aggregate Core/spec,
current-source fresh packed acceptance and required CI on the submitted SHA.
The snapshot route must preserve its family operation and cleanup handle,
charge reported save/reload work once, reserve serializer/reload workspace
before I/O, verify the exact stored CID, and confirm physical temporary-body
release. Internal roundtrip does not substitute for that connection.

## Integration of current main after the key-evidence checkpoints

Main `9fe3e2d738b541c17414a5eb09cd759c3e99adb4` adds installed INFER and
the current Array/Map foundation. The eighteen content conflicts are resolved
without restoring an executable tuple Graph profile or dropping model tasks,
barrier contracts or INFER acceptance commands. Public interfaces are generated
from the merged sources rather than selecting either conflicting interface.

The independent Values preimages preserve both the earlier Graph vector and
main's INFER predecessors. The new barrier manifest changes the Run to
`sha256:f2b1556c0f99714896e7ea77c817f174797d3a5e66b3a8c593315ad4365ed77a`;
the Unit, bound proof and Result Plan above remain unchanged. Node independent
vector tests pass **2/2**. The actual Values issuer/admitter, current Graph
Pipeline key/projection/audit checks, model execution contract and model closure
pass **14/14 on each of JS, Wasm and native** from the merged working source.
These focused checks do not replace aggregate Core, spec, fresh packed or CI.

Initial protocol generation lacked `moonfmt` on PATH; the pinned toolchain
rerun succeeded. An initial `-f` invocation selected no test names, and two
attempts named nonexistent test files. None is counted as passing acceptance;
the reported fourteen checks use actual file-path selection.
The added main-predecessor vector initially rebound its historical AoA registry
to the current Graph registry and failed. Pinning its original normative body
restored that historical vector without changing the expected CID.

The current-foundation record separately references integrated source
`ed122c01c6be379f2e5943b89cfb041ad833599e`, including the exact merged package
digest and both Graph and INFER acceptance commands. Historical #148 evidence
remains immutable. This is provenance registration, not approval or an
extension of the Relation proof to Graph.

The committed provenance record passed **40/40** history and mutation checks.
Before committing that record, the repository guard correctly rejected its
uncommitted state (**39/40**); the guard was not bypassed.

Current Graph scope fixtures now exercise definition-selected MATCH with
explicit independent identity/source/target aliases and business properties.
Labels are not synthesized property columns. Definition-free scopes are typed
refusals; opaque Graph and wrong-carrier diagnostics remain distinct. The
original scope fixtures are retained as non-executable historical text in
`portability/historical/graph-expression-scope-pre-property-graph.mbt.txt`.
The three scope/profile files passed **11/11 on each target**. An initial JS
fixture declared only one field for a two-component key and failed two tests;
correcting that fixture's declared bound restored the tests without changing
the checker or their independent expectations.

The complete spec command at `446d9cc84500122db08b8a1504c99219717dfe8d`
exited **1** in the resource-accounting stage: **213 tests, 210 passed, 3 failed**.
The failures require production dispatch markers for removed tuple Graph routes
and still treat historical SGA/row-bridge coverage as current assurance. Earlier
engine-accounting checks passed **1092/1092**. Stages after the resource stage
did not execute. The protected log is
`/private/tmp/property-graph-spec-446d9cc84-20261002.log`.
Neither restoring a tuple fallback nor relaxing accounting assertions is an
acceptable substitute for reconciling current supported/refused routes and
their evidence. The spec gate is not reported as green.

The family coverage inventory now separates the prior tuple-profile claims
from the current implementation: **19 non-Graph operations complete, 4 keyed
Graph operations partial, 17 retired/unconnected Graph routes blocked**. The
original inventory is retained as inert historical text. Eight inventory
regressions pass, including mutations that try to promote `reach` using old
suite evidence or delete the current profile. This correction does not satisfy
or weaken the strict resource gate: open entries remain open and the old
production-route inventory still requires migration with current evidence.

The full typing package at the inventory checkpoint was **62 total, 19 passed,
43 failed**. Its old tuple-consumer successes are now inert historical fixture
text, not skipped tests or a retained execution profile. Seventeen original
files were preserved byte for byte; twelve unconnected/retired-consumer files
were removed from executable tests. Supported MATCH, selectors, predicates,
TRAIL and path-shape fixtures were migrated, retaining independent full
composite identities, repeated occurrences, qualified input columns, indexed
copy isolation, exact/one-short budgets and original diagnostic locations.
Explicit current structural/shortest/apply refusals replace old positive
assumptions. The complete current typing package passes **27/27 on JS, Wasm and
native**. The initial migrated fixture compile lacked two qualified enum names;
the fixture spelling was corrected without changing product code. No full Core
or public snapshot success follows from this package result.

### Integrated Core diagnosis at `bf02dc660463bcb72bf8f171a9a408020f442b2b`

The full Core JS run exited **2**: **7581 total, 7079 passed, 502 failed**.
The protected log is
`/private/tmp/property-graph-core-js-bf02dc660-20261002.log`.
This is not an all-legacy failure classification: **81 failures** were in the
newly integrated `client_infer_host` package. Its generated admission fixture
still contained the predecessor registry. The existing non-mutating generator
check independently rejected that fixture before any update. Regenerating it
from the current normative registry with `scripts/infer-host-fixtures.mjs
--write` changed only admission input, not expected rows, accounting boundaries,
model behavior or Run assertions. The complete package then passed **82/82 on
JS, Wasm and native**. The original full-Core failure remains recorded; these
narrow successes do not supply a new aggregate Core result.

The other **421 failures** span Graph preflight, typing, lowering, runtime,
Program checking and Host integration. They remain subject to individual
current-profile migration or product diagnosis. Historical positive fixtures
do not justify reintroducing the tuple runtime, and they must not be removed
wholesale where current custody, work or resource regressions can be preserved.

The seven `managed_graph_runtime/output_wbtest.mbt` lifecycle regressions now
use the current property Graph and definition-selected MATCH ports instead of
unsupported normalize/tuple ports. The original file is preserved byte for
byte at the integrated source above. None of these regressions was skipped:
two exact consumers, operation-port/foreign-owner rejection, source revocation,
duplicate-key failure, cancellation and idempotent final reclamation remain
checked. The complete runtime package passed **11/11 on each target**.
An initial migration tried scalar key ordering on a structured Graph identity
and was correctly refused; the assertion now uses bounded complete equality
against an independently authored typed/domain identity. An enum pattern typo
also failed compilation before correction. These are fixture corrections, not
permission to admit structured keys as scalar order values. Internal lifecycle
success is still not public snapshot roundtrip acceptance.

## Public Store snapshot connection (2026-10-02, working unit)

The selected constructor provider attaches the existing lazy family snapshot
factory. Installed serialization/read limits and a 64 MiB private workspace
envelope are included in candidate capacity before input access. These are
installation limits, not a machine-independent allocation-byte theorem. The
same Local driver validates cumulative stage reports and charges their deltas
to its existing provider work owner. Exhaustion is sticky: no new Compute or
handoff is authorized; failure cleanup remains possible.

The installed public Host now supplies snapshot-only physical Store wiring.
It does not change Relation tasks to file-backed execution. Previously, the
public MATCH/TRAIL checks passed without calling snapshot I/O because that
configuration was absent. The new route uses the existing Local file Store:
save and independently seal bytes, revoke the source generation, verify the
entire physical read, reload through family admission, reclaim the temporary
body, then expose the restored checked completion. Process-backed callers
require the parent's typed release confirmation; local close or zero local
usage is not physical reclamation. The common failure progression keeps both
family and file cleanup handles. No second Graph, storage, or accounting owner
is introduced.

The public oracle now covers compound String/Number keys and multiple label
sets. Its canonical schema, records, domain and snapshot CID are authored
independently from the constructor definition and input rows. Both public
Local and real HTTPS paths saved/reloaded before MATCH and TRAIL; their saved
CID/byte count matched that oracle and their temporary directories were empty.
An installed awaited diagnostic hook observes this completed route; it grants
no execution or completion authority. Result reattach is retained as a
separate publication assertion, not used as snapshot evidence.

Focused results in this unit:

- Common constructor/snapshot/provider accounting: **34/34 on each of JS,
  Wasm and native**.
- Real-file transport: **5/5**, including changed sealed bytes, cancellation,
  cleanup failure/retry and delayed parent release.
- Driver/Host adapter regressions: **49/49**, including snapshot cumulative
  work, no Compute re-entry and cleanup retry without another allocation.
- Public Local/HTTPS: **2/2**, each checking MATCH and TRAIL after verified
  physical reload, compound identity and label-set preservation.

The first source public run stopped before execution because the borrowed
node_modules held an older client-wire without validCheckOutcome. The source
rerun explicitly resolved the same checkout's packages using a test loader;
it is not a fresh-packed result. Two initial diagnostic fixtures lacked the
required reviewer/account installation and were refused before dispatch;
the corrected fixture installs real synthetic keys and an explicit admitted
test account, without weakening authentication. A common capacity fixture
initially required Eq/Debug on the opaque capacity type and then mistook a
reclaim request's Boolean for authoritative cleanup completion. The corrected
test compares capacity fields and the existing Material cleanup-pending
status, including the already-disposed source case.

Evidence logs are preserved under /private/tmp/property-graph-public-snapshot-*
and the public Host state/DBs under this worktree's
_build/property-graph-public-host/. Full Core/spec, fresh packed, latest-main
integration and final-SHA required CI are still outstanding. The published
125a186ae revision failed multiple CI jobs and became conflicting after main
advanced; neither its CI nor previous historical successes is approval for
this working unit.

## Deliberately not claimed

### Current required-gate scope alignment (2026-10-03)

The existing pure-operation evidence index now points blocked Graph entries
to the shared inventory-driven public refusal test, separately from current
MATCH/TRAIL execution evidence. Its source-gate audit derives blocked keys
from the existing family classification and detects adding any of those keys
back to execution admission. No second support inventory or per-operation
fixture set is introduced. The current Graph law check requires the owned
Property Graph law and the sole admission route; it does not demand the
retired tuple-profile identity pin in executable implementation.

The unchanged historical Graph quantity-law body remains CID-pinned with
independent arithmetic tests. The current count checker is required to emit
exactly applicable current laws: keyed construction sums and MATCH quantity
transfers. Its historical node-emission traversal rule does not apply to
current TRAIL path emission. Current unsupported Graph laws cannot silently
re-enter that checker. Other family law-body coverage is unchanged.

The document-metadata generator updated the grammar and normative document
imports after the current Graph specification changes; requirement identifiers
and statuses were not rewritten. Non-mutating metadata and family checks
passed. Focused law/source-index tests passed **10/10**, capacity-law tests
**17/17**, and the complete existing `check:contracts` command passed after
the obsolete index and count-emission assertions were corrected. Initial
failures are preserved in `/private/tmp/property-graph-contracts-current-20261003.log`
and `/private/tmp/property-graph-contracts-index-current-20261003.log`; the
successful run is `/private/tmp/property-graph-contracts-index-fixed-20261003.log`.
These results do not replace final-SHA Core, fresh packed or Linux CI.

The full spec run at `3b0fd3bba2d68de450ab9d1750d9a6ed88c5a0f6`
passed the required resource mutation checks and contracts, then failed at the
document-link stage on a removed tuple-Graph integration test. The current
design now distinguishes that historical reference from the new constructor
and TRAIL resource suites. The non-mutating link check passes **1,259 links**;
checks after the failed link stage were not executed by that aggregate run.

The old source-free SGA checker suite's tuple-only execution cases are retired,
not converted into claims of successful current SGA execution. The same
distribution command keeps a real current-profile rejection of the retired
constructor and runs the existing current Property Graph Plan/Host suite,
including **22/22** successful lifecycle/snapshot/cancellation checks. The
refusal case passes separately **1/1**. An initial edit used the wrong law-body
directory and failed with ENOENT before its test ran; correcting the fixture
path to the existing owned dependency body restored that test. The old
capacity and lifecycle obligations still require the broader native Host
fixture migration; retiring this tuple-only preparation suite does not waive
them or establish final acceptance.

Resuming the existing spec commands after the link stage passed examples,
documentation tests, nest, Unicode and encoding, then correctly rejected stale
generated canonical vectors. The existing independent generator changes only
the grammar-manifest preimage and its outer CID, matching the previously
refreshed normative import. Its **366** fixed identities pass freshness, and
the generated MoonBit tests pass **366/366 on JS, Wasm and native**. The
failure log is `/private/tmp/property-graph-spec-tail-c17158ae9-20261003.log`;
the three-target result is
`/private/tmp/property-graph-canonical-targets-20261003.log`. This staged
diagnostic run is not reported as a complete final-SHA spec success.

### Fused construction input custody regression (2026-10-03)

Migrating the existing real DuckDB Host publication matrix exposed a current
provider failure before publication: a fused constructor/MATCH with one
pipeline input used by both node and edge definitions was rejected as InputSet.
The provider incorrectly required the selected-task occurrence count even for
the fused pipeline input set. Selected tasks continue to require every ordered
operation occurrence. Fused tasks use the checked pipeline input count, and
input_at still checks every exact operation edge and live producer owner. A
constructor-only prefix also uses the existing constructor_material projection
to finish as Graph rather than attempting to project a consumer outside that
prefix. No task graph generation, selection rules or provider owner is added.

The new common regression checks a shared composite-key input, NULL exclusion,
both fused MATCH and constructor-only prefix, surplus-handle rejection and
repeated cleanup. Removing the input-count fix makes it fail (0/1); the fixed
construction suite passes **21/21 on each of JS, Wasm and native**, with
--deny-warn. Evidence is in
`/private/tmp/property-graph-fused-regression-without-fix-20261003.log` and
`/private/tmp/property-graph-fused-regression-fixed-{js,wasm,native}-20261003.log`.
An initial diagnostic invocation used mutually exclusive Moon test arguments;
it did not run tests. That command error is kept separately in
`/private/tmp/property-graph-fused-regression-js-20261003.log`.

The existing spec tail also passed from the canonical freshness stage through
the final events check at the current grammar pin; its log is
`/private/tmp/property-graph-spec-tail-canonical-current-20261003.log`. This is
still staged evidence, not an aggregate final-SHA spec or CI success. Host
guarantee migration and final integration acceptance remain unfinished.

Full SGA, external producer-definition provenance, a durable Graph catalog and
complete mechanized correspondence are not claimed. Remaining fixture and
consumer migration plus aggregate gates remain required in the current unit;
they are not waived by these focused results. The current laws and
independent fixtures are ActQL-owned. Executable conformance is not represented
as a proof of the entire implementation. A/B task splitting, carrier tasks and
Frontend implementation are not changed by this unit. The existing Graph
provider dispatch retains its bounded sessions and owners; no parallel
provider is introduced.

### Real Host guarantee migration checkpoint (2026-10-03)

The existing DuckDB `standard-host` and `retained-values-chain` tests pass
**41/41, no skips** with the pinned toolchain. The log is
`/private/tmp/property-graph-host-guarantee-migration-current-20261003.log`.
This run includes the new typed constructor, node/edge MATCH, downstream
filter/sort/take, two independent consumers, retained-file publication and
cleanup failure followed by successful retry. Construction capacity overflow
and predicate/Relation failures publish no partial result. Construction and
node/edge MATCH cancellation wait for reported positive work, preserve the
exact stopped owner, and finish with zero held/reserved capacity. Retained
VALUES uses a file route, so the MATCH cancellation assertion checks the
actual task identity rather than treating its managed-start ordinal as a
physical task number. The normal retained Graph factory also executes the
new constructor/MATCH path; surrounding Values, Events and Vectors guarantees
remain executable and pass in the same run.

Tuple-only algorithm positives are removed from this execution matrix, not
counted as migrated algorithm guarantees. Unsupported consumers remain subject
to the shared inventory-driven public refusal test. The conformance issuer
selects the current Property Graph profile without a compatibility fallback.
Earlier migration failures and corrected task-mapping assumptions remain in
the diagnostic logs; none is reported as a successful run. This successful
run emitted a Node FileHandle garbage-collection close/deprecation warning.
It is recorded rather than described as a warning-free resource audit; its
origin is not established by these assertions.

This is local fixture-migration evidence at the fused-input fix, not final
integrated-source Core/spec/packed acceptance or pushed-SHA Linux CI. Latest
fetched main is `52ca17c4645a10d8010da616410fdd5f2bf4a13b`; integration and
the final published #164/B handoff remain required.

### Integrated selected Relation guarantee migration (2026-10-03)

Main advanced during the fetch/integration interval. The actual merged parent
is `a32d8c94404c3f6be52d1fcfb73aab21cbf7093c`, integrated at
`b2180c826a0115b0f2a611efb77d25dc2cdb39ad`. The one package-script conflict
retains both Property Graph acceptance and main's cancellation-response-loss
regression. Official tracked three-target API verification passes at that
clean integration.

The integrated spec job initially fails in the existing resource regression
suite: **176 total / 173 passed / 3 failed**. Six selected Relation Host
evidence references still named deleted tuple normalize/row-prefix cases.
This is a missing guarantee migration, not a reason to delete the references
or mark supported Relation operations refused. The corrected cases run the
sole typed constructor -> MATCH -> filter/select/take/sort/assert/unique.
They retain delivered cancellation after positive work, exact task identity,
confirmed physical stop, original input custody and zero held/reserved
capacity after cleanup. The wide sort keeps seven keys, 660-byte text and
cancellation after 70 advances reporting work 70. Its measured timing is
diagnostic, not a new latency guarantee or billing authorization.

The complete real `standard-host` test passes **1/1, no skips** with these
six cases inside the existing test, and the previously failing resource
regressions pass **3/3, no skips**. Evidence:
`/private/tmp/property-graph-host-relation-guarantees-b2180c826-20261003.log`
and `/private/tmp/property-graph-resource-migration-regression-20261003.log`.
The former is integration plus the recorded uncommitted fixture migration,
not clean-source final-SHA evidence. Its run emits no FileHandle warning; that
does not establish the cause of the prior run's warning. The failed spec log
is retained at `/private/tmp/property-graph-spec-b2180c826-20261003.log`.
The existing resource gate and its expected strict scope are unchanged;
only the six evidence pointers move to real current positive cases.

Complete spec/Core, fresh packed snapshot and pushed-SHA required CI are
still outstanding. The first failed aggregate is not overwritten by these
narrow successes.

### Independent Run-vector grammar refresh (2026-10-03)

The Core JS job at `b09b5e69a987d20a90b5c3ecfbc6efaaf1cbd718` passes the
common `moon check --deny-warn`, then stops at the independent Run identity
test (**1/2**). The full Core test command has not run in that attempt. Log:
`/private/tmp/property-graph-core-js-b09b5e69a-20261003.log`.

The independent hand-assembled preimages reproduce both previous Run vectors
with grammar `sha256:a008ad4bb4aa68f02a688b00306bc3818de0dae7beae81d977e54e76f156ad5d`.
The current grammar pin
`sha256:2bf8ef0846b81f91fec96548d10dddd8c7e5a82b7db05444b38eefa316779c11`
changes invocation-template, compilation and Run identity. Values Unit,
cardinality proof and Result Plan remain unchanged and are separately asserted.
The new Run vector with the current barrier manifest is
`sha256:6feea7b7aec5bf825c5db7e46123c9b08f72f5fa85e795968e707d4e4d6c16c4`;
the original-barrier vector is
`sha256:3e86d58da98d5af468f0cd07aaef40562c46117c099dfa1cb41a2de052f983f3`.
Both old vectors remain frozen tests using their original grammar/contract and
dependency closure; their historical identities are not rewritten.

No product compiler, issuer or generated output participates in that expected
calculation. The independent Node tests pass **2/2**, and the real materials
issuer/admission fixture passes **1/1 on each JS, Wasm and native** with the
independently derived literal. Target logs are
`/private/tmp/property-graph-run-vector-refresh-{js,wasm,native}-20261003.log`.
The complete final-source Core/spec/packed and pushed-SHA checks remain
required, rather than treating these narrow vectors as full acceptance.

### Published-source CI integration repairs (2026-10-03)

The first PR run for `8c052888503e130e3d6c5f5a5ea74037be407e3f`,
`37083655552`, passes all three Core targets, spec and the native jobs, but
fails Workers, Host, Salesforce, distribution and packed acceptance. These
failures are not replaced by an assertion that the whole run succeeded.

Workers fixture freshness identifies a stale generated projection. Regenerating
with the existing generator removes retired tuple helpers and projects the
current fixture; the generator and source expectations are unchanged. The
resolved Workers dependency gate then identifies the newly reachable,
dependency-free Carrier snapshot transport. Only that exact module is added
to both existing bundle inventories. Node/native, unknown and transitive
dependency rejection remains enabled. The complete local Workers job passes,
including 27 workerd tests and the negative dependency checks.

The Host and distribution failures come from historical Values vectors mixing
pre-String identities with current grammar, check-environment and transfer
preimages. The independent oracle freezes those predecessor preimages from
`02a60baf0^`, preserving the existing historical Unit and Result Plan literals.
Current vectors use the current owned Property Graph law. Historical bindings
are compared with the independently derived historical contract, not current
bindings. Both previously failing narrow tests pass; no product output is
copied into expected identities.

The Salesforce checked three-Stage Effect refusal used a removed tuple Graph
constructor and unsupported normalize/row projection. Its fixture now uses a
three-Stage Relation chain, retaining the same compiler refusal, typed public
rejection, zero accepted requests and prohibition on physical execution. The
narrow regression passes. An intermediate attempt using a new Graph fixture
failed at preparation and is not counted as acceptance.

The packed aggregate previously required successful execution of retired SGA
consumers. It now invokes the existing shared Property Graph public regression
and its authoritative coverage inventory, without a second capability table.
Normal SQL/Pipe, source-count, recovery, failure and cleanup assertions remain.
The positive pre-start cancellation case and native Client case use the current
independent parallel-edge Program rather than restoring old algorithms.

The complete fresh packed diagnostic exits zero: Local/HTTP query acceptance,
two-source custody/recovery, planner selection, exact String reread, positive
Graph cancellation, public snapshot/source-revocation/reload/MATCH/TRAIL, the
17 inventory-driven refusals on both transports, and native Client Named
Results all pass. Evidence is retained at
`worktrees/.codex-scratch/public-query-evidence-LHSZ91` and
`/private/tmp/property-graph-packed-aggregate-fix-diagnostic-20261003.log`.
Its command records explicitly report dirty source; this is repair validation,
not the final published-SHA acceptance or Linux CI result.

Initial local narrow launches also required preparing all runtime packages
and installing this worktree's own DuckDB dependencies. Missing generated
Coordinator modules and missing DuckDB Node packages were startup failures,
not successful test executions. No test loader, borrowed-dependency rewrite,
ACK relaxation or expected-row relaxation is used. Remaining full related
jobs and final clean-SHA CI are still required before the B handoff.

The local Host job at `291fa9c571477b64fc59578e1578a363dfbe7912` passes
its custody, publication, Remote Site, Checkpoint and Run Host phases, then
fails the final runtime-build command inventory comparison (28/29). Main's
redundant-check removal test did not include the three deliberately registered
Graph acceptance commands. The repair requires those exact additions in their
exact positions; it does not ignore extra commands or weaken stale-artifact
rejection. The full builder regression passes 29/29. Its first cold pack fails
on inaccessible shared npm cache, while the separate run using the existing
owned npm cache successfully builds and packs all four runtime packages from
missing bundles. Logs remain separate at
`/private/tmp/property-graph-host-291fa9c57-20261003.log`,
`/private/tmp/property-graph-cold-runtime-fixed-20261003.log` and
`/private/tmp/property-graph-cold-runtime-owned-cache-fixed-20261003.log`.
No shared cache is changed; neither failed aggregate is reported as passing.

The complete local Salesforce job at
`98fd56e02db720bf80fbb371dbd7216a508e0312` passes 277 Node/Host tests,
the Effect recovery probes and all six public Host process-death boundaries,
then fails the first lower-level capture crash probe. Node 24's default spec
reporter hides the deliberately terminated test worker's exit code, although
the saved record confirms the requested `effect-source` Store boundary was
reached. This failed aggregate is retained at
`/private/tmp/property-graph-client-salesforce-98fd56e02-20261003.log`.

The lower-level probe now uses the existing process-isolated test reporter,
as the public Host crash harness already does. It still requires nonzero
termination and exit code 77, and additionally checks the recorded boundary
and holding namespace. The three probes (`effect-source`, `effect-capture`,
`publication-private`) pass after this change, including physical holding
sharing, failed directory-sync cleanup, retry and zero remaining holdings and
objects. Their logs are
`/private/tmp/property-graph-crash-reporter-{effect-source,effect-capture,publication-private}-20261003.log`.
No product stop, recovery, ACK or expected-result condition is relaxed.
The complete clean-source aggregate and pushed-SHA CI remain separate checks.
