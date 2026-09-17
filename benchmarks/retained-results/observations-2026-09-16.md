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

## Follow-up: public baseline assembly and remaining internal capacities

A separate `received-row-envelope` probe mode now assembles the old public
MoonBit/Node APIs without changing any archived source. It raises only the
transport received-row allowance; the final formula includes metadata rows as
well as full validation and projected output. The first diagnostic formula
omitted metadata for low-selectivity cases; that formula was corrected rather
than treating its `Rows` failure as evidence of an internal semantic limit.

With the corrected allowance, the 100-row narrow selective case gets past the
Node row check and fails the MoonBit Host boundary instead. The earlier full
27-case diagnostic also exposed fixed cell and preparation limits after the row
check. No successful timing samples were produced. Inspection confirms fixed
100-row/10-column acquisition and transport limits, 100-row generated sequence
and fragment input bounds, and small guard/retention envelopes in the original
example's `host_limits.mbt` and `limits_and_generation.mbt`.

Thus merely increasing Node transport settings cannot produce a comparable
baseline. The next adapter must parameterize the old example assembly's limits
explicitly, without copying new retained, batching or streaming algorithms into
the old runtime. This diagnostic mode remains distinct from both the unchanged
example and a future capacity-matched baseline. All failed cases remain incomplete.

## Follow-up: first verified capacity-adapted old-runtime execution

Diagnostic error reporting now retains MoonBit constructor names: the 100-row
selective case first failed `PhysicalResultIssue.RowLimit`, then (after raising
only that receiver cap) `NativeReceiptIdentityIssue.ReceiptRows`. This narrowed
the required change to two receiver ceilings rather than an execution rewrite.

A separate archive of the same baseline at
`/tmp/actql-baseline-capacity-CeBFcq` changes only those two literals in
`src/physical_strategy_example/host_limits.mbt`, from 100 to 104. The exact diff
is preserved in `baseline-receipt-104.patch`; the unchanged source SHA-256 is
`905a1ac2bbd1fa702b4da3a07b1ebd1a39c0b4141cc0875f00f60858dca4dc9a`.
After rebuilding with the pinned toolchain, the public-entry assembly with the
matching transport allowance completed acquisition and all three Compute tasks
for `native-acquisition-full-validation-low-selectivity/narrow/100`, matched the
independent final CID and completed cleanup. The probe exited successfully.

This proves one capacity-adapted original-runtime case, not the unchanged
baseline, all 27 profiles or any paired performance threshold. No new batching,
retained representation, encoder or evaluation algorithm was imported into it.
The larger and wider capacity profiles and other comparator remain unfinished.

## Follow-up: resident reuse phase attribution

Resident Compute now supplies the same installed task diagnostic channel with
sequential timings for input verification, view setup, materialization, receiving,
awaited output finalization and temporary SQL cleanup. It still imports zero rows
on reuse; verification is not silently counted as zero work. Finalization timing
includes the asynchronous independent-holding callback. Transaction settlement
and environment lifetime remain outside this callback-level interval.

Six real-DuckDB resident lifecycle tests pass, including awaited verification and
holding attribution, failed holding rollback, cancellation and cleanup ownership.
The related fixed-input, batching, standard-Host and benchmark-helper run also
passed 23 tests. These tests confirm attribution and preserved behavior, not a
wall-clock improvement or completion of the four-comparator performance gate.

The subsequent complete `adapters/duckdb-node/test/*.test.mjs` run passed all
75 tests in approximately 80 seconds, including the 27-case default smoke
(not the larger registered matrix). The patched baseline selective/narrow/100
case also passed again: one diagnostic execution interval was 189.868 ms and
cleanup 0.423 ms. This was measured while other tests were running and is only
instrumentation evidence, not an uncontended performance sample. The same case
against the unchanged archive failed `PhysicalResultIssue.RowLimit`, returned
exit code 1 and emitted no successful timing sample. The two-literal patch was
checked forward against the original tree and in reverse against the adapted
tree. Larger baseline capacities and paired equivalent-obligation timing remain
unfinished.

## Follow-up: selective 1000-row baseline receiver profile

