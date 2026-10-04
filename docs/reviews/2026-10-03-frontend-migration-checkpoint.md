# Frontend migration: independent source checkpoint

This ledger separates implemented source, public execution evidence and remaining
migration work. The integrated main baseline is
`11fde3441fdcf0766c583c5173ccf8e788a09751`, including the JSON composition in
#246. Results below retain their own verified source/package identities; they
are not blanket execution evidence for this baseline or the full migration.

The earlier Graph development integration combined B
`b19ed2cfb0bdce93832d47a8c3a7a8da95266c14` and C
`51376bca11d57b775aa22d42453176f8ad1f681b`. Fresh packed Local/HTTP acceptance
passed at clean `a6675aa5945389e66aa15978c9ed0ae66cbe69a1`, as recorded in
[public acceptance](2026-10-03-property-graph-public-acceptance.md).
That result does not establish all Graph consumers or completion of the migration.
Earlier checkpoints below retain their original source and package identities.

## Current public composition checkpoint (2026-10-04)

The adopted main is `3a7be90e681326fef04cf2c28fe11dbfee729e2b`, including
#273, A #292, selected-fragment capacity, incremental Session CI, traversal
nodes, durable Site cancellation, formal resident cleanup and installed
connector manifests, plus B #303's Graph row source lowering. D's latest
ordinary integration is `b5bf88385400f8c0b711f4c01a79bda2da77714e`.
The previous integration `4f323850097280978e5765a43f33ce650cde8a14`
adopted main `d5f0802c93e2863b092aa8f1a9e9a7cc97b12c5b`;
the accepted two-Source packages
below include main through `5caeccc79dacc758afa5d87c2cee6be024e32565` via
`3bd65feb11770cd45819ef34dcd08fba2db03a3f`. This section
supersedes status statements in the historical
table below without rewriting their evidence. The sole operation-family
classification remains `2026-09-19-sga-veca-tea-local-coverage.json`.

| Composition boundary | Current state and fixed evidence | Next acceptance or excluded scope |
|---|---|---|
| Two Sources → JOIN → multi-row INFER → KEEP/filter → approved Effect, JSON/text | Publicly accepted. #273 source `8a5195451195b7e4566b19bf7ba9fb5772b8f2d1`; [automatic CI 37163835916](https://github.com/actql/actql/actions/runs/37163835916) succeeded, including fresh-packed Local/HTTPS from tested merge `e90fea951f63cf0586f095c47521e29d18a4bf73`. Approval/restart/replay and the reused failure/cleanup cases passed. | This proves the authored full text and JSON fixture, not all syntax or Graph combinations. |
| Pure two DuckDB Sources → selected Native/Broad → JOIN | A #292 `de96f1c5cd28154deea182a9a84743a016db81f0` is adopted via main merge `b48301401592c2e9f00a2ea9f1f82a283cb5a2a4`. The earlier JSON-only acceptance at `1f17eb56c88d0b63b99cf24b1ce4f6ad43355752` passed 8 normal and 8 retained cases. Draft #313 extends the existing harness with authored text: fresh-packed `27dc783a4c1b8dca34c496d21362c42866250513` passed 12 Local/HTTPS normal cases, 12 retained-Run cases and 12 existing recovery/failure scenarios. Independent Native/Broad JSON/text rows, types and order agree; binding/generation refusal, second acquisition failure, cancellation and cleanup retry use A's existing fixtures/owner. | Automatic CI at submitted `ee892e1155da1bbd287e8ffabc2407a8f8029a57` has passed the packed consumer from clean tested merge `d6176313d4a21c08497241fd8f3df5453cd72d00`; its retained public-query summary is complete/passed. Full CI was still running when inspected. This fixed evidence precedes the #303 main integration; formal active temporary-hold inventory remains a separate requirement. |
| Graph → node_rows/edge_rows → guaranteed Relation columns → physical Store/reload → Named Result | Publicly accepted through C #275 (`fa615ff1d7b199b476c9673c613dcbcfb40d576d`), included in main. Selected clean packed acceptance is recorded at `9bc97334b1ec6afddef1b319fc48ac52f8ec7879`. | Nullable Required properties and original scalar key types remain supported; Conditional refinement is not inferred from samples. |
| Graph rows → multi-row INFER → approved Effect | Source-free checked DAG compilation and original Model/capture/Effect owners are connected at `325eb381313a2d688043acb38d4e09b5ea61f61f`. Producer export/import provenance is connected at `d8a68550ead7fe326cb2d7922d8cec7a84b43e79`. Its fresh-packed Local node case reaches two Model calls `[100,200]`, zero Source calls and zero writes, then fails dependency preservation before approval. Typed diagnostic: `MissingDependency`, because the Result Policy CID has no retained original body. | A owns the common Result Policy binding, early refusal and durable restoration; D owns adoption and public composite acceptance. HTTPS, edge rows, approval and restart at this new source are not yet accepted. The earlier `ClientProgramUnsupported` and `NotSourceFree` reproductions remain historical evidence, not the current failure. |
| Graph rows through text → ordinary Relation → Named Result | B #303's `compile_query_script` Graph→Relation transition is now adopted from main; D has not implemented another transition. B's retained packed predecessor evidence covers five positives and five pre-admission refusals on Local/HTTP, with exact rows and descriptions. | This is an adopted implementation with fixed predecessor acceptance, not fresh full-composition acceptance of D's new integration. Graph rows text remains outside the first completion unit; D continues CTE/predicate/assert/Effect composition. See `2026-10-04-graph-row-source-inputs.md` for identities and restrictions. |
| Conditional-property refinement; NEAREST/Cloud expansion | Outside this completion unit. No presence evidence is inferred from samples or a nullable guard. | Separate subsequent units and their existing owners; no fallback or duplicate execution mechanism. |

The new Graph fixtures are
`scripts/fixtures/graph-node-infer-effect.program.template.json` and
`graph-edge-infer-effect.program.template.json`. Each is one complete Program;
the consumer binds only the published MappingRef. Expected rows, types, order,
typed identities and calls are authored in `graph-infer-effect-input.mjs`.
Both expect Model inputs `[100,200]`, Source sessions `[0,0,0,0]`, writes
`[0,0,1,1]`, and the existing capture-waiting/approval-committed restart points.
The constructor identity is independently derived from its normative authored
preimage, not observed Graph output.

### Source-free Result Data Policy handoff to A

The public reproduction is the complete node fixture above, submitted with only
its published MappingRef bound. At `d8a68550ead7fe326cb2d7922d8cec7a84b43e79`,
normal fresh-packed execution with
`node scripts/test-packed-salesforce-source.mjs --composed-graph` fails after
Model calls and before Effect preview/approval. An explicitly instrumented
diagnostic identifies the existing dependency inventory's `MissingDependency`;
the diagnostic overlay is not pristine packed acceptance. The fixture's Model
`data_handling.contract_cid` is `sha256:` followed by 64 `a` characters.
It is an egress contract, not a Result Data Policy body.

The connection points are
`client_compiled_run_infer_observation_policy` in `client_compiled_run.mbt`,
`sourceFreeInferEffectPublicationPlan` in `local-values-plan.mjs`, and the
existing `prepareLocalEffectDependencyInventory` call in `effect-input-export.mjs`.
The source-free observation currently borrows that Model CID. The checked
inventory correctly refuses its absent Data Policy original. The temporary
Model-CID choice in `eb0bf193d47997b4eddaf4291bb6072c8a22ded1` and its test
are not the agreed Result Policy contract and must be replaced by A's connection.

