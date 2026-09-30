# SGA source and packed Run handoff

The Frontend branch owns named SGA syntax and, after the public Host source
connection is adopted, packed Local and HTTP acceptance. The Host connection
owner retains the shared submit, planning, dispatch and publication files.
This record separates checks that ran from the product acceptance still needed.

At the earlier source `5acb8f04d659f67f9a1e6a60a25c3003830abdb4`, independently
authored `graphs-equal.named.aql` and `graphs-equal.expected-program.json`
matched exactly after Frontend lowering. The ordinary checker admitted a
source-free Program reusing its Graph producer. The separately authored Result
fixture expects one `equal: true` row. No sort is implicit in either source or
Program. The named-source fixture has not passed packed runtime acceptance.

The packed installation created by `scripts/test-node-client-package.mjs`
accepted the generated JSON Program through `@actql/node`, but its Local Run
ended `failed` with `ACTQL_E_UNPUBLISHED_RUN` before Result publication. The
journal recorded a reserved physical start and confirmed physical close. A
direct `match_nodes` variant reached the same failed state; a `node_rows`
variant was rejected at compilation with `RunHostTaskCompilationRejected`.
These variants are diagnostic probes, not new language expectations or proof
that the Graph kernels failed. An ignored installed copy with logging only
showed the first call to `core.next` failing before any Compute task completed.
The common `strategyHostNext` bridge returned `Dispatch(NoStrategy)` from
`prepare_next_compute_task` / `prepare_next_installed_task`: the captured DAG
had no selected strategy revision. The Host then reported
`host-tasks-failed`, and publication rejected `StrategyNotComplete`. That
publication rejection is a consequence, not a Graph kernel failure. The
physical strategy and installed Host owners need to determine why this
admitted Graph Program had no selected revision; the Frontend must not invent
one or bypass the normal selection boundary.

The Reach Relation-selector gap above was subsequently closed on this branch:
`reach.start.from` resolves through the ordinary producer table, the common
checker accepts the shared selector, and Local Reach uses the existing bounded
selector machinery. The source-free selector, duplicate, empty, missing-ID,
nullable, capacity and cancellation cases have focused checker/kernel tests.
Packed public-source Result acceptance for that selector remains unproved.

At `ce66e22bece4582406ab41108175fb1669c4d637`, the independently authored
`normalize-rows` source and Program match exactly and pass ordinary Program
preparation under the Local Check Environment. The input nodes are B then A;
the authored sort and Result order require A then B. Task compilation stops at
`ClientDirectResultRootIssue::RequiresResultTransformation`. This is the
existing Result Plan connection owned by the Host integration; the Frontend
does not remove the declared order or publish the untransformed output.
The independently authored `degree-rows` and `graph-bounds` fixtures also pass
preparation and stop at that same Result transformation boundary. The former's
out-degree expectations come from two authored A-to-B and A-to-C edges. The
latter expects the node-count violation before A's degree violation, plus a
separate empty Result at inclusive limits. Neither expectation comes from
runtime output. `graphs-equal` passes ordinary preparation but the earlier
packed probe failed at `Dispatch(NoStrategy)`. These are separate blockers.
The other authored fixtures still require their exact checker and packed
execution evidence;
`components` also needed its existing capacity application, and the
edge-row fixtures need lawful order evidence for nullable edge identity.
The Client job now includes `scripts/sga-surface-checker.test.mjs` at the
common preparation boundary. It rejects a Relation chained into
`normalize_graph` and an unbounded `graph_bounds` call before Run acceptance.

For the earlier Components fixture probe, the exact shared gap was in
`pipeline_check_context::derive_program_capacity`: it derived Host-owned
engine-atomic applications for Join and Traverse/Reach, but no corresponding
Components consumer. `capacity_program_step::check_components_applications`
therefore returned `MissingApplication` for the checked Components step. The
existing contract requires two distinct applications:
`actql.bound.components-input-nodes` in nodes from the retained Graph producer,
and `actql.bound.components-nodes` in output rows under
`max_graph_output_rows`. The shared builder must supply them with the checked
producer and policy; the Frontend must not issue substitute claims or raise
ceilings. The acceptance fixture still needs packed Result rows and a ceiling
rejection.

