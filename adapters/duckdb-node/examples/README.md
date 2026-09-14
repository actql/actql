# Checked serial strategy example

This runnable source-checkout application accepts user-owned Program, Parameter,
Check Environment and local database files. It uses the public checker and the
standard Node Host; it never imports conformance exports, test catalogs or test
fixtures. It is not a formal Program/Run runner or permission to publish partial
Program results.

## Build and run

Use the repository's pinned MoonBit toolchain on `PATH` and install the pinned
Node dependencies as described in the [adapter guide](../README.md). From the
repository root:

```sh
moon build --target js --release src/duckdb_host_node
moon build --target js --release src/physical_strategy_example
node adapters/duckdb-node/examples/physical-strategy.mjs \
  --database /absolute/path/to/trusted.duckdb \
  --environment /absolute/path/to/check-environment.json \
  --environment-cid sha256:YOUR_EXPECTED_ENVIRONMENT_CID \
  --program adapters/duckdb-node/examples/program.json \
  --parameters adapters/duckdb-node/examples/parameters.json \
  --schema main --table records --native-ms 5
```

Supply a valid Check Environment matching your Program. The supplied Program
references `crm/main` resource `r`; change that reference to your declared
SourceView if necessary. This example requires one checkpoint-free snapshot
acquisition followed by the three filter/select Compute stages shown in the
Program. Their imported visits are explicitly bounded as `[1,2,2,3]`; it is not
a general arbitrary-Program setup frontend. The source must declare `id` as a
non-null number; all other known columns are also validated. The selected real
table and declared schema must match. The example does not create a source DB,
generate a Catalog, grant access based on Program text, or repair an invalid file.
The path is an explicit Host binding to a trusted existing file opened read-only.

Limits are deliberately small: 100 rows per configured boundary, ten columns,
100000 transport bytes per attempt, 400000 cumulative transfer bytes, 200000000
retention-envelope bytes and 268435456 execution-envelope bytes. See the explicit
application limits in `src/physical_strategy_example/host_limits.mbt`. Native
validation and query receipts both count; 100 source rows plus native result
rows may exceed the combined receipt limit. Limits are not optimizer estimates.

`--native-ms` is a supplied estimate for the whole native work bundle, including
setup, both transfers, conversions, computation, retention and cleanup. It is
not a DuckDB benchmark. Local estimates are `1 + 2 * input_rows` milliseconds.
The example forecasts no row reduction until a completed producer supplies an
actual row count. Comparing `--native-ms 1` with `--native-ms 20` illustrates
placement choices without changing Program meaning or its capture boundary.
For source ids `[3,1,2,3]` and minimum 1, the supplied model at 5 selects native
A/B and, after A completes, Local C. These numbers illustrate the mechanism,
not recommended production cost coefficients.
Static unsupported native expressions are excluded before comparison. For example,
changing A's filter to `id + 0 > 2` keeps A on Local even with `--native-ms 1`;
the report's `excluded_realizations` records `unsupported_predicate`. This is
candidate eligibility, not retry after a failed DuckDB execution.

The JSON report contains internal task status, realization choices, bounded
diagnostic output CIDs, selection/rejection explanations, remaining estimated
cost and cumulative physical ledger. `program_success` remains false even when
every internal task succeeds. The report's ledger is captured before closing
retained result handles, not a claim that those allocations were already freed.

The imported `runExample(options)` API returns `capture` and `execution` handles
plus `close()`. The caller owns them and any original failure's pending
`cleanupHandle`. The CLI closes its retained results and attempts pending cleanup
once; it never retries computation. Pending cleanup is reported, never counted
as confirmed release or durable recovery. Cancelling the imported API accepts
an `AbortSignal`. Completed-input sharing is process-local; no resident DuckDB
sharing, streaming, automatic failed-query retry or remote replay is provided.

## Adopted execution contracts

The row engine still selects its adopted registry, REL.values and fragment pins.
The current main specification includes a newer REL.values resource-scope
contract; this example does not silently claim that newer engine support.
`../contracts/adopted-relation.json` packages the exact previously published
bodies from revision `aa3c7a3e047144b8823ec59ae86dfdaeb76b4d74`, with their CIDs.
These are contract material, not test outputs or a compatibility implementation.
The existing product admission verifies the bodies against its unchanged pins.
Current Query Acquisition/process-evidence/two-receipt contracts are loaded from
their repository-owned files. Updating engine contract support is separate from
this example; neither pins nor shared semantics are rewritten here.