The Source-backed reference is `acquiredMultiEffectPublicationPlan`: the common
owner supplies its effective policy CID and
`clientProgramEffectPublicationPolicyBodies` supplies retained originals. The
installed source-free profile currently supplies an opaque
`policyCid('local-result-data')`, not this original-body connection. The earlier
source-free INFER handoff `d9501d023cadff6e345533c4b267d2d880039814` carries
Model fragment contracts; it does not resolve this Result Policy boundary.

The agreed split is A for the common preparation/Run/capture connection and D
for public Local/HTTPS acceptance. Reuse an existing Result Policy setting and
original-body source if available. Otherwise bind an explicit Host Policy and
its original through the existing owner. No unused Source policy, invented
original, weakened dependency check or Model contract substitution is permitted.
Source-derived constraints must survive any Host binding.

| Acceptance condition after A's connection | Independent observation required |
|---|---|
| Policy unconfigured, original missing or CID/body mismatch | Preparation refuses before Run execution, Model calls and Effect writes; Model calls 0 and writes 0. |
| Valid, Result-applicable Policy distinct from Model egress | Full authored Program returns the fixed fixture rows, types and order; Model inputs `[100,200]`, Source calls 0, writes 0 before approval and 1 after it. |
| Capture-waiting and approval-committed restart | Stop both dedicated processes; restore the same request/Run with the original Policy binding and required bodies as dependencies, even if current Host settings change. No saved Source/Model replay, redundant approval or confirmed Effect replay. |
| Source-backed control | Original effective Source constraints and bodies remain enforced; Host Policy cannot downgrade them. |

The successful pure-Source evidence is retained in
`public-query-evidence-1LEidN/two-source-acceptance.json`. Failed normal Graph
evidence is retained in `actql-packed-salesforce-Zfx0ss`; typed-cause-only
diagnostic evidence is in `actql-packed-salesforce-S3VT6J` and
`actql-packed-salesforce-kuWp6x`. These are local evidence directories under
the workspace's `.codex-scratch`, not portable repository fixtures. Reproduction
uses the checked-in Programs, expectations and existing packed consumer.

Resource acceptance distinguishes original temporary task/consumer, Graph,
Source and Model holdings from durable Named Result retention. Logical close,
physical cleanup and reservation return are separate observations. A false
cleanup retains original custody and required reservation; only confirmed
last-holder cleanup permits return. Named Results remain rereadable without
Source/Model replay or confirmed Effect duplication. `wait(): succeeded` and
`client.close()` alone establish no release claim. Final Run deletion and
physical deletion of another consumer's data are outside this unit.
The Graph attempt confirmed temporary physical cleanup and zero held bytes and
reservations. The ledger's `holdings` counter records cumulative created holds
(9 in this attempt), not active remaining holds; it cannot establish an active
hold count of zero. Named Result retention and an explicit active-hold inventory
remain separate acceptance observations, and are not claimed complete here.

### Independent CI fixture corrections