At `64b84e3bc71db28ada3720d3e9f418783a0e3d6f`, the common capacity
builder now derives the Components node proof from the checked Graph producer
and separately resolves the row claim under `max_graph_output_rows`. The new
Program-only limit helper retains exact owned proof handles and rejects empty
or foreign candidates. The focused Host-witness tests passed 31/31 and
pipeline-context tests passed 281/281, including Components preparation and
claim/subject checks. The packed Local probe then accepted the Components Run,
where the previous probe failed during common preparation. That Run still
ended before Result publication with `ACTQL_E_UNPUBLISHED_RUN`; its precise
dispatch or publication cause is not established by the public status. No
Components Result acceptance is claimed. The same packed probe passed raw
SQL/Pipe on Local/HTTP, the named `normalize_graph -> node_rows` Result on
Local/HTTP, and the native CLI Result. All seven other SGA probes remained
unsuccessful. The probe evidence and package digests are in the workspace's
`worktrees/.codex-scratch/public-query-evidence-0xPLsd`; the generated
installation and Store were removed after the run.

The edge-row order gap is independent of source spelling. The Graph
projection key includes `(src, dst, rel)`, but `edge_rows` publishes nullable
`rel`. `relation_evidence::select_key` currently excludes nullable fields for
`CanonicalOrder`, so an explicit sort by the edge identity still reaches
`UnresolvedOrder`. A diagnostic with a non-null input label and an authored
sort failed at the same boundary because the bridge output remains nullable.
The ordering owner needs a Graph-identity-specific proof or another lawful
completion mechanism; making all nullable Relation keys eligible would change
general key semantics. The Frontend must retain the authored edge order and
must not replace it with an arbitrary representative or unsorted Result.

`scripts/reproduce-sga-baseline.mjs <packed-installation> --graphs-equal`
replays the exact authored Program and reports public status and terminal error
code. It uses the installed package with a fresh `ACTQL_LOCAL_STATE_DIR` and
the packed test source profile through `ACTQL_LOCAL_SOURCE_PROFILE`. A failing
diagnostic is not an acceptance test. The existing reach/subgraph mode remains
available, including its explicit Result order.

After the Host source connection has a committed SHA, the Frontend owner will
submit named source through the installed SDK using `format: "aql-text"`,
then read Named Results through packed Local and HTTP. Acceptance must compare
independent rows and declared order for representative Graph-to-Graph,
Graph-to-Relation and Delta chains. Published schema type, nullability and
column order require separate publication-boundary verification until the
public Result API exposes them. The existing client request, cancellation,
authorization and Result delivery semantics remain owned by the common Host.

`scripts/accept-sga-public-source.mjs` is the packed acceptance
application. Copy it and `spec/frontend/fixtures/sga-surface` into a clean
packed installation, then run it with the installation directory, copied
fixture directory, and `local` or `remote`. Remote mode requires
`ACTQL_TEST_REMOTE_ENDPOINT` and `ACTQL_TEST_REMOTE_TOKEN` for a real HTTPS
Host backed by the same packed packages. Local mode requires a fresh
workspace-local `ACTQL_LOCAL_STATE_DIR`. It uses the same application body
for both modes, submits named source, checks request lookup and attach,
and accepts an optional final fixture name to isolate an operation during
diagnosis without changing the public execution path. It compares the
independently authored rows and nonempty row shapes, and reads
each Result to normal stream termination. The public Result API does not expose
the published schema, so this script does not verify schema types, nullability,
or column order; empty Results have no row-shape evidence. Publication boundary
tests must verify those schema properties separately. A passing named-source
case proves only that operation and its checked Result contract; other SGA
operations retain separate Host and physical execution obligations.

## Public Host connection evidence

The integrated test source at `b388bbce3aa3ca5289d9fc7d42ce387c4ff330b0`
combines the Frontend branch `f91d7f50d71e8b0c9ff6473d0ca33dfaef10523d`
with the committed Host source connection `0d4111d17c0705c29480b48628679b4e2bcb6c4d`.
This is a development integration branch, not a release or merge decision.
The tracked `scripts/test-packed-public-query.mjs` created an external clean
installation and ran the same authored `normalize-rows.named.aql` through
packed Embedded Local and HTTPS Host. Both modes returned the independently
expected `[{"id":"A"},{"id":"B"}]` Named Result after the input nodes were
authored in B, A order. Lookup, attach, same-request resubmission, a second
delivery attempt and normal reader termination passed. The same packed Host
accepted the five existing SQL/Pipe cases in each mode. The successful
`normalize_graph` case proves one SGA public path, not every named operation.

The Node-free native CLI was built from this integrated source and used the
same packed HTTPS Host. The tracked
`scripts/test-native-sga-public-source.mjs` submitted the same AQL text with
`--format aql-text`, waited for the Run and read the independently expected
Named Result. Its binary SHA-256 was
`b735ac546176230bfa8d5daffa9e358fb51da64ad2664d0ab7117dcc1e1588e8`.
The CLI test runs outside the package installation and does not put a parser
or Local kernel into the CLI.

The packed tarball SHA-256 digests for that run were:

| Package | SHA-256 |
| --- | --- |
| `client-wire` | `8e09005f4aac5063c1f6f8e4680dbb778a00e5c098126a85283e1f07685a76e5` |
| `sdk` | `1e4e83612b9c965388795f066be8cf24b0358feb46bd2335c8d98c36e83ed515` |
| `run-host-core` | `f6baa1caabb8c0655d62769157bb39274d9981c85f9940539061d82e67ea7a6a` |
| `local-node` | `04ab32d6bf4dee666a26f8107a933bd622813bde71d79b66456b891097b3a2d0` |
| `node` | `c72364973dd1ed42faea32425632b314de037c9b92035c9f5ec35b875914f225` |

The remaining authored SGA cases were also submitted to the same packed
Local installation for diagnosis. `graphs-equal` and `degree-rows` accepted a
Run but ended failed before publication (`ACTQL_E_UNPUBLISHED_RUN`). For
`graphs-equal`, the earlier isolated probe identified a missing selected
strategy revision; the `degree-rows` failure still needs the same diagnosis.
`graph-bounds` reached Run compilation and was rejected there.
`components` failed common Program preparation at the separately recorded
capacity application gap in that earlier probe; the newer fixed-SHA result is
recorded above. `reach-subgraph`, `diff-apply` and `mean-graphs`
were refused during preparation; their explicit edge-row ordering still
requires lawful evidence for the nullable `rel` field. These failures are not
successful Result evidence. The diagnostic response for some pre-Run failures
was conservatively surfaced as `SubmissionUnknown`; that public error
classification also needs review before these forms are declared supported.
After the Host owner added evidence-preserving cleanup, the same packed
Local/HTTP acceptance passed again at
`2cf73e88c602166fd29f1ada05322db16021b496` with the same five tarball
digests listed above. Its `summary.json` recorded all eight child commands as
successful and `artifactsRemoved: true`; stdout/stderr logs and digests were
retained while the temporary installation, npm cache, tarballs and Host Store
were removed. The evidence-helper tests separately passed for success,
nonzero exit, timeout and explicit artifact retention. This cleanup applies
to the passing `normalize-rows` acceptance, not to the earlier diagnostic
Store needed for unresolved SGA cases.

## Main integration and packed public-source evidence

The development integration branch merged `origin/main` at
`08052fd34f62472a39fa107e236afc6f59800e75`, including the public Host
source connection, without a source conflict. The tested commit is
`d14b53a9f167f7831be9eb82ff20d39519a7034d`. This is not a merge-ready
claim for all named SGA operations.

`node scripts/test-packed-public-query.mjs` installed the five packages into
a clean directory. The same application accepted five independently expected
SQL/Pipe queries through Embedded Local and HTTPS Remote, including duplicate
rows, NULL, an empty Result, typed and nullable parameters, request lookup,
attach, same-intent resubmission, a second reader, and a read limit. Six
syntax, declaration, value, alias and language refusals had zero new Run
acceptances and zero source reads. The named `normalize_graph` then
`node_rows` source returned `[{"id":"A"},{"id":"B"}]` in the declared
order through both Host profiles. The Node-free native CLI submitted the same
named source through the packed HTTPS Host and read the same Named Result.
Its binary digest was
`sha256:b735ac546176230bfa8d5daffa9e358fb51da64ad2664d0ab7117dcc1e1588e8`.
The driver records stdout, stderr, exit status, signal, elapsed time and
digests before deleting only its own installation, npm cache, tarballs and
Host Store. The separate evidence-helper success, nonzero and timeout tests
passed 6/6. The Frontend source tests passed 115/115, named SGA baseline
20/20, and common preparation 3/3 at this merged source.

| Packed artifact | SHA-256 |
| --- | --- |
| `client-wire` | `8e09005f4aac5063c1f6f8e4680dbb778a00e5c098126a85283e1f07685a76e5` |
| `sdk` | `1e4e83612b9c965388795f066be8cf24b0358feb46bd2335c8d98c36e83ed515` |
| `run-host-core` | `591cc67b13f69bb83220ab74264cf02f49ae0497d4dfc9031ea4b364d4155687` |
| `local-node` | `4864c6285892471b5d9c9fdf9fc3da423f7a1004986747d95c5a56ae808a2deb` |
| `node` | `c72364973dd1ed42faea32425632b314de037c9b92035c9f5ec35b875914f225` |

`node scripts/test-packed-public-query.mjs --probe-sga` then ran the seven
other independently authored fixtures through the same installed Local API.
It intentionally exited nonzero, preserved a per-command log and removed its
own installation. The failures are not silently excluded from SGA coverage:

| Fixture | Observed boundary | Next owner and file |
| --- | --- | --- |
| `graphs-equal`, `degree-rows` | Run accepted, then failed before publication with `ACTQL_E_UNPUBLISHED_RUN` | Physical strategy / Host dispatch: `src/physical_strategy/captured_dag.mbt` and `adapters/host-node/client-dispatch-owner.mjs`; confirm the precise dispatch cause for each. |
| `graph-bounds` | Run compilation rejected before acceptance | Host compilation/profile: `adapters/host-node/local-values-plan.mjs` and `src/run_publication_host/client_values_compilation.mbt`. |
| `components` | Common capacity preparation now passes; packed Run is accepted but ends before publication | Inspect the exact physical dispatch and publication cause; the public `ACTQL_E_UNPUBLISHED_RUN` status alone is insufficient. The Components Result and ceiling rejection remain unverified. |
| `reach-subgraph`, `diff-apply`, `mean-graphs` | Checked preparation rejected before acceptance | The prior source-level trace reached `UnresolvedOrder` for nullable `rel`; order-evidence owner should inspect `src/relation_evidence/sets.mbt` and the Result transformation boundary. The packed error does not itself expose that inner reason. |

For the preparation/compilation failures, the installed Local facade returned
`SubmissionUnknown` in some cases despite an apparent pre-Run failure.
`packages/client-wire/index.mjs` and Host submit error classification need an
exact acceptance-boundary check before any code is added to the typed refusal
set. Do not infer safe resubmission from this diagnostic. The current probe
covers Local only for these seven failures; their Remote success is untested.
The passed `normalize-rows` case has no public schema type/nullability/column
order observation, so publication-boundary tests retain that obligation.

## Nullable edge identity and current packed probe

At `9122707277fc2bb0ac2e61b75d51f73fe8ab31f1`, the existing Graph
edge identity `(src, dst, rel)` admits an explicit null label for canonical
ordering only when the key comes from an admitted `edge_rows` projection.
General nullable Relation keys and scalar identity remain ineligible. The
ordinary preparation test now passes for all eight authored SGA Programs;
the focused relation-evidence tests pass 20/20 on JS, Wasm and native. This is
checker evidence, not a claim that every Program executes.

The same source was packed and installed outside the repository. Raw SQL/Pipe,
`normalize_graph -> node_rows`, and native CLI Named Result acceptance passed.
The optional seven-case Local probe passed `mean-graphs` and failed the other
six; the driver exited nonzero as required. In particular, the nullable edge
fix moved `mean-graphs` through Result publication without dropping its
declared edge order. It did not change the other failures into success.

| Fixture | Current observed boundary |
| --- | --- |
| `mean-graphs` | Packed Local Named Results and independently authored rows pass. HTTP for this case is untested. |
| `graphs-equal`, `degree-rows`, `components` | Run accepted, then `ACTQL_E_UNPUBLISHED_RUN`. A direct captured-strategy probe identified `Dispatch(NoStrategy)` before Compute for these fused Graph tasks; no Compute completion is claimed. |
| `reach-subgraph`, `diff-apply`, `graph-bounds` | Packed submit returns `SubmissionUnknown` with nested `RunHostCompilationRejected`. The direct common task compiler returns `ClientResultPlanPartsIssue::Root(RequiresResultTransformation)`; Result publication never begins. |

The physical strategy currently leaves fused Values/Graph/SGA tasks without an
installed strategy for `Components`, `Degree`, `GraphsEqual`, and `GraphBounds`.
Splitting a task at the last Graph operation alone does not make the fused
prefix executable; the bounded provider and task boundary need to agree.
This remains an execution-owner interface question, not a reason to invent a
Frontend executor or weaken the checked Result root. The separate Result-root
failures need the checked producer task and Result occurrence to agree before
the existing transformation is selected. The direct-root refusal must remain.

The packed probe log and tarball digests are under
`worktrees/.codex-scratch/public-query-evidence-1Eo3Mr`. Its generated
installation and Store were removed after failure. An earlier attempt at the
same source stopped before packing the Run Host because `moon` was absent from
the process PATH; it is not counted as product validation. The packed tarball
digests for the completed probe were `client-wire`
`8e09005f4aac5063c1f6f8e4680dbb778a00e5c098126a85283e1f07685a76e5`,
`sdk` `1e4e83612b9c965388795f066be8cf24b0358feb46bd2335c8d98c36e83ed515`,
`run-host-core`
`fec8e83f944e8720d7238d59e1077fafa6ae21397d92a138d027fd8c9d61b8d8`,
`local-node` `cd2bc6a378e8a650d9b17fe3aa221bcf5ba1cbc4ec22a6a5a0c84bfa157e9ec1`,
and `node` `c72364973dd1ed42faea32425632b314de037c9b92035c9f5ec35b875914f225`.

