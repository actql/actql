# Retained execution: diagnostic observations, 2026-09-16

These are development observations, not performance acceptance. The worktree is
uncommitted on `b87584fed46217659589315c1f819994dc0cfe77`; that commit alone does
not contain the implementation tested here. The preregistered four-comparator
experiment remains unmeasured. No thresholds or fixture pins were changed.

Follow-ups below are chronological. The latest standard-Host integration combines
independent retained-file Compute outputs with resident DB-copy reuse; earlier
entries describe prerequisites before that path was enabled. The example's
managed-process composition now also exercises that combination, as recorded
in the latest follow-up below.

## Execution readiness

- The registered 27-case run passed 13 cases, including low-selectivity native
  acquisition with one million narrow rows and 100000-row wide layouts.
- Its next case, `fixed-join-count-shrinking-intermediate/narrow/1000000`,
  reached the unchanged 600-second timeout and failed. Other diagnostic tests
  were running concurrently, so this is not an isolated speed measurement or
  evidence of a regression relative to another run.
- The separate diagnostic
  `fixed-join-count-shrinking-intermediate/numeric-64/100000` succeeded in about
  96 seconds after the Acquisition holding-accounting correction. Previously it
  was rejected during placement selection for retention capacity. This time
  includes setup, execution, identity checks and cleanup, and is not an
  end-to-end performance sample under the registered comparison protocol.
- The later Compute confirmed-retention change passed the standard real-DuckDB
  Host test. Query integration passed 264 tests on each of JS, Wasm and native.
  Those are correctness results, not completion of the full benchmark matrix.

The Acquisition correction reserves the original file ceiling before execution,
then commits metadata allowance plus the exact sealed file bytes at completion.
The Compute correction uses an optional installed capacity measurement at the
common holding boundary, bounded by the original reservation. Neither change
refunds consumed transfer or treats cancellation as physical cleanup.

## Native insertion probe

Observed runtime: Node `v22.23.2`, DuckDB Node API `1.5.5-r.4`, macOS
`darwin/arm64`. This is not a Linux or Cloudflare performance measurement.

`adapters/duckdb-node/bench/import-probe.mjs` isolates insertion into a temporary
DuckDB table: 10000 exact Double integers, one column, three rotated rounds,
single native thread, 128 MiB configured engine limit, one transaction per run.
Each run verifies count, minimum, maximum and sum before rollback. Appender
flushes every 128 rows. Database creation, verification and final cleanup are
outside this diagnostic timer.

| Path | Round 0 (ms) | Round 1 (ms) | Round 2 (ms) |
| --- | ---: | ---: | ---: |
| Extract/prepare/stream/drain/destroy per row | 737.33 | 721.53 | 720.78 |
| Reuse prepared statement, stream/drain per row | 358.87 | 356.10 | 371.15 |
| Appender, flush every 128 rows | 4.66 | 3.82 | 3.59 |

These measurements exclude ActQL admission, logical guards, canonical encoding,
CID generation, independent holding, process startup and cleanup. They cannot
be used as ActQL speedup ratios, equivalent-obligation costs or benchmark gates.
They identify per-row native command orchestration as an optimization candidate;
they do not measure its share of the complete ActQL run.

The pinned SDK exposes explicit prepared-statement destruction. Appender
destruction, unlike close/flush, is native-finalizer managed. Production adoption
must preserve failure cleanup responsibility, bounded buffering, exact physical
types, cancellation and actual transfer accounting. The probe is not evidence
that those contracts are already implemented for Appender.