At submitted Graph HEAD `cfd8ff3dc3982fc32d7a1f70e286d3aed409973f`,
[automatic PR CI 37170021748](https://github.com/actql/actql/actions/runs/37170021748)
passed retained-history preflight and all three Core targets. Salesforce's
negative fixture still expected the newly supported source-free DAG to be
unsupported; distribution acquisition-failure mocks omitted their explicit
one-source count; Host's command inventory omitted the registered Graph fixture.
These three independent fixture issues are corrected at
`5a0ecadbf5aab688bdd1f6be9450ea490b5dc06d`. The replacement public HTTP negative
uses a genuinely checked but unsupported acquisition shape and verifies refusal
before acceptance with zero journal records. After ordinary main merge
`4f323850097280978e5765a43f33ce650cde8a14`, the pinned JS runtime build and all five
affected Node cases passed, as did complete retained-history validation.

The packed Graph failure remains distinct: it reaches `needs_reconciliation`
instead of `waiting_checkpoint` before approval. No Graph acceptance or Result
Policy repair is claimed from the fixture corrections or main integration.

Automatic CI [37172121681](https://github.com/actql/actql/actions/runs/37172121681)
completed for submitted `add687a865b615be34989638b015905b457540b3`, tested
merge `c46e9921e7c6d8e4ccff2f4c7f4fc751e3d6b2a9`. The three corrected
fixture jobs, all Core targets and retained-history/pipeline evidence passed.
The packed Graph approval assertion still failed (`needs_reconciliation`,
expected `waiting_checkpoint`, `effect-run.mjs:243`); `client` and `check`
aggregates failed consequently. No old run was retried.

The new #303 main integration has no conflicts. The authored Graph fixture
checks passed (4 cases), the public-query fixture checks passed (2 cases),
complete retained-history validation passed, and `git diff --check` passed.
These focused checks do not constitute fresh packed Graph acceptance or repair
the Result Policy/active-holding observation dependencies. No local full Core,
packed or performance campaign was added.

The newer automatic run
[37174699329](https://github.com/actql/actql/actions/runs/37174699329) completed
for submitted `f90ba1b2f3f875becc2e58fe0cc24d30f88b2957`, tested merge
`ffd38b33156c8772adb920a38153a860a78e84a4` against main
`3a7be90e681326fef04cf2c28fe11dbfee729e2b`. Its packed Graph case stops at
the same first public state assertion: `needs_reconciliation`, expected
`waiting_checkpoint`, external `effect-run.mjs:243`. Only that packed job and
its downstream `client`/`check` aggregates failed. The log does not expose a
typed cause; the earlier diagnostic-only `MissingDependency` reproduction
remains separate evidence. Graph approval and restart are still incomplete.

The independent two-Source JSON/text comparison's current automatic run
[37174701220](https://github.com/actql/actql/actions/runs/37174701220) passed all
required checks for `f4d92d89dc9e55caeb6cc5f0c94fae98efcb91c8`. The producer
and packed consumer tested merge `f8babc08f177595c92d9e15450d9eda42cfe84e3`
against the same `3a7be90` main. Its new packed log confirms all 12 normal
Local/HTTPS cases, including four Native/Broad text cases, retained restoration,
second-input failure, cancellation and cleanup retry. The
[public-query artifact](https://github.com/actql/actql/actions/runs/37174701220/artifacts/11293870226)
records a clean source, complete/passed status and all 40 commands with expected
verification status. This is distinct from old-SHA successes and does not close
the formal active-temporary-hold inventory gap.

### Prepared Graph assertion counterexamples

Two complete, independently authored node-row JSON Programs extend the existing
assertion phase, without adding a job or a separate execution path:

- `graph-node-infer-effect-duplicate-key.program.template.json` constructs
  distinct Graph keys `['a',1]` and `['b',1]`, then projects scalar INFER keys
  `[1,1]`. Graph identity uniqueness does not establish uniqueness of that
  projection. The existing explicit `assert_rows.unique_by: ['id']` must fail
  before Model execution; no row is implicitly removed.
- `graph-node-infer-effect-null-property.program.template.json` preserves the
  positive Graph, non-NULL Graph/Model keys and guaranteed nullable `note`
  column. An additional explicit `unique_by: ['note']` precedes the existing
  id assertion/INFER and must refuse its NULL. This tests a nullable-property
  assertion, not a NULL Graph identity or a NULL Model key.

The consumer binds only the actual installation's MappingRef. Each negative
case requires failed execution, no checkpoints, zero Model calls, zero Source
acquisition and zero writes. Positive full composition must complete first so
that missing Result Policy cannot count as assertion acceptance. The existing
normal node case runs these two refusals on Local/HTTPS; the edge case and
recovery/failure matrix are not multiplied. Both public refusals remain unverified
until A's Policy connection permits the positive composition. Focused authored
fixture checks pass 8/8 (`run-uXQ3Za`); the outer harness and its generated
external driver pass syntax checks. This does not establish runtime refusal.

The prepared Graph acceptance also omits installed Source profiles entirely,
including the environment fallback. Existing source-backed cases retain their
two-profile installation. This uses the existing no-profile Host entry, rather
than permitting an empty plural-profile setting (which that owner rejects).
The captured submission records the actual configured Source profile count,
and Graph acceptance requires zero. This prevents a later Policy connection
from passing the source-free case by borrowing an unused installed Source's
Policy. Positive rows, Model contract/input counts and approval/restart
expectations are unchanged. Removing installed Source context can change Run
identity; only the same request's resubmission/recovery identity is required.
No public Graph execution with this prepared setting is claimed yet.
The read-only `installedSourcePaths` boundary check confirms omitted profiles
select none, the existing two-profile setting is retained, and an explicit
empty plural setting is still rejected. Outer/generated driver syntax and
diff checks pass; no runtime build or extra packed campaign was added.

### Prepared current-main integration and unchanged NO-GO

Normal merge `d8dd3a918294c8f719f1d18e9272bc54f9fca0de` has ordered parents
`1cab6d28d377080d722974b51dc508b2d26a516c` and main
`779ef222a165c644ffb9b97090b4d060dc7feeab`. It adopts the latest diagnostic,
Graph frontend and GitHub connector changes without conflicts. Selected Graph
fixture and Client scheduling checks pass 18/18 (`run-71PAHm`).

The first actual complete-history check rejects this merge's undeclared
`package.json` overlap. The separate declaration introduced at
`e5e250828446a6e8b683cac5676e8d436af9d283` binds the exact parent bytes/modes,
result bytes and all 41 ancestral package source groups. The same complete
history validator then succeeds. Existing declarations, supplements and their
introduction histories are preserved; neither the validator nor gates changed.
This closes that new integration obligation, separately from product acceptance.

Public #304 remains Draft at `f90ba1b2f3f875becc2e58fe0cc24d30f88b2957`,
with its recorded packed Graph failure. The prepared integration is not pushed
solely to repeat the known unresolved Policy failure. No publicly available A
Result Policy/body implementation has been verified for adoption. The temporary
Model egress CID selection is still present and must be replaced by A's formal
common connection. Node/edge Local/HTTPS approval, execution and both-process
restoration remain unaccepted. Independent expected states, rows, call counts
and assertion counterexamples are unchanged; no Policy body is fabricated.

### Resumed Draft and accepted optional-Effect integration

#304 was closed without merge and reopened as Draft, base main, under the
explicit continuation instruction. Its public source remains
`f90ba1b2f3f875becc2e58fe0cc24d30f88b2957`. A's Result Policy connection is
still pending; #335's accepted Source-backed optional-Effect pairs do not
establish Graph acceptance. Keep the same PR's counterexamples and history.

Normal merge `1edb1560ceed004f275adb743e4efc80ce00ca71` has ordered parents
`89536be07f5bc3e290890e644d575dc913ac55fd` and main
`e51097122b949849ef2bb895dfb305bad1c3a248`. The `package.json` and shared
packed driver conflicts retain Graph cases, accepted optional-Effect cases and
the SDK/Host read-progress registrations. Focused Graph flags exclude unrelated
optional-Effect pairs. Source-free installation, original expectations, custody
diagnostics and retained Named Result observations are preserved.

At `35d6895c07710884ce812475ea077f230d96d000`, selected Graph/CI/acquisition
custody checks pass 33/33 (`run-vmGxMi`), and both outer and generated driver
syntax checks pass. Complete actual-history validation succeeds with 102
declarations and 2 supplements; the new exact-merge declaration binds all 44
ancestral package source groups. No old record or validator was changed.
The initial bounded wrapper could not inspect its owned process group inside
the sandbox; the approved retry ran the same selected checks successfully.

These local conflict resolutions are not yet public, so GitHub can still report
conflicts on the old public HEAD. Combine them with A's fixed public Policy
adoption before pushing. No new packed Graph execution or CI success is claimed;
the original node/edge Local/HTTPS approval and same-Run restoration requirements
remain unchanged. The final integration target is main through normal merge,
never an A dependency branch; no merge action is requested.

## Historical pure two-Source JSON/text composition checkpoint (2026-10-04)

The packed acceptance adopted main
`7dee31c1cc61b081f0feb12761b2bd5c2f41c12c`, including A #292 Native/Broad
acquisition and the formal cancellation/cleanup foundation. Fresh packs from
clean `27dc783a4c1b8dca34c496d21362c42866250513` passed
`node scripts/test-packed-public-query.mjs --two-source-only` through external
Local and authenticated HTTPS installations with no runtime MoonBit toolchain.
This is fixed-SHA local packed evidence; automatic PR CI is a separate check.

The previous ordinary integration is
`5962250507a903413654c0744bfb1176fd2b410c`, adopting main
`d5f0802c93e2863b092aa8f1a9e9a7cc97b12c5b` and its installed connector
manifests. Both additions in `scripts/test-packed-public-query.mjs` survive the
merge; existing foundation records are preserved. Pinned JS runtime build,
the two real capture boundary cases and complete retained-history validation
passed at this integration. It is not a new local packed campaign.

Automatic PR CI [37172424649](https://github.com/actql/actql/actions/runs/37172424649)
at submitted `ee892e1155da1bbd287e8ffabc2407a8f8029a57` passed the packed,
distribution and client aggregate jobs. Fresh packages bind clean tested merge
`d6176313d4a21c08497241fd8f3df5453cd72d00` against main
`d5f0802c93e2863b092aa8f1a9e9a7cc97b12c5b`. The packed log confirms all
12 normal cases, retained recovery and the existing second-input failure,
cancellation and cleanup-retry cases. Retained public-query artifact
`11291694091` has a complete passed summary and expected verification status
for all 40 command records. Full CI was still running when inspected; it is
not yet recorded as fully successful.

The latest ordinary integration is
`586cf84261a1ce86e142b9da9b327b138477ccca`, adopting main
`3a7be90e681326fef04cf2c28fe11dbfee729e2b` and B #303's Graph row source
lowering. The packed consumer retains both the pure JSON/text cases and the
new Graph row case registration. There were no conflicts or new foundation
declaration requirements; all existing records and supplements are preserved.
The public-query/frontend fixture checks passed (10 cases), complete
retained-history validation passed, and `git diff --check` passed. This is
focused integration verification, not another local packed campaign or a
success claim for the new HEAD's automatic CI.

[Earlier automatic PR CI 37170657090](https://github.com/actql/actql/actions/runs/37170657090)
at `e210c920e6b05b21bb6f9216933717ea635dd0c2` found two capture expectation
failures: the test compared post-predicate logical captures with unfiltered
physical database input. Fix `07f717e0f501598af6df5a81b772e9013987b41d`
separately authors each captured relation's expected rows, retaining NULL and
duplicates and excluding the negative keys by the specified predicate. The
public packed JOIN expected rows and product behavior are unchanged.

The submitted text is retained verbatim in
`adapters/host-node/fixtures/two-source/two-source-join.aql`. Both independent
JSON and text inputs specify Source predicates `id >= 0`, the same id equality
JOIN, `max_output_rows`/`MAX_OUTPUT_ROWS` 100, result column order
`id,left_amount,right_amount` and ascending order on those fields. Existing
expected rows/types/nullability remain unchanged. Matching negative Source keys
are deliberately present in both inputs' databases so losing the Source
predicates changes the joined output; duplicate rows and NULL amounts are preserved.
This does not introduce deduplication, a different lowerer or a new executor.

The existing harness now covers 12 normal cases (the previous 8 and 4 text
Native/Broad Local/HTTPS cases), 12 fresh-process retained cases and the same
12 recovery/failure scenarios. Each used Source has exactly one physical read
session. Unused Source installation opens no unused provider. Fresh attach,
row/description/stream reading, request lookup and resubmission of the exact
stored document/format return the same Run with zero provider opens or SQL I/O.
JSON and text Program/Run CIDs need not agree across different submissions;
generated Stage structure is allowed to differ without changing these semantic
and physical observations.

Second-input failure, cancellation, started-unknown recovery and cleanup retry
reuse the original owner/harness. A generation-drift fixture republishes its
alias against the deliberately changed valid SourceView, allowing the existing
Run dependency refusal to execute before I/O. An initial failed attempt at
`d7d8f7d7f238142e8ee81a2c3dc2ff28aa257f30` reached all normal/retained cases
but failed this fixture's Host alias initialization; it is not counted as a
complete acceptance pass. No product check was relaxed to repair that fixture.

Successful evidence is retained locally in
`public-query-evidence-DxoLOl/two-source-acceptance.json` (21 child command
records, zero unexpected failures); the earlier failed attempt is retained in
`public-query-evidence-B1bvYj`. Both live under the workspace `.codex-scratch`.
The packed local-node SHA-256 is
`f09bf206ecb80841375d93f3a56956c7aa61a4df3ac3b63bb42814ef0e9ea06c`;
run-host-core is
`ae96f379933ec3199cd02c4d2dac7b373815a37bb6d0345cf0f836b096209d2e`.
The pack manifest binds all five distributions to the fixed source above.

This closes the selected pure JOIN JSON/text comparison. Temporary confirmed
cleanup and zero byte/reservation observations remain distinct from an explicit
active-hold inventory and durable Named Result retention. The cumulative ledger
`holdings` count is not an active count. Graph→INFER→Effect Result Policy binding
and public acceptance remain D/A work in Draft #304; this pure JOIN acceptance
does not establish that Graph composition or its approval/restart boundaries.

## Historical implemented versus execution evidence

| Surface or boundary | Implemented checkpoint | Acceptance still required |
|---|---|---|
| Retired AQL/PROGRAM/STAGE and STEP/OP public entry | Typed refusal; no compatibility parser or formatter | Preserve existing SQL/Pipe and machine-input regressions when integrating the unified owner |
| JSON/YAML Program | Existing machine admission remains available | Machine execution is not evidence that replacement text executes |
| Relation DATA and explicit RESULT | Shared script parsing and lowering; public preparation retains named roots | Three authored source examples and the independent JSON control passed fresh packed Local/HTTP at `93f4689f3b5029b0a11b5435be6d1f0d5444718c`, as detailed below; this does not cover Graph DATA |
| Pure PROPERTY GRAPH | Bounded parsing and ordinary Program construction connected to C's unified owner | Fifteen keyed source cases passed packed Local/HTTP with exact rows and descriptions; common JSON snapshot controls and authored-source snapshot/TRAIL tests passed separately; source-specific exact snapshot CID assertion remains unexecuted |
| Named SGA calls | Nineteen adopted names and argument roles parsed by the shared query parser; DATA aliases and normalize-before-MATCH lower to retained producers | Adapted common Carrier/schema contracts for remaining calls; all promised examples through Named Results |
| Public Graph source | DATA constructor lowers to the unified ordinary Program; standalone retired Graph aliases remain refused | Packed Local/HTTP passed 18 successes, 3 execution failures and 12 input refusals per transport; required final CI and native CLI acceptance remain pending |
| Source INFER KEEP/AS | Selected source-free execution is in main through #261; common owner is reused | Seven positives/four typed refusals per Local/HTTPS transport passed at `1ba6c06670f991594a8404d7f61a28ab5bdb5789`, including NULL, complete descriptions/streams and fresh-process capture replay with zero Model redispatch; acquired-source text and wider compositions remain separate |
| INNER/LEFT/CROSS JOIN chains | #266 lowers ordinary SQL/Pipe, DATA and CTE chains to existing JOIN operations | Nine positives/four refusals remain the packed Local/HTTP target. Submitted `d4ba0a96ed94d3ba78e8ae126cf1577b5d283c86` CI failed on an imported-main history declaration before product jobs; updated source execution is unverified |
| NEAREST KEEP/AS | Independent source/Program/row/type fixtures and public consumer are prepared; explicit-profile common checker/Plan diagnostic succeeded using historical packages | Standard installed Host capability/source connection is coordinated with D, not waiting for a C artifact; public Local/HTTP execution remains unverified |
| Other target Effect, VecA and TEA surfaces | Adopted targets and machine capability are distinct from public syntax support | Feature-specific source, checker and real execution evidence; no bulk completion claim |

The public Graph refusal retains standalone installed Graph aliases; DATA pure constructors now lower to the unified ordinary Program.
No retired property-label route, simple-Graph conversion or old consumer fallback
is enabled. Syntax-only normalization must not be reported as common Graph
checker or kernel acceptance.

## Evidence and handoff boundaries

The [unified-source separation record](2026-10-03-property-graph-unified-source.md)
lists the constructor, checker, Graph identity, MATCH/TRAIL and public snapshot
interfaces required from C. Its retained authored fixtures specify independent
schema, rows, parallel edges, composite keys, static labels and NULL exclusions.
The [named-call checkpoint](2026-10-02-sga-query-calls.md) records B's parser,
lowering and canonical identity tests; its provisional-dependency results are
explicitly historical.

`src/source_frontend/unified_dependency_test.mbt` verifies keyed DATA lowering,
typed refusals and Relation DATA/RESULT preparation. It does not itself observe
Host counters, deliver a Result or roundtrip a snapshot. Separate packed evidence
now covers the selected Graph sources. The later
[source-INFER acceptance record](2026-10-03-source-infer-public-acceptance.md)
closes the selected source-free KEEP/AS cases, not the full INFER corpus.
The [JOIN chain record](2026-10-03-join-chain-frontend.md) separates ordinary
JSON diagnostic success from updated source execution still required in #266.
The [NEAREST connection report](2026-10-03-nearest-public-connection-boundary.md)
identifies its installed Host boundary and prepared, unexecuted acceptance cases.

C's earlier submitted candidate `8c052888503e130e3d6c5f5a5ea74037be407e3f`
and provisional #164 `125a186ae9396fbfc7865641922e8e8a4ffc87d9` are historical,
not current dependency inputs. The pushed unified SHA `51376bca11d57b775aa22d42453176f8ad1f681b`
was the development input for that Graph checkpoint. The user authorized connection before C's
all-CI or merge completion. Both parent SHAs, clean acceptance SHA and package
digests are recorded in the linked acceptance report. Formal adoption still
requires review and necessary CI. No unsubmitted worktree is a release dependency.

The [architecture and migration obligations](../design/frontend-language-migration.md)
remain broader than this implementation checkpoint. Existing JSON/YAML inputs
are retained capabilities, not completed replacements for withdrawn text paths.

## Historical main integration and Relation packed acceptance

The integration commit is `7a5d7c62148066ea1bfe0a4cc487161dc7ca1168`;
its source-registration resolution is recorded independently at the verified
SHA above. No C unification commit was adopted. Three merge conflicts retained
main's stronger DATA-task input-port checks and the existing packed controls,
while preserving B's authored source acceptance group. The group now reuses
main's independent JSON fixture rather than maintaining a second inline copy.

The two `client_data_set_task_wbtest.mbt` tests passed through
`scripts/local-checks.mjs`. The MoonBit formatting check, compilation-manifest
freshness and foundation source-history composition also passed. Grammar and
barrier pins did not change. An initial attempt used `-f` as a filename selector;
the runner rejected its zero-test result. Only the corrected two-test execution
is counted as successful evidence.

```sh
node scripts/test-packed-public-query.mjs --relation-data-only
```

At the clean verified SHA, normal prepack and an external installation passed
the same three authored sources and the independent JSON control on Embedded
Local and authenticated HTTPS: **4/4 positives and 3/3 preparation refusals per
transport**. Exact Named Result rows and declared columns, types, nullability
and order agreed with authored expectations. Internal sort columns were absent;
refusals left Run admission and provider I/O counters unchanged. The JSON control
returned `[{"id":1}]`. README controls, the existing planner-selection group
(22 Local/HTTPS cases) and the documented two-source example also passed.

All fourteen recorded commands completed successfully. The harness preserved
logs, command outcomes and digests, then removed its own temporary installation.
No whole local Core or Client gate was rerun for this integration.

| Normally packed artifact | SHA-256 |
|---|---|
| actql-client-wire-0.0.0-development.tgz | `5da98d3edb615f960f0511be9d6e61431cd34d02304a8bd6b6e576f7775f91a0` |
| actql-sdk-0.0.0-development.tgz | `2fc910067348e421346945ced1e728e107bbe6fa455ee00f9d71da46e8123c5b` |
| actql-run-host-core-0.0.0-development.tgz | `ae2dce5569ed9e35db2b43b466e193c98574ba388c3c39e5837bbcb93deef512` |
| actql-local-node-0.0.0-development.tgz | `dcd251b0c70a27cbda77c9260ddc39f7252e176630d6a97003dcd644dfe771ec` |
| actql-node-0.0.0-development.tgz | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |

[CI run 37078508563](https://github.com/actql/actql/actions/runs/37078508563)
completed successfully for the earlier implementation SHA
`5221799a271e2cb838d1806ea4db9d38b7d43135`. Conditional macOS/performance/probe
jobs were skipped. This is historical CI evidence, not same-SHA CI for the main
integration or evidence that new Graph/source-INFER execution works.

## Historical packed Relation DATA execution

Verified SHA: `979b59605ab4ff2d52ca3e772cfd93827b1816fe`. Its product sources
are unchanged from the checkpoint above; it adds the independent acceptance
fixtures and a narrow selection in the existing packed harness.

```sh
node scripts/test-packed-public-query.mjs --relation-data-only
```

The normal `npm pack`/prepack process built five packages from this clean SHA.
The installation was outside the checkout; the runtime had no MoonBit toolchain.
The ordinary installed Embedded Local and authenticated HTTPS Hosts both passed:

- Ordered DATA set input, hidden sort-slot reuse and LIMIT: `nodes = [{"id":1}]`.
- Quoted DATA reference and set ordering: `nodes = [{"id":1},{"id":2}]`.
- Explicit retained Results: `original` and `active` both contain `[{"id":2}]`.
- Independently authored two-root JSON Program with append, derive, sort,
  projection and LIMIT: `nodes = [{"id":1}]`.

Each transport passed **4/4** successful inputs and **3/3** preparation refusals
(forward DATA reference, duplicate DATA name and DATA supplied as SQL format).
For each success the harness compared exact Named Result rows and the complete
`Result.describe().columns`, including order and nullability. Hidden sort columns
were absent. Physical source-table reads were zero; attach, reread and identical
request resubmission did not increase admission or I/O counters. Each refusal
left those counters unchanged and request lookup returned `not_found`.

The independent JSON control also executes the formerly failing strategy shape.
It therefore supplies actual execution evidence beyond the earlier seven-task
preparation check; it is not a replacement for source acceptance. No strategy,
Graph carrier, provider, Host or common checker implementation was added by
this test commit. README Local/HTTPS quickstart and the packaged missing-wire
asset refusal also passed as the harness's existing controls.

| Normally packed artifact | SHA-256 |
|---|---|
| actql-client-wire-0.0.0-development.tgz | `5da98d3edb615f960f0511be9d6e61431cd34d02304a8bd6b6e576f7775f91a0` |
| actql-sdk-0.0.0-development.tgz | `9fd8d7c7019eafcd1401fa1804108644f13875b2197bb3d3e012abbb5428143e` |
| actql-run-host-core-0.0.0-development.tgz | `7360f0c9d09b8748cd0518df95045f509f14c62bd9da2cd9b2fb67f6d9ef7ad0` |
| actql-local-node-0.0.0-development.tgz | `6c204bb1c1ecb677fb350f9a491f7dd3f05be6e8829701cb2748009a3ce48798` |
| actql-node-0.0.0-development.tgz | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |

The harness retained command results/logs and these digests, then removed its
own successful temporary installation. This is local fixed-SHA acceptance;
it is not a same-SHA Linux CI result, Graph/snapshot acceptance or source-INFER
execution evidence.

## Historical development Graph connection

The connection target is C #164 public HEAD
`51376bca11d57b775aa22d42453176f8ad1f681b`, integrated with B
`b19ed2cfb0bdce93832d47a8c3a7a8da95266c14` in an isolated development
branch. This supersedes the historical submitted-candidate status above.
Starting acceptance does not require C all-CI or merge success, and is not
formal adoption or migration completion. Follow the linked unified-source
record and public acceptance report for executed tests and remaining coverage.
The later source-free INFER acceptance reuses the common owner already in main;
no frontend executor is introduced. JSON composition in #246 does not establish
equivalent authored-text composition or all Graph/VecA/TEA surfaces.


### Fixed A Result Policy adoption for Graph acceptance

A's public #339 candidate is
`33c4af2f9995feb64948c808e94b9dee40f87af9`. D first adopted it in the isolated
`integration/graph-result-policy-339` worktree through normal merge
`cb695ca95ebc457796accc134fbcdedf5454432b`, with ordered parents
`b65ff13f689985c5a82fc9c8e2d280913bf52cdd` and that exact A SHA.
The four conflicts retain the Graph source-free admission/provenance while
adopting A's retained Policy field and original-body validation. The temporary
Model-egress-CID substitution for source-free Effect Results is removed.

The existing acquired Effect computation forwards the saved Result Policy and
limits to `adoptCheckedClientEffectInferRun`. The Graph Model publication plan
retains `compiledInferSourceFreeResultPolicy` in its ordinary capture dependency
bodies. There is no extra executor, fabricated Source declaration or dependency
validation exception. Fixture commit
`c3503d88935939de7db04c96595211439443bb17` explicitly configures A's admitted
unknown-provenance original, CID
`sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563`.
Model egress remains a separate contract; all authored Programs, independent
rows/types/order and call expectations remain unchanged.

The existing node/edge Local/HTTPS consumer now omits current Host Policy
configuration when restoring both capture-waiting and approval-committed runs,
checks the original preserved in request admission, and retains Source calls 0,
Model inputs [100,200], writes [0,0,1,1] and identical request/Run lookup.
The positive case precedes the missing-Policy and duplicate/NULL refusals.
Missing Policy must reject before accepting a Run or invoking a Model/Effect;
missing original and CID mismatch are also checked at the installed Host entry.

Focused JS composed-INFER tests pass 7/7 (`run-XOXtDl`), including A's separation
of Model egress and Result Policy. The consuming Host runtime builds successfully
(`run-Ir7wTx`). Selected bridge/journal/installed-Host/custody cases pass 4/4
(`run-vU1UeX`), and the Graph fixture/acquisition custody selection passes 18/18
(`run-VZCuYz`). Changed MoonBit formatting, outer/external driver syntax and diff
checks pass. Complete retained-history validation succeeds at integration merge
`cb695ca95ebc457796accc134fbcdedf5454432b` with 104 declarations and 2 supplements;
no original record, introduction history, validator or gate is rewritten.
These are focused preparation results, not fresh-packed Graph acceptance.

#304 remains Draft, base main, dependent on #339. Final merge order is #339 then
#304, both ordinary merges into main; no merge operation is requested. The failed
public CI at `f90ba1b2f3f875becc2e58fe0cc24d30f88b2957` remains historical evidence.
Fresh-packed node/edge Local/HTTPS approval, execution and both-process restart
must pass on the new submitted source before Graph acceptance is claimed. Formal
active temporary-holder inventory remains a separate common-owner observation
handoff; zero bytes or cumulative allocation counts do not prove active count.


### Actual Compiled Run Policy accessor regression

While automatic #304 CI `37185226241` was running for
`8f115d142763c37ec1411e6243d3cbf3760173a4`, additional caller inspection found
that A's `compiledInferSourceFreeResultPolicy` passed a Compiled Run through the
publication-contract token map. The real installed-INFER bridge selection
fails with `Foreign publication contract` before correction (`run-gbRILx`,
1 executed failure). This is a JS token-domain projection fault, separate from
A's formal Policy/body admission and the historical missing-original failure.

Correction `6b551aa87de825ab28fa7f3e8a185592081ae09a` uses the existing
`compiledRunTokens` map and rejects foreign compiled owners before invoking the
common accessor. The same real bridge selection passes 1/1 (`run-4bxJGZ`),
returns the exact admitted unknown-provenance original, and refuses an ordinary
Run Definition as a Compiled Run. No new Policy, fallback or common execution
owner is introduced. D owns this small Host projection correction; the two-file
commit is independent of Graph fixture imports and can be shared with A's #339.
Fresh-packed Graph approval/restart remains unproven until the corrected source
runs through the existing public consumer.

### Packed public reader-close evidence from #342

Submitted #342 source is `00c3519e1afc0015d65f674ebd8f83dd4daa32a5`, automatic
CI `37184275679`. Its tested merge is
`79ca0c42ba0be0e6559092d355ce64f91decd32f`, with ordered parents main
`4cd79be2d720d60288c2816aee318aeb7bd2b3e6` and that submitted source.
Public-query artifact `11296264067` has a clean complete/passed final summary
and 40 commands with status and verification status zero and complete output.
All five consumer tarball digests match exact-source producer artifact
`11296511816`. Submitted and tested merge blobs are identical for the authored
expected rows and all three reader-close harness files.

Four retained observations pass: Native JSON (`distinct`) and Broad text
(`broad-text`), each Local/HTTPS. One reader closes after its first row and stays
prefix/1; another attempt completes all five independent expected rows.
New full read/description preserve NULLs, duplicates, types, column and row
order. Lookup/resubmission return the same Run, the request journal is unchanged,
and retained acquisition observation reports no new Source session or SQL I/O.
This verifies public consumer iterator independence, not physical producer
cleanup, remaining active-holder inventory or formal reservation return.
The overall exact-HEAD CI is still running; this artifact predates later Effect
composition and is not evidence for that phase or for source-free Graph.


### Current packed Graph failure: missing issued retention original

Automatic #304 CI [37186660530](https://github.com/actql/actql/actions/runs/37186660530)
failed at submitted `8207fd14b0eca7a1771435e0300428f61b19ed17`, tested merge
`5c417e7d7cc148f90edd67e29cd160869ca60527`. The first Graph node Local
wait returned `needs_reconciliation`, not the unchanged `waiting_checkpoint`.
The token accessor correction did not close this failure.

A retained-package reproduction verified producer artifact `11297605317`,
its exact tested-source manifest and all five tarball digests. An explicit
fixture-only diagnostic overlay preserved the public Program and captured
`MoonBitHostFailure` with typed cause 6 (`CapturedEffectDependencyIssue.MissingDependency`).
The rejecting owner is `run_publication.issue_captured_effect_dependency_inventory`,
called by `prepareLocalEffectDependencyInventory` before capture custody commit.
Graph/Relation/Model computation had completed and its cleanup owner had returned
the temporary byte reservations. This was not a Model invocation failure.

The failed request journal retained the actual Host Result Data Policy original
with CID `sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563`.
The 66 submitted dependency bodies included that exact admitted original.
Their admitted typed reference graph instead lacked the Result retention policy
`sha256:8f96af4d8e1aa7cf573375c9ce07297127440c98d94d1a75f0873ed1381d60f5`,
named by three Result artifacts and two upstream acquisition relations.
No missing Model-egress Policy original was invented, and no dependency check
was relaxed. Failure logs, admitted body/reference observations and Run journals
remain preserved outside the checkout.

Product correction `42ebb01daef57fd41ba4bcf00611047c4f9fa926` passes the already
issued retention original from the source-free publication plan into its normal
Effect dependency inventory. The focused fixed-time original-body regression
failed before correction (`run-N8nEl5`, missing original), then passes with the
actual common seal and body admission (`run-cZcLDJ`: 12/12 selected tests).
Its first draft incorrectly named the identity field `retention_policy_cid`;
the authoritative publication contract uses `effective_retention_policy_cid`.
The expectation was corrected to that contract field, with times, policy, CID
preimage and required original unchanged. CI registration/Graph fixtures and
the original-body selection pass 27/27 (`run-QNHou2`). These selections overlap
and their counts are not summed. The existing distribution job includes the new
regression; there is no extra package installation or CI job.

The same immutable package set with the declared JS retention connection overlay
passes node_rows and edge_rows on Local and HTTPS (`run-8WFxFg`, four records).
Each keeps Source sessions [0,0,0,0], Model inputs [100,200], writes [0,0,1,1],
the independent typed rows and both capture-waiting/approval-committed crash
boundaries. The same request and Run restore while current Host Policy is absent;
the saved original and Model response are reused and confirmed Effects are not
resent. Node duplicate/NULL assertions refuse before Model dispatch. The limited
retained-package diagnostic omits the long shared cleanup/deadline fault block;
the ordinary fresh-packed CI consumer retains it unchanged. This is explicitly
an adapter-overlay diagnostic, not pristine new-HEAD packed acceptance.

Two dormant fixture assertions exposed after the positive path were corrected:
the SDK wraps Host 500 submit errors as `SubmissionUnknown` (cause
`ClientHostFailure`), so the missing-Policy case also requires lookup not_found,
an empty request journal and Source/Model/write counts zero. A separate refusal
process writes a zero-I/O observer snapshot; the bad-row case checks every
physical call count and command/open list rather than requiring the log file to
remain byte-identical. No expected successful Run state or timeout changes.
The first failed public wait now reports its Ref, state and operator diagnostics;
internal Effect-start diagnostics preserve the typed cause separately from the
public wire response.

Main merges preserve the Source approval continuation and source-free Graph
INFER through the same Effect dispatch owner. Resolution `13c0d39d24051048ecfa025b504cb6fa1f731ded`
keeps all four conflicting connection/fixture changes, and its package resolution
lists all 47 required ancestral source groups. Ordinary registration and both
real parents/blobs/modes are separately declared. Complete history validation at
`f1505f07858c8f371b808b59cdcc5b90a70b83a9` passes 110 declarations/2 supplements;
existing declarations, supplements and introduction histories are unchanged.

A's corrected #339 SHA `5e22c522becb80477cb7ed4f4733a48a463d5bf2` is now merged
into main (`6da81257a`); D first adopted it through normal merge `2ad13cb290c31a47fd9e208f667dfb2b84e455c2`.
Latest main `c26339bed484c1965da78f6a9540333c2583ea31` is integrated through
`e3ecb26c952a045e8a4984a7b2e0a318c50a4cce`. #304 remains Draft pending
fresh-packed acceptance and all mandatory CI on the submitted new HEAD.
The final merge destination remains main; D does not merge this PR.

#342's full automatic CI `37184275679` subsequently completed successfully;
its reader-close unit is merged into main as `6c2c65742`. That accepted consumer
iterator boundary still does not prove the formal active temporary-holder
inventory, which remains an A-owned observation dependency.

### Final-main merge preflight and additive resolution

Submitted `ed139eff22eb8a91f893ac8ad74c9effe8ec823d` automatic CI
[37191034738](https://github.com/actql/actql/actions/runs/37191034738)
failed preflight before package production or public Graph execution. Its first
error is the missing resolution for merge
`e3ecb26c952a045e8a4984a7b2e0a318c50a4cce`, requiring
`.github/workflows/ci.yml` and `package.json`. A complete local history check
at the same submitted source reproduces that exact error. The earlier
`f1505f07858c8f371b808b59cdcc5b90a70b83a9` history success does not cover this
later main merge, and this CI failure is not a new runtime diagnosis.

The additive `resolve-graph-retention-policy-main-e3ecb26c9` resolution binds
the actual ordered parents `f1505f07858c8f371b808b59cdcc5b90a70b83a9` and
`c26339bed484c1965da78f6a9540333c2583ea31`, both maximal Git ancestors
`5e22c522becb80477cb7ed4f4733a48a463d5bf2` and
`60394aacca05c297c07cf6e8129973a34318a6c3`, and all 85 ancestral source-binding
groups touching either required path. Identical resulting workflow bytes still
require this real multi-base resolution. Both parent blob digests/modes and the
merged result are pinned; current CI cost controls and all test registrations
remain. Existing declarations, supplements and their introductions are retained
unchanged. Complete history acceptance and pristine fresh-packed Graph coverage
must be evaluated on the new submitted source and its automatic CI separately.

### Post-preflight failures and the next main adoption

Submitted `996d5aade5b60de7ba5190ddcf21a52e6d8123a3` automatic CI
[37192092537](https://github.com/actql/actql/actions/runs/37192092537) tests
merge `97b4a53f6d9a3ff1affdbbc0f6f3b6f9775a81bf`, with ordered parents
main `4a897acc2687fcf63d2f5913acf999e1257bdb17` and that submitted source.
Preflight, including actual retained history and public interfaces, succeeds.
This is not inferred from the earlier local result. The generated grounds for
`e3ecb26c952a045e8a4984a7b2e0a318c50a4cce` require both declared paths at
base `5e22c522becb80477cb7ed4f4733a48a463d5bf2`; the other base contributes no
required path but remains recorded in each obligation. The resolution's
rationale concerns the combined union, not two independently required records.

The `host` job fails at the independent exact command inventory in
`scripts/build-runtime-packages.test.mjs`: the real distribution registration
contains `local-values-plan-policy.test.mjs`, while that authored expected
inventory omits it. Local selection `run-ipru2V` reproduces the same mismatch.
The correction pins only this intended file addition, retaining exact command
order and rejection of duplicate or unrelated additions. Runtime builder and
CI selection regressions pass 48/48 (`run-D5r1K5`); their compiler fixtures do
not establish a new product runtime build. No successful-row expectation,
verdict, timeout, package registration or CI job is changed by this correction.

The separate `lint` failure is the nonresistant direct-process TERM fixture:
expected direct code 7, observed 0 after the interruption assertions passed.
[Issue #366](https://github.com/actql/actql/issues/366) records the exact SHA,
job and selected command for G. The fixture's reliance on the descendant for
event-loop liveness is a candidate explanation, not a proven product guard
failure. D does not skip the assertion, fabricate a direct exit code or label
it as a Graph runtime failure.

Latest main `7763fe148d80f4443b52f7428143ae325301fe9a`, including the selector
derive/Store work and main full-profile checkpoint correction, is normally
integrated through `2da6db903b9c43c0836fd45745480c742d22aec0`. It has a single
maximal common ancestor `c26339bed484c1965da78f6a9540333c2583ea31`; no source
conflicts were encountered. Existing declarations, supplements and originals
remain. The checkpoint correction and the separate #366 observation must not
be conflated.

Fresh producer artifact `11299771882` binds the tested merge
`97b4a53f6d9a3ff1affdbbc0f6f3b6f9775a81bf`; all five tarball digests are
verified. Its public packed consumer is still running at this record's
introduction. That source predates the latest main merge above and cannot be
relabeled as fresh-packed success of the next submitted HEAD.

The existing restart fixture places the installed Host and Run execution owner
in one dedicated Node child, also hosting its HTTPS server when selected.
At each durable boundary it exits without graceful close; the supervisor waits
for child closure before starting the recovery process. No Host or Run-owner
memory survives that child termination. This describes the actual existing
fixture topology rather than claiming two distinct Host/worker PIDs. The
fixture provider service remains available to observe calls; it is not the
Run-custody owner. Formal active temporary-holder inventory remains separate
from byte/reservation return and durable Named Result retention.

### Pristine node Local success and cleanup observation isolation

The fresh producer at tested `97b4a53f6d9a3ff1affdbbc0f6f3b6f9775a81bf`
and ordinary public consumer now pass Graph node Local through the unchanged
`waiting_checkpoint`, approval, one confirmed write and both durable restart
boundaries. The emitted record has Source sessions [0,0,0,0], Model inputs
[100,200], writes [0,0,1,1], the expected typed identity and NULL property,
and the exact accepted Policy original restored without a current Host binding.
Missing Policy, duplicate Model keys and NULL arguments refuse before Model
dispatch. Source-backed JSON/text Local/HTTPS positive and shared fault cases
also pass before this Graph case. These are results of the pristine producer,
not the earlier JS adapter overlay.

The next actual failure in job `111409282355` is at consumer line 1352,
comparing `released.resourceUsage.transferredBytes` to
`completed.resourceUsage.transferredBytes`: Graph release reports 2451, but
`completed` was selected from the first prior Source pending-cleanup Run and
reports 1029. There is no hardcoded 1029 expectation to update. The consumer
filtered the entire cumulative custody log by `pendingScratch`, then combined
its first completed event with its final release event. This crossed unrelated
execution windows. It is distinct from the repaired missing-original rejection.

The shared cleanup consumer now records its append-only custody offset
immediately before the single pending-cleanup child and selects only subsequent
observations. An independent fixture with different prior/current counters
rejects the predecessor selection (`run-gIz3VO`), then passes with the window
bound (`run-ycCghd`: 27/27 selected tests). The existing exact before/after
transfer and planning invariants, pending execution reservation, confirmed
release and replay assertions remain. Expected rows, the 512 MiB limit and
physical owners are unchanged. The new regression is in the already registered
Graph fixture test, with no additional job, pack or execution mechanism.

The old fresh run stops before Graph node HTTPS and both edge cases; their
success is not inferred from node Local or the retained-package overlay.
Complete history at `beeead8aaa893f101f60573e915ba88d1b2782d0` passes
112 declarations/2 supplements after the latest main adoption. The final source
including this consumer isolation must separately retain that history result
and finish its new automatic CI and all four pristine Graph cases. #304 remains
Draft, and the independent #366 guard fixture failure remains tracked for G.

### Effect target-read main integration

Main `44e07a2de522d4dfc6d7924d4672e88d237aa6e3` adds the existing common
Effect target-read approval owner through #359. Normal integration into the
Graph branch resolves one Host conflict: source-free Programs retain the
optional Source profile access, while acquired Source continuations use main's
separate `sourceCheckpoints` journal port. The target-read owner, current-use
authorization and atomic next-Checkpoint transition remain main's implementation.
The issued retention original and cleanup observation window remain intact.

The new main CI-selection regression initially expects only main's four
composition cases and fails against this branch's six cases (`run-K7RXiz`). Its
independent literal inventory now includes the already registered Graph node
and edge cases. This changes neither expected product rows nor call counts.
The Graph fixture, Client selection and target-read owner selections then pass
33/33 (`run-WUe8ff`). Host/consumer syntax and whitespace checks pass. These
focused checks do not establish fresh-packed execution of the integrated source;
the complete four-case public Graph matrix and automatic PR CI remain required.

### Saved Result Policy restoration at the target-read boundary

Automatic run [37196944495](https://github.com/actql/actql/actions/runs/37196944495)
tests merge `f1460dcc4f0509a62e1aff6a98751c6b39ecc1b3` for submitted
`bf05c785a869f9d38b732b59613c403042c13533`. The tested tree equals the
submitted tree. Producer artifact `11301856265` binds that merge; all five
downloaded package digests match the manifest. Preflight, Host, lint and package
distribution pass. The ordinary packed consumer `111424478016` fails; its
dependent Client and Check aggregates fail as a consequence.

The first Graph failure is `PackedEffectTimeout` with diagnostic
`effect_resume_failed / InvalidHostResultDataPolicy`, before a Graph acceptance
record is emitted. This differs from the historical typed MissingDependency
failure. Main's target-read preparation restores the already started Effect
computation through `client-effect-run.mjs:restoreComputation`. That adapter
retrieves retained admission but omits its `resultPolicyOriginal` from the facts
passed to `prepareExecution`. The source-free preparation calls
`runtime-core.mjs:admitSourceFreeResultPolicy`; its Host original-shape guard
rejects the missing value before body/CID admission. The failed runner's saved
journals were not downloadable, so this record does not claim direct inspection
of their bodies. The omitted adapter handoff is independently reproduced with
a JSON-roundtripped retained admission containing the fixed, valid original.

The product correction forwards the saved original, as initial execution already
does. Restoration still rechecks current authority, does not select today's
Host Policy, and neither reserves a new physical start nor dispatches work.
An independent regression fails before the correction (`run-O3c4oQ`); the
missing-original counterpart continues to reject. After correction, the Graph
fixture, Client selection and target-read continuation tests pass 35/35
(`run-pCwVID`, focused evidence `focused-test-Hvlxm2`). These are targeted Host
adapter tests with opaque core tokens stubbed, not pristine Graph acceptance.
No successful-state expectation, timeout, original body, provider count or
resource limit changes.

Before the Graph failure, the pristine consumer passes Source-backed JSON/text
Local/HTTPS composition and their shared fault cases. The separate pristine
public-query artifact `11301906464` contains 40 complete successful commands,
all bound to clean tested source `f1460dcc4f0509a62e1aff6a98751c6b39ecc1b3`.
Its twelve two-Source cases cover Native/Broad, JSON/text, equal-content and
unused-Source variants in Local/HTTPS; four reader-close observations preserve
the continuing reader's five rows. Second-input failure/cancellation and cleanup
retry are also covered. These prove their recorded scope at that tested source,
not the pending restored Graph matrix or active temporary-holder inventory.
All four Graph node/edge Local/HTTPS cases and the new automatic CI remain
required after this correction and the next main adoption. #304 remains Draft.

The next normal merge `2669b421e0e9bd131f9a98b74e621aaaeb00b47f` adopts main
`336b1d8ceb1cc9bbe3c2291660129d3bedad0f89` without source conflicts. Full
retained-history validation passes on that merge, with existing originals and
supplements preserved. Main does not change the selected Effect restoration,
embedded preparation, common Policy receiver or Graph fixture files.

A bounded retained-package diagnostic (`run-Vzks3F`, 2/2) additionally uses the
exact failed `f1460dcc4f0509a62e1aff6a98751c6b39ecc1b3` Local tarball and its
compiled MoonBit Policy body owner. It reads the original from the preserved
earlier local Graph request journal, rather than fabricating a body. That
original has CID
`sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563`.
The original passes real common body admission with independently pinned limits
`{maxWireBytes:1000000,maxNodes:100000,maxDepth:64}`. Through the failed
package's restoration adapter, the same saved original becomes undefined and
the real common shape guard throws `InvalidHostResultDataPolicy`. Through the
corrected source adapter, it remains exact and passes that unchanged packaged
common owner. Missing original and malformed limits still reject. This isolates
the missing handoff, with core Run tokens stubbed; the positive half is explicitly
a mixed-source diagnostic, not fresh-package public acceptance or inspection of
the failed runner's unavailable journal.

The complete handoff uses the Host-selected original during admission, stores it
in `runAdmissionEvidence.resultPolicyOriginal`, reuses that stored value during
initial execution and restoration, and revalidates it with `localContractLimits`.
`effectPublicationAdmission` supplies the same limits as `resultDataPolicyLimits`;
`acquired-effect-computation.mjs` forwards the admitted original and those limits
to `adoptCheckedClientEffectInferRun`. No Model contract substitution, Policy or
limits guard relaxation, timeout increase or new execution owner is introduced.
Active temporary-holder count observation is a separate completion unit. The
existing cleanup and reservation-return checks remain; no all-holder-zero claim
is made here. Graph text and additional operations are outside #304.