A fresh pinned archive at `/tmp/actql-baseline-1000-z4KnQQ` was built with the
same pinned MoonBit and DuckDB versions. `baseline-receipt-1004.patch` records
six numeric changes to the example receiver assembly: transport rows, physical
rows/cells/nodes, receipt rows and receipt bytes. No runtime algorithm changed.
Both forward and reverse patch checks succeeded against the original and adapted
trees respectively.

The new `received-transport-envelope` probe supplies fixture-derived acquisition
transport bounds but preserves the old Compute envelope. Initially forwarding
the larger acquisition byte allowance to Compute correctly failed its selected
physical envelope; separating the two configurations fixed the benchmark wiring
without weakening that check. Failed task diagnostics now retain the actual
Host failure chain, not just `MoonBitHostFailure`.

Selective/narrow/1000 completed acquisition and three Compute tasks, matched the
independent final CID and cleaned up. One diagnostic run recorded 194.125 ms
execution and 0.373 ms cleanup. This is not paired performance evidence, a wide
or large-output compatibility result, or confirmation of equivalent obligations
across all four comparators. Those acceptance requirements remain open.

## Fixed-HEAD regression audit after receiver diagnostics

At `97f50c83996fe1622ce2a72517c70c49b3e135ef`, with the pinned toolchain:

- `moon test --target js --deny-warn`: 4328 passed.
- `moon test --target wasm --deny-warn`: 4327 passed.
- `moon test --target native --deny-warn`: 4327 passed.
- `npm run check:retained-boundary`: 77 passed.
- Portable Core, backend semantic and connector-dispatch boundary tests:
  16 passed, including negative injection cases.
- `node adapters/workers/verify.mjs`: passed, including real workerd,
  artifact/resolved-module checks and pinned stdlib verification.
- `node scripts/check-node-without-duckdb.mjs`: passed; isolated standard-entry
  execution plus 27 tests without the DuckDB dependency.
- `node scripts/check-moonbit-api.mjs`: passed across all three targets.

The runtime contract audit also distinguishes two tested paths. The installed
managed execution fixture selects Local-to-DuckDB and DuckDB-to-Local task chains
through normal estimates, verifies their independent result CID and file
holdings, and releases the process through common accounting. The separate
managed reader verifies, readmits, binds and physically reads a held result in
a new process; it does not start a new Compute. Its result must not be counted as
evidence of task continuation or control-Host restart recovery. No such capability
was added by this audit. The prior 75-test real-DuckDB run covers the former
execution fixture; this turn did not rerun that entire suite again.

These checks strengthen functional regression evidence, not the incomplete
four-comparator performance acceptance. Linux and remote CI were not run here.

## Follow-up: explicit data profile with resident reuse

The application no longer rejects `dataProfile` together with `resident` before
planning. Its import estimates now use profile-derived transfer and bounded
transport scratch, and the connector's existing full table retention bound for
the DB copy. Streamed completion metadata is reserved separately; it does not
replace that DB-copy allowance. The existing 128 MiB shared engine bound remains
unchanged, so this is not unlimited resident capacity.

The new installed managed-process test passes all three narrow 1000-row
workloads. Supplied fresh estimates of 20 select resident tasks through normal
comparison, with exactly one initial import and no downstream reimports. The
independent final CID matches, all Compute outputs are files, holdings survive
actual process exit, and explicit close leaves no pending file cleanup. This
is functional reuse evidence, not a performance comparison.

The JS application capacity test and existing real standard-Host integration
also passed. Attempting the application-only test on Wasm correctly reported
that this application package supports JS only; it is not a failed portable
Core test or a successful Wasm verification of this new application policy.
Full large/wide resident performance and final regression remain open.

Extending this test exposed an actual long-text start-capacity mismatch: the
candidate's native retained allowance also supplies the resident output-copy
ceiling, so using only streamed metadata understated that copy. The estimate
now conservatively covers both bounds via their maximum; execution still
accounts for the independent holding and shared copy separately. The regression
keeps this text-1024/1000 case through both installed in-process and managed
assemblies. It now completes with one import, reuse and the expected final CID.