Run the diagnostic (requires the connector's pinned SDK):

```sh
node adapters/duckdb-node/bench/import-probe.mjs
```

`ACTQL_IMPORT_PROBE_ROWS` and `ACTQL_IMPORT_PROBE_ROUNDS` select bounded diagnostic
sizes only. They do not alter the registered experiment or its workload limits.

## Still unproven

The full 27-case readiness matrix now passes on the working tree (see the
bounded-import follow-up below). Still unproven: that matrix on a final fixed
revision; all four
performance comparators and confidence gates; execution of a subsequent Compute
in a fresh process (current reader only re-admits and binds); full final
regression checks and Linux/GitHub Actions. No completion claim is made here.

Native acquisition now exposes metadata, validation-receipt and native-result
wall-clock phases through the standard Host result's `diagnostics`. These include
installed receiver validation/encoding/storage, not pure SQL time. Session
command/callback counters are nested; do not add them to these phases. The body
timer excludes session opening, transaction settlement and native cleanup. Empty
receipts are timed as well. This instrumentation is not a new timing sample or
evidence that validation, hashing and storage have individually been isolated.
After adding these phases, the native acquisition, batch import, fixed import
and session tests passed 26/26, followed by the standard real-DuckDB Host test
1/1. The latter checks diagnostics on retained nonempty and empty results;
rejection, cancellation and cleanup assertions remain enabled. This rerun did
not include the large benchmark matrix or the full three-target suite.

## Follow-up: explicit-lifetime prepared imports and phase diagnostics

The fixed-input product path now reuses one prepared INSERT per active SQL in
the owned session. Physical parameter validation, per-row result draining,
cumulative transfer and logical input admission remain unchanged. This removes
repeated extraction/preparation, not the per-row native execution round trip.
Appender remains a candidate, not an installed product path: the pinned SDK
does not expose its explicit native destruction. GC expectations are not cleanup
evidence. A reusable statement is explicitly destroyed; injected destruction
failure keeps cleanup pending until a successful retry.

The replacement-representation liveness callback now captures the original
logical liveness check rather than its entire completion/physical store. This
removes a code-level retention path; it is not a measured RSS/leak result.

The actual bounded session diagnostic (`bench/session-import-probe.mjs` under
the DuckDB Node adapter) compared 10000 BIGINT inserts in three alternating
rounds. Ordinary commands took 797.58 / 756.86 / 754.69 ms; reused statements took
409.48 / 400.58 / 401.57 ms. Both executed 10002 statements and charged exactly
1429302 transport bytes. Preparation counts changed from 10002 to 3. The timer
includes DB setup, a verification query and explicit native cleanup, but excludes
MoonBit admission, logical guards, CID and independent retention. This was a
development run while a separate correctness command was also launched; do not
use these figures as isolated performance acceptance or an end-to-end speedup.

The managed `fixed-join-count-shrinking-intermediate/narrow/10000` diagnostic
passed independent result identity, holding and cleanup checks in about 3.87 s
(excluding its preceding build). Its four tasks imported 10000, 10000, 20000 and
20000 rows: the expected 6N import work is real, not shared away. Total preparation
count was 14, while each row still executed one INSERT. The observed INSERT
intervals totaled about 2.63 s. Input intervals include INSERT time, and command
time includes preparation and receive callbacks; these nested times must not be
added together. The full acquisition/validation/CID/seal breakdown and formal
four-comparator measurement remain unfinished.

The previously timed-out million-row narrow join/count case then completed in
303.89 s with the unchanged 600 s ceiling. Independent CID, surviving file
holding, execution-process exit and final cleanup all passed. This was a single
readiness diagnostic, not a paired comparison with the prior timed-out run.
Its total imported rows were 6 million and its preparation count was 14.
INSERT intervals summed to 256.91 s; total input intervals summed to 291.48 s;
query/receive intervals summed to 7.22 s. INSERT is a subset of input time.
The latter intervals include receiver validation/CID/storage callbacks, not
pure DuckDB compute. These observations support batching as the next target,
without attributing the entire old timeout to preparation overhead.

That diagnostic loaded the initial reusable-statement implementation. Explicit
per-row `clearBindings()` was added while it ran and is covered by subsequent
regression tests, not retroactively by the 303.89 s measurement. No final fixed
HEAD or full registered matrix is claimed by this intermediate measurement.

Follow-up checks on the working tree passed: session/fixed-Compute/Appender
transport tests 23/23; the standard real-DuckDB Host integration test 1/1;
replacement-representation import tests 4/4 on each of JS, Wasm and native.
These targeted checks are not the repository's complete regression suite.
`npm run check:docs` also passed. Linux and GitHub Actions were not executed.

## Follow-up: bounded multi-row prepared import

The next implementation uses the same owned fixed-import compiler to produce
multi-row INSERTs within SQL/parameter limits. Node batches snapshotted physical
parameters within explicit row and frame-byte bounds; wide strings can flush a
batch earlier. It uses explicitly destroyed prepared statements, not Appender
finalizers. The application reserves the larger bounded parameter capacity
before selection. Logical row/cell/join limits, total resource/transfer ceilings,
fixture pins, timeout and performance acceptance thresholds were not relaxed.

In a single managed readiness diagnostic, the million-row narrow join/count
completed in **44.14 s**, with the expected CID, independent holding and cleanup.
The earlier reusable single-row diagnostic was 303.89 s. These are development
observations of successive worktree versions, not paired confidence measurements
or a formal speedup claim. The 10000-row case also passed in about 1.18 s.

The million-row batch run still imported 6 million logical rows across four
tasks; it did not fuse tasks or omit the intermediate join output. It executed
46886 native statements instead of 6000009. INSERT intervals totaled about
7.45 s, input intervals 31.34 s, and query/receive intervals 7.27 s (nested
intervals are not additive). There is still repeated import/validation work:
retained/resident integration and complete end-to-end comparison remain needed.

The initial batch helper's three tests and the fixed-Compute transport's
three tests passed, including both single-row and batch import of the adopted
text/boolean/integer/number/decimal/date/timestamp fixtures. The whole 27-case
registered readiness matrix subsequently passed in 369.23 s, with no skipped
cases and unchanged fixtures/timeouts. In that full run, million-row narrow
join/count took 45.94 s; 100000-row numeric-64 join/count took 14.85 s;
million-row narrow downstream reuse took 45.87 s; numeric-64 downstream reuse
at 100000 rows took 134.27 s; text-1024 downstream reuse at 100000 rows took
55.86 s. The wide reuse imports used 51-row batches under the SQL byte ceiling.
Every case checked independent final CID, retained availability after process
exit and cleanup. The wide reuse reader also checked fresh-process readmission
and exact input binding, still not execution of a subsequent Compute.

This is the first successful full-size readiness run in these observations,
not final fixed-HEAD verification or the four-comparator performance experiment.

After batching, the complete query-integration package passed **265/265 on each
of JS, Wasm and native**. Targeted Node tests (batch bounds/failure, scalar fixed
imports, session cleanup and the standard real Host) passed **26/26**. The
unchanged pinned fixture/matrix/selection checks passed **6/6**, and
`npm run check:docs` passed. Work remains uncommitted on the baseline noted above;
Linux/GitHub Actions and the full repository regression suite were not rerun.

## Follow-up: physical reads after process re-admission

The fresh-process reader now registers the exactly admitted retained material
with the same Store representation access used by Local and DuckDB. After
binding its checked consumer port it actually consumes the retained bytes and
verifies the file digest, instead of stopping at the readable predicate. The
original custody borrow remains outstanding until both admission and consumer
access finish. Both transfers are reserved before reading and charged as bytes
arrive; uncertain close still retains responsibility until process exit.

Numeric-64 downstream-reuse diagnostics at 100 and 1000 rows passed with no
source reread. The 1000-row test additionally checks that the receiving process
reports exactly twice the body bytes (admission plus consumer read) and releases
its execution reservation. Shared Store access, Local retained-reader and
completion-custody tests passed 19/19. This is not a fresh-process Compute or
DAG-resumption result, and does not make the extra diagnostic read a required
scan in every product execution. The full registered matrix was not rerun for
this change.

## Follow-up: resident transaction failure safety

Real-DuckDB regressions exposed falsy rejection payloads (`undefined`, `null`,
`false`, zero and the empty string) being mistaken for absence of failure in the
native session. A caught receiver rejection could consequently commit a resident
table. The session now tracks failure occurrence separately from its payload,
including the cancellation-deadline wrapper. The resident provider also preserves
primitive rejection values rather than replacing them with a property-access
error. Tests verify that a failed table creation is rolled back and a later task
can use the still-owned environment. The two added regressions failed before
the fix; session/resident-session/batched-import tests then passed 27/27.

Resident imports now use the same explicitly destroyed prepared INSERT cache as
fresh imports. This removes repeated preparation only: it is not resident batch
import, retained/resident interoperability, or a measured end-to-end speedup.
The real standard Host integration passed after fixing the fresh reader's
default wire configuration and updating its exact two-read byte accounting.
It asserts that the three-row resident import runs four statements with only
two preparations. The typed resident composite-join/count integration also
passed. These are targeted regression checks, not final whole-repository
verification or a new performance acceptance run.

## Follow-up: independent holding versus resident-copy capacity

The shared execution contract now distinguishes resident-copy bytes from
independent completed-output holding bytes. Copy size remains bounded by the
selected resident offer and allocated inside the independently reserved live
environment. Output holding remains bounded by the task's retained envelope.
The DuckDB driver uses the row/copy bound for the DB representation even when
completion itself uses streamed metadata plus a file. It no longer substitutes
the stream metadata allowance for the DB copy's capacity.

New numeric-bound regressions check that neither budget compensates for an
excess in the other. Physical-strategy tests passed 3/3 and query integration
265/265 on each of JS, Wasm and native. Generated interfaces were regenerated.
This is a prerequisite, not enabled retained/resident interoperability: the
standard contribution still rejects that combination until data access,
transaction/retention settlement and candidate costs are connected.

## Follow-up: file work in resident candidate composition

Fresh and resident offer construction now share the independent-file work and
holding calculation. A file adds one work item and its declared holding ceiling;
it does not enlarge the DB copy. A regression selects three resident tasks with
100-byte copies and separate 1000-byte files against a 1000-byte DB environment.
Known per-task compute/file estimates of 19/7 produce 78 total time units with
zero shared setup/import/cleanup estimates; unknown file work remains unknown.
The supplied estimate array is not mutated, and invalid file bounds/costs are
rejected before any attempt. The installed contribution's unsupported-combination
check remains intact: these are composition tests, not evidence that the combined
physical execution path is enabled.

## Follow-up: output finalization before resident commit

The installed Compute Host now uses one output-finalization operation for row
and retained-file completion. Resident execution awaits it inside its native
transaction; fresh execution invokes it after ephemeral native settlement. The
retained branch includes stream completion, canonical tail writing, exact
identity sealing and material staging. Common completion/publication still
occurs only after native settlement; sealing alone is not task success.

Real resident-session tests passed 5/5, including an asynchronous holding gate:
while held, no task settlement is reported; failed holding or cancellation rolls
back the provisional table; successful holding allows the table to commit.
The standard real-DuckDB Host integration passed as well. The holding-gate test
is a lifecycle test, not an end-to-end retained/resident combination. Its
installed contribution is still gated pending input-access and bridge wiring.

## Follow-up: bounded full-storage import validation

Added a common retained-storage scan that operates on an exact completed
`ProducerStorage`, without manufacturing a consumer input or retaining the full
row table. It reuses typed row decoding and canonical output streaming, checking
ordered identity, exact owner/target/schema, counts and value measurements at
finish. Its proof is tied to that storage handle and current availability, not
equal contents. A DuckDB resident-import stream converts the provisional rows
through the existing physical scalar converter and requires the storage proof
before its scan succeeds.

Three common scan tests and one connector integration test passed on JS, Wasm
and native, including reordered/truncated/changed content, foreign storage
handles, cancellation, loss of holding and row limits. These do not claim a
successful native DB import: the Node Store/transaction/copy-installation bridge
still needs connecting, and later consumer guards must still run.

## Follow-up: retained acquisition input reused by resident consumers

The Node bridge now connects that bounded storage scan to the real resident
import transaction. It obtains the exact installed Store representation, charges
file bytes before decoding, verifies the complete ordered identity, and installs
the DB copy only after successful transaction settlement. No whole-row table or
synthetic consumer admission is required for this physical copy. An uncertain
Store read failure retains cleanup responsibility; closing the native session
alone is not treated as proof that the Store read has closed.

The standard Host integration now runs its shared resident graph with both
row-backed and retained-file Acquisition inputs. The retained variant imports
the captured file once, reuses that DB copy for A and B, and executes C from A.
It checks zero per-task reimports, immutable capture after source replacement,
the existing result identities, last-use release and independent source holding.
Each retained consumer still performs its required bounded measurement read;
the test checks those file bytes separately from DB import bytes. Reusing a DB
copy does not waive consumer demand, guard or transfer accounting.

After regenerating interfaces and formatting, the standard real-DuckDB Host,
resident-session and Store representation tests passed 8/8. This is a functional
reuse result, not a new timing measurement or formal performance acceptance.
Compute outputs in this integration remain row-backed. Simultaneous retained
Compute output and resident DB copies are still gated in the installed
contribution pending combined output-bridge and capacity wiring. The full
registered matrix and whole-repository regression suite were not rerun here.

## Follow-up: independently retained output with resident DB copies

The combined output bridge now passes file holding and resident inputs through
the existing common task admission. Trying to add file output to a row-only
selected configuration was rejected at start; the integration instead configures
file work and its ceiling before constructing/selecting offers. The installed
DuckDB contribution now accepts that combination and uses the same execution
and completion path, without a backend-specific common Host branch.

The real standard Host integration passed with both low-level and installed
contribution coverage: X is imported once, A/B reuse X, C reuses A, and all three
Compute outputs have independent files. The installed finisher closes the DB
while C's completed result remains bindable with its expected CID. Explicit
output close and cleanup leave no pending file responsibility. Consumer file
reads remain measured even when native reimport is zero. The example CLI's
combined configuration remains disabled until its separate estimate/profile
setup is wired; this result is not a managed-process or benchmark acceptance run.

## Follow-up: retained/resident selection in the managed Run process

The shipped application now threads the resident option through retained,
materializing and Local-export dispatch preparation. File work remains installed
before offer construction. For an explicit data profile with resident candidates,
the conservative row/copy bound is preserved rather than using stream metadata
as a DB-copy estimate. The existing bounded resident environment and import
limits are not automatically enlarged for large profiles.

The real standard Host test passed with two managed-controller cases. Supplied
fresh cost 1 selects three fresh DuckDB tasks; cost 20 selects three resident
tasks with one root import and no later reimports. Both keep all outputs as
independent files, produce the expected final CID, and retain four holdings
(capture plus three results) after confirmed worker exit. Explicit controller
close removes those files and leaves no pending cleanup or execution reservation.
This tests ordinary candidate comparison, not forced placement or measured costs.
The test uses the same Run resource limits as the existing controller tests;
parent process admission is separately provisioned from the delegated child
budget. Formal performance comparison and full final regression remain pending.

The application package's JS test passed 1/1 and document links passed. The
application is explicitly a JS-only foreign-library assembly: an attempted Wasm
package test correctly rejected that target, so no Wasm/native application test
success is claimed. Shared Core/connector multi-target coverage is separate.

## Follow-up: failed retained input does not settle with the DB

The Compute Host now tracks an outstanding retained-input read independently
from native session settlement. A rejected Store consume does not establish a
read-stop receipt, even when native rollback/close succeeds. The common physical
settlement remains unconfirmed, the returned cleanup handle stays pending, and
retry performs available cleanup without rereading or claiming success. Bounded
row framing is disposed on every path. This is conservative: a logical read
failure with no separate close proof may require execution-process exit for final
supervisor settlement; it is not automatically retried in-process.

A real-DuckDB regression imports an intact retained capture, then corrupts the
same file inode without changing its length before the resident consumer runs.
The existing DB copy does not bypass the consumer check: the task fails, no
output is published, future dispatch stops, and closing the native DB cannot
release the outstanding common responsibility. Explicit cleanup still reports
pending. The standard Host integration passed with this case, and the shared
retained-boundary suite passed 76/76. These results do not constitute the final
all-target/all-connector verification or a new performance sample.

## Follow-up: cancellation delivery at import batch boundaries

Bounded parameter batches now yield to the Node event loop before each native
write, then recheck cancellation. Awaiting already-resolved row callbacks alone
does not allow queued timer/IPC cancellation to run. The yield is per batch, not
per row; it neither interrupts an already-started native operation nor establishes
a cleanup receipt. A cancelled batch is poisoned and cannot be retried.

Regression tests schedule cancellation in the event loop while append calls
continue through microtasks. Both a full batch and a final partial batch reject
before any native write. The real DuckDB import/session/resident tests passed
29/29, and benchmark fixture/selection/paired-assessment tests passed 9/9.
The existing duplicate/NULL payload and reduced statement-count checks still
pass. No timing comparison was rerun for this scheduling change; prior diagnostic
durations do not certify its performance or the four-comparator acceptance gate.

## Follow-up: executable raw DuckDB reference

The raw comparator now executes all declared stages without fusion, retains the
A/B and A-to-C dependencies, and verifies intermediate cardinalities plus final
values against the pinned independent fixtures. It records execution, per-stage,
post-execution verification and rollback separately. The diagnostic runner uses
one DuckDB thread, the fixture memory ceiling and an in-memory deterministic
source prepared outside timing. It is not the equivalent-obligations comparator:
ActQL validation, logical identity, independent holding and admission are absent.

All 27 registered cases completed in a diagnostic run. The three real-DuckDB
regressions passed, including all nine 100-row shapes, changed payload rejection,
pre-start cancellation, and cancellation after one stage with rollback before the
next stage. These are executable-reference/readiness results, not seven paired
measurements or performance acceptance. Raw computation and independent result
verification have distinct costs; neither is comparable to the managed smoke's
inclusive elapsed time without a matched harness. No threshold or timeout changed.

The fixed original baseline still needs a benchmark adapter for the larger
registered profiles: its shipped example has fixed small input/column/transport
caps and no parameterized managed-retention entrance. Do not retrofit the new
algorithm into that baseline, label a different implementation as baseline, or
drop unsupported cases to obtain a passing comparison.

## Follow-up: actual controller/executor wire volume

The installed process channel now counts every received byte and every frame
submitted to its outgoing stream, including configuration, protocol envelopes,
accounting and Store/completion messages. Counts are monotonic decimal strings
backed by integer counters, not estimates or logical budget charges. Submission
is not a delivery acknowledgement. A rejected oversized request is not sent or
counted; invalid incoming frames still contribute received bytes.

Two registered narrow retained-reuse cases passed with independent result CID,
process exit, retained-file survival and explicit cleanup checks:

| Source rows | Controller submitted bytes | Controller received bytes | Inclusive diagnostic elapsed |
| --- | ---: | ---: | ---: |
| 100 | 90,292 | 16,718 | 671.7 ms |
| 1,000,000 | 90,518 | 17,078 | 46,469.9 ms |

The source grew 10,000-fold while this channel's traffic grew only by small
metadata differences. This is measured evidence for these two cases, not a
general memory bound or proof that all possible messages exclude row payloads.
The million-row case still reports 143,078,424 connector transport bytes per
Compute: data-side work was not eliminated by keeping it off the controller.
Elapsed time includes source setup and cleanup, is a single diagnostic run, and
must not be used as a formal paired timing sample or a speedup claim.

Process-channel/capacity tests passed 31/31, including exact UTF-8 envelope byte
counts, immutable snapshots and unsent-request exclusion. The shared retained
boundary suite passed 77/77. No identity definition or resource admission changed.

## Follow-up: sampled controller memory, isolated from source generation

The readiness harness now samples controller memory every 20 ms only around
`host.run`, storing a fixed-size baseline/last/peak aggregate. Failed samples,
including falsy thrown values, produce `incomplete`. RSS, heap and external
categories overlap; they are not added together. Observed peaks can miss brief
allocations and are not an allocation bound or a memory-gate pass.

An initial measurement found that generating the source DuckDB in the controller
contaminated its RSS baseline: 97,796,096 bytes at 100 rows versus 188,940,288 at
one million rows. Although execution-time increments were similar, those absolute
peaks did not isolate control work. Source generation now runs in a separate
process, awaited through exit before execution; the generator preserves the
unchanged pinned fixture SQL. All nine source shapes are checked after generator
exit through a read-only connection, and invalid arguments create no database.

After that harness correction, separate controller invocations observed:

| Narrow reuse input | Baseline RSS | Observed peak RSS | Peak RSS above baseline | Observed peak heap used | Samples |
| --- | ---: | ---: | ---: | ---: | ---: |
| 100 rows | 80,789,504 | 137,150,464 | 56,360,960 | 41,545,000 | 21 |
| 1,000,000 rows | 80,920,576 | 139,100,160 | 58,179,584 | 43,349,224 | 2,203 |

Both cases passed independent CID, retained-file survival, process exit and
cleanup checks. This provides limited scale evidence for this fixed graph and
layout, not all 27 cases or a general proof of constant memory. Preparation and
module initialization are included; independent expected-value hashing, optional
readmission and final file release are outside the sampled interval. No forced
GC or memory threshold was added. The source-generator and benchmark helper
tests passed 13/13. These diagnostic runs are not paired performance samples.

## Follow-up: bounded initial import into resident environments

The resident-copy import now uses bounded multi-row INSERTs when the configured
transport supplies chunk limits, for both in-memory and file-backed producers.
It shares the connector-private MoonBit tuple/parameter/SQL-cap compiler with
fresh fixed Compute rather than reconstructing SQL in JavaScript. Batch sizing
is checked before transfer reservation. Unbounded compatibility profiles retain
their explicitly owned single-row prepared INSERT path.

The existing batch writer enforces row/byte limits, snapshots typed parameters,
yields for cancellation before native writes and cannot retry after failure.
For retained inputs, the final partial batch is flushed only after full framing
and immutable content verification. Earlier writes remain transaction-local;
no copy is installed before native settlement and common transfer completion.
Missing Store stop evidence still cannot be settled by native DB close alone.

The standard real-Host suite passed with new memory/file producer variants:
three imported rows use three statements (CREATE plus two batches) instead of
four (CREATE plus three single-row writes), with exact downstream values/CIDs,
shared-copy reuse and independent file cleanup unchanged. Preparation count is
three because the two-row and one-row tail have distinct SQL shapes. The shared
SQL-cap tests passed on JS/Wasm/native, 17 tests per target; batch and resident
session tests passed 10/10. This establishes fewer native calls, not a measured
large-profile wall-clock improvement or formal performance acceptance.

## Follow-up: retained comparison execution leg

Readiness and retained measurement now share the same immutable benchmark
configuration builder, including cumulative transfer/planning allowances and
separately delegated child attempts. All 27 configurations are tested, with a
fixed independently calculated join envelope case; the fixture pin is unchanged.

The retained leg invokes the installed managed Host, validates the independent
final identity and file lifetime after child exit, and times explicit result
cleanup separately. Incorrect expected identity still releases completed files
and never produces a successful sample. Real integration covers the three narrow
100-row workloads, and the benchmark helper suite passed 14/14. These are runner
verification cases, not acceptance measurements. Its interval includes Host and
process setup, so no ratio against the raw comparator's compute-only interval is
claimed. Baseline/equivalent-obligations implementations and paired provenance/
timing boundaries remain required before applying registered thresholds.

## Follow-up: unchanged baseline compatibility, actually executed

An exact `git archive` of baseline
`b87584fed46217659589315c1f819994dc0cfe77` was extracted to
`/tmp/actql-retained-baseline-gsZV6e`. Its DuckDB Host bridge, generated Node
composition and example assembly were freshly built in release mode using the
pinned MoonBit 0.10.12 toolchain. The baseline's pinned DuckDB 1.5.5-r.4 dependency
was supplied from the installed connector dependency tree. No baseline source or
limit was modified.

The new capability probe invoked that exact example entry with all 27 pinned
fixtures and separately generated input databases. **0 verified, 27 incomplete**:
21 cases raised transport `Rows`; six numeric-64 cases rejected preparation.
Even 100-row narrow cases exceed the example's fixed 100 received-row ceiling
when full-scan validation and projected acquisition output are both received.
The six wide cases exceed the original example's supported preparation profile.
The probe returned exit code 1 and did not discard any failed case. No pending
cleanup was reported, and its per-case temporary directories were removed.

This is a compatibility result, not evidence that baseline execution is slow,
and supplies no denominator for a speedup ratio. A benchmark adapter must expose
the registered capacities through old public contracts, or clearly identify any
capacity-only assembly adaptation, without importing new execution algorithms.
The unchanged baseline cannot silently be replaced by current materialized code.
Until comparable execution is established, the baseline performance gate remains
incomplete even though retained readiness has passed.
