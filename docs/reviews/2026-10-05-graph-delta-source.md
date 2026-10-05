# Property Graph Delta source connection

Status: frontend connection implemented; successful text Delta execution is
pending the separately approved generic JSON literal dependency. This is not
completion of the Property Graph migration or the full frontend profile.

Fixed base: `7e337afa9e5a64035c5925aca1d93ba0ef787aaf` (main, including
#428, #431 and #442). The common application contract is documented in
[Property Graph Delta application](2026-10-05-property-graph-delta-application.md).

## Meaning and ownership

The existing named-operation syntax accepts
`FROM g |> apply_graph_delta(with: changes, field: 'delta')`.
The pipe receiver supplies the Graph input; `with` is a previously declared
Relation producer reference and `field` is a column-name string. The frontend
retains the admitted Graph definition and identity domain for subsequent DATA,
MATCH, node_rows and edge_rows use. It does not acquire, persist or apply a Delta
itself, change any wire contract, or use a legacy Graph conversion.

The new lowering helper emits the existing `apply_graph_delta` Program operation
and reuses the shared named-argument and producer resolver. The common checker
owns field presence and its non-null JSON type. The common execution owner owns
the single-row requirement, closed Delta shape, exact base/before/target checks,
capacity and cleanup. Malformed bodies are not accepted merely because their
column has JSON type.

Both Graph-prefix call sites are connected: DATA/MATCH prefixes and Graph-to-
Relation prefixes. A Graph operation after a Relation transition remains
unsupported, and string-valued producer references are not guessed as names.

## Independent evidence

- Before the change, focused JS run `run-ZJfvUc` passed the independently
  authored complete JSON Program check and rejected its source equivalent with
  `UnsupportedGraph` (1/2 tests).
- After the change, focused JS run `run-hRAD7Z` passed 5/5 tests: complete
  expected Program, ordinary checker, quoted DATA and MATCH continuation,
  common argument refusal, and exact scope/Carrier diagnostics.
- Existing Graph rows and Subgraph caller tests passed 11/11 in JS run
  `run-ghnOFn`. Node syntax checks and independent fixture loading also passed.
- The public fixture reuses the common owner's independently authored valid
  Delta application Program and expected node/edge rows. These are machine-input
  controls, not evidence of successful text Delta generation.
- Two text cases supply a typed identity JSON as an intentionally malformed
  Delta. They test semantic execution refusal. Seven text cases test preparation
  refusal and zero durable Run acceptance/provider I/O. Neither group is a
  successful text Delta acceptance test.

Focused command (pinned MoonBit/Node PATH):

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 120 -- \
  --target js src/query_program --filter '*Graph Delta source*'
```

Packed evidence will record the clean source SHA, normal-pack manifest/digests,
Local/HTTPS results and logs separately. No CI success is asserted here.

The first packed run (`run-SZmSsj`, source
`2b88e0c23fc3de86ef29c0f0ce4eca6ca2ca2bb0`) passed both JSON controls and
both semantic execution refusals in Local, then failed the aggregate Source-I/O
assertion before HTTPS. The source-free execution-refusal fixtures had omitted
their zero-read count, so the harness expected one external read per case.
That fixture accounting is corrected; rows, contracts and refusal expectations
are unchanged. This run is not full public acceptance evidence.

## Separate JSON literal dependency

Normal source execution needs an ordinary JSON-producing expression. The common
parameter contract has no untyped JSON parameter, and the existing managed
DuckDB transfer profile only supports DOUBLE/VARCHAR. A Delta-only literal,
provider adapter or post-lowering Program mutation would hide that gap.

The approved follow-up is GoogleSQL `SELECT JSON '…' AS delta`, available in
ordinary SELECT and DATA queries. Before implementation it must establish
number precision, duplicate-key handling, JSON null versus SQL NULL, bytes/depth
limits and independent machine-input equivalence. Successful authored source
through `apply_graph_delta` to Named Result in packed Local/HTTPS is a required
integration acceptance after that dependency lands. It is not claimed by this
connection PR.
