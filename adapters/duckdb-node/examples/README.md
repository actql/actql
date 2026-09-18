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
moon build --target js --release src/connectors/duckdb/host_node
moon build --target js --release src/connectors_builtin_node
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
SourceView if necessary. This example supports one checkpoint-free snapshot
acquisition followed by three filter/select Compute stages (`program.json`),
or four Compute stages: two branches, inner join, then group/count
(`join-count.json`). Their imported visits are explicitly bounded as `[1,2,2,3]`
and `[1,2,2,5,6]`; this application is not a general arbitrary-Program setup
frontend. The source must declare `id` as a
non-null number; all other known columns are also validated. The selected real
table and declared schema must match. The example does not create a source DB,
generate a Catalog, grant access based on Program text, or repair an invalid file.
The path is an explicit Host binding to a trusted existing file opened read-only.

`prepareExampleText` exposes the same application preparation over bounded text
documents. Its returned `open(signal)` performs source authorization/acquisition
and creates the standard strategy setup; preparing alone does not touch the DB.
The fixed `managed-worker.mjs` assembly uses this entrance with the common Node
`serveManagedStrategy` protocol. It is launched with the dedicated IPC descriptor
by trusted Host wiring, not as a standalone CLI or a request-selected plugin.
Its `prepare`, `execute` and `release` messages keep the owned MoonBit setup in one
process and return diagnostics only. Local and DuckDB task execution still uses
the standard Host. A report's CIDs are not retained-result admission or proof of
recovery after process loss. The real-DuckDB conformance suite also runs this
assembly with independent result expectations and checks process reuse/isolation.

Trusted application wiring can pass an `installCompletionObserver` token as
the second argument to `runExample` (fourth argument to `runCapturedStrategy`).
It observes exact common-completed outputs, not connector diagnostic values.
It cannot replace verification or authorize completion, and it is not a JSON
Program/CLI option. Delivery failure stops unstarted tasks while retaining the
completed result and any unconfirmed delivery cleanup responsibility. Inspecting
a retained completion descriptor is not permission to reopen it in another
process.

This managed assembly requires `createManagedProcessHost.start` capacity with
`childLimits`. For the default small profile, supply planning work 100000,
attempts 10, holdings 10, transfer bytes `500000n`, retained bytes `200000000n`
and execution bytes `268435456n` using the ledger's snake-case field names.
The enclosing `retainedBytes` and `executionBytes` must be at least the two
child byte limits. Parent cumulative quotas must cover the delegated allowance
plus one provisioning attempt. Limits are snapshotted in the startup handshake;
the child creates the actual acquisition/task ledger from them. Lower limits
are allowed but can reject a candidate or execution. Usage is reconciled into
the parent independently of diagnostic replies; an unknown exit conservatively
consumes unreported quota. These are admission budgets, not OS RSS guarantees.

### Managed execution process

`managed-host.mjs` exports `createManagedExampleHost(limits)`. It uses the same
checked application and standard Connector assembly as the in-process example,
but acquisition, Compute, content validation and CID generation run in the fixed
`managed-worker.mjs` child. The controller receives bounded reports and retains
completion custody, not result rows.

Create one controller for a cumulative budget, then call
`controller.run(input, {run, childLimits}, signal)`. `input` is the text-based
configuration accepted by `prepareExampleText`, including explicit
`retainedOutput`, `retainedWorkMilliseconds`, and
`localImportWorkMilliseconds`; the controller installs `controlStore` itself.
The limits contain `planning_work`, `attempts`, `holdings`, and BigInt
`transfer_bytes`, `retained_bytes`, `execution_bytes`. Parent capacity must cover
the child delegation and process provisioning. Without an explicit data profile,
the bounded example limits inputs to 100 rows.

The text-based entrance also accepts a closed `dataProfile` object with positive
integer `source_rows`, `task_rows`, `columns`, `value_bytes`, `wire_bytes`,
`value_nodes`, `text_bytes`, `work`, `entries`, and `batch_bytes`. The source scan
and intermediate Compute row ceilings are distinct. Physical acquisition receipt
capacity spans validation plus output, without resetting its counters.
`wire_bytes` bounds one retained representation. Acquisition's shared measurement
and receipt identity budgets allow two such representations; fixed Compute's
shared measurement budget allows two inputs plus one output. Thus `wire_bytes`
must be at most 715827882 for the signed 32-bit measurement counters.
Other fields bound cumulative value/guard work, scratch entries, and framing;
they do not authorize unreserved resources. Counts and combined cell products
must fit the current signed 32-bit counters. Retained wire/frame settings must
agree with the profile when using Local export. Resident execution does not yet
accept this extended example profile.

