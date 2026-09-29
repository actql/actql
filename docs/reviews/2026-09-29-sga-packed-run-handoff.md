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
`components` additionally needs its existing capacity application, and the
edge-row fixtures need lawful order evidence for nullable edge identity.
The Client job now includes `scripts/sga-surface-checker.test.mjs` at the
common preparation boundary. It rejects a Relation chained into
`normalize_graph` and an unbounded `graph_bounds` call before Run acceptance.

For the Components fixture, the exact shared gap is in
`pipeline_check_context::derive_program_capacity`: it derives Host-owned
engine-atomic applications for Join and Traverse/Reach, but no corresponding
Components consumer. `capacity_program_step::check_components_applications`
therefore returns `MissingApplication` for the checked Components step. The
existing contract requires two distinct applications:
`actql.bound.components-input-nodes` in nodes from the retained Graph producer,
and `actql.bound.components-nodes` in output rows under
`max_graph_output_rows`. The Compute/capacity owner should supply them through
that common builder with the checked producer and policy; the Frontend must
not issue substitute claims or raise ceilings. The acceptance fixture then
needs normal preparation, packed Result rows and a ceiling rejection.

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

`scripts/accept-sga-public-source.mjs` is the pending packed acceptance
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
tests must verify those schema properties separately. The script is not a passing test or a
claim of public source support until the Host connection and physical
strategy selection are fixed and both modes complete.

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
capacity application gap. `reach-subgraph`, `diff-apply` and `mean-graphs`
were refused during preparation; their explicit edge-row ordering still
requires lawful evidence for the nullable `rel` field. These failures are not
successful Result evidence. The diagnostic response for some pre-Run failures
was conservatively surfaced as `SubmissionUnknown`; that public error
classification also needs review before these forms are declared supported.
The packed test driver still retains its installation on success; the Host
owner has a separate cleanup and failure-log fix to apply before this is a
routine acceptance gate.
