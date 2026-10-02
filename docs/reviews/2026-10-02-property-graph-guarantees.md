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
| Tuple constructor and endpoint-derived edge identity | Retired representation | `query_integration/property_graph_provider_profile_wbtest.mbt` rejects the old constructor; current keyed constructor retains independently keyed parallel edges | Audit remaining product symbols, readers and provider branches; negative tests alone do not remove them |
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