Transport is separately charged. Acquisition includes the one-cell table metadata
query. Compute allows two inputs' INSERT acknowledgements plus output rows;
its input-cell ceiling counts both inputs, even for identical contents.
The configured Compute transfer envelope is
`3 * wire_bytes + 2 * task_rows * (128 * columns + 256) + 8192` bytes.
This is a bounded application allowance for representation transfer, parameter/type
envelopes, acknowledgements and metadata, not a guarantee that arbitrary input
values fit. The selected offer and Node transport use the same capacity function;
actual usage still consumes the ledger and exceeding the allowance fails.
Schema matching has a separate fixed 100000-work budget, independent of row count.
Completion entry capacity is `max(columns, 2)` for output names and exact input
bindings; it is not the row/value scratch-entry budget. Increasing `entries` or
`value_nodes` does not increase the streamed result's retained metadata capacity.
File bytes and temporary execution capacity remain independently accounted.
The extended profile limits each converted transport batch to 128 rows and
`batch_bytes` encoded bytes. SDK chunks are read through column-vector slices;
they are not first converted into a full array of row objects. Splitting adds
no decoded values to the parent SDK vector's chunk-wide string cache; each
delivered batch has its own short-lived vector view. Splitting still adds
actual framing bytes to cumulative transfer usage. A batch exceeding its byte
ceiling fails before delivery, and cannot reset already consumed capacity.
With both bounds, the Node transport reserves a bounded frame plus the SDK vector
window and validates variable-width lengths before copying. This is distinct
from the common MoonBit scratch allowance and does not constitute an RSS limit.
Join preflight also charges its supplied validation-work limit to planning before
scanning inputs; the parent and child must reserve that in addition to search work.

Profiles use the connector's configured retention capacity when constructing
the selected native envelope, rather than deriving retention from wire bytes.
They also raise its execution capacity to 4 GiB; the parent/child resource
ledgers must admit it. Merely supplying a
large profile is not evidence that the entire benchmark matrix is supported or
that a memory/performance target is met. The integration cases use 1000 and
10000 source rows and the same standard Host path, not a separate evaluator.
The explicit wire/transport ceiling must cover actual import commands and
parameters, not just the canonical output bytes. Diagnostic identity projection
uses the same application's profile and rejects a foreign DAG.
The installed fresh reader consumes the same data profile for full-content
verification and framing, reserving its bounded parser workspace before reading.
Its completion descriptor ceiling follows the configured column count rather
than the default ten-column example. The per-row decode-node ceiling is bounded
by both the cumulative value allowance and the frame byte ceiling. Its declared
scratch reservation covers concurrent encoded/decoded/admitted representations;
raising cumulative row counts alone does not enlarge that frame workspace.
The integration also re-admits 997-row and 9997-row retained outputs after the original
process exits and binds it to its checked consumer port. The reader also registers
that material with the shared Store access contract and performs a bounded byte
read through it, keeping the custody borrow until both reads finish and charging
both transfers. This does not authorize or execute that consumer's Compute, nor
does it resume a Program.

The controller validates and snapshots configuration before resource creation,
creates one process per accepted Run, and never automatically retries it. A pure
configuration error is correctable without reserving a process or Store. An
accepted Run ID cannot be reused. All Runs share the controller's cumulative
ledger, including costs consumed by failures.
This bounded controller accepts only one live Run/result set at a time: close
its retained results and confirm cleanup before starting another Run. Store
capacity is capped by the child retention envelope. The entry does not claim
concurrent cross-Run Store quota management or a process pool.

`run()` returns after child release and confirmed exit. The returned `report`
describes internal tasks, and `program_success` is always false. Inspect saved
metadata with `completion(task)`, current Store usage with `storageUsage()`, and
cumulative physical accounting with `usage()`. `prepareReader(task)` provides an
exact, one-shot reader service for later installed readmission; it is not a new
Compute execution permit or failed-Program continuation.