## Intermediate Result tasks and the Graph provider handoff

At `f44c96f2ffac8bb640502214c5a9fb5322feaf21`, Stage-zero
Values-to-Graph segmentation also considers a Result bound to an intermediate
checked Step. It still splits only if every selected Step has an installed
bounded execution candidate and its input handoff is supported. A GraphDiff
Program with an intermediate `changes` Result and a later `selected` Result
now compiles into two tasks: `task_0.graph_diff_6` is the first Result and
the sole input to `task_1.select_7`, which is the second Result. The source
Graph construction occurs only in `task_0`. This does not turn an unsupported
Graph operation into an executable candidate or remove Result-root checks.
The focused checker/Plan test passed 4/4; physical-strategy tests passed
24/24 on JS, Wasm and native.

The committed packed installation at this SHA passed five SQL/Pipe cases,
`normalize_graph -> node_rows`, and `mean_graphs -> node_rows/edge_rows`
through both Embedded Local and HTTPS Remote, each with independently authored
Named Result rows. The Node-free native CLI passed the existing Graph source
case. The evidence is in
`worktrees/.codex-scratch/public-query-evidence-tPfLjQ`; its generated
installation and Store were removed. The package digests were `client-wire`
`8e09005f4aac5063c1f6f8e4680dbb778a00e5c098126a85283e1f07685a76e5`,
`sdk` `1e4e83612b9c965388795f066be8cf24b0358feb46bd2335c8d98c36e83ed515`,
`run-host-core` `0df5cbfc86bf98c7755b0e794dbc5aae83329276e5cfe67bb0de2a04a2361d51`,
`local-node` `dd9ab67a3694d6bd36256d4d628456ade3bb6bf39312376e1faa434e7d55b407`,
and `node` `c72364973dd1ed42faea32425632b314de037c9b92035c9f5ec35b875914f225`.

The Graph provider owner retains `src/local_sga_provider/graph_pipeline.mbt`
and the matching capability declarations in
`src/lowering_relation/semantic_ports.mbt`. The packed counterexamples for
that owner are the six nonpassing fixtures under
`spec/frontend/fixtures/sga-surface`:

| Fixture | Required existing operation shape | Last verified failure |
| --- | --- | --- |
| `graphs-equal` | Two constructed Graph inputs to `SGA.equal`; one boolean Relation output | Fused source-free task: `Dispatch(NoStrategy)` before Compute. |
| `degree-rows` | Constructed Graph to `SGA.degree_metrics`; Relation output | Fused source-free task: `Dispatch(NoStrategy)` before Compute. |
| `components` | Constructed Graph to `SGA.components`; Relation output, with both checked capacity claims | Fused source-free task: `Dispatch(NoStrategy)` before Compute. |
| `graph-bounds` | Constructed Graph to two checked `SGA.bounds_check` occurrences and two separate Results | One fused task cannot expose the first Result; task compiler rejects `RequiresResultTransformation`. The selected Graph-boundary capability still needs provider evidence. |
| `reach-subgraph` | Graph to `SGA.reachable` Relation, then Graph `SGA.subgraph`, then separate node/edge projections | One fused task cannot expose both intermediate outputs; task compiler rejects `RequiresResultTransformation`. Exact Graph and Relation handoffs need installed candidates. |
| `diff-apply` | Two Graphs to `SGA.diff`, followed by `SGA.apply_delta` and separate node/edge projections | Same Result-root rejection; Graph/Delta handoffs need installed candidates. |

The final three fixtures above passed common preparation after the nullable
edge identity fix, but that is not runtime success. The provider owner should
use the exact checked operation inputs and bounded managed view, retain each
output required by another task or Result, and avoid retrying a failed fused
task as a second compute path. Frontend acceptance will merge a committed
provider SHA and rerun the same packed Local/HTTP Named Result fixtures.

At `12fb12ff686179591e191f92160d10eb2782e673`, the full Core JS job
passed 7,021/7,021 tests. The nullable Graph edge ordering change also passed
the existing two-consumer publication test with an independently calculated
logical Relation CID for the declared four Result fields in canonical order.
The same fixed source passed packed SQL/Pipe, `normalize-rows`, and
`mean-graphs` Named Results on Embedded Local and HTTPS Remote, plus the
Node-free native CLI. The optional six-case Local probe still failed all six
cases and therefore exited nonzero. `graphs-equal`, `degree-rows`, and
`components` were accepted then ended before publication; `graph-bounds`,
`reach-subgraph`, and `diff-apply` were rejected during Run compilation.
The common task compiler still forms one task for each of the latter three
fixtures, since their full selected operation chains lack installed bounded
candidate support. The B-owned intermediate-Result task split is verified in
isolation with a fully selected GraphDiff/Select chain; it cannot substitute
for the provider capabilities owned by A. The probe logs and tarball digests
are in `worktrees/.codex-scratch/public-query-evidence-NWjb0m`; the generated
installation and Store were removed. This is not a full SGA acceptance claim.

