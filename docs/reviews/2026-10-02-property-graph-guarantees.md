# Property Graph guarantee migration ledger

## Decision and evidence rules

The current decision removes the executable tuple Graph implementation, not
its generic resource and custody obligations. Historical sources are available
in Git. Inert text copies are not readers, fallbacks or compatibility adapters.
An unsupported-operation test does not establish that operation's former
capacity, completion or cancellation guarantee.

Three classifications are used below:

- **Retired representation**: an expectation required tuple construction or
  endpoint-pair identity. It cannot be a positive current Graph expectation.
- **Required guarantee**: capacity, input ownership, cancellation, cleanup,
  bounded preparation or publication atomicity must survive on current Graph.
- **Unsupported consumer**: no current implementation is connected. Refuse at
  the checked boundary without a tuple fallback; do not claim its old algorithm
  or resource proof migrated.

Focused successes are not aggregate Core/spec/CI acceptance. The published
#164 checkpoint is not the tested local source. Final acceptance requires the
public snapshot and required CI at the same submitted SHA.

## Current obligations

| Obligation / old failure group | Classification | Current executable evidence | Remaining work |
| --- | --- | --- | --- |
| Tuple constructor and endpoint-derived edge identity | Retired representation | The old Carrier factory is deleted; current keyed constructor retains independently keyed parallel edges | Audit remaining homogeneous getters and unsupported checked consumer branches; negative tests alone do not remove them |
| Graph builder capacity/work/cancellation and no partial publication | Required guarantee | `managed_graph_storage/storage_wbtest.mbt`, `property_storage_wbtest.mbt`; current constructor tests in `query_integration/property_graph_construction_wbtest.mbt` | Repeat aggregate verification at submitted source |
| Completion, exact consumer/input owner, revocation, final reclamation | Required guarantee | All seven migrated `managed_graph_runtime/output_wbtest.mbt` lifecycle cases; keyed provider foreign-input and cleanup tests | Keep these positives, not substitutes that merely refuse old input |
| Snapshot byte limits, cancellation, trusted read schema, corrupt/interrupted reload | Required guarantee | `query_integration/property_graph_snapshot_wbtest.mbt`, `managed_graph_runtime/property_snapshot_wbtest.mbt` | Fresh public Local/HTTPS save → revoke original Source → reload → MATCH/TRAIL at submitted SHA |
| Repeated constructor input occurrences and mixed definition roles | Required guarantee | `pipeline_typing/construction_test.mbt`, `operation_obligations_test.mbt`; `capacity_program_step/property_graph_test.mbt` | Migrate remaining imported input/preflight fixtures |
| Distinct node/edge extents, producer owner and no fabricated row proof | Required guarantee | `pipeline_typing/produced_input_test.mbt`, `graph_counts_test.mbt`; current MATCH node/edge cases | Empty declared node universe exposed a real upper-bound regression; minimal `row_counts.mbt` fix preserves zero edges while still debiting every operand |
| MATCH predicate types, typed identity rows, downstream Relation consumers | Required guarantee | `pipeline_typing/graph_test.mbt`; `lowering_relation/graph_match_test.mbt` | Migrate Program and query integration inputs without Frontend-specific evaluation |
| TRAIL selector owner, bounded preparation, empty selector counts, row guard vs proof | Required guarantee | `pipeline_typing/graph_test.mbt`, `graph_report_counts_test.mbt`, `graph_empty_selector_audit_test.mbt`, `author_guards_test.mbt` | Retain current paths positives and exact/one-short tests |
| Graph input bound owner, foreign dependency rejection, imported closure, limit consumption | Required guarantee | `capacity_graph_preflight` uses scoped MATCH and TRAIL; downstream resolved ownership, foreign collection rejection, limit consumption and exact/one-short assertions remain | Current preflight migration passes focused JS; complete Core/spec and final submitted-SHA acceptance remain open |
| Diff/apply, union/graft/subtract/mean, structural counts, report bounds, reach/shortest | Unsupported consumer | Current typing/lowering and diff refusal tests; legacy algorithm implementation is not a fallback | Remove remaining obsolete execution branches. Old algorithm-specific count/schema proofs are not claimed preserved. Keep generic projection/owner guarantees in supported fixtures |
| Consumer coverage and strict resource inventory | Required guarantee + unsupported consumers | Inventory distinguishes connected partial Graph routes from blocked routes | Aggregate spec remains red; do not remove checks or silently retain old completion claims |

## Latest narrow pipeline unit

The five migrated files (`graph`, `graph_unary_audit`, `graph_bounds`,
`graph_counts`, `graph_report_counts`) pass **11/11 on JS, Wasm and native**.
Logs: `/private/tmp/property-graph-pipeline-graph-contract-{js,wasm,native}-20261002.log`.
The empty-universe count regression failed before the `row_counts.mbt` fix:
`/private/tmp/property-graph-empty-extents-before-20261002.log`.
This is a static upper-bound regression, not evidence of corrupt runtime rows.

Five pure tuple-algorithm fixture files are withdrawn from executable tests:
`union_list`, `path_counts`, `mean_counts`, `mean_acceptance_audit`, and
`graph_structural_audit`. Their nine positive tests concern currently
unsupported consumers. They are not reported as nine migrated resource proofs.
Ten original files are byte-identical inert copies of source
`01c19faf0aa7d9a690ae09c66e98bac43d7e2e28`; Git remains the historical authority.
Non-Graph positives in mixed files remain executable.

Full pipeline, Core, spec, fresh packed acceptance and required CI have not
been rerun for this unit. The previous full pipeline at `d5e2b5b49` remains
343 total / 308 passed / 35 failed; it is not this unit's result.

## Preflight owner migration

### Supported-path replacement checkpoint

The four previously failing fixtures below now have supported-path evidence.
The complete `capacity_graph_preflight` package and the existing
`capacity_program_step/{join_resolution,property_graph}_test.mbt` files pass
**34/34 on JS, Wasm and native**. Logs are
`/private/tmp/property-graph-preflight-migration-{js,wasm,native}-20261002.log`.
This is a focused result, not a new complete Core or CI result.

- `resolved_output_test.mbt` uses TRAIL paths → TAKE. It retains the exact
  physical output owner, rejects reconstructed foreign collections, validates
  downstream dependency order, duplicate/missing applications and exact/one-
  short work, and retains resolved output after caller-array mutation.
- `trail_owner_coverage_test.mbt` replaces the retired components ledger with
  TRAIL plus a retained MATCH branch. Foreign Graph inputs/programs, missing
  dependencies, limit consumption, unused branches, collection custody and
  exact/one-short budgets remain positive/rejection pairs.
- `input_bounds_test.mbt` follows node/edge MATCH through SELECT and DERIVE
  into TAKE. It retains the original row-bound owner and rejects substituting
  an equal-valued Graph measure. Existing imported-closure tests remain.
- Dead traversed-node scaffolding and its duplicate path mode were removed
  from `traversal_coverage_test.mbt`; all distinct current TRAIL scopes remain.

The old union/normalize/subgraph algorithms are unsupported, not restored.
Their algorithm-specific claims are withdrawn, not reported as migrated.
Repeated definition operands and mixed premise order remain positively tested
by `capacity_program_step/property_graph_test.mbt`. Late candidate final
revalidation remains tested by the supported JOIN resolver: an initially valid
host-only minimum rejects a candidate added later to the same complete table.
It would be invalid to admit the retired traverse-nodes proof against a TRAIL
path result just to retain that old test shape.

Initial migration compilation caught two stale ledger variable names and a
string-concatenation line break. Both were corrected before the three-target
runs. No capacity validator, owner or acceptance expectation was weakened.

### Earlier migration evidence

The shared current input has independent N/E key definitions and an explicit
identity domain. Graph-to-Relation proofs now use the existing
`actql.bound.match-nodes` / `actql.bound.match-edges` laws; bound witnesses still
come from the original input owner. Imported input closures retain exact owner
registrations, reject foreign or missing dependencies, copy caller arrays and
enforce cumulative input/application work. No capacity owner or proof checker
is replaced or weakened.

The supported TRAIL fixture retains separate search-path/output-row scopes,
missing/foreign candidate and subject rejection, unused-branch coverage,
caller-array retention, missing/duplicate application rejection and
exact/one-short budgets. Its typed start belongs to the declared N/domain;
the retired traversed-node output is not claimed supported.

Focused native evidence is **14/14 plus 1/1 plus 1/1**:
`/private/tmp/property-graph-preflight-supported-native-20261002.log`,
`/private/tmp/property-graph-preflight-bound-owner-native-20261002.log`, and
`/private/tmp/property-graph-preflight-import-owner-native-20261002.log`.
The current complete Wasm package is **32 total / 28 passed / 4 failed**:
`/private/tmp/property-graph-preflight-current-trail-wasm-20261002.log`.
JS's preceding package run was **32 / 27 / 5**, followed by the migrated
TRAIL file **1/1**; that is not a new aggregate JS result. An attempted full
native package aborted at the still-obsolete `resolved_output` fixture with
SIGABRT; only the explicit focused native runs above are counted.

The remaining four cases are the old union composition, normalize/subgraph
bound forwarding, components ledger, and resolved components/traversed-node
output chain. The resolved-output guarantee still needs a supported positive
counterpart; it must not disappear under a blanket refusal. Initial migration
fixtures had a zero field ceiling despite a one-component key and omitted
the required node-MATCH predicate. Those fixture errors were corrected without
changing admission or capacity rules.