Numeric-64/1000 correctly selects fresh DuckDB: its full-copy node allowance
alone exceeds the unchanged 128 MiB shared environment. The test checks that
lower bound explicitly and verifies normal fresh completion rather than forcing
resident placement. All five managed cases (three narrow workloads, wide reuse,
long-text reuse) pass. `check:docs` and cross-target API checks also passed before
the final conservative-estimate adjustment. After that adjustment, the JS
application test, cross-target API check and whitespace check passed again.

## Follow-up: resident profile refusal under a delegated attempt ceiling

The managed resident profile regression now also runs narrow retained reuse
with only two delegated attempts. It reports `host-tasks-failed`, publishes no
Compute completion, records no more than two attempts, and confirms actual child
exit with zero outstanding execution reservation. Explicit close removes the
capture holding and leaves neither pending cleanup nor output files. The cheap
resident cost estimate cannot bypass the delegated Run ceiling.

The combined test passes its five positive managed profiles, the independent
in-process long-text check and this budget-refusal case. No capacity threshold,
performance acceptance rule or execution semantics changed in this follow-up.

## Follow-up: reproducible 10000-row baseline acquisition adaptation

The baseline capacity transformations now reject source-hash mismatches and
unrelated profiles, return auditable numeric changes, and keep query/dispatch
algorithms unchanged. Original capacity helpers remain available to Compute;
scaled copies are used by Acquisition only. An earlier shared-helper attempt
raised Compute scratch unintentionally and was rejected at start; it was not
recorded as a successful sample.

A new archive at `/tmp/actql-baseline-scaled-mlQGqW` was rebuilt with the pinned
toolchain. The original 500000-byte transfer / 200000000-byte retention ledger
rejected the larger acquisition reservations. The explicit diagnostic ledger
now allows acquisition plus three unchanged Compute transfer envelopes, with
the registered managed benchmark's 1 GiB retention and 4 GiB execution caps.
Reservation checks and candidate envelopes remain active.

Selective/narrow/10000 completed acquisition and all three Compute tasks,
matched the independent CID and completed cleanup. A single diagnostic interval
was 242.430 ms execution / 0.413 ms cleanup, not a paired acceptance result.
The actual adapted files match the pure transformations byte for byte. All 17
benchmark helper tests pass. Wide/join/large-output baseline adaptations and the
equivalent-obligations comparator remain unfinished.

## Follow-up: distinguish baseline data and completion metadata capacity

The first selective/narrow/100000 baseline attempt rejected retention before
execution. Inspection found that the adapter had expanded completion-record and
capture metadata with source size, and allocated the multi-task cumulative value
allowance to each held copy. This was an overly conservative benchmark assembly,
not evidence that the old runtime inherently cannot process 100000 rows.

The revised adapter leaves record/capture metadata limits unchanged and derives
the value-node allowance from this fixture's flat two-scalar rows. All runtime
limit checks remain in place. A regression checks the original metadata block
byte for byte. The rebuilt archive `/tmp/actql-baseline-100k-4QRjMZ` completed
acquisition, three Compute tasks, independent expected CID verification and
cleanup within the 1 GiB retention / 4 GiB execution Run ceilings. One diagnostic
public-entry interval was 523.461 ms, cleanup 0.367 ms.

The retained registered 100000-row case also passed, with controller wire traffic
90583 submitted / 17063 received bytes and sampled RSS increase 56098816 bytes.
Its inclusive readiness diagnostic was 954.623 ms. These two timings have
different boundaries and are not paired; no speedup ratio or acceptance result
is inferred from them. All 17 benchmark helper tests passed. Full comparator
coverage and formal performance acceptance remain open.

## Follow-up: measure fresh and resident through the same retained entry

The retained diagnostic comparator now accepts explicit resident eligibility and
native cost-estimate inputs, snapshots them before execution and records their
hash alongside actual task realizations. Both modes include Host preparation,
child startup, validation, required identity, independent holding and child exit;
final file release remains separately timed. Default selection is unchanged.

All three narrow 100-row workloads pass with fresh and resident configurations,
with identical independent expected CIDs. Resident execution imports once and
does not reimport downstream inputs. Both paths release all output files. Invalid
options fail before preparation. The two comparator tests and all 17 benchmark
helper tests pass. These are functional checks of the measurement entry, not
paired timing samples or a claim that the supplied cost estimate is calibrated.
The equivalent-obligations comparator and full formal comparison remain open.