## Additional packed Graph acceptance

At `ce57ad870b8b636c14748b080bc49a2fb3505fe3`, the standard packed
acceptance passed four independently authored SGA source cases through both
Embedded Local and HTTPS Remote: `normalize-rows`, `mean-graphs`,
`traverse-paths`, and `union-graphs`. Each used the public `aql-text` submit
path and read its declared Named Result to normal termination. The
`union-graphs` fixture constructs two different Graphs with a shared node,
then checks the ordered node and edge Results against independently written
expectations. `traverse-paths` checks the path node and edge identities. The
same run passed the SQL/Pipe cases and Node-free native CLI Graph Result.
The driver saved logs and digests, then removed its own installation and
Store. Its evidence is under
`worktrees/.codex-scratch/public-query-evidence-L2F84n`.

| Packed artifact | SHA-256 |
| --- | --- |
| `client-wire` | `8e09005f4aac5063c1f6f8e4680dbb778a00e5c098126a85283e1f07685a76e5` |
| `sdk` | `1e4e83612b9c965388795f066be8cf24b0358feb46bd2335c8d98c36e83ed515` |
| `run-host-core` | `57a2e01e1aaf206af241ab38afcdbfcc34c50418c90ee929225e314b6e6b7a0e` |
| `local-node` | `88ec0e4559ada881959681baa872f60c26d828a15b0608346ff7a5106c39a54e` |
| `node` | `c72364973dd1ed42faea32425632b314de037c9b92035c9f5ec35b875914f225` |

The optional packed Local probe at the preceding source
`9965f0d625c0ecfc13ad95807122857050fdfb62` also passed `union-graphs`,
but intentionally exited nonzero because the six cases in the provider
handoff table still failed. The terminal Graph-to-Relation task segmentation
in `229b00814f6500724ed8427ceb89bb0e4649d5ae` passed its focused
checker/Plan test and physical-strategy tests on JS, Wasm, and native. It
requires installed bounded candidates for every checked step, so the six
remaining cases are not claimed as product acceptance.

At `30768aabb7c734643d3176075ace6681d80a5bb0`, `graft-graphs`
joined the standard packed acceptance after passing the optional Local probe
at `f7062b0c475916076e2a44d7388eb61c9940daa9`. Its checked source
uses add-only graft with an identity-equal shared B node, then reads ordered
node and edge Results against independently authored values. The same packed
Local and HTTPS Remote run passed the four earlier SGA cases, SQL/Pipe cases,
and the Node-free native CLI Result. Its evidence is under
`worktrees/.codex-scratch/public-query-evidence-LgGiKY`; generated artifacts
were removed. The package digests match the preceding `ce57ad870` run.
The optional probe still failed the six provider-handoff fixtures, so this
does not establish complete SGA execution coverage.

The earlier pushed `a58fdc5d4b9db30f1c3d5a15148d0b26e72d19ff`
failed Linux `connector-addition` and `duckdb-node` in CI run
`36600655406`. Both jobs reached the same standard Host test: it expected a
fixed row order from an `edge_rows` projection without an authored order.
The `62e4301e5` test correction compares the projected edge rows as a
multiset, preserving their values and multiplicity; cases with an authored
sort retain exact order comparison. The focused standard native/broad Host
test passed 1/1 locally after this correction. The later
`747acd6b04daf29f62f775ef2dd63fb023b7a49a` completed Linux CI run
`36644881348` successfully, including both affected jobs. The performance
matrix and optional six-case probe were skipped by configuration.

At `3beaf1e9031c1d41cef6dd8ae95553e617637240`, the standard packed
acceptance added `subtract-graphs`. Its independently authored base has
A, B, C and D and the A-to-B, B-to-C and C-to-D edges; the removal Graph has
C, D and C-to-D. The expected Results contain A, B and A-to-B. B-to-C must
disappear by endpoint closure even though it is absent from the removal
Graph. The named source matched the independently authored Program and
ordinary preparation admitted it. The fixed-SHA Client job passed packed
Embedded Local and HTTPS Remote Named Result reads for this and the five
previous SGA cases, SQL/Pipe, native CLI, and its other Client regressions.
The retained evidence is
`worktrees/.codex-scratch/public-query-evidence-FXK9iM/summary.json`;
the generated installation and Store were removed. Its package digests
match the table above because only fixtures and acceptance scripts changed.
This adds one supported structural operation; the six original provider
handoff cases remain unaccepted.

