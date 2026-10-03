# Resident Source acquisition

The resident Site executes a checked acquisition task with the existing native
DuckDB acquisition owner and the standard remote runtime. Its initial installed
profile supports one read-only Source, one checked task and one named Result.
Other checked shapes require their dispatch and retained-input edges to be
installed; sharing a Site does not combine those tasks.

The Program and Run materials contain logical Source references. The Site
operator supplies `--source-ref`, `--source-contract-cid`, `--source-database`,
`--source-schema`, `--source-table` and `--duckdb-library`. All six settings are
required together. The Site checks the original Program's admitted Source and
the exact logical input binding before accepting dispatch. Physical database
opening happens only after the existing exclusive start claim, current lifetime
check and executor-entry observation. DuckDB opens the configured database
read-only with external access disabled.

The engine root contains the pinned `registry.json`, `values.json` and
`fragment.json`, plus the installed acquisition contracts `query-contract.json`,
`query-evidence-contract.json` and `query-two-receipt-contract.json`. The
expression-fragment contract admits the same filter/select sequence used by the
existing Local query-requirement owner. These files and the physical mapping
are operator configuration, never dispatch authority.

Run materials reuse the bounded materials codec and reconstruct the original
checked compilation, authorization, Run identity and lifetime. Source-free
Values keeps its existing compilation. Both enter the same resident admission,
start, Output, transfer and release lifecycle.

The live acquisition owner issues the captured input's logical identity and
Source evidence. A bounded `actql-remote-source-observation/0.1` binds their
original wires and capture interval to the dispatch, Run and task ordinal. It
is persisted atomically with the native managed Output observation and retained
with the Coordinator's first completed Output. Exact replay preserves its
bytes; another observation cannot replace it. Source-free observations omit
the optional member.

This transport observation is a candidate for publication, not read authority.
The receiving Host derives the expected Source and policy from the original
checked Catalog, verifies the dispatch's Run/task binding, rechecks current
authorization, and uses the existing completed-observation and task Invocation
owners. Neither authenticated transport nor a matching CID permits another
acquisition. Result schema and projection come from the checked Result port;
an additional publication Plan node is not an additional physical task.

The standard runtime retains the acquired input and its cleanup owner through
Output export and formal release. A failed export releases its pins; pending
payload cleanup retains capacity until physical deletion is confirmed. Export
cancellation uses the existing captured-input owner. Durable outbound
cancellation and restart guarantees remain separate contracts.