## Follow-up: wide selective baseline and current real-driver regression

At `c51444d4`, the complete real-DuckDB Node suite passed 77 tests, including
the 27-case default smoke and managed resident data profiles. This is not a rerun
of the larger registered matrix, the three MoonBit targets or remote CI.

The baseline capacity adapter now supports selective wide source shapes without
changing Compute's id-only envelope. A new pinned archive at
`/tmp/actql-baseline-wide-bhed5w` changes only example capacity arguments: source
column bounds, receiver/receipt limits, metadata matching work and the existing
benchmark ledger allowances. Runtime algorithms remain those of `b87584fe`.

Initial attempts were incomplete: overreserved retention, insufficient metadata
work, transport text exhaustion, then overreserved execution capacity. In
particular, numeric source values have no string payload, but their serialized
columns do use transport text. Logical wire is bounded separately from framed
transport; the two-row output does not need source-sized retention. The adapter
now makes these distinctions explicitly rather than enlarging the Run ceilings.

Numeric-64/10000 then completed acquisition and three Compute tasks, matched the
independent final CID and released its resources. One public-entry diagnostic
was 1329.507 ms execution / 0.428 ms cleanup. This is not a paired timing or a
performance acceptance result. Wide 100000-row, text, join and large-output
baseline execution still need verification/adaptation; equivalent-obligations
and formal paired comparisons remain unfinished.

## Follow-up: baseline comparison has an irreducible capacity conflict

At `c4ef5099`, JS 4328, Wasm 4327 and native 4327 MoonBit tests passed, as did
all 77 retained storage/process boundary tests. These reruns include the current
resident data-profile product changes. They do not establish formal performance
acceptance or remote CI success.

The new baseline feasibility audit ties its lower-bound derivation to exact
`b87584fe` receiver and native-capacity source snapshots. The receiver's counters
accumulate across the whole validation scan; the old capacity formula reserves
each physical row/cell/text bound twice. Even omitting nodes, wire, metadata and
all other output storage, the per-shape lower bounds are:

| Input | Minimum declared retention bytes |
| --- | ---: |
| narrow / 1000000 | 1536000000 |
| numeric-64 / 100000 | 3328000000 |
| text-1024 / 100000 | 1792000000 |

These exceed the 1073741824-byte retention ceiling for each of the three
workloads: nine registered cases cannot fit. This is a source-derived necessary
reservation, not a timing sample or RSS observation. Unlike the earlier overly
conservative adapter settings, it cannot be fixed by tightening assembly bounds.
The audit reports `not-ruled-out`, never `passed`, for the other 18 cases.

The audit CLI exits 1 as intended; all 20 benchmark helper tests pass, including
the source-hash and lower-bound regressions. The two `.mbt.txt` snapshots are
archival evidence only, not product implementations, and allow shallow CI to
check the evidence without fetching history.

An acceptance decision is now required for the impossible baseline comparisons:
retain the ceiling and explicitly report baseline capacity refusal instead of a
time ratio for these cases, or define a separate larger-capacity experiment for
both paths. No change to the registered matrix, budget, thresholds or failure
treatment has been made. The equivalent-obligations comparator remains a
separate unfinished implementation regardless of that decision.

## Follow-up: portable and document audit at 137cb8be

The Workers verifier passed its artifact/dependency checks and 24 actual workerd
runtime tests. `check:docs` and cross-target generated API verification also
passed; generated tracked files remained unchanged. These checks do not expand
the local process-retention guarantee into remote execution or durable recovery.

Review of the installed managed test confirms both DuckDB-to-Local and
Local-to-DuckDB selection with retained outputs, exact completion custody and
final independent CID checks. Fresh-process readmission remains a separately
tested read/bind path, not Compute continuation. No broader recovery claim is
made. The direct retained Compute entry is available for comparator reuse, but
its non-strategy entry omits DAG physical reservation; using it alone would not
establish equivalent obligations. That comparator is still unimplemented.

The baseline capacity decision requested above is still pending. Neither the
acceptance thresholds nor the registered failure treatment were changed during
this verification pass. Linux and remote CI were not executed.

