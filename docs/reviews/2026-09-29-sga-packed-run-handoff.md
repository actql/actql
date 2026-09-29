# SGA source and packed Run handoff

The Frontend branch owns named SGA syntax and, after the public Host source
connection is adopted, packed Local and HTTP acceptance. The Host connection
owner retains the shared submit, planning, dispatch and publication files.
This record separates checks that ran from the product acceptance still needed.

At source `5acb8f04d659f67f9a1e6a60a25c3003830abdb4`, independently
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
that the Graph kernels failed. The public status does not expose the internal
cause, so ownership of the underlying fix remains to be established at the
Host-to-kernel boundary.

`scripts/reproduce-sga-baseline.mjs <packed-installation> --graphs-equal`
replays the exact authored Program and reports public status and terminal error
code. It uses the installed package with a fresh `ACTQL_LOCAL_STATE_DIR` and
the packed test source profile through `ACTQL_LOCAL_SOURCE_PROFILE`. A failing
diagnostic is not an acceptance test. The existing reach/subgraph mode remains
available, including its explicit Result order.

After the Host source connection has a committed SHA, the Frontend owner will
submit named source through the installed SDK using `format: "aql-text"`,
then read Named Results through packed Local and HTTP. Acceptance must compare
independent schema, rows and declared order for representative Graph-to-Graph,
Graph-to-Relation and Delta chains. The existing client request, cancellation,
authorization and Result delivery semantics remain owned by the common Host.