Always `await result.close()` when its holdings are no longer needed. A failed
task can leave independently completed predecessor results in custody; close
revokes those result ports but consumed transfer/work is not refunded. Failed
cleanup retains an explicit `cleanupHandle`; retry only that cleanup operation,
not `run()`. Source credentials, arbitrary module loading, formal Run/Result
publication and control-Host restart recovery are not provided by this example.

### Retained representations

The JavaScript application entrance also accepts `retainedOutput` (a local
`parentDirectory`, `maxFrameBytes`, and canonical `wire` limits) together with an
explicit `retainedWorkMilliseconds` estimate. This installs file-backed output
for DuckDB candidates; it does not force DuckDB placement. With `resident: true`,
resident candidates can keep a DB copy alongside the independent file. File writing, sealing and cleanup
add a separate estimated work slot and file capacity to candidate comparison.
These supplied estimates are not performance measurements. Omitting the file
estimate is rejected by this example instead of silently assigning zero cost.
The connector policy itself can represent unknown work for Hosts with an explicit
unknown-cost selection policy.

The managed example uses the same comparison and completion path. Resident
execution imports a shared retained input once, while each consumer retains its
required validation and read accounting. The worker closes the DB before exiting;
the controller's independently held files survive that exit until explicitly
released. DB-copy capacity is not replaced by the smaller streamed metadata
allowance. The example's resident environment remains bounded to 128 MiB; large
profiles may therefore reject resident placement rather than enlarge the engine
or discard capacity obligations.

Explicit `dataProfile` settings can also offer resident execution. Import
transfer, bounded transport scratch and DB-copy allowances are derived before
selection instead of reusing the small example's fixed import envelope. A
streamed completion reserves its metadata separately from the resident DB copy;
independent file holding is still required. The 128 MiB environment bound and
the Run's cumulative capacity checks remain in force.
The current candidate estimate also supplies a resident output-copy ceiling,
so it conservatively covers the greater of the full-copy and streamed-metadata
bounds. Actual copy holding and independent file/metadata accounting remain
separate; lowering this estimate to metadata alone would understate the copy.

