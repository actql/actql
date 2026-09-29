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
packed probe failed
at `Dispatch(NoStrategy)`. These are separate blockers. The other authored
fixtures still require their exact checker and packed execution evidence;
`components` additionally needs its existing capacity application, and the
edge-row fixtures need lawful order evidence for nullable edge identity.

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