## Follow-up: correct the baseline source-limits argument

Reading `limits_and_generation.mbt` showed that `source_limits(10)` takes a
stage count, not a source column count. The wide adaptation had unnecessarily
raised it to 64. That edit has been removed; the actual DuckDB query-mapping
column bound still becomes 64, while source topology remains byte-for-byte
unchanged. The regression now requires `source_limits(10)` for the wide case.

Rebuilding the same isolated baseline with this correction still verifies
numeric-64/10000 through acquisition, three Compute tasks, independent final CID
and cleanup (1393.514 ms diagnostic execution, 0.420 ms cleanup). All 20 benchmark
helper tests pass. This corrects the earlier characterization of source checking;
it does not change runtime algorithms, fixture identities or acceptance limits.

A separate diagnostic of narrow join/count at 100 source rows in this archive
fails before any Compute completion with transport `Rows`. The unchanged Compute
receiver has 100 rows total, while the old row-wise INSERTs consume response rows
before the query output is read. This acquisition-only archive is not a valid
join baseline profile. Future capacity matching must distinguish protocol
acknowledgments from logical input/output counts rather than treating this as a
join semantic failure or dropping the case from comparison.

## Follow-up: old-runtime narrow/100 join runs through completion

A new isolated `b87584fe` archive at `/tmp/actql-baseline-join-l7SeZX` uses the
small-join capacity transformation. Its original first attempt failed physical
`RowLimit`: the acquisition receiver's allowance must cover validation and
selected rows together. Raising that assembly allowance to 204, and separately
allowing the 200-row join result and downstream input, resolves the refusal.
Compute's Node envelope includes INSERT acknowledgment rows without counting
them as logical output. No runtime algorithm or canonical contract changed.

With `small-join-envelope`, the exact registered narrow/100 case completes
acquisition and all four Compute tasks, verifies the independent final CID and
cleans up. The one diagnostic was 261.954 ms execution / 0.456 ms cleanup, not
a paired acceptance sample. The transformation requires pinned source hashes,
keeps topology unchanged and is tested as numeric-only. The CLI rejects other
cases rather than pretending these small bounds scale to the full matrix.
The benchmark helper suite now has 21 passing tests. Larger join baselines,
equivalent-obligations comparison and the pending capacity decision remain open.

## Q7 selection diagnostic: resident capacity must not contaminate fresh offers

The capacity decision above was subsequently approved in
`acceptance-addendum-2026-09-16.md`; it is no longer awaiting approval. Neither
that approval nor this diagnostic establishes performance acceptance.

At `5937c155`, enabling resident alternatives with the unchanged supplied
`nativeMilliseconds: "1"` produced these observations for retained downstream
reuse:

- narrow/10000 completed in 1077.953 ms, with 1.168 ms cleanup. All three tasks
  selected fresh DuckDB and each imported 10000 rows. This is not direct-path
  selection evidence.
- numeric-64/10000 failed before any Compute task, with `no_feasible` and
  `retention_limit` on every candidate. The all-fresh estimate alone requested
  8,302,369,152 retained bytes under the unchanged 1 GiB limit. This is a
  declared reservation, not measured memory consumption.

The example reused a full DB-copy bound for fresh and resident estimates whenever
resident alternatives were enabled. The fix uses the streamed completion bound
for fresh offers. The connector independently adds the actual start-time DB-copy
minimum to resident offers, without lowering their capacity requirements or
raising any Run limit. A three-target regression checks that fresh remains
selectable while the undersized resident environment is still rejected.

With this correction, the same numeric-64/10000 case and default estimates
completed through three fresh tasks: 13730.013 ms execution, 19.979 ms cleanup.
Each task still imported 10000 rows. Input intervals were 2526.048, 2408.730 and
2437.463 ms; their included INSERT intervals were 549.843, 522.072 and 532.879 ms.
Query/receive intervals were 1138.976, 1100.182 and 1111.261 ms. The independent
final CID and cleanup checks passed. These are single working-tree diagnostics,
not alternating paired measurements or calibrated selection evidence.