## Current main integration and three-case provider handoff

The integration branch merged `origin/main` at
`7bb612ff113946df43bcab05ffd383a7379ce71b`. The clean packed
acceptance at `14b108bc2d4af771cce116e1021ae482dd4d3030` passed the
following named-source cases through both installed Embedded Local and HTTPS
Remote: `normalize-rows`, `mean-graphs`, `traverse-paths`, `union-graphs`,
`graft-graphs`, `subtract-graphs`, `degree-rows`, `components`,
`graph-bounds`, and `match-projections`. Each read its independently authored
Named Result to normal termination. The same driver passed raw SQL/Pipe and
the Node-free native CLI's representative SGA Result. The driver records
`status: passed` in
`worktrees/.codex-scratch/public-query-evidence-wA0PFq/summary.json`.
The same evidence directory retains `planning.jsonl`, three `named-*.log`
and three `json-*.log` counterexamples. Its temporary package installation,
npm cache and Run Stores were reclaimed after those probes; `cleanup.json`
records that separate cleanup because the driver used `--keep-artifacts` for
direct JSON replay.
Its installed tarball digests are:

| Package | SHA-256 |
| --- | --- |
| `client-wire` | `8e09005f4aac5063c1f6f8e4680dbb778a00e5c098126a85283e1f07685a76e5` |
| `sdk` | `1e4e83612b9c965388795f066be8cf24b0358feb46bd2335c8d98c36e83ed515` |
| `run-host-core` | `6de98d41935134939a567807f55da7e10ed03472b473812eb01f372c6cc35e46` |
| `local-node` | `e7478495c39ac9dcbd6cf1a9625d993c13493da4dbc2744c70be5eb387611088` |
| `node` | `c72364973dd1ed42faea32425632b314de037c9b92035c9f5ec35b875914f225` |

The original eight-case SGA acceptance set now has five passing cases and
three open cases. This supersedes the six-case historical table above. For
each open case, `scripts/sga-surface-baseline.test.mjs` proves that the named
source matches the separate `*.expected-program.json`; the ordinary common
checker admits that Program in `scripts/sga-surface-checker.test.mjs`.
`node scripts/diagnose-sga-provider-handoff.mjs` prints the checked task
pipeline and common compiler result. The independently authored
`*.expected-results.json` files state the required rows and schemas.

| Source and expected Program | Required output | Checked task and failure on packed Local | Direct JSON Program without Frontend |
| --- | --- | --- | --- |
| `graphs-equal` | `answer = [{"equal":true}]` | One task ends in `SGA.equal(Graph, Graph) -> Relation`. The common task compiler succeeds. The Run is accepted, then fails before publication with `ACTQL_E_UNPUBLISHED_RUN`. An earlier captured-strategy probe returned `Dispatch(NoStrategy)` before Compute. | Same accepted-then-failed state. |
| `reach-subgraph` | `nodes = A,B`; `edges = A -> B` with null `rel` | One fused task contains `SGA.reachable(Graph) -> Relation`, `SGA.subgraph(Graph, Relation) -> Graph`, then separate node/edge projections. The task compiler returns `Plan(TaskGraph(Root(Root(RequiresResultTransformation))))`; public submit exposes nested `RunHostCompilationRejected` inside `SubmissionUnknown`. | Same compiler refusal and public codes. |
| `diff-apply` | `nodes = A,B,C`; `edges = A -> B, B -> C` with null `rel` | One fused task contains `SGA.diff(Graph, Graph) -> Delta Relation`, `SGA.apply_delta(Graph, Delta Relation) -> Graph`, then separate node/edge projections. It returns the same common compiler issue and public codes. | Same compiler refusal and public codes. |

The exact minimal sources, Programs, schemas and rows are the three named
fixture pairs under `spec/frontend/fixtures/sga-surface`. The generated AoA
uses the registered operation strings and typed input order; it does not
rename `SGA.equal` or substitute a different operation. The Graph provider
accepts `SGA.equal` in its terminal fused-sequence branch but its selected
step branch currently rejects `GraphRelationStep`. The observed `NoStrategy`
is therefore a physical selection/provider gap, not a Frontend spelling
mismatch. The provider owner should confirm the selected-step shape and add
only the bounded candidate and owned input handoff that satisfy the existing
Graph equality contract. The two Graph/Relation/Delta chains need installed
candidate boundaries that retain each Result producer; the Frontend must not
remove Result roots, drop order, or retry the fused task as another Compute.

Reproduce after `npm run build:runtime-packages -- local-node` with:

```sh
node --test scripts/sga-surface-baseline.test.mjs scripts/sga-surface-checker.test.mjs
node scripts/diagnose-sga-provider-handoff.mjs
node scripts/test-packed-public-query.mjs --keep-artifacts
ACTQL_LOCAL_STATE_DIR=<fresh-directory> node scripts/reproduce-sga-baseline.mjs <packed-installation> --graphs-equal
ACTQL_LOCAL_STATE_DIR=<fresh-directory> node scripts/reproduce-sga-baseline.mjs <packed-installation>
ACTQL_LOCAL_STATE_DIR=<fresh-directory> node scripts/reproduce-sga-baseline.mjs <packed-installation> --diff-apply
```

The latter three commands submit the authored JSON Program directly through
the installed standard Client, with no Frontend parse/lower path. The
equivalent named-source commands use
`scripts/accept-sga-public-source.mjs <packed-installation>
<fixture-directory> local <case-name>`. The nonzero result is a reproduced
failure, not a passing acceptance. At
`76c97eb2c2f4d5a5ef8f12c5f834e0db3209498a`, the Core JS, Wasm and
native jobs passed 7,027/7,027, 7,024/7,024 and 7,086/7,086 respectively.
The later source changes only reproduction scripts and this evidence. These
common-kernel gates do not prove the three pending packed product paths.

## Current main integration and packed acceptance

The previous three-case handoff describes the source before the Graph path
query changes in main. This section supersedes its pending-case count. Main
`89991451cb5da3c4ecfe93bbca26aaa4395e009a` was merged without replacing
Frontend changes. Its Reach implementation initially failed to compile
because the retained and ordinary execution views passed each other's start
binding. Commit `4491db39869dd2b0536181223073ac6d7d08d86e` shares the existing
checked selector resolver between those views; it does not add a Reach
contract. Local SGA JS tests passed 59/59, including the selected Graph view
and Relation selector tests.

At `8aa414c4ee90aa6247a7e49b4383b7b82e9d7be9`, a clean installation of
five packed packages ran eleven named SGA sources through Embedded Local and
HTTPS Remote, including `reach-subgraph`. Each source reached its authored
Named Results and independently authored rows; the native CLI also passed its
representative SGA Result. The original eight-case acceptance set has six
passing cases and two remaining cases. The public Result API does not expose
schema type, nullability, or field order, so those properties are not claimed
as packed Result evidence. The exact command was
`node scripts/test-packed-public-query.mjs` with the pinned MoonBit toolchain.
Evidence is in `worktrees/.codex-scratch/public-query-evidence-ecITw8/summary.json`.
The run removed its installed packages, cache, and Stores after preserving logs.

| Package | SHA-256 of packed tarball |
| --- | --- |
| `client-wire` | `8e09005f4aac5063c1f6f8e4680dbb778a00e5c098126a85283e1f07685a76e5` |
| `sdk` | `1e4e83612b9c965388795f066be8cf24b0358feb46bd2335c8d98c36e83ed515` |
| `run-host-core` | `b20244d639f9fb51f0a402ce79dcf2c3f6e122963caae063d19d1c97bb0a4a03` |
| `local-node` | `6a350e411ec0d5f8b3ad650f0597e8910ac3d0f6df6c1afe6998660dc58cebac` |
| `node` | `c72364973dd1ed42faea32425632b314de037c9b92035c9f5ec35b875914f225` |

At `4491db39869dd2b0536181223073ac6d7d08d86e`, the optional packed
Local probe passed `reach-subgraph` and reproduced failures for the other two
cases. The change from that SHA to the accepted SHA only promotes the passing
case into mandatory Local/HTTP acceptance. The two remaining failures are:

| Case | Checked task and public failure | Required owner work |
| --- | --- | --- |
| `graphs-equal` | A fused `SGA.equal(Graph, Graph) -> Relation` task compiles, but the accepted Run ends as `ACTQL_E_UNPUBLISHED_RUN`; the prior captured strategy trace shows `Dispatch(NoStrategy)` before Compute. | A: select a bounded Graph Relation provider for the existing checked task without changing the Frontend operation. |
| `diff-apply` | A fused `SGA.diff` Delta Relation, `SGA.apply_delta` Graph, and node/edge projections still returns `Plan(TaskGraph(Root(Root(RequiresResultTransformation))))`; public submit reports nested `RunHostCompilationRejected`. | A: retain the typed Graph/Delta handoffs and Result producers in physical tasks without silently dropping Result roots or order. |

Both sources match independently authored Programs, pass common preparation,
and have independently authored expected Results. The direct JSON replay in
the earlier evidence fails after the Frontend boundary as well. A's fixed SHA
must be merged into this integration branch, then both named sources must pass
the same external packed Embedded Local and HTTP acceptance. Until then PR #63
remains Draft. The Frontend must not add a second execution path or silently
weaken these expectations.