The standard Host can execute the all-DuckDB file-backed chain and release its
files asynchronously; call `await result.close()`. Without an export policy,
Local-only selection creates no output files. To allow a file-to-Local edge, also supply an explicit
`localImportWorkMilliseconds` estimate. This installs bounded Local conversion
capacity before selection. For example, `nativeMilliseconds: '5'`,
`retainedWorkMilliseconds: '0'`, and `localImportWorkMilliseconds: '0'` exercise
DuckDB A/B followed by Local C in the supplied small example. These zero work
values are controlled selection examples, not measured costs. Local diagnostics
report actual imported rows/bytes; conversion verifies the original logical CID
without recomputing the producer. The initial comparison allowance is conservative
per input, not a complete model of upstream representation choices. The managed
process assembly can use `controlStore: true` with an installed
`createProcessRetainedStore` Host service and an explicit `maxHostCalls` limit.
This requires an explicit `localImportWorkMilliseconds` estimate and retained
output settings. The captured input is stored as `capture-0` before DAG adoption;
retained Compute outputs use `task-<index>`. Provision capacity and entries for
the capture as well as the selected retained outputs (four entries and 400000
bytes for this example's all-DuckDB case). These are Store allowances, separate
from the process and DAG ledgers.
To independently retain Local outputs too, supply `localExportWorkMilliseconds`
in the managed-process input (for example `'0'` as a controlled selection fixture,
not a measured estimate). This example's export profile fixes both
`retainedOutput.maxFrameBytes` and `retainedOutput.wire.max_bytes` at 100000 and
requires the installed control Store. Local candidates then include export,
file retention and cleanup work; Local results also occupy `task-<index>` and
survive child release/exit. All-Local and mixed configurations need the same four
Store entries when every task is independently retained. A following Local task
explicitly imports a retained result; the producer is not recomputed.
With that export policy, `nativeTaskMilliseconds` can supply one decimal-string
estimate per Compute, in checked task order. The example snapshots and validates
the array before source access. For example, `['20', '20', '1']` offers expensive
DuckDB execution for A/B and cheaper execution for C; ordinary candidate
comparison selects Local/Local/DuckDB for this fixture. These are supplied
estimates, not forced placements or measured execution times.
Call `store.observe(channel)` before executing the prepared application. Files
are allocated after acquisition/task admission, not during preparation, and body bytes
are written/read in the execution process. Child release and exit preserve the
parent's sealed holdings; the control owner separately closes and cleans its
Store. The all-DuckDB, all-Local and both mixed-direction chains exercise this
path. Diagnostic replies and surviving file digests are not evidence for logical
result admission into a new execution process.

Limits are deliberately small: 100 rows per configured boundary, ten columns,
100000 transport bytes per attempt, 500000 cumulative transfer bytes, 200000000
retention-envelope bytes and 268435456 execution-envelope bytes. See the explicit
application limits in `src/physical_strategy_example/host_limits.mbt` and the
cumulative ledger in `src/physical_strategy_example/application.mbt`. Native
validation and query receipts both count; 100 source rows plus native result
rows may exceed the combined receipt limit. Limits are not optimizer estimates.

`--native-ms` is a supplied estimate for the fresh-DB native work bundle, including
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
an `AbortSignal`. Completed-input sharing is process-local; task streaming,
automatic failed-query retry and remote replay are not provided.

## Resident candidates

To run the join/count variant, use the same command with
`--program adapters/duckdb-node/examples/join-count.json`. For source ids
`[3,1,2,3]` and minimum 1, A contains two occurrences of 3, B contains
`[3,2,3]`, their inner join contains four occurrences of 3, and the separate
group/count consumer produces `[{"id":3,"n":4,"present":4}]`.
Join capacity material uses the selected Environment's `max_relation_output_rows`
Host ceiling and is validated by the public checker; the example's 100-row
consumer/output guard remains independently enforced. A small final aggregate
does not waive the join intermediate limit.

The same document runs with Local, fresh DuckDB or resident candidates. Under
the supplied estimates, `--native-ms 20 --resident` can mix Local branches with
resident join/count because cumulative transfer reservations also participate
in feasibility. It does not increase the 500000-byte ledger to force a preferred
placement. Count's retained DB result and Host result have separate ownership.

`--resident` defaults to false. It adds resident candidates to the comparison;
it does not force every task onto resident DuckDB. For example:

```sh
node adapters/duckdb-node/examples/physical-strategy.mjs \
  --database /absolute/path/to/trusted.duckdb \
  --environment /absolute/path/to/check-environment.json \
  --environment-cid sha256:YOUR_EXPECTED_ENVIRONMENT_CID \
  --program adapters/duckdb-node/examples/program.json \
  --parameters adapters/duckdb-node/examples/parameters.json \
  --schema main --table records --native-ms 20 --resident
```

The example resident model uses 1 ms each for shared DB preparation, each needed
input import, final DB cleanup, and each task's work bundle. These are supplied
estimates, not measured speedups; `--native-ms` still controls the separate
fresh-DB realization. Actual completed sizes may change the remaining selection.

With source ids `[3,1,2,3]`, minimum 1 and all three tasks selecting resident,
one run-owned source-isolated DB shares X between A/B and retains A for C.
Compute input imports fall from 3 calls / 8 rows to 1 call / 3 rows. Acquisition
validation transfer is unchanged. Host validation and Host result retention
continue; the DB copies require their own capacity and lifetime management.
The DB allowance is reserved before creation through confirmed destruction;
table quotas are suballocations, while Host copies and scratch are separate.

Tables are retired after their last planned use, with capacity released only
after removal and reader cleanup are confirmed. Unexpected DB-copy loss is
different: if the same fixed Host input survives, unstarted tasks may compare
Local or reimport candidates without retrying started work. Closing the driver
retains pending cleanup responsibility until the DB is actually recovered.

Application users should use `runExample` or the standard `runCapturedStrategy`
driver. Individual environment/table/transfer operations are a trusted Host
implementation protocol, not user-authored execution commands. Import preflight
failures can be corrected before an attempt starts; started import failures
stop the graph rather than enabling automatic fallback.

## Adopted execution contracts

The row engine selects its adopted registry, REL.values and fragment pins.
`../contracts/adopted-relation.json` packages the exact selected bodies from
revision `9edb5a65db8b822b8629cfa4913fb1097fb99945`, with their CIDs. The bundle
and the product pins are generated from the same registered contracts; this
example does not infer compatibility with older bodies. These are contract
material, not test outputs or a compatibility implementation. Current Query
Acquisition/process-evidence/two-receipt contracts are loaded from their
repository-owned files.