Latest fetched main is `0fd6332757176b88e8c4071e4a2cd0be3d6254e3` (#185/#188).
The preflight runs above predate its integration. It is now integrated at
`5608b2eeed5432a1e2b511a23ace7cb66163a209`. The single textual conflict in
`client-dispatch-owner.mjs` retains main's `sourceAccess` presence check and
this branch's local snapshot configuration. All other main source-custody
changes are retained; no independent carrier-task edit was made. Syntax
validation passes, but integrated Host acceptance must still run.

The old constructor admission body is removed from the public pipeline check:
the retired key is refused before operand resolution or compatibility-operation
creation. Current constructor, Graph and keyed-constructor fixtures pass
**13/13 JS** after integration:
`/private/tmp/property-graph-retired-constructor-boundary-20261002.log`.
An unused `GraphConstruction` variant warning exposes remaining retired type
and lowering scaffolding. It is a removal task, not a warning exemption or a
claim that implementation unification is complete. The old Carrier factory
and other obsolete branches remain on the explicit removal inventory.

The published #164 remains `125a186ae9396fbfc7865641922e8e8a4ffc87d9`,
Draft and not GO. Historical evidence does not require an executable adapter.

## Current-main reconstruction

The old source is preserved by local refs, not executable compatibility code:

- `archive/pr164-published-125a186-20261002` retains the published checkpoint.
- `archive/pr164-pre-reconstruction-b88d27bb3-20261002` retains
  `b88d27bb30b4d38bd046ce5912bdf29e6b78d418`.

The source was reconstructed on main
`0fd6332757176b88e8c4071e4a2cd0be3d6254e3` at
`81ef098cb8a588f0ebb9eca2ae7f95ec972d55d3`. Its tree equals the preserved
source tree (`ce291321393d62d38f5095f36a3e8384c7421961`). The subsequent
`a55b5d92a2bf23db19b64e810c0c0b71308eb7a8` declares the exact package
verification registration without changing the frozen baseline or validators.
History, foundation and integration tests pass **113/113** at that checkpoint:
`/private/tmp/property-graph-reconstructed-foundation-tests-20261002.log`.
This does not prove later source changes or the final PR CI. Public branch
replacement has not occurred; preservation refs, full old/new SHAs and the
exact lease will be announced before that operation.

## Retired constructor implementation removal

The old `CheckedConstruction`, checked-pipeline `GraphConstruction`,
`ConstructionOwner`, lowering payload/step/expansion, legacy construction
execution candidate and their downstream switch arms are removed. Obsolete
endpoint-completion/collapse obligations are removed from the constructor
contract. The current keyed constructor keeps its existing exact-occurrence
owner, duplicate-key/endpoint-exclusion rules and resource envelope. Common
field parsing and wire-node emission helpers still used by the keyed
constructor are not compatibility implementations.

The retired construction-rule whitebox test is removed. Its applicable owner,
ordered/repeated-input, foreign-occurrence, execution-phase and shared-capacity
obligations are tested by
`property_graph_construction_execution_wbtest.mbt`. Core contract inventory
tests now retain the current constructor and scoped MATCH owners, with the
same exact/one-short collection budget assertions. Publication-policy tests
retain shared/distinct producer occurrences, original checked owners and
mandatory construction ceilings on the new constructor/MATCH path.

These eight files pass **15/15 on JS, Wasm and native**:
`/private/tmp/property-graph-constructor-removal-{js,wasm,native}-20261002.log`.
The interface regeneration succeeds for all three targets; its reported
backend differences concern native-only packages and require the normal API
checker after the interface changes are committed. No unused constructor
warning is suppressed.

One migration limitation is explicit: a directly bound external Source still
lacks its admitted producer-definition projection at the constructor boundary
and is refused with `MissingPropertyProducerDefinition`. A row schema/name or
bound Artifact CID is not substituted for that definition. The current
publication test uses retained Values producers and verifies that an unused
external Source lends them no provenance. This is **not** a replacement proof
of the old direct-Source constructor guarantee. Result-import producer custody
is tested separately by `graph_branches_wbtest.mbt`; direct external-definition
admission remains unconnected.

Initial migrated fixtures failed because node-MATCH omitted/non-emptied its
required projected fields and because the direct external definition was not
available. Those failures are not classified as successful gates. A diagnostic
attempt using Debug on non-Debug issue wrappers also failed to compile; that
temporary diagnostic code was removed. The successful narrow runs above use
only supported fixtures and retain positive owner/capacity assertions.

The old Carrier factory and other obsolete consumer bodies are still on the
removal inventory. Preflight resolved-output guarantees, full Core/spec,
fresh packed public snapshot acceptance and same-SHA required CI remain open.

## Constructor-removal committed checkpoint

The unit is committed as
`da2a0189d3dbfc5ffd5cdded891670e197b3d68a`
(`refactor(graph)!: remove retired constructor execution`). Official tracked
three-target API verification and composed-foundation validation pass at this
commit. The working tree was clean throughout the subsequent full Core JS run.

Full Core JS is **7,554 total / 7,238 passed / 316 failed**, exit 2:
`/private/tmp/property-graph-core-js-da2a0189d-20261002.log`.
The residual failures group as follows; these counts do not classify all
individual assertions as obsolete:

| Package | Failed tests | Next obligation |
| --- | ---: | --- |
| query_integration | 173 | Separate retired algorithms from current constructor, lifecycle and custody guarantees |
| local_sga | 58 | Remove obsolete kernels/fixtures only after mapping applicable resource guarantees |
| program_check | 37 | Migrate supported Program/capacity/owner routes; classify unsupported operations separately |
| pipeline_check_context | 18 | Preserve owner and preflight closure guarantees on current occurrences |
| capacity_program_step | 11 | Keep valid bound-owner and enforcement proofs; do not manufacture unsupported consumer counts |
| pipeline_typing | 7 | Old Delta/projection fixtures still require guarantee-by-guarantee disposition |
| query_program | 7 | Existing Frontend fixtures emit retired Graph forms; coordinate with the Frontend owner rather than restoring fallback |
| capacity_graph_preflight | 4 | Resolve imported bounds and supported resolved-output/late-candidate custody migration |

This checkpoint is not submitted as complete, does not have new required CI,
and does not supersede the previously recorded public snapshot acceptance.

## Required-definition consumer checkpoint

`Graph` already owns a mandatory `PropertyGraphDefinition`. Its public
`graph_property_definition` projection now returns that definition directly,
not an always-present optional compatibility discriminator. This is an
intentional breaking MoonBit API change; all current callers and the generated
interface are updated together. It does not alter the current contract bytes,
domain derivation, typed key identity, snapshot CID or Result wire format.

Storage, structural reader views, snapshot preparation/reload, keyed MATCH,
TRAIL and the selected provider no longer branch on an impossible absent
current profile. Actual input availability, exact positioned owner, trusted
schema, identity validation, capacity and cleanup checks remain. Unsupported
typing consumers always report `UnsupportedGraphOperation` for a complete
current Graph. Incomplete Graph knowledge remains a distinct refusal.

Related construction, contract, storage, managed output/view, snapshot,
provider and unsupported-operation tests pass **95/95 on each of JS, Wasm and
native**. Logs:
`/private/tmp/property-graph-required-definition-{js,wasm,native}-20261002.log`.
Three-target interface generation succeeds. The official tracked-interface
check initially rejects the expected uncommitted generated API delta; rerun
it after committing that interface, rather than weakening its comparison.
Initial compilation also found one shared shortest caller of the narrowed
private label parser and unused bindings made obsolete by guard removal;
those were corrected without warning exemptions.

This is not complete implementation unification: retired factory stubs,
homogeneous Carrier projections, old unsupported checked-operation bodies
and legacy kernels are still on the removal inventory. Their generic
resource/custody obligations must be mapped before withdrawing executable
fixtures. The previous complete Core JS failures and the public snapshot/CI
acceptance requirements remain open.

The required-definition unit is committed as
`69656810ff0e4dbbacbb0e9441ccf6d7b20c56a0`. Its official tracked three-target
API check passes after commit:
`/private/tmp/property-graph-required-definition-api-committed-20261002.log`.

## Retired structural kernel removal checkpoint

The old Local `normalize`, `graft` (including finite-list union/subtraction)
and `mean` kernels and their public execution handles are removed. Production
references to these entrypoints were checked before removal; the current
selected Graph provider does not dispatch to them. Five retired whitebox
fixture files (`normalize`, `graft`, `mean`, `structural_merge_resource`,
`subgraph`) are withdrawn from execution. The subgraph fixture shared helper
code from the withdrawn normalize/graft fixtures; the unconnected subgraph
product body is separately still on the removal inventory. Original source
is preserved by Git, not copied into a compatibility owner.

Applicable obligations are mapped to current positive tests as follows. This
does **not** claim support for the retired algorithms or their count laws.

| Retired fixture obligation | Current positive evidence |
| --- | --- |
| Work/workspace admission, exact/one-short ceilings | `keyed constructor admits exact control work and workspace and refuses one short`; keyed storage atomic capacity/work boundaries |
| Exact positioned input, ordered/repeated operands, input availability | `keyed constructor rejects foreign input custody and bounds preparation and control work`; repeated producer definition test; provider surplus-input/custody tests |
| Output budget breach never publishes partial material | Keyed constructor capacity/cancellation test, MATCH failure/cancellation test, TRAIL capacity/cancellation test |
| Stop before reclaiming partial output; cleanup remains possible after failure | Managed Graph cancellation, failed/revoked/unavailable output lifecycle cases; corrupted/interrupted/cancelled snapshot handoff cases |
| Two downstream consumers and final release owner | `managed Graph completion supports two exact downstream consumers`; `managed Graph material owns final reclamation` |
| Structural numeric/set folds, support weighting, endpoint merging, algorithm-specific sorting complexity | Unsupported under current contract; former algorithm proofs are withdrawn, not renamed to current resource evidence |

New typed-boundary tests use valid structural/mean options and complete keyed
inputs to require `UnsupportedGraphOperation` for graft/union/subtraction,
mean and subgraph. A syntax error is not accepted as the unsupported-consumer
evidence. They do not substitute for the positives in the table.

The related contract, construction, storage, lifecycle, snapshot and provider
suite passes **96/96 on JS, Wasm and native**:
`/private/tmp/property-graph-structural-kernel-removal-{js,wasm,native}-20261002.log`.
Unused imports found by the first check were removed, not suppressed. Current
generated interfaces no longer export the deleted handles.

The common `sga_graph` resource profile now points to those current source and
fixture owners and explicitly limits its evidence to constructor/MATCH/TRAIL.
It makes no resource-completeness claim for blocked operators. However, the
separate production-route inventory still contains obsolete kernel references.
The unchanged strict validator correctly fails on those references and on
incomplete family layers:
`/private/tmp/property-graph-structural-kernel-removal-resource-gate-20261002.log`.
Neither validator expectations nor the frozen provenance foundation were
changed. Aligning the route inventory and current supported/refused contract
is still required before aggregate spec/CI can be called successful.

The structural removal unit is committed as
`2fa05b1ff6d02f541aec9350ab117977e368e36b`. Official tracked three-target API
verification passes at this commit:
`/private/tmp/property-graph-structural-kernel-removal-api-committed-20261002.log`.
The unchanged composed-foundation validator also passes and records this exact
source revision in
`/private/tmp/property-graph-structural-kernel-removal-foundation-20261002.json`.
No new common-foundation digest declaration is needed for this unit. None of
these focused checks is a substitute for final public packed acceptance or CI.

## Retired diagnostic kernel removal checkpoint

The unconnected Local `graph_bounds` and `degree` implementation, its execution
handles, and ten tuple-only integration tests are removed. Four helper
declarations used only by those tests are removed too. A declaration-level
comparison confirms every remaining block in the mixed integration fixture
is unchanged apart from whitespace. Current complete Graph typing still
refuses both operators with `UnsupportedGraphOperation`; no provider fallback
has been introduced. Degree counts, self-loop incidence semantics and the old
diagnostic schemas are unsupported, not claimed migrated or proved.

The resource/custody obligations are retained by the current constructor,
managed output lifecycle and snapshot tests listed above. In addition, a
positive keyed node MATCH regression independently derives its exact three
workspace slots and five control-work units from its one-node fixture. Both
stored and viewed inputs admit the exact limits, refuse one-short limits,
and never publish partial rows on output-capacity failure. Cancellation is
tested at every quantum-one private yield, including after private row commit
and before public completion. Cleanup releases scratch exactly once, prevents
further polling and keeps the original Graph input available. The successful
result is checked against the independently authored value `one`.

Focused current contract, construction, storage, output, snapshot and provider
tests pass **97/97 on each of JS, Wasm and native**:
`/private/tmp/property-graph-diagnostic-retirement-focused-{js,wasm,native}-20261002.log`.
The first narrow compile found a raising preparation call inside a non-raising
test closure and an assertion on a value without Eq/Debug; preparation is now
obtained before the closure and the value is pattern-matched. Neither limits
nor expectations were loosened. The narrow construction file then passed
19/19 before the three-target run.

Latest fetched main remains
`0fd6332757176b88e8c4071e4a2cd0be3d6254e3`. This is still local unsubmitted
work, not a new full Core/spec/public packed/CI result. The old remaining
reach/shortest/components/diff/apply/traverse-nodes kernels and homogeneous
Carrier/reader branches remain explicit removal tasks. The unchanged strict
resource gate's obsolete-route and completeness failures remain open.

The diagnostic removal is committed as
`9bcaea698788c57713c4552b971ace48dba8e7e1`; the official committed three-target
interface check passes:
`/private/tmp/property-graph-diagnostic-retirement-api-committed-20261002.log`.

## Retired components kernel removal checkpoint

The old weak/strong components execution kernel and public handles are removed,
with six obsolete components/diagnostic tests and three now-unused helper
declarations in the mixed integration fixture. Its other declaration blocks
are unchanged apart from whitespace. The typed current boundary still rejects
components explicitly. Canonical component grouping, minimum identity ordering
and its algorithm-specific work formula are withdrawn, not claimed supported.

Empty-output admission is a separate required guarantee. A new current keyed
MATCH positive uses explicitly empty node and edge VALUES producers while
retaining its definition and output schema. Both stored and viewed inputs need
one workspace slot for the output column and one Finish work unit: exact
limits succeed, zero workspace is refused and zero work fails without output.
Cancellation before completion stops at zero work. Cleanup is idempotent,
releases scratch, preserves the input and disallows further polling. This
complements the nonempty MATCH all-private-yields regression, current storage
limits, two-consumer ownership, constructor/provider and snapshot failures.

The initial empty fixture accidentally retained a node and selected no rows.
Its scan correctly consumed work and the independently fixed one-unit empty
Graph expectation failed. The input was corrected to explicit empty producers,
not by relaxing the expected limit. Preserve that initial result at
`/private/tmp/property-graph-components-retirement-empty-js-20261002.log`;
the corrected narrow regression passes 1/1 at
`/private/tmp/property-graph-components-retirement-empty-corrected-js-20261002.log`.

Current related tests pass **98/98 on each of JS, Wasm and native**:
`/private/tmp/property-graph-components-retirement-focused-{js,wasm,native}-20261002.log`.
No warning exemption, owner substitution or successful unsupported-operator
expectation is used. This remains local work, not final Core/spec/public
snapshot/CI acceptance; reach/shortest/diff/apply/traverse-nodes and old
Carrier/reader removals and the strict route inventory remain open.

The components removal is committed as
`06930c874e30c8fc1aa63d72c9efe4e912b90c6a`. The official committed three-target
API check passes:
`/private/tmp/property-graph-components-retirement-api-committed-20261002.log`.
Neither retirement unit is pushed. Their sources and retired fixtures remain
recoverable from Git; neither dependency installations nor evidence logs were
deleted. The current public #164 revision is still the unadoptable historical
checkpoint, not this local verification result.

## Retired subgraph kernel removal checkpoint

The old Local subgraph kernel and its private tuple-copy helper are removed.
No other production kernel called that helper. Five old selected/Host
subgraph integration tests and their sole owner factory are withdrawn from
execution; their historical source remains in Git. Subgraph-specific induced
edge selection, scalar selectors and tuple projection semantics are
unsupported, not claimed transferred to keyed MATCH.

Generic input preservation, two-consumer lifetime and final reclamation stay
positive in current managed Graph output tests. The keyed MATCH test covers
every private yield before handoff, and keyed constructor/provider tests keep
input cardinality, foreign owner, failure and partial-material cleanup.
Current snapshot handoff tests preserve exact completion/input ownership after
saving and revoking the original. Typed subgraph admission still requires the
explicit unsupported-operation error; no old converter or provider is used.

The related current suite passes **98/98 on JS, Wasm and native**:
`/private/tmp/property-graph-subgraph-retirement-{js,wasm,native}-20261002.log`.
This does not claim final Host/public snapshot acceptance or full Core/spec/CI
at a submitted revision. Other obsolete product paths and the strict resource
inventory remain open.

### Current aggregate diagnostic after mean retirement

At source `ecd003217e0a960b88a4ecdf3b0e09925ea84abd`, the official public
MoonBit API check passes across targets and tracked interfaces:
`/private/tmp/property-graph-mean-api-committed-20261003.log`.
The full Core JS diagnostic completes with **7,398 total / 7,250 passed /
148 failed** (exit 2), at
`/private/tmp/property-graph-core-js-after-mean-retirement-20261003.log`.
All 148 failure records, including the union failure without a colon after
`failed`, are counted. This is not a green Core result.

| Remaining failing package | Failures | Required next action |
| --- | ---: | --- |
| `capacity_program_step` | 9 | Separate unsupported union/structural/nodes/shortest algorithms from applicable overflow, exact work and bound-owner assertions; migrate the latter positively |
| `pipeline_check_context` | 16 | Remove unsupported bindings; migrate TRAIL selector/guard/phase, resource-owner and repeated producer requirements without substituting equal checked owners |
| `pipeline_typing` | 7 | Retire Graph diff/apply Delta forwarding assumptions without disabling non-Graph contract and input ownership checks |
| `program_check` | 34 | Separate unsupported algorithm-specific claims from imported policy, preflight, selector and atomic failure guarantees; investigate the mixed malformed-step diagnostic test rather than changing every expected refusal |
| `query_integration` | 75 | Retire old constructor/kernel-specific fixtures; retain positive current MATCH/TRAIL quantum, work/workspace, private cancellation, input/retained output custody and Host composition coverage |
| `query_program` | 7 | Coordinate Frontend fixtures and typed Graph lowering with B; no old contract fallback or parallel Frontend change |

This table is an outstanding work inventory, not a claim that every failing
assertion is obsolete. In particular, mixed capacity/cancellation/cleanup
fixtures cannot be removed merely because their old setup is now refused.
No required gate is weakened or bypassed. The final published snapshot
save/revoke/reload acceptance, aggregate checks and required CI remain pending;
the public PR still points to its previous archived source.

## Current Graph contract expectation custody

The seven failing Delta setup cases in `pipeline_typing` are migrated to an
independently authored current Graph contract and explicit input expectations.
Its canonical body has the independently computed SHA-256 literal
`78b5e6a56288c04737f3a13a4b1ad9c653892cd22c060225f990e12406b45d1e`.
No retired Carrier constructor or diff-generated contract supplies this fixture.

Positive obligations remain: independent SELECT aliases, DROP/RENAME transfer,
value-preserving filters/sorts/empty derives, loss of an overwritten field's
expectation, exact retained input contract and producer, duplicate/unknown field
binding refusal, exact and one-short work/node/text accounting, immutable
extension of imported evidence, projected producer ownership and 2,000 ancestry
forwarding steps without recursive traversal. Bare but text-identical JSON rows
remain valid rows, without acquiring the separately retained expectation.
Former diff/apply execution, binary roles and exact-base identity obligations
are not claimed supported by these expectation tests.

Initial fixture compilation catches missing target qualification, the schema
Field accessor and the helper's raising assertion signature; each is corrected
without changing the bound checker or its expectations. The corrected narrow
suite passes 10/10 JS. The complete `pipeline_typing` package then passes
**327/327 on each JS, Wasm and native**:
`/private/tmp/property-graph-delta-pipeline-{js,wasm,native}-20261003.log`.
The preceding aggregate failure count remains the diagnostic for its recorded
SHA, not a new whole-Core result. Other unsupported typed Graph branches and
generic guarantee migrations remain open.

The subgraph removal is committed as
`7dd8c80797f788649a00af038f0c7aea2a16943d`. Its official committed API check
passes at `/private/tmp/property-graph-subgraph-retirement-api-committed-20261002.log`.

## Retired Reach kernel and current Relation selector custody

The homogeneous Reach kernel, public handles and the traversal adapter's node
fallback are removed. Four pure retired Reach/traversal fixture files and
eleven obsolete tests in the mixed integration fixture are withdrawn; their
source remains in Git. Scalar node depth, old shortest/simple-node emission,
Reach predicates and their algorithm-specific work formulas are unsupported,
not claimed migrated. The common typed boundary still refuses unsupported
consumers. Path-owner node-emission internals and other retired kernels remain
separate unfinished removals; this checkpoint is not complete unification.

The new positive `property_graph_selector_custody_wbtest.mbt` obtains its JSON
typed identity selector from actual keyed MATCH, then uses the existing bounded
APPEND with two exact retained occurrences. It does not fabricate a trusted
completion or permit unsupported JSON VALUES. Independent constructor keys
determine the two parallel-edge TRAIL results, including their order; repeated
selector rows do not multiply paths. Stored and viewed Graph reads preserve
both retained inputs, reject a missing/foreign selector and clean up stopped
private state idempotently without revoking the original inputs.

An empty selector on the one-node fixture independently requires one initial
selection slot and three control units (initialize, collect, Finish). Exact
limits pass; workspace zero is refused and work two fails without output.
Cancellation at all three private prefixes preserves the reported cumulative
work, both input owners and zero private entries after cleanup. This is a
current TRAIL guarantee, not restoration of an unsupported Reach algorithm.

Initial test failures are preserved: JSON VALUES were rejected by the existing
checker, so the fixture was replaced with real MATCH/APPEND. The added stop
assertion initially treated cumulative poll work as a delta; it was corrected
to the existing bounded-session contract, without changing the product budget.
Logs: `/private/tmp/property-graph-selector-custody-exact-js-20261002.log` and
`/private/tmp/property-graph-selector-custody-exact-corrected-js-20261002.log`.

Current related suites pass **99/99 each on JS, Wasm and native**:
`/private/tmp/property-graph-reach-retirement-focused-{js,wasm,native}-20261002.log`.
No warning exemption or fallback is introduced. Full Core/spec, fresh public
snapshot and required CI on a submitted SHA remain open.

The Reach retirement is committed as
`cc1c78ebc` (see Git for its full SHA). The committed official API check passes:
`/private/tmp/property-graph-reach-retirement-api-committed-20261002.log`.

## Path owner node-emission removal

The remaining homogeneous node-depth initialization, node endpoint sorting,
node row emission and their scratch state are removed from the shared path
owner. There is no `emit_nodes` flag or alternate node kernel. Both stored and
viewed traversal dispatch require an explicit current path mode and path
emission, as does the installed provider. Path frontier reservation, work,
value limits, typed identities and cancellation are unchanged.

The same independent MATCH/TRAIL, snapshot, storage and custody suite passes
**99/99 on JS, Wasm and native** after removal:
`/private/tmp/property-graph-node-emission-retirement-focused-{js,wasm,native}-20261002.log`.
The narrow construction/selector suite also passes 20/20. Obsolete homogeneous
node traversal fixtures are not evidence for current support. Other retired
consumer kernels and typed/storage APIs still need removal; no final acceptance
or public-source replacement is claimed here.

## Remaining Local consumer kernel retirement

The old scalar/weighted shortest, endpoint-tuple equality, delta generation
and delta application execution kernels and public handles are deleted. The
Local SGA package now contains only current MATCH, keyed path execution and
their exact stored/viewed read adapter; it no longer imports a delta/snapshot
execution fallback. The unused definition-free edge-index reader is removed.

The mixed integration fixture withdraws 19 old shortest tests, 14 old
equality/diff/apply tests and their private helpers. A pure obsolete delta
resource fixture is also removed. Historical bodies remain in Git. Weighted
path selection, equality alignment, tuple delta actions and their exact work
formulas are not current guarantees or current supported algorithms. They
remain explicitly refused at the typed boundary. Generic exact producer
binding, retained input lifetime, two consumers, empty outputs, one-short
admission, cancellation and private reclamation remain positive in the current
storage/runtime, constructor, MATCH, TRAIL selector and snapshot suites.

After integrating main `bcbf77049fe4991c9b0f1a18541ac7a7952b01ad`, the foundation
history validator passes without changing any frozen hash or validation rule:
`/private/tmp/property-graph-current-main-foundation-20261002.log`. The five
bound-fixture audit regressions pass; this is not the full pipeline evidence
gate. Related Graph suites pass **99/99 each on JS, Wasm and native**:
`/private/tmp/property-graph-remaining-consumer-retirement-focused-{js,wasm,native}-20261002.log`.

Old Carrier constructor/getters, obsolete storage/runtime entry points and
mixed old fixture scaffolding still need removal. Full Core/spec and strict
resource-route inventory, plus fresh public snapshot and submitted-SHA CI,
remain required. No final handoff or merge is authorized by this local result.

The Local consumer removal is committed as
`6b414308c360cfea1502ace54c2731deb8becf13`. Its official committed API check passes
at `/private/tmp/property-graph-remaining-consumer-retirement-api-committed-20261002.log`.
The 139 retained declaration blocks in the mixed integration fixture remain
byte-identical; 51 obsolete blocks were removed, not rewritten into refusals.

## Tuple mutation API removal

Storage and managed output no longer expose `append_node`, `append_edge`,
`observe_node`, `observe_edge` or definition-free `contains_declared_node`.
The retired `DerivedEndpoints` builder mode is deleted, leaving explicit keyed
node declarations. Current `append_property_node`/`append_property_edge`, their
private reservation and existing retention owner are unchanged.

The two tests of removed compatibility APIs are not retained as product
execution. Opaque Graph knowledge still has its explicit allocation refusal;
all keyed storage capacity, duplicate keys, missing endpoints, failed builder,
cancellation, retained bytes and lifecycle owner positives remain. Eight
obsolete tuple mutation/provider structural tests and their unreachable
scaffolding are removed. Their former algorithm support is not claimed current.

Related current suites pass **98/98 each on JS, Wasm and native**:
`/private/tmp/property-graph-tuple-builder-api-retirement-focused-{js,wasm,native}-20261002.log`.
This count decreases by one because the withdrawn tuple-mutation test is no
longer a current operation, not because a keyed capacity or custody positive
was changed into a refusal. The narrow storage/runtime/selector run passes
23/23. Remaining Carrier convenience APIs and old typed/fixture scaffolding,
full Core/spec, strict resource inventory and final public snapshot/CI remain
open. No compatibility owner or fallback was introduced.

The tuple mutation API removal is committed as
`4060dedd675e3e77d0c9ff5fc15cefa2cc95bfe6`. The official tracked API check passes:
`/private/tmp/property-graph-tuple-builder-api-retirement-api-committed-20261002.log`.

## Aggregate diagnostic after kernel retirement

Full Core JS at committed source
`4060dedd675e3e77d0c9ff5fc15cefa2cc95bfe6` is **7,404 total / 7,243 passed /
161 failed**, exit 2. Evidence:
`/private/tmp/property-graph-core-js-after-kernel-retirement-20261002.log`.
Named failure groups are capacity_program_step 12, pipeline_check_context 18,
pipeline_typing 7, program_check 37, query_integration 80 and query_program 7.
The capacity union failure uses the expect-test reporter without a colon;
counting only `failed:` lines would incorrectly report 160 failures. No
Local SGA failure remains. This is still red aggregate verification.

These failures are not blanket retired: upper bound/owner and supported
MATCH/TRAIL/Host positives require migration; delta/structural algorithm
claims are unsupported; typed old-constructor fixtures require separate
classification. Frontend Graph lowering/source-definition binding remains a
specific open boundary, not assumed fixed by runtime kernel removal.

## Keyed MATCH row-law migration

`capacity_program_step/graph_rows_test.mbt` now retains the original positive
quantity-law assertions through valid keyed node/edge definitions. For counts
0, 1 and 3, independently authored distinct keys produce explicit self-loop
edge identities. TRUE/FALSE node MATCH and FALSE edge MATCH derive the row
upper bound from the original node/edge premise rather than an observed
filtered result. Exact input-owner identity, value mismatch, entity-unit
substitution, wrong-law substitution and application collection remain tested.
Degree/components and scalar-ID selection formulas are not claimed migrated.

The keyed constructor checks its single premise in five bounded operand
passes, unlike the removed tuple unary rule. The initial fixture supplied the
old zero allowance and correctly failed `OperandWorkLimit`. The fixture now
admits exactly five and separately requires failure at four; no product limit
or validator is relaxed. Temporary Debug/Show diagnostics also failed before
correction and are not successful checks. Their logs remain under
`/private/tmp/property-graph-match-row-law-migration-*-20261003.log`.

The migrated row law and existing repeated/mixed-definition quantity evidence
pass **3/3 on each JS, Wasm and native**:
`/private/tmp/property-graph-match-row-law-focused-{js,wasm,native}-20261003.log`.
The preceding 161-failure aggregate predates this migration; no new aggregate
success or computed reduction is asserted. Remaining upper fixtures, Carrier
API retirement, supported/refused route inventory, fresh public snapshot and
fixed submitted-SHA CI remain open.

## Distinct entity measures and imported-input custody

`capacity_program_step/graph_measure_test.mbt` now uses independent explicit
N/E key definitions, including empty and unequal input extents. Both entity
units retain their original VALUES premise. MATCH bridges preserve the row
unit, reject entity-unit or foreign-input substitution and fabricated values,
and TAKE consumes the original row bound. Bounds remain conservative input-row
upper bounds, not filtered output counts. Missing endpoint exclusion does not
authorize fabricating a smaller witness for the input-row law.

The retired concise constructor's endpoint-occurrence node formula is
withdrawn. Its generic imported-input guarantee is migrated positively: the
receiver's MATCH retains the exact produced Graph premise; one input-work unit
succeeds and zero fails. Current constructor operand validation requires exactly
five passes for each selected definition premise; four fails. No checker,
capacity expectation or ownership boundary is relaxed.

The measure fixtures, row-law fixture and existing keyed proof fixtures pass
**5/5 on JS, Wasm and native**:
`/private/tmp/property-graph-measure-custody-{js,wasm,native}-20261003.log`.
The initial narrow JS run also passes 5/5. This is not a new aggregate Core,
packed or required CI result. Remaining old Carrier/typed branches, supported
upper fixtures, inventory and final public snapshot acceptance are still open.

## Program preflight and MATCH obligation ownership

The Program conversion fixture now binds a declared definition-scoped Graph
and MATCH, rather than the retired factory/node-row projection. It retains
preflight enforcement, exact original Graph input, foreign pipeline rejection
without budget mutation, independent canonical proof preimages and the closed
three-claim publication set. Existing literal converted witness/limit CIDs
remain unchanged; no expected product CID was copied. The input conversion
itself remains the same owner-controlled boundary.

The old projection execution fixture is replaced by
`pipeline_check_context/graph_match_execution_wbtest.mbt`. Node and edge MATCH
retain admission/order/predicate/resource obligations, the exact checked
operation and input, shared policy ceilings and the current phase/failure
contract. Separate but text-identical checked owners must not substitute for
one another. Profile obligations remain unresolved, not treated as permission.

The migrated test exposed a real common MATCH boundary defect: group 1 could
substitute for the operation's sole body group. The handler also lacked an
exact obligation-owner check. The regression fails before correction:
`/private/tmp/property-graph-match-custody-before-js-20261003.log` (0/1).
The minimal correction exposes the retained MATCH owner from the existing
obligation handle and checks group 0 and physical owner identity. It adds no
new execution or accounting owner. Invalid index/step/group, foreign pipeline
and foreign obligation owner are rejected; distinct valid policy owners retain
their own ceilings. The retired projection's homogeneous restoration rules
are not claimed as current MATCH algorithms.

These migrated cases plus keyed construction, imported producer custody and
the existing operation-resolution-index tests pass **9/9 on JS, Wasm and
native** at `/private/tmp/property-graph-upper-custody-{js,wasm,native}-20261003.log`.
The Program-only initial run passes 1/1; the corrected first combined run
passes 3/3. The test path in those logs predates the rename to MATCH.
Full Core/spec, old typed branch/API removal and final submitted public
snapshot/packed/CI verification remain open.

The committed MATCH owner API check passes at
`/private/tmp/property-graph-match-owner-api-committed-20261003.log`.

## Tuple Graph-to-Relation reader removal

The Local bridge's homogeneous node/edge reader is deleted: `GraphRowsState`,
`GraphRowsExecution`, its stored/viewed source union, field-role restoration,
endpoint/label tuple readers, bounded projection loop, start/advance/cleanup
entry points and poll type. It cannot be a fallback for current MATCH. The
current keyed constructor still uses its original bounded session and shared
checked-cell reader; those are not duplicated or removed.

Five obsolete projection tests and two private projection helpers are removed
from the mixed integration file, along with an unused missing-endpoint source
helper. Historical work formulas and homogeneous output schemas are withdrawn,
not represented as new refusal successes. Positive equivalents remain:

- Explicit keyed construction, repeated producer occurrences, missing endpoint
  exclusion, foreign owner refusal and exact/one-short constructor work and
  workspace are tested by `property_graph_construction_wbtest.mbt`.
- Current node MATCH tests all private stop prefixes, exact/one-short work and
  workspace, output limits, stored/viewed inputs and idempotent cleanup.
- A new independent one-edge MATCH case applies the same obligations to edge
  output: three workspace slots and five phase-derived work units; two slots
  or four units fail. Every private quantum-one yield can be cancelled without
  output. Completed typed identity rows remain readable after Graph reclamation
  and feed two independently checked Relation consumers (SELECT and FILTER),
  each retaining the original output owner.
- Runtime lifecycle tests retain two exact downstream Graph consumers,
  revocation, final reclamation and unavailable/failed output custody. Keyed
  snapshot and selector tests retain their existing cancellation and ownership
  positives.

The first retirement run passes 31/31 JS but reports the newly unused helper;
that helper is removed, not warning-exempted. The new edge test first passes
32/32. Adding downstream FILTER initially fails in the old demonstration
`compute_test_sequence` helper, which supplies contexts only for a three-step
fixture. Using existing `task_test_generated` prepares the exact authored
expression context; no evaluator or assertion is relaxed. The initial 19/20
log is `/private/tmp/property-graph-edge-match-retained-rows-first-js-20261003.log`;
the corrected run passes 20/20.

The current Graph/storage/runtime/snapshot suite plus migrated entity bounds,
MATCH obligation custody and Program preflight now passes **103/103 on each
JS, Wasm and native**:
`/private/tmp/property-graph-tuple-reader-retirement-{js,wasm,native}-20261003.log`.
This is focused evidence, not full Core/spec or published-SHA acceptance.
Old Carrier constructor/getters, unsupported typed consumer branches, mixed
upper/Host fixtures and the strict resource-route inventory remain open.

## Retired mean consumer removal

The unconnected `mean_graphs` consumer no longer has an executable checked
Graph type, operation/obligation variant, profile requirement, row-count law,
execution binding, publication-policy arm or lowering payload. Its old Carrier
factory call and homogeneous merge/output schema path are deleted, together
with the obsolete mean execution and Program fixtures. Shared execution
dispatches no longer contain mean branches. This is a breaking removal, not a
compatibility adapter or a new mean implementation.

The authored option checker remains bounded and validates weights, support and
property strategies, but cannot issue an executable Graph. The public pipeline
boundary preserves alias/from/name/metadata validation and refuses a valid mean
with `UnsupportedGraphOperation` at the operation body. Independent invalid
weight and strategy cases retain their specific diagnostic paths. This does
not promise new-contract mean arithmetic, weighted samples, numeric rounding,
support thresholds or merge semantics; those historical guarantees are
withdrawn rather than renamed as refusal coverage.

Applicable non-mean guarantees remain positive in the new contract: the formal
constructor/MATCH Result-import case in `graph_branches_wbtest.mbt` retains
repeated positional input occurrences, exact producer and obligation owners,
resource enforcement and all three publication visits. Current construction
and MATCH execution tests retain shared policy ceilings and foreign owner
rejection. New Graph capacity, private cancellation, scratch cleanup, snapshot
and retained-output tests remain in the executed suite; no success assertion is
replaced by a generic old-format rejection.

The first narrow test attempt found missing namespace qualification in the new
diagnostic fixture. After correction, 22/23 passed and exposed the removal of
the existing alias-required check; the check is restored, not its expectation
relaxed. The corrected narrow suite passes 23/23 JS. The combined current Graph
and refusal/owner suite passes **112/112 on each JS, Wasm and native**:
`/private/tmp/property-graph-mean-current-{js,wasm,native}-20261003.log`.
Three-target interface generation completes; the official committed API gate
is run separately. These are local focused checks, not the final published-SHA
public snapshot acceptance or required CI. Other old Carrier constructor and
unsupported consumer branches, mixed old fixtures and the strict resource
inventory remain open.

## Retired structural and comparison pipeline removal

Equality, diff, delta application, union, graft and subtraction no longer have
checked executable operation types, profiles, obligations, lowering payloads,
sequence steps or driver dispatch branches. Their homogeneous output factories
and the `GraphCombine` quantity rule are deleted. The public authored boundary
still checks bounded option structure, references and names before explicitly
refusing these unimplemented current-contract consumers. The independent apply
refusal uses a valid current Graph and an explicitly bound current contract,
not a missing input or malformed operation. No comparison or Delta permission
is issued, and there is no tuple fallback.

Two shared facilities were extracted rather than deleted: bounded selector
schema alignment and MATCH's `GraphComparisonResource` checks. Their existing
owners, limits and custody rules are unchanged; neither is an old Graph
executor. The old operation-specific execution and Program tests are withdrawn
with their implementations. They do not prove current-contract diff, patch,
merge, source-policy or algorithmic work formulas.

Applicable arithmetic and ownership guarantees are positive current tests:
33 node definitions consume the same checked producer 33 times, retain each
original operand owner, require exactly 165 operand work units and reject 164.
Safe-integer overflow is an explicit `BoundOverflow`, never a successful zero
or saturated proof. Current `PropertyGraphMeasure` also retains the empty and
directional operand-sum cases in the bounded arithmetic unit tests. Constructor,
MATCH, snapshot, private cancellation and retained-output custody remain in the
executed current suite; explicit contract expectation forwarding remains in
the complete pipeline-typing suite.

The first product check exposed a shared resource type in a deleted file and
an unused import. The resource type/helper were moved into MATCH and the import
removed, not warning-exempted. An initial test command named a nonexistent test
path and executed no acceptance; the corrected suite passes **483/483 on each
JS, Wasm and native** at
`/private/tmp/property-graph-binary-retirement-{corrected-js,wasm,native}-20261003.log`.
The added repeated-operand/overflow migration and arithmetic unit tests pass
**3/3 on each target** at
`/private/tmp/property-graph-repeated-arithmetic-{js,wasm,native}-20261003.log`.
Three-target interface generation completes. These are focused local results,
not an inferred full-Core pass or final published snapshot/CI evidence. The old
Carrier factory stub and other unconnected consumer types still need removal;
mixed upper/Host fixtures and the strict resource inventory remain open.

## Current TRAIL selector and upper binding custody

The mixed upper-driver selector and traversal fixtures now construct the
current Graph through its admitted producer. Literal selectors use complete
definition/domain/typed-key identities, and Relation selectors use the exact
Graph identity contract on a qualified field. Successful cases retain repeated
literal occurrences, the original checked step, operation, policy and site,
primary/selector input roles, and refusal of foreign pipeline/group/index
owners. Explicit TRAIL is tested with patterned and bounded unpatterned hops,
canonical path obligations and the original unresolved output guard.

The former subgraph/shortest endpoint-role and homogeneous node/simple-path
cases are not represented as supported execution. Definition-free start/hop
property predicates are also not claimed migrated: current per-definition
MATCH predicates are supported, but these traversal predicates still need a
contract connection before they can be offered. The current test does not
pretend its absent predicates prove their evaluation.

The first narrow run passes 3/3 JS. Including current constructor/MATCH owner
checks, selector custody and selector/traverse typing, the migrated suite
passes **10/10 on each JS, Wasm and native**:
`/private/tmp/property-graph-trail-owner-migration-{js,wasm,native}-20261003.log`.
This preserves applicable upper custody checks as positive current-contract
tests, rather than converting them all into unsupported-operation assertions.

## Aggregate diagnostic after comparison retirement

Full Core JS at `e8efd8a393c08f2e1058f40a833e5d96aa0aa46f` is **7,388 total /
7,260 passed / 128 failed**, exit 2, at
`/private/tmp/property-graph-core-js-after-binary-retirement-20261003.log`.
The exact failure groups are capacity_program_step 7, pipeline_check_context
12, program_check 27, query_integration 75 and query_program 7. The union
expect-test failure without `failed:` is included; no result is inferred by
subtracting removed cases from the prior run.

The remaining mixed bound/owner, supported MATCH/TRAIL and ordinary Host
cases must be migrated. Component/reach/shortest, structural merge/diff/apply
and homogeneous node/simple-path formulas are unsupported algorithm claims,
not new-contract resource acceptance. Query-program failures include the
unconnected external producer-definition boundary; they are not silently
reclassified as desired language refusals. Current per-definition MATCH and
TRAIL fixtures pass, but that does not establish all external Source routes.
This diagnostic predates the next Carrier factory unit, and is still red.

## Carrier tuple factory deletion and provider custody migration

`carrier_contract.graph` is deleted, rather than retained as a compatibility
stub returning a rejection. No remaining source call constructs a tuple
Carrier. Old API-specific negative fixtures and three pure unsupported
basic/reach/shortest execution fixtures are removed from execution. Historical
sources remain in Git. Current incomplete knowledge still cannot allocate
storage or issue a pinned contract; those checks use the existing opaque
knowledge type directly, not a fabricated historical producer.

The former provider material fixture mixed generic lifetime guarantees with
unimplemented graft/union consumers. Its positive lifetime obligation is now
`property_graph_provider_custody_wbtest.mbt`: the registered current constructor
delivers one material with composite node keys and two independent parallel
edge keys. Two current node/edge MATCH consumers are started from exact views.
A reconstructed foreign producer is rejected. One consumer's cleanup does not
invalidate the other's view or material; a third cancelled consumer cannot
reclaim the shared input. Repeated cleanup remains safe. Final reclaim revokes
both views while already completed Relation rows remain available. Expected
rows and typed edge keys are authored independently. This is not support for
graft or union and does not claim their old two-input algorithm migrated.

The new test first failed to compile because its local start closure omitted
`raise`; its next run rejected a node MATCH without a selector, before reaching
the edge consumer. The fixture also lacked the edge's explicit identity binding.
Both were connected through the existing valid MATCH contract, without changing
the checker or expected rows. It then passes 1/1 JS. The first factory suite passes
49/49 but exposes two now-unused private old producer helpers; those are
deleted, not warning-exempted. The corrected factory/contract/snapshot/provider
and task-port suite passes **49/49 on each JS, Wasm and native** at
`/private/tmp/property-graph-factory-removal-{js,wasm,native}-20261003.log`.
The current constructor/MATCH/snapshot, byte limits, corrupt reload, private
cancellation and typed task-port positives remain executable. Other homogeneous
metadata getters and unsupported checked consumer branches, mixed Host/Source
fixtures, strict inventories and final submitted-SHA packed/CI acceptance remain
open. This local result does not authorize a final B handoff or merge.

## Retired reach removal and current TRAIL resource migration

The unsupported reach checker, checked operation, obligation owner, prepared
node/emitter, expansion/resource/semantic bindings and driver branches are
deleted. The authored pipeline boundary retains closed-body and reference
checks, then explicitly rejects a current Graph with
`UnsupportedGraphOperation`. Incomplete knowledge and wrong Carrier kinds
remain separate refusals. No checked reach can issue an executable tuple
output or runtime permission. The direction emitter is retained separately
because current keyed TRAIL lowering uses it.

The former reach resource/import and publication-owner tests are migrated
to positive current TRAIL tests, not replaced by blanket refusals. Formal
Program construction retains independent search-path and output-row ceilings,
the producer Unit's application and original policy owner through three visits,
and the checked TRAIL operation through publication. Three direction choices
and ordinary/over-Int hop bounds are covered. Missing applications specifically
fail as `TraversalCollection(MissingApplication(3))`; a differently scoped
claim specifically fails as `Traversal(0, SubjectMismatch(SearchPaths))`.
Neither case can seal a partial checked Program.

The authored selector uses typed key `N/[number:1]` in domain
`sha256:3c07a675d79b8ca20df7ccce6bf1282b0ac34059bfbbaec8a8cd102f5027a5c3`.
Its independent canonical SHA-256 preimage is:

```json
{"constructor":{"edges":[],"nodes":[{"input_occurrence":0,"key":["id"],"name":"N"}],"version":"actql-property-graph-constructor/0.1"},"producer_definitions":[{"body":{"values":{"rows":[{"id":1},{"id":2}],"schema":{"id":{"nullable":false,"type":"number"}}}},"dependencies":[]}],"version":"actql-property-graph-definition/0.1"}
```

The literal is compared with the checked constructor domain; it is not copied
from compiler output. The shared upper-capacity fixture also now constructs
current typed Graph and explicit TRAIL, retaining exact/one-short work,
foreign pipeline/policy/guard rejection, independent path/output ceilings and
Parameter binding custody. Unsupported node emission and shortest/reach
algorithms are not claimed supported.

The publication fixture uses an admitted Values definition. It specifically
retains zero borrowed provenance from its unused external Source. The old
external Source-dependent case is **not** claimed migrated by that success:
external producer-definition admission remains an open boundary in the
aggregate diagnostic and must be closed separately.

Initial product checks exposed remaining deleted-type references in exhaustive
dispatch arms; those were removed, not converted to fallback. The first narrow
run also rejected an empty `ids` selector as `InvalidBody`. It was replaced
with the independently derived valid identity above, without relaxing the
selector or the capacity assertions. The resulting current resource/custody
and surrounding regression suite passes **31/31 on each JS, Wasm and native**:
`/private/tmp/property-graph-reach-retirement-{js,wasm,native}-20261003.log`.

Basic/subgraph/shortest checked implementations, homogeneous metadata and
projection routes, external Source/Host fixtures, strict inventories and
published-SHA fresh packed/CI acceptance remain open. These local results do
not make the old public #164 HEAD adoptable and do not close the previous
full-Core diagnostic.

## Retired shortest-path removal and current TRAIL guard custody

The old shortest checker/type, endpoint/selection types, obligation owner and
groups, prepared node/emitter, resource/semantic closure and all lowering and
driver arms are removed. The public authored operation still performs bounded
closed-body and endpoint-reference checks. A current Graph is explicitly
rejected with `UnsupportedGraphOperation`; missing Graph knowledge and wrong
Carrier kinds remain distinguishable. A nonexistent selector is not silently
accepted. No checked shortest operation can issue executable output.

The former dedicated capacity test now uses current TRAIL. It retains the exact
seven-unit checking boundary, one-short rejection, separate search/output
ceilings, original guard occurrence/pipeline/policy custody, foreign guard
rejection and complete-application coverage. Guard values 1, 7 and 20 do not
change the independent path ceiling. The shared upper fixture no longer has an
old shortest-construction switch.

The formal guard and Unit conversion tests also now construct the current
typed Graph and TRAIL with the independently derived N identity above.
Positive literal and Parameter guards, three imported visits, before-output
enforcement custody, two distinct synthetic Unit namespaces, exact/one-short
work/byte/node conversion budgets and foreign occurrence rejection remain
executable. The existing expected limit CIDs were retained, not updated from
product output: the policy and traversal scope preimages did not change.

An independent Node SHA-256 calculation constructs the fixed policy fields
(all ceilings 1000, except the selected output ceiling), Host and author-guard
witnesses, sorted candidate lists and Unit-scoped resolved limits without
importing ActQL. It verifies all four namespace/output-ceiling pairs and the
three guarded literals. The fixed policy CIDs are
`sha256:2708864ce4629856aca01376b7f6641f6c177484e4afa8cbb5a2e67082b5f5e8`
(output ceiling 1) and
`sha256:b2c843e5b5c83761dae40dc6afe9a364864c3f683a1c20e4e5ed4bd538d904a9`
(output ceiling 1000).
The independent reproduction and complete preimages are preserved at
`/private/tmp/property-graph-trail-limit-independent-20261003.mjs` and
`/private/tmp/property-graph-trail-limit-independent-20261003.jsonl`.

Shortest-specific endpoint pairing, weighting and tie-break tests are
withdrawn with their implementation, not relabelled as current support.
Shared checked multiplication still retains safe-integer/zero/overflow
regressions; nearest-selection shortcuts are removed. The bound-law registry's
declared law metadata is unchanged and does not grant a shortest execution
route. External Source-dependent publication custody and the remaining
unconnected node-emission bound path are still open; the positive Values
fixture does not claim to close them.

The first narrow run exposed an extra closing brace in the removal patch,
which was corrected. The first wider invocation named a nonexistent order
test file; the corrected invocation then exposed missing test-only IssueKind
annotations. Explicit annotations were added without changing product
classification or weakening expectations. The final surrounding regression
suite passes **53/53 on each JS, Wasm and native**:
`/private/tmp/property-graph-shortest-regression-{js-final,wasm,native}-20261003.log`.
Intentional interface removals were generated on all three targets.

Basic/subgraph checked consumers, homogeneous metadata/projection routes,
external Source/Host fixtures, strict inventories and submitted-SHA public
snapshot/fresh packed/CI acceptance remain open. The earlier aggregate Core
diagnostic is not replaced by this narrow success, and public #164 is not yet
adoptable.

## Retired subgraph removal and current selector custody

The retired subgraph checker, checked type, obligation owner, prepared kernel,
emitter, resource closure and every lowering/driver arm are removed. The public
authored operation retains closed-body and selector-reference checking and
explicitly refuses the unconnected operation. Current Graph, incomplete Graph
knowledge and wrong Carrier kinds have distinct diagnostics. The existing
selector emitter is extracted unchanged into `lowering_relation/graph_selector.mbt`;
current TRAIL keeps its existing checker and selector owner, not a second owner.

The former formal selector/resource checks are migrated to current TRAIL with
the independent typed N identity above. Duplicate literal identities and an
independently wired Relation selector from definition-scoped MATCH are both
positive cases. Three imported visits retain the exact original pipeline,
Graph target, selector target, group, StartSelector scope, checked selector,
before-input/before-output phases, rejection behavior and work/byte resources.
Negative resource indexes remain rejected. The shared capacity fixture now
accepts the actual traversal step so the MATCH-producing variant has an exact
step-4 claim rather than borrowing the old step-3 occurrence. Its seven-step
direct Program has an explicitly declared seven-step test budget; product
limits are unchanged.

A separate formal SourceView program checks publication custody: the original
TRAIL operation and its Primary/Right edges remain retained, and the unused
external Source lends no provenance to the VALUES definition. This is **not**
a replacement for the old external Source-dependent constructor/publication
case. That admitted producer-definition boundary remains open. Subgraph-only
induced-edge/filter/materialization tests are withdrawn with their unsupported
algorithm; definition-free node predicates are not relabelled as supported.

The first new fixture runs exposed a missing required MATCH selector, a
hard-coded capacity step and a six-step budget for a seven-step direct Program.
Those fixture coordinates were corrected without relaxing product validation.
A policy check incorrectly attempted to read a non-published producer port;
it now checks a separate actually published direct Program and its original
owner. All initial logs are retained under
`/private/tmp/property-graph-subgraph-*-20261003.log`.

The surrounding regressions pass 61/61 on JS and Wasm, with the 22 existing
shared-fixture tests separately passing on each; native passes the combined
83/83. Logs are `property-graph-subgraph-regression-{js-final,wasm,native}`
and `property-graph-subgraph-fixture-{js,wasm}`, with the same date suffix.
Four generated interfaces contain only intentional retired subgraph removals.

Basic/components, homogeneous metadata/projection routes, external Source/Host
guarantees, strict inventories and submitted-SHA public snapshot/fresh packed/CI
acceptance remain open. Local narrow success is not the final #164 acceptance.

## Retired basic/components checked-pipeline removal

The old basic Graph checked type, checker, obligation owner, lowering payload,
emitter, driver arms, operation resolution phases and dedicated components
capacity applications are removed. Their Program conversion, guard conversion,
automatic claim selection and preflight coverage branches are removed together,
not retained behind a profile rejection. The authored unsupported operations
still refuse current Graphs explicitly, distinguish incomplete Graph knowledge
and wrong Carrier families, and do not create a checked execution grant.

Pure components algorithm and claim-conversion fixtures are withdrawn with the
unsupported algorithm. Its canonical grouping, degree/bounds diagnostic schema
and diagnostic-cardinality law are not claimed migrated. Declared historical
capacity/guard law metadata is not an execution route. The components fixture
claim issuer is removed from DuckDB and projected Node/Workers conformance;
generated copies are refreshed from their source, not patched independently.
Historical authoring probes still cannot obtain a current execution grant.

The generic guarantees have supported positive replacements: current TRAIL
retains guard ownership, independent search/output scopes, all candidates,
foreign owner rejection and exact/one-short work/byte/node conversion budgets;
the complete preflight suite retains unused-branch, missing/duplicate claim,
input owner, imported closure and limit-consumption checks. Formal current
Property Graph construction now additionally proves that both imported Results
retain the exact original constructor step and capacity policy through three
visits (one producer and two imports), for empty/nonempty inputs and two Host
ceilings. The original unresolved-envelope refusal remains a separate test.
The old external Source publication-policy case is not replaced by these
VALUES fixtures: admitted external producer definitions remain an open boundary.

The final surrounding regression suite, including the complete preflight
package, passes **125/125 on each JS, Wasm and native**. Logs are
`/private/tmp/property-graph-basic-final-preflight-{js,wasm,native}-20261003.log`.
Initial runs found a stale diagnostic-helper test, a nonexistent input-filter
filename and the old four-item assertion after removal of the components use;
those obsolete references were corrected. The retained collection still checks
all three actual consumer roles, exact/one-short work, caller-array retention
and foreign equal-CID limit rejection. No capacity validator, ACK or limit was
relaxed. Initial logs remain under `property-graph-basic-*-20261003.log`.

Homogeneous Carrier metadata/projection scaffolding, node-emission bound paths,
external Source/Host guarantees, strict inventories and submitted-SHA public
snapshot/fresh packed/required CI acceptance remain open. The earlier aggregate
Core failures are not reclassified as passing by this narrow result. Public
#164 remains unchanged and is not yet ready for adoption.

## Sole current path schema and bound rules

The unreachable `TraversedNodes` and `ShortestPaths` checked output variants,
their node/depth and weighted-shortest schemas, legacy path-profile switch,
lowered emission arms and scalar start/node key inference are removed. The
current path schema keeps full independent identities for both node and edge
arrays. Its two wrappers, five fields and 39 field-name bytes independently
fix the seven-work/two-node preparation envelope; exact and each one-short
boundary remain tested. Authored `emit: nodes` is explicitly refused before a
checked path grant; unsupported shortest typing remains independently covered.

The retired node-emission query-bound rule, selector-clamping calculator,
capacity operand/derivation readers and wire emission arm are removed together.
Current path enumeration still requires its existing resolved search/output
ceilings; a start/node product cannot prove its row bound. MATCH and constructor
entity measures retain their original operand units and owners. Shared
safe-integer, zero and overflow multiplication cases are moved to the existing
common bound calculator, not a second Graph calculator. The removed
node-membership product/clamping law is not claimed supported or preserved.

A mixed bound-reader test still authored old constructor/union bytes. Its
generic ownership/arity portion now uses a current constructor with one node
and three independent edge definitions, all reading the same original VALUES
producer. It positively checks the node's original Rows edge and three distinct
edge-definition Sample occurrences, rather than collapsing repeated uses or
turning the test into an unsupported-operation refusal. Existing nearest and
ranking arity/fallback assertions remain unchanged.

The final surrounding suite passes **139/139 on each JS, Wasm and native**:
`/private/tmp/property-graph-sole-path-regression-{js-pass,wasm,native}-20261003.log`.
Initial runs exposed that historical fixture, a missing constructor alias and
an empty authored selector (which correctly fails before emission checking).
The selector now has an independently authored N/domain/composite typed key;
the exact unsupported-emission diagnostic is asserted. Product validation and
capacity expectations were not weakened. Initial logs remain alongside these
final logs.

Homogeneous metadata/projection and definition-free predicate scaffolding,
external Source definition admission, strict inventories, aggregate Core and
submitted-SHA public snapshot/fresh packed/required CI remain open. The public
PR has not been replaced, pushed or declared GO by these local results.

## Current constructor capacity and profile fixture migration

The clean `49e83ac3a8f3e2e398773fb0c4b62115d43b5ec3` checkpoint passes
Core JS compilation with `--deny-warn`, but its aggregate test result is
**7,363 total / 7,264 passed / 99 failed**. The logs are
`/private/tmp/property-graph-current-core-check-js-49e83ac-20261003.log` and
`/private/tmp/property-graph-current-core-js-49e83ac-20261003.log`.
That aggregate remains red, not replaced by the narrower results below.

Generic capacity fixtures now use current constructors and definition-scoped
MATCH. The same original row owner supplies three independent edge-definition
occurrences; derivation preserves all three inputs, the Edges unit, a bound of
three, exact operand work 15 and one-short rejection at 14. Supplying the same
constructor's Nodes proof instead of Rows still fails `InputUnitMismatch`.
The ordinary preparation path separately retains two node rows and one edge
row, distinct Nodes/Edges proofs and MATCH Rows conversions, in both consumer
orders. Generated claims are re-admitted through the existing capacity owner;
exact total preparation work succeeds and one-short fails.

Counts alone still cannot authenticate capacity claims: zero, the conservative
upper bound and an overclaim all fail without original proof inputs. MATCH E
selects one definition semantically, while the existing static row-count rule
keeps the conservative whole-Graph edge upper bound of three. This fixture
does not equate that upper bound with actual result cardinality. The initial
migration mistakenly asserted a tighter per-definition bound and failed;
no bound rule or validator was changed to satisfy it.

The former derived reach/shortest/node-emission fixture is now a supported
TRAIL positive, for empty and nonempty constructors. It retains independently
fixed definition domains, separate search/output subjects, the original Host
ceiling of seven, swapped-subject rejection and exact/one-short preparation
work. Domain preimages are independently authored in
`/private/tmp/property-graph-capacity-domain-independent-20261003.mjs`;
no product-generated domain is copied into the expected identities.

Repeated producer profile visits retain the current constructor's single
Property Graph law, not retired SGA law grants. Unsupported reach, subgraph and
shortest inputs assert their exact public refusal and source path after their
checked owners have been removed. The current unsupported node-emission
diagnostic remains distinct. The pure retired node-emission product-bound
fixture is withdrawn; its generic arithmetic boundaries were already migrated
to the common bound calculator, not granted to current path enumeration.

The whole capacity-program-step package and touched context/refusal fixtures
pass **102/102 on each JS, Wasm and native**. Final logs are
`/private/tmp/property-graph-quantity-migration-{js-pass,wasm,native}-20261003.log`.
Initial logs retain the old union fixture failure and the conservative-upper-
bound mismatch. The old union fixture's count-versus-admission guarantee has
been positively migrated, not discarded with the unsupported union algorithm.

Homogeneous metadata/projection and definition-free predicate scaffolding,
external Source declaration admission, remaining Core fixture migrations,
strict inventories and submitted-SHA public snapshot/fresh packed/required CI
remain open. No public branch replacement, push, merge or GO is implied.

## Retired homogeneous Graph projection pipeline removal

The checked `NodeRows`/`EdgeRows` projection variants, their Graph obligation
owner, lowering payload arms, semantic port capabilities, count/claim
conversions, execution checks and output envelope are deleted together. The
old tuple key issuer, producer/origin and nullable-label order-completion
fallback are also removed. Current Graph identity stays definition-scoped MATCH
identity; endpoint/label tuples cannot issue independent edge identity.
Events and Vectors keep their existing projection, key and resource paths.

The authored `node_rows`/`edge_rows` spellings refuse directly at the public
pipeline checker, before any checked projection or execution grant exists.
They retain exact malformed-body, unsupported-current-Graph, incomplete-Graph,
wrong-family and source-path diagnostics. Zero preparation budgets still fail.
Old direct checker tests cannot keep removed enum variants executable; their
public refusal cases are now tested at this boundary. Ordinary projection's
exact/one-short work, node and text budgets remain positive Events/Vectors tests,
and current MATCH retains its own typed schema/evidence/resource positives.

Typed MATCH identity still cannot become ordinary JSON scalar ordering or use
nullable business properties/endpoints as key components. Its inherited
publication order and exact original producer remain tested. The obsolete
Graph-only fallback selector is removed rather than left as a second ordering
route. The cross-family test positively retains a Vector projection key and
checks that it has no Graph query producer; it does not require legitimate
Vector evidence to disappear.

The complete carrier-projection, capacity-program-step, pipeline-typing,
pipeline-check-context, relation-evidence, publication-order-policy,
lowering-relation and Graph-preflight packages, plus current formal TRAIL,
selector/construction and managed-provider custody regressions, pass
**972/972 on each JS, Wasm and native** with `--deny-warn`:
`/private/tmp/property-graph-projection-removal-{js-pass,wasm,native}-20261003.log`.
Initial logs retain missed dead capacity arms, unused package imports and a
migration assertion which incorrectly required a legitimate Vector key to be
absent. Those stale references/assertions were corrected; validators were not
weakened. Four generated interfaces contain only intentional retired API
removals, and two package dependencies used solely by that route are removed.

Homogeneous Carrier metadata and definition-free path-predicate scaffolding
still require removal. External Source declaration admission, remaining Core
fixtures, strict inventories, current submitted-SHA snapshot/fresh packed and
required CI remain open. These local results are not public #164 acceptance.

## Retired homogeneous path-predicate execution removal

The definition-free start/edge/node predicate lowering views, homogeneous
binding reader and evaluator phases are removed. Current checked paths already
refuse these unsupported authored predicates; exact typed refusal tests now
cover all three entry points. No fallback schema is synthesized. Definition-
scoped MATCH continues to use the shared expression checker and evaluator.

Supported literal and Relation-backed starts, per-hop static label selection,
path identity, input-owner checks, capacity, cancellation and final cleanup are
retained. Removing the unreachable predicate phases does not introduce work
for cleanup or change the actual path work: their no-predicate transitions
previously charged no work. Initial workspace admission retains the exact
node-selection requirement and cancels its unpublished output on refusal.

Graph typing/lowering and current construction, selector and provider custody
regressions pass **253/253 on each JS, Wasm and native** with `--deny-warn`.
Logs: `/private/tmp/property-graph-predicate-removal-{js-pass,wasm,native}-20261003.log`.
The first JS check exposed the now-unused historical scalar edge-label reader;
it was removed, not waived. Generated API removals are intentional.

Carrier metadata/preflight, unreachable checked predicate/profile fields,
external Source declarations, remaining aggregate fixture migrations and
published-SHA public snapshot/fresh packed/required CI are still pending.

## Sole definition metadata and bounded input preflight

The homogeneous Graph property/label fields, row-role alias owner and public
compatibility getters are deleted. Graph metadata now retains only its admitted
Property Graph definition and full typed identity contract. The endpoint/
property non-key regression stays positive on current MATCH; attaching retired
row aliases is no longer a product operation.

The previous common preflight inspected the retired unknown homogeneous schemas
and missed current definitions altogether. Two independent regressions fail on
that implementation: nested unused node/edge property contracts evade the
depth ceiling, and six added array levels consume zero additional preflight
work. Current preflight visits the domain, every node/edge definition name,
every composite key type, complete and label-specific property schema, static
label and endpoint-definition reference within the same budget. Indexed reads
of the same opaque definition owner avoid copying uncharged arrays. No input
Artifact, Run identity or property value is inserted into the static domain.

The regression independently counts the six array levels twice (complete and
label-exposed schemas), one additional key slot/type as two work units, a label
with empty exposed properties as two units/four text bytes, and a minimal edge
definition plus its endpoint references as seven units/three text bytes.
Exact and one-short shared work/text limits and nested-depth refusal pass.

The complete surrounding regression passes **1,045/1,045 on each JS, Wasm and
native**, with `--deny-warn`. Logs are
`/private/tmp/property-graph-metadata-preflight-{js-full-pass,wasm,native}-20261003.log`.
The before-fix failure log is
`/private/tmp/property-graph-metadata-preflight-before-20261003.log`.
An initial expanded run caught invalid Eq assertions on opaque contracts in
the new indexed-reader test; explicit shape/absence assertions corrected the
test without changing product admission. Generated API changes are the intended
retired getters/alias removal and three bounded indexed definition reads.

Unreachable checked predicate/profile fields, stored scalar-label/tuple reader
scaffolding, external Source declarations and the aggregate migration/strict
inventory/public snapshot/fresh packed/submitted CI remain open. Historical
proof sources are unchanged. No #164 GO or B completion handoff is implied.

### Aggregate checkpoint after metadata migration

Product source `e66b9b5034e6309feee7536770a87a1a038b7e3f` passes the official
public API check across targets and the historical foundation verifier:
`/private/tmp/property-graph-metadata-api-committed-20261003.log` and
`/private/tmp/property-graph-metadata-foundation-20261003.json`.
Fetched `origin/main` remains `bcbf77049fe4991c9b0f1a18541ac7a7952b01ad`, already
an ancestor of the reconstructed branch; no main integration was pending.

Full Core JS completes with **7,361 total / 7,271 passed / 90 failed**, exit 2:
`/private/tmp/property-graph-current-core-js-e66b9b503-20261003.log`.
All 90 failure records are counted; this is not green Core acceptance.

| Remaining fixture boundary | Failures | Required handling |
| --- | ---: | --- |
| Program structural SGA | 4 | Old reach/diff/mean/equality setup; distinguish retired operation semantics from imported ownership before withdrawing any fixture |
| Program traversal and reach-limit fixtures | 3 | Migrate producer/limit custody and atomic admission to current TRAIL, not blanket refusal |
| Program Source policy fixtures | 2 | Admit the exact static Source owner for current definitions and retain selector/search policy provenance |
| Mixed malformed later-step fixture | 1 | Preserve whole-Program refusal and source diagnostic; investigate independently of the retired Graph setup |
| Physical Graph fixtures | 2 | Migrate supported Carrier/Relation task edges; do not modify task splitting or retain unsupported subgraph |
| Local Carrier Graph fixture | 71 | Mixed retired homogeneous constructor/algorithm and generic MATCH/TRAIL/Host guarantees; map every retained guarantee to positive current tests before withdrawal |
| Frontend Graph compile fixture | 7 | Still authors historical constructor metadata; coordinate current definition-scoped public inputs/fixtures with B, not an old fallback |

The former capacity-program-step, pipeline-typing and pipeline-check-context
failure groups are absent at this checkpoint. The 71 Local cases include work,
workspace, quantum, cancellation, cleanup, exact input ownership and repeated
consumer guarantees that cannot be discarded with their old setup. Public
snapshot and submitted required CI remain incomplete; no branch replacement,
push, merge or completed B handoff has occurred.

## Sole keyed storage and reader representation

Stored nodes/edges now require their admitted definition index, canonical
identity-order token and typed composite key. Every edge requires its independent
identity. Optional fields that permitted a homogeneous record and the scalar
edge-label field are deleted. Strict snapshot admission reuses the exact
retained endpoint keys and preserves its canonical ordering and identity checks.
No identity is reconstructed as reference authority.

The endpoint-tuple lookup and scalar-label reader APIs/callbacks are removed
from storage and managed views, along with unused retired storage issues.
Managed property reads always select the exact admitted definition schema;
there is no fallback to a global homogeneous property count. Events/Vectors
retain their existing record view. Its optional Graph-specific view means
different Carrier families, not old/new Graph implementations.

Current positive regressions retain same-endpoint parallel edges, independent
typed keys, key-copy isolation, exact definition labels (not property names),
invalid record/component refusal, unchanged snapshot bytes/CIDs and reference
authority, original owner custody, cancellation and idempotent cleanup.
Logical workspace accounting is unchanged: removing the unused scalar-label
slot branch does not alter any current keyed edge's charge.

The storage/runtime/view/snapshot packages and current construction, selector,
snapshot and managed-provider custody tests pass **72/72 on JS, Wasm and native**
with `--deny-warn`:
`/private/tmp/property-graph-sole-storage-{js-pass,wasm,native}-20261003.log`.
The deleted tuple/scalar reader refusal assertions do not retain obsolete public
APIs as a compatibility layer; current public identity/non-key, wrong-domain,
endpoint, label and malformed snapshot tests remain active.

Remaining checked profile/predicate scaffolding, Source declaration ownership,
aggregate fixture migration, strict inventories and published-SHA public
snapshot/fresh packed/required CI still prevent #164 completion.

## Mandatory checked MATCH scope and path mode

Checked MATCH now requires one admitted definition scope; checked traversal
requires one explicit current path mode. The corresponding lowering getters
return that retained metadata directly rather than an optional old/new profile.
Only genuinely optional label selection and role bindings remain optional.
Consumers use these same checked owners and preserve exact input-reference,
completion-owner, membership, workspace, work and output checks.

Retired homogeneous MATCH/traversal profile obligations, minimum-depth node
emission and simple-path enumeration are removed from the executable obligation
and resolution types. Current operations always select the Property Graph
profile and its count contract. Neither missing definition metadata nor a
missing path mode can select a historical SGA contract. Existing current
lowered bytes and authored path modes are unchanged; the public MoonBit getter
return-type changes are intentional breaking changes in the sole implementation.

Independent literal lowering expectations still pass. Additional assertions
fix the complete current obligation order and compare indexed enumeration with
the same owner, including invalid-index refusal. Typed-key MATCH and all
WALK/TRAIL/ACYCLIC modes retain their positive shared-budget admission tests.
The surrounding checking/lowering/evidence/preflight/storage/runtime packages,
current constructor, managed-provider/selector custody and snapshot regression
pass **1,100/1,100 on each JS, Wasm and native**, with `--deny-warn`:
`/private/tmp/property-graph-mandatory-scope-{js,wasm,native}-20261003.log`.

This checkpoint does not supersede the red aggregate result above. Unreachable
definition-free predicate scaffolding, external Source declaration ownership,
old fixture guarantee migration, strict inventories and published-SHA public
snapshot/fresh packed/required CI remain open. No public branch replacement,
AoA change, merge or completed B handoff has occurred.

## Retired definition-free predicate owners

The old public homogeneous scope/predicate admission APIs and their refusal-only
fixtures are deleted. The scope used by current MATCH is private and must be
created from its retained admitted definition. Current MATCH continues to use
the common expression checker, lowering and evaluator, including structured
reference diagnostics and exact work/text/token limits.

Selectors retain only full typed literal identities or an exact Relation input.
The optional old-profile flag, predicate selector variant/getter and predicate
resolution rule are removed. Traversal hops retain direction and static label
selection, not unreachable predicate owners. Definition-free start/hop predicates
are explicitly refused at the authored field before any executable checked
form is returned. The published diagnostic code/path remains specific; a new
direct-selector regression checks both unsupported operation and invalid limits.

The dead traversal expression consumer variants, lowering branches and source
policy predicate scans are removed. Literal/bound/label provenance and selector
input ownership remain active in source policy. The traversal obligation now
states its implemented duty, `FilterTraversalLabels`, with
`FilterAuthoredLabels` at resolution. Copied/indexed obligation order tests still
agree. Current serialized MATCH/path steps and static identity domains are not
changed by these internal representation/API removals.

Expression-slot collection now charges one visit for a checked traversal step
instead of visiting empty start/hop predicate slots. This is preparation work,
not a reinterpretation of runtime `max_work` or an invented cleanup charge.
An independent positive Relation-selector regression fixes that one-unit cost;
MATCH still owns its common expression slot and costs two units. Exact work and
one-short refusal remain tested. The initial expanded JS run failed one old
six-unit empty-slot expectation, retained in
`/private/tmp/property-graph-selector-retirement-js-20261003.log`; it was corrected
to the actual one-step traversal rather than relaxing its work-limit test.

The surrounding regression passes **1,099/1,099 on JS, Wasm and native** with
`--deny-warn`:
`/private/tmp/property-graph-selector-retirement-{js-pass,wasm,native}-20261003.log`.
Three tests of the removed scope APIs were withdrawn; two current selector/slot
regressions were added. Existing positive MATCH, path capacity/stop/cleanup,
selector ownership and snapshot regressions remain active.

The earlier aggregate Core result remains red until the documented legacy
fixture migrations and external Source-definition ownership are finished.
Strict inventories and published-SHA snapshot/fresh packed/required CI are still
pending. No public branch replacement, AoA write, merge or completed B handoff
is implied by this narrower checkpoint.

## Original SourceView definition custody (2026-10-03)

SourceView registration previously reduced a resolved input to `CarrierInput`.
That lost its original declaration and selected Catalog owner; a current Graph
constructor correctly refused to invent producer provenance from the row schema.
`SourceViewInput` now retains the original Stage, declared input name, exact
declaration Cursor and existing opaque `SourceViewCarrier`. The common checker
requires the original steps and declaration; SourceView attachment requires
the same Stage, declaration and selected Catalog owner. Same-shaped foreign
Catalog inputs, foreign Programs and foreign declaration Cursors are refused.
The declaration table scan is charged before lookup, and domain issuance uses
the retained Cursor rather than repeatedly reopening uncharged input tables.

The domain projection keeps unbound Source syntax, the static Carrier schema
body CID and the selected SourceView member body CID. It excludes the DATA
alias, Program ID, enclosing Environment bundle, bound Artifact, actual
Parameter values and Run/Invocation identity. It follows the existing retained
producer chain through transformations/imports. No second request-admission,
authorization, acquisition or execution owner is introduced. Bare Carrier
registrations still refuse `MissingPropertyProducerDefinition`.

The two new formal Program regressions exercise Source → constructor → MATCH,
original publication-source policy, alias-invariant domain and changed producer
definition. Restoring the old registration/attachment connection makes **0/2**
pass: `/private/tmp/property-graph-source-owner-ablation-20261003.log`. This is
a connection ablation, not a claim that the complete old SHA was rebuilt.

Independent canonical preimage for the fixed Source fixture:

```json
{"constructor":{"edges":[],"nodes":[{"input_occurrence":0,"key":["id"],"labels":[{"name":"Node","properties":{"columns":[{"from":"id","to":"id"}],"mode":"columns"}}],"name":"N"}],"version":"actql-property-graph-constructor/0.1"},"producer_definitions":[{"source_view":{"carrier_schema":"sha256:dfdd25f9d1e53aa575aa8b5ad61d1247761d11cc67859c8d5c4e811d99c293d8","declaration":{"connector":"crm/main","request":{"id":1,"tenant":null},"resource":"r"},"selected_view":"sha256:5d7ab8ccf736b60aa69eda9669f3cd77b7d1a234377375fefe9a8105ff566a11"}}],"version":"actql-property-graph-definition/0.1"}
```

Node's SHA-256 of those UTF-8 bytes independently gives
`sha256:4e99c7ad4487c68499e66d81ddef818b42053f8b6f439ca65dcfcd975a850cc3`.
The schema and selected member hashes were calculated from the authored input
fixture in `program_check/remote_wbtest.mbt`, not compiler output. An initial
oracle used the SourceView's self-declared contract CID instead of the full
member body CID; the mismatch exposed that distinction and the corrected
preimage above independently establishes the literal expectation.

The surrounding owner/admission/Graph regression is **1,369/1,369 on JS,
Wasm and native** with `--deny-warn`. Logs:
`/private/tmp/property-graph-source-owner-{js,wasm,native}-20261003.log`.
Latest main is `bcbf77049fe4991c9b0f1a18541ac7a7952b01ad`, already an ancestor.
The aggregate Core/spec migration, fresh public snapshot acceptance and
published-SHA required CI remain unfinished; this is not B's completed handoff.

## Source-backed MATCH policy migration (2026-10-03)

`graph_match_policy_wbtest.mbt` no longer constructs a tuple Graph. All seven
original policy cases remain positive current Graph cases: repeated explicit
identities, a field-only predicate, a predicate with a literal, edge MATCH,
empty label selection, repeated static labels and a literal edge predicate.
Node and edge definitions share the retained SourceView producer but keep
independent key roles and ordered constructor occurrences. Property `id` is
projected separately from the complete typed element identity; a numeric
endpoint is not passed off as the new identity.

Each case keeps the original Source count, unknown-value provenance expectation,
exact checked MATCH owner, original input occurrence and the admission/resource
execution checks (including the three resource scopes and original 1,000-row
ceiling). None was replaced with an unsupported-input expectation.

The repeated typed node selector uses independently derived domain
`sha256:e95f67084a112ecd81cf96752d7dcffc731922c81ee7946fcf8ab2ef11a5b4a5`.
Its preimage uses the Source projection above twice, a node N with key `[id]`
and Node/all_columns, and an edge E with independent key `[id]`, N/[id] source,
N/[extra] target and R/all_columns. Ordered input occurrences are N=0, E=1.
Node's canonical SHA-256 calculation was performed before the product test.

The focused policy regression comprises ten tests on each target. Acceptance
is rerun after formatting has finished at the committed source; the first
preflight overlapped formatting's lock and is not used as the final run.
Public API consistency and frozen historical foundation verification passed
for the preceding Source owner commit. Full Core/spec, fresh packed public
snapshot and pushed-SHA CI are still required for #164 as a whole.

## Constructor compatibility entry removal (2026-10-03)

The public `local_bridge.start_rows_to_graph` wrapper is deleted rather than
kept as an alias. All live source references now call
`start_rows_to_property_graph`. The same existing `RowsToGraphExecution`
bounded session, poll, stop and cleanup functions remain the sole current
constructor/reload custody owner; their generic names do not select a retired
representation. No replacement session or execution owner was added.

The current constructor, provider, selector and snapshot regressions pass
**36/36 on JS, Wasm and native**, with `--deny-warn`:
`/private/tmp/property-graph-constructor-alias-{js,wasm,native}-20261003.log`.
The legacy mixed integration file has only mechanically renamed entry calls
in this unit; its remaining tuple fixtures are not claimed migrated or green.
The old name occurs only in the frozen September production-route evidence
and a negative resource-inventory test that deliberately selects an invalid
marker. Neither is a current callable product adapter.

## Source-backed TRAIL and retired duplicate fixtures (2026-10-03)

The former path-policy fixture now admits the current Source-backed constructor
and positive TRAIL cases: an independent typed literal identity, a scoped MATCH
Relation selector from N, and a selector from M backed by the second original
Source. Finite-depth and authored static-label hop cases retain the exact
checked traversal owner, primary/selector input occurrences, original one/two
Source policy and independent 1,000-path / 1,000-output limits. Bound/label and
literal identity provenance remains unknown; removed definition-free predicates
do not lend these operations a false provenance proof. Unsupported shortest
paths and predicate hops remain explicit refusals, not hidden legacy execution.

The old traversal fixture's positive Unit-limit ownership guarantees are
retained in `property_trail_resources_wbtest.mbt`, strengthened with invalid
indices, no fabricated proofs, converted/original claim CID distinction and
unchanged minimum/candidate identity. A later invalid imported consumer still
rejects the whole Program and exposes no partially checked producer.
`traversal_limit_identity_wbtest.mbt` already preserves the old reach conversion
fixture's independent Unit namespaces, exact work/bytes/nodes, one-short and
foreign-occurrence refusal under the implemented TRAIL contract. Only the
retired reach CID and minimum-depth/node-emission semantics are withdrawn.
The old duplicate traversal/reach executable tests are removed; their source
and historical identities remain available in Git. The existing capacity
fixture helper is retained because current resource owners use it.

The surrounding policy/selector/Unit-limit regression passes **18/18 on each
JS, Wasm and native** with `--deny-warn`:
`/private/tmp/property-graph-source-trail-{js,wasm,native}-20261003.log`.
The early narrow run exposed an authored hop field typo (`types` instead of
`edge_types`) and an assumption about policy traversal order; the final test
selects the unique exact operation occurrence, not an arbitrary list index.
This is not the unfinished whole-Core or published-SHA packed/CI acceptance.

## Current Host composition and interruptible identity order (2026-10-03)

The current keyed constructor → MATCH → Relation chain retains positive Host
coverage for filter (including an empty result), edge projection, select,
derive, ordered TAKE, sort and both row/unique assertions. The same installed
modules and dispatch owner execute seven physical tasks; no retired normalization
task is inserted. Two downstream consumers share the original material, and
closing one does not revoke the other. Normal completion and cancellation
return execution/retention reservations and held bytes to zero. The DAG checks
retain exact ordered input occurrences and the adjusted exact/one-short task
ceiling; the adjustment removes a genuinely absent legacy task, not a capacity
check. These positives replace the applicable old Host composition obligations,
not support for retired structural Graph operators.

Migrating the old long-text cancellation obligation exposed a real regression:
MATCH and TRAIL scanned a whole canonical identity key in one charged control
transition. Their existing bounded sessions now retain the UTF-16 comparison
position and advance one code unit per transition. Ordering, typed identities,
storage ownership and output bytes are unchanged. No extra stop/session owner
or unreported work is introduced. The comparison cursor is cleared by cleanup.
Independent UTF-16 cases include prefix, equality, supplementary/BMP ordering
and a long common prefix. The current integration test verifies yield, cancel,
idempotent cleanup, live original input and independently authored complete
MATCH/TRAIL rows after a fresh session finishes.

The regression fails when the charged incremental comparisons are replaced
by an uninterruptible whole-key loop: MATCH fails at `long node comparison
must yield`, and the separate TRAIL ablation fails at `long start comparison
must yield`. Evidence:
`/private/tmp/property-graph-long-match-ablation-20261003.log` and
`/private/tmp/property-graph-long-trail-ablation-20261003.log`. Both ablations
were restored before the final formatted verification. An early TRAIL fixture
used an invalid zero upper depth; the final fixture uses the supported finite
range and explicitly checks zero/one-hop self-loop rows.

The combined current construction/selector/snapshot/provider, Source policy,
Host composition and physical-DAG regression passes **92/92 on each JS, Wasm
and native** with `--deny-warn`:
`/private/tmp/property-graph-host-comparison-{js,wasm,native}-20261003.log`.
The legacy mixed integration fixtures are still to be retired after their
remaining applicable guarantees are mapped. Aggregate Core/spec, fresh public
snapshot and submitted-SHA CI remain open; these narrow successes do not make
the currently published #164 checkpoint adoptable.

## Mixed tuple integration fixture retirement (2026-10-03)

`local_carrier_graph_wbtest.mbt` is removed from the executable suite. Only its
seven shared, representation-neutral helpers are retained in
`property_graph_fixture_helpers_wbtest.mbt`; the Program factory now delegates
exclusively to the current keyed constructor/MATCH fixture. The query fixture
no longer enables the retired profile, selects old apply stages, or issues
reach/shortest/predicate/emission proof material. The unused legacy traversal
proof helper is removed. The old tests and helper implementations remain in Git.

The retirement is not a blanket conversion of successes to refusals:

| Former integration obligation | Current positive evidence / explicit limit |
| --- | --- |
| Typed/literal predicates, identity selection, canonical sorting and duplicate removal | Current node/edge MATCH construction tests; typed current empty MATCH; current path selector deduplication |
| Missing selected identity fails before publication | New same-domain composite-key MATCH membership test, stored and viewed reads; exact `MissingMatchNodeIdentity` and retained original input |
| Long-key comparisons yield and can stop | Current text-key MATCH/TRAIL regression and the preceding charged comparison repair |
| Exact work/workspace, one-short refusal, every private stop point | Current node/edge MATCH and constructor tests; stored/viewed TRAIL selector work/workspace tests |
| Relation selector exact owner, empty selector, repeated use and foreign owner | Current selector custody tests; checking/lowering revalidate typed identity/nullability; no legacy scalar selector is admitted |
| Path arrays reject oversized output without allocating all items | New typed output ceiling test: early minimum failure has zero item attempts; two authored two-hop TRAIL rows require exactly 150 nodes and 149 fails atomically with the existing capture owner |
| Start-major/depth order, duplicate starts, physical edge permutations and direction | New independently authored current TRAIL test covers in/out/both, two reversed/duplicated starts, both edge orders, stored/viewed reads and resume quanta 1/7/1024 |
| Independent parallel-edge identity, path-mode eligibility and zero-hop output | Current parallel self-loop WALK/TRAIL/ACYCLIC tests and long-text zero/one-hop TRAIL rows; no endpoint-tuple collapse |
| Graph retention across consumers, cancellation, final reclaim | Current managed output lifecycle and provider custody tests; current Host two-consumer composition and cancellation return all Site reservations/held bytes to zero |
| Generic Relation filter/select/derive/take/sort/assertion composition and physical input/task ceilings | Current Host/DAG tests; ordinary Relation owners remain in use |
| Minimum-depth node emission, definition-free hop/start predicates, graft/union/mean/subtraction | Unsupported consumer obligations are explicitly withdrawn, not migrated to a false current algorithm/count proof; checked-boundary refusal tests remain |

The exact output count above is an independent calculation from the authored
typed identities: each row has root 1 + hop count 1 + two 11-node endpoint
identities + a 34-node node array + a 17-node edge array = 75 nodes. It is
different from the retired scalar/endpoint-tuple fixture's limit. Output
admission counts both rows, so 150 is exact; no existing capacity rule is relaxed.

After retirement, the related current-owner/policy/Host/DAG suite passes
**95/95 on each JS, Wasm and native** with `--deny-warn`:
`/private/tmp/property-graph-retired-integration-{js,wasm,native}-20261003.log`.
The strict resource route inventory still needs its explicit current-source
registration; frozen historical references must not be overwritten. Aggregate
Core/spec, fresh public snapshot and pushed-SHA CI remain acceptance tasks.