This restores feasibility in that configuration; it does **not** satisfy Q7 for
the case. Required next work remains direct physical representation access and
justified normal selection, rather than row JSON reconstruction and reinsertion.
The 21-case scope, original fixtures and performance thresholds are unchanged.

The diagnostic also exposed a reporting bug: final cleanup dereferenced a final
completion even when no task had completed, masking the real capacity failure
with a TypeError. Cleanup now permits an absent final completion, still rejects
unconfirmed release, and preserves the execution report. The product timing leg
also retains the strategy explanation instead of reporting only chosen tasks.

### Native retained-file input diagnostic

The standard fresh DuckDB Compute path can now read an exactly borrowed managed
file using generated `read_json` SQL, instead of reconstructing each stored row
in JavaScript/MoonBit and producing INSERT parameters. This is physical parsing,
not proof reuse: the resulting table still passes the common ordered identity,
typed-value, demand and consumer-guard scan. The initial profile supports numeric,
Boolean and text columns; unsupported schemas retain the explicit row path.
Only the exact files are allowlisted before disabling general external access.
The Store borrow checks physical integrity and unchanged material before accepting
the callback result. Output remains canonical row JSON; this is not direct output.

With resident alternatives enabled and the unchanged default estimate of 1 ms,
`retained-large-output-downstream-reuse/numeric-64/10000` completed in 9042.736 ms,
plus 7.340 ms cleanup, under the same 1 GiB limit. All three tasks selected fresh
DuckDB with `verified-file-native-read` and zero parameter INSERT rows. Input
intervals were 1012.567, 988.567 and 985.486 ms; query/receive intervals were
1079.038, 1100.207 and 1080.349 ms. Independent final CID and cleanup checks passed.
This is one working-tree diagnostic, not a paired speed ratio, calibrated cost
selection proof, or a performance acceptance result. An earlier invocation used
the join/count oracle against the existing reuse source and failed the final CID
assertion; that mismatched-fixture invocation is not a timing sample.

Validation for this increment: retained native-input MoonBit tests passed three
tests on each target; real session tests passed 20; standard retained timing-leg
tests passed three; resident data-profile test passed one; retained boundary
tests passed 84; semantic dependency tests passed four. Generated interfaces
match across targets. All 21 direct cases, independent equivalent-obligation
comparison and formal performance acceptance remain outstanding.

### Full native-input exploratory matrix

`direct-matrix-diagnostic-2026-09-16.json` preserves all 27 outcomes from a
sequential exploratory run based on `112f262e`. All completed with the registered
1 GiB retention limit, independent expected final CIDs and confirmed cleanup.
Every Compute input used native file reads with zero parameter INSERT rows,
including all 21 registered large cases. Each fixture source was created in its
own setup process; no resident table was preloaded. The normal planner was used
with resident alternatives enabled and the existing 1 ms example estimate.
These estimates are not calibrated, so Q7 normal-selection acceptance is open.

This run is deliberately **not** fixed-revision performance evidence: telemetry
counters were added before cases 23–26, and a small Store regression test ran
during the last case. The revised `direct-matrix.mjs` runner detects source
changes before/after each future sample instead of silently accepting them.
No formal paired samples or confidence assessment are claimed.

Large diagnostic times: narrow million-row join/count 21.976 s; narrow
million-row reuse 25.239 s; numeric-64/100000 reuse 84.312 s; text-1024/100000
reuse 45.867 s. Wide reuse still performs three full consumer identity scans:
numeric-64 records 6.4 million validated cells per input, about 9.9 s per input,
and about 11 s per query/output interval. Native parsing removes row restoration
and parameter imports, not these validation/hash/output costs. Direct output,
safe proof reuse and the independent equivalent-obligation comparator remain
implementation work, not completed items.

Follow-up inspection found that the native input charged its physical file bytes
after the initial integrity scan. The Store now invokes installed read admission
before opening/hashing, and the adapter charges integrity plus native read there.
Negative tests show budget rejection wins even over a nonexistent file path,
does not enter native use, and cannot charge through a foreign consumer handle.

### Fixed-source follow-up at 19e947e1

`direct-matrix-fixed-19e947e1.json` records a second full run at clean
`19e947e19c8140ce2c64efb398df3f28ca79b503`, with unchanged source fingerprints
before/after every case. All 27 passed final identity and cleanup checks, and
all 21 large cases used native file input on every Compute port. Physical read
admission occurred before the integrity/native reads. The artifact includes
per-port work, intervals, control traffic/memory, ledger usage and hashes of
the raw per-case reports. Ledger peak retention is a reservation quantity,
not a resident-set-size measurement. Native file read counts are invocations,
not instrumented OS page reads.

Fixed-source diagnostic examples: million-row narrow join/count 22.169 s;
million-row narrow reuse 25.216 s; numeric-64/100000 reuse 88.049 s;
text-1024/100000 reuse 54.147 s. Differences from exploratory timings are not
paired ratios or evidence of a regression threshold being met/violated.

This closes one fixed-source 27-case functional/direct-input coverage check,
not Q7's calibrated selection requirement or formal performance acceptance.
The file/row choice is currently made inside the selected fresh DuckDB transport;
separate representation-aware cost evidence remains necessary. Independent
equivalent-obligation assembly, proof reuse and direct output are still open.

### Independent assembly prototype (not an equivalent timing sample)

The new benchmark-owned assembly executes the fixture without the product Host,
planner or DAG. It shares value admission and canonical encoding, independently
orders its SQL and table lifetimes, preflights join cardinality, and retains each
named intermediate through the low-level Store. It can charge completed scalar
measurement summaries to each consumer without rereading an unchanged private
table merely to measure the same values again. New, stricter consumer budgets
are not waived. This is a benchmark implementation, not product proof reuse.

Nine small workload/layout combinations passed final independent CIDs and
cleanup. Separate tests cover order/duplicate/NULL/Unicode encoding, permuted
transport columns, nonfinite values, cumulative budgets and poisoned streams.
An invalid field in a source row excluded by the filter is still rejected.

One numeric-64/10000 reuse diagnostic completed in 5328.820 ms, plus 5.618 ms
cleanup, including validation (958.714 ms), four independently held outputs and
three reused input measurement summaries. The final ordered CID matched the
independent fixture. **This is not an equivalent-obligation comparison or a
performance pass:** process/timing parity, combined DB/file capacity admission,
expression-demand failure parity, evidence metadata and accounting remain open.
The executable explicitly reports `acceptanceEligible: false` and its missing
obligations; its time must not be used as the registered 1.25 denominator yet.

### Managed-profile fixed-revision 27-case matrix

The clean `d14d58250dab73302aa4fadcea364a56a8265000` revision completed all
27 registered cases through `actql-managed-retained-execution/0.1`. Every case
reported zero logical-content CID computations and zero held/reserved bytes
after close. Exact one- and two-input producer ports were supplied by the
standard dispatcher; the checked join output was admitted once and reused by
the downstream count. Intermediate managed materials closed after their last
checked consumer, while sink results remained held for caller close.

All 18 acquisition/reuse cases used direct DuckDB-to-Store output and reported
zero JavaScript output-cell materialization and zero managed-frame re-encoding.
The nine join cases still create new values through the bounded fallback. Across
those cases, 2,662,218 cells were materialized and 20,812 frames encoded. Direct
join/group output therefore remains an explicit later optimization.

Representative elapsed times were 21.238 seconds for million-row narrow
join/count, 30.147 seconds for million-row downstream reuse, 86.590 seconds for
numeric-64/100000 reuse and 28.005 seconds for text-1024/100000 reuse. This was
one sequential diagnostic sample per case, not an alternating paired comparison.
The complete case table, controller-memory observations, ledger peaks and
interpretation are in
`managed-profile-fixed-d14d5825.md`.

The unchanged runtime tree then passed the existing CID-required registered
matrix as a separate compatibility run: all 27 case IDs, independent final CIDs,
managed-process exit and cleanup completed in 234.676 seconds. Representative
times were 18.896 seconds for million-row join/count, 23.487 seconds for
million-row downstream reuse, 88.610 seconds for numeric-64/100000 reuse and
36.751 seconds for text-1024/100000 reuse. This sequential run is functional
compatibility evidence, not the registered alternating paired assessment.

### First fixed-revision matched logical-accounting pair

The clean `8af2af7474e3872e6538ef4a12227e1e5da1e960` revision completed one
alternating pair for
`native-acquisition-full-validation-low-selectivity/narrow/100`. The independent
leg ran first and the retained ActQL leg ran second, each in a fresh process
against the same hashed immutable source. Source setup was outside both legs.

The two implementations reported exactly equal complete logical guard usage:
328 work, 2222 bytes and 316 nodes. They also reported equal comparison usage:
122 work, 207 bytes and 110 nodes. The independent implementation measured
324/2218/314 of the guard itself and charged the remaining 4/4/2 from an exact
retained measurement for the final consumer. The product implementation
measured the full 328/2222/316. This is the intended distinction: the logical
obligation is equal while one eligible physical measurement pass is reused.

Other physical accounting remains intentionally different. The independent
leg admitted 112 semantic rows and 212 cells; the product leg admitted 114 rows
and 214 cells. Identity passes, identity preimage bytes and retained Store bytes
were equal. The pair runner therefore admits exact logical-accounting parity
without pretending that physical work must be identical.

This is a single small diagnostic pair, not a timing acceptance sample. Both
legs still report `acceptanceEligible: false`. Expression-demand failure parity,
shared DB-plus-scratch capacity, acquisition evidence metadata parity, complete
transfer/work equivalence, negative fixtures and final equivalent-obligation
admission remain open. Observed timing is retained only as diagnostic output and
must not be used as a registered speed ratio.

### Fixed-revision independent resource admission follow-up

The clean `6449c8507526caa6aa5a941f4c855bd570360ebc` revision repeated the
same small matched case with the retained ActQL leg first and the independent
leg second. Exact logical-accounting parity remained true. This follow-up
closes the independent comparator's previously missing combined execution
capacity admission; it is not an acceptance timing sample.

Before opening DuckDB, the independent leg admitted one 2 GiB engine
reservation plus 38,798,848 bytes of simultaneous bounded transport, semantic,
container and SQL scratch. The resulting execution reservation was
2,186,282,496 bytes under the registered 4 GiB ceiling. The execution ledger
held that reservation during the leg and returned to zero after confirmed
DuckDB close.

Independent retention admitted an 84-byte output file and a 17,472-byte
metadata allowance. The four serialized completion records used 1,932 bytes,
so the settled holding was the exact 2,016 bytes rather than the allowance.
The retention ledger reported a 12,287-byte peak while outputs were created
and returned to zero after confirmed Store close.

The pair remains `diagnostic-completed` and deliberately not acceptance
eligible. Acquisition evidence metadata parity, complete expression-demand and
guard failure parity, transfer/work accounting equivalence, complete negative
fixtures and final equivalent-obligation admission remain open. The observed
565.673 ms retained and 27.539 ms independent execution intervals are recorded
only to identify this run; no ratio or performance conclusion is drawn from a
single order-specific pair.

### Fixed-revision acquisition metadata parity follow-up

The clean `31eb70c82a2ccb49b9d66c71948aa9434595d4e1` revision repeated the
small matched case with the independent leg first. Logical accounting remained
exactly equal and the pair now also reports
`acquisitionMetadataEquivalent: true`.

Both legs independently produced the same semantic acquisition metadata:
two receipt roles and three evidence roles, source and output contract CIDs,
parameter and resolved-request CIDs, scan scope, snapshot and retention state,
and the exact validation/native row CIDs, row counts, field order and canonical
row-array byte counts. The validation receipt covered 100 rows, two fields and
2,281 bytes; the native result covered two projected rows, one field and 21
bytes.

The comparison does not replace per-execution authority with a common token.
The retained leg verifies that every receipt and record uses its exact issuer,
attempt, read view and requirement, then verifies the receipt-to-record and
record-to-observation CID references before projection. The independent leg
uses its actual validation and capture outputs. The two projections are equal
only after those separate checks succeed. A changed coverage CID is rejected
rather than normalized away.

This closes acquisition evidence metadata parity for the registered comparator
shape, not complete failure or accounting equivalence. The pair remains
`diagnostic-completed` and not acceptance eligible. Complete expression-demand
and guard failure parity, transfer/work accounting equivalence, complete
negative fixtures and final equivalent-obligation admission remain open.
