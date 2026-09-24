# Retained execution cost review

The fixed `e09ffd716` Linux assessment remains the acceptance baseline. Its
registered 27-case matrix, resource ceilings, comparator obligations, and
identity rules must not change to make a performance result pass. This review
separates costs that can be removed from obligations that must remain.

## Measured diagnostic boundary

A local macOS arm64 diagnostic used the existing 10,000-row, 64-column retained
reuse fixture and the ordinary managed Host, but forced the fresh DuckDB
candidate with synthetic one-millisecond estimates. It did not exercise the
resident realization selected by the registered paired assessment. This is a
cost attribution probe, not a paired Linux acceptance result. Each of its
three DuckDB tasks used the `verified-file-native-read` input representation.
The task did not use the
Node Appender (`appendedRows = 0`). Each task admitted 640,000 input cells and
640,000 output cells. In one faster local run, input admission took about
0.54–0.59 seconds per task, output admission about 0.49–0.50 seconds, and
output stream draining about 0.32–0.33 seconds. Physical output writing took
about 7–8 milliseconds and was already coalesced into about 20 writes for
10,000 rows. Runs made under other machine load were substantially slower;
these local times are not stable performance estimates.

Set `ACTQL_DUCKDB_COST_DIAGNOSTICS=1` to record the separate JSON encoding,
MoonBit admission, stream drain, and Store writing intervals in task phases.
The flag defaults off; zero timing fields when it is off are not observations.
The interval measurement itself has overhead, so formal paired timings must
use the default path.

A bounded multi-row drain experiment preserved per-row MoonBit admission and
identity, but did not reduce elapsed time in the same fixture. It added a
second UTF-8 length pass and extra intermediate arrays. The experiment was
removed. A separate Node DataChunk Appender experiment improved its own
microbenchmark but could not affect this fixture because the Appender is not on
the selected production path; it was also removed.

The measured path therefore points to repeated whole-cell admission and
canonical row construction, rather than filesystem write count or Appender
calls. The cost of output admission is distinct from output identity generation;
the diagnostic does not prove either can be skipped.

A subsequent CPU profile of the selected 10,000-row, 64-column path showed
substantial time in physical scalar decoding and allocation. A JS DataView
replacement for floating-point hex parsing passed the adapter tests but did
not improve this product path in an A/B probe; it was removed. The physical
number path instead now uses a scalar value-admission operation after the
physical token has been decoded. It preserves the generic path's exact number
contract, finite/negative-zero check, one-node charge, and error location,
without allocating its traversal stack for every numeric cell. A targeted
comparison checks values and budget errors for nullable and non-null numbers
on all three MoonBit targets. The transport preflight also records its final
source position, removing a separate full-frame position scan after parsing.

The same wide fixture still admitted 640,000 input and 640,000 output cells per
task, reused physical identity without a logical-CID pass, and produced the
same final rows CID after these changes. Local end-to-end probes varied enough
that they do not establish a reliable speedup or a passing performance result.
The remaining whole-cell admission, JSON transport, output row construction,
and parent/worker preparation costs remain open.

The next transport change replaces generic raw-JSON tree traversal for a
physical column with a flat, closed scalar-column admission path. It checks
shape, Unicode, cumulative text bytes, node count and depth while building
the owned cursor once, in cell order. This removes the adapter's separate
per-cell text-length pass and the generic decoder's continuation stack. Its
cursor usage and failures are compared with generic raw admission on JS,
Wasm and native. JSON parsing and the subsequent ActQL value admission remain;
this is not a claim of zero-copy transport or a timing pass.

The registered retained-reuse record shows a different path: all four tasks
selected `duckdb-resident`. The first and join tasks scanned the full resident
input, while the filter task also scanned every stored column because the new
comparison demand prevented whole-input value reuse. That repeated an
immutable 64-column validation to obtain one demanded field. The receiving
stream now reuses exact live generation value and measurement evidence when
its limits permit, then reads only the filter column in original `rowid` order.
The new demand is measured and charged separately. If evidence, SQL projection,
or bounds are unavailable, the original full scan remains in place. This does
not skip a fresh join or the output's own admission and retention.

The product Host regression for 10,000 rows and 64 columns completed with the
same final rows CID. Its filter task reported one reused input and one demand
column scan, zero full input scans, and 650,000 native semantic cells: 10,000
input cells plus the unchanged 640,000-cell output. The first and join tasks
still scanned full inputs. The resident data-profile suite passed, including
the 10,000-row case. These are path and correctness observations; timing under
this machine load is not an acceptance result.

At clean revision `c1ffb07a4`, the unchanged local registered narrow/100
runner completed seven qualified equivalent-obligations pairs. Its warm
overhead interval was 41.963–74.565 milliseconds against the 10 ms limit;
cold overhead was 971.479–1392.912 milliseconds against the 100 ms limit.
This is still a failure. The result was slower than earlier local assessments
under different machine conditions and must not be used to attribute a
regression to the scalar change. It also confirms that removing scalar
traversal does not resolve the startup gap. The one-case evidence is in
workspace scratch at `.codex-scratch/perf-equivalent-small-c1ffb07`; the
other 26 cases and the fixed Linux assessment remain outstanding.

## Small-case startup cost

The 100-row narrow fixture used about 225 milliseconds for parent preparation,
217 milliseconds for child preparation, and 83 milliseconds to start the child
in one local run. Its three task intervals summed to about 35 milliseconds.
Both processes load and compile the same 15 MB generated JavaScript runtime,
then each performs full application preparation. A CPU profile located a large
part of the fixed startup cost in JavaScript module compilation.

The Node managed Host now enables Node's built-in on-disk module compile cache
before importing its generated runtime; the standard Node Host does the same.
This caches V8 code, not ActQL checking results or authority. Node's
`NODE_DISABLE_COMPILE_CACHE=1` remains an opt-out, and a failed or unavailable
cache leaves execution unchanged. In a local single-run comparison using a new
cache directory, the first run took 876 milliseconds and the next fresh-process
run 587 milliseconds. Parent module import fell from 108 to 24 milliseconds;
worker preparation fell from 279 to 179 milliseconds. Output identity and
completion were unchanged. These are diagnostic observations, not a paired
acceptance result; cache warmup, filesystem policy, and the remaining checking
cost must remain visible in cold-run reports. See the [Node 22 module compile
cache contract](https://nodejs.org/download/release/v22.17.0/docs/api/module.html#module-compile-cache).

At clean revision `2d931055a`, the unchanged local registered one-case runner
completed seven alternating qualified pairs for
`native-acquisition-full-validation-low-selectivity/narrow/100`. The 95%
interval was 22.823–24.353 milliseconds of warm overhead against the 10 ms
limit, and 529.610–535.367 milliseconds of cold overhead against the 100 ms
limit. The result is a timing failure, not an incomplete obligation check.
The other 26 cases and three other comparator families were not measured at
this revision. The raw one-case assessment is retained in the workspace at
`.codex-scratch/perf-equivalent-small-2d931`; it is not a durable CI artifact.
The compile cache is a useful reduction, but it does not close the fixed-cost
gap. Full application preparation remains duplicated across processes.

A scratch-only minification experiment reduced the generated example runtime
from about 15 MB to 3 MB. With a warm Node compile cache, alternating local
probes reduced median total time from about 510 to 463 milliseconds, while the
sum of task intervals rose from about 34 to 39 milliseconds. This was not an
accepted product change: it does not address the dominant remaining cold gap,
and the warm effect needs a controlled paired assessment. The scratch runtime
override was removed.

A separate CPU profile of 100 repeated warm application preparations showed
that the example re-admitted the same installed relation registry and fragment
contract for every stage. The preparation now admits these immutable contracts
once per application, while each stage still prepares and checks its own
fragment against its own lowering request. In one profiler run, 100 repeated
preparations took 2,259 milliseconds before this change and 2,080 milliseconds
after it. This is a local attribution probe, not an alternating performance
assessment or a claim that cold preparation is solved. The parent and worker
still prepare the application independently.

The unchanged registered narrow/100 assessment at clean `dbf36ac57` then
completed seven qualified pairs and still failed: warm overhead was
28.658–32.773 milliseconds against 10 ms, and cold overhead was
652.437–749.094 milliseconds against 100 ms. These intervals were worse than
the prior local run, so the small preparation probe must not be presented as a
measured end-to-end improvement. Both assessments remain local diagnostics;
the final Linux acceptance run is still required. The raw assessment is in
workspace scratch at `.codex-scratch/perf-equivalent-small-dbf36`.

## Next changes to test independently

1. Separate immutable application preparation from per-run parameter,
   authority, material, and budget checks. The managed example currently calls
   `prepareExampleText` in both controller and worker. Preserve child-side
   validation at the process trust boundary; reuse only an exact, authorized
   preparation result where its issuer, Program, contract pins, and lifetime
   can be checked.
2. For retained input reuse, identify the exact generation, physical bytes,
   schema, order, owner, and validation evidence already established by the
   previous task. Reuse only evidence that satisfies the new consumer's
   obligations. Current authority, availability, resource reservation, new
   expression evaluation, and consumer-specific logical work remain fresh.
3. Profile canonical row encoding and hashing separately from cell admission.
   The writer already hashes checked ASCII spans, so replacing only byte-wise
   ASCII hashing is not an untried general solution. Test any new encoder on
   its selected production path and compare exact output bytes and CIDs.
4. Diagnose the two `text-1024` calibration failures by exact case, rejection
   site, and logical charge. A candidate that cannot satisfy the registered
   ceiling is ineligible; it must not be assigned a fictional slow timing or
   block timing of a feasible candidate. Do not raise the ceiling implicitly.

The first calibration probe at `7d2ffee26` narrowed this gap. Separate-source
training for the low-selectivity and join/count `text-1024/1000` fixtures
completed for both Local and DuckDB. The retained-reuse `text-1024/1000`
forced Local candidate instead failed before completing its first task. An
instrumented scratch run found
`LocalDispatchIssue.Preparation(Materializing(Candidate(Execution(Rows(0,
RowLimit)))))`; the 100-row training candidate also failed. This identifies
the first Local sequence operation. The Local output budget is cumulative
across operations in a task. In this registered program, both `filter` and
`select` preserve every retained-reuse row, and each materialized output
charges the 1,024-byte payload plus `id` and `payload` field names. The lower
bound is therefore `2 * rows * (1024 + 2 + 7) = 2066 * rows` text bytes,
above the unchanged `2048 * rows` ceiling. This is a genuine Local
ineligibility under the registered limit, not a slow Local timing or a physical
copy charge. The instrumented diagnostic was removed.

The calibration profile now records this exact eligibility proof and leaves
Local timing absent for the retained-reuse text cases. The standard Host omits
the Local offer for those cases while still measuring and selecting DuckDB.
The profile admission recomputes the proof for training and held-out cases;
it rejects a fabricated Local rate or a mismatched eligibility claim. Other
registered cases still require measured Local and DuckDB training. This is a
candidate-selection correction, not a performance result.

The next Node resident-import change removes a separate per-row transport-byte
pass and per-cell staging pairs. It validates the whole typed row, measures its
bounded physical charge, and charges before any native write. The validated
values are passed to DuckDB through batches of at most 64 rows and 1 MiB of
charged representation, with a single oversized-but-admitted row isolated in
its own batch. The existing session owner flushes pending rows before finish;
chunk construction or append failure poisons the physical appender and follows
the same cleanup path. Canonical 32-bit integer strings now convert without
`BigInt`, and float bit strings decode through a fully overwritten scratch
buffer. The byte and value contracts, whole-row rejection, and independently
retained output remain unchanged. The complete Node connector suite passed
145/145 after this change. This is an implementation change, not a measured
end-to-end gain.

At clean revision `bbef1ad52`, the registered equivalent-obligations
`retained-large-output-downstream-reuse/numeric-64/10000` case completed seven
local paired observations. Its execution ratio was 1.7041, with a 95% interval
of 1.5323–1.8611 against the 1.25 limit: a failure. The first resident import
alone took about 2.25 seconds. This fixed case selected the resident path, so
the earlier forced fresh-file probe cannot explain its full cost.

Revision `96977d16d` stages eligible retained scalar rows directly into the
provisional DuckDB resident table and then performs an ordered typed scan to
verify the exact retained receipt before commit. The Store read, frame bounds,
transfer charge, typed values, complete content identity, and cleanup ownership
remain in force. The first local one-case paired run at this revision completed
seven pairs but was too variable for a conclusion: its execution ratio interval
was 0.980–1.901 and crossed the 1.25 threshold. Product execution ranged from
11.1 to 15.3 seconds and the comparator from 5.2 to 18.3 seconds. This is not
an end-to-end speedup claim, and the Linux 27-case gate remains open.

The subsequent output-side change uses the already necessary canonical
retention encoder's byte, node and depth progress to charge the native result's
record guard on the ordinary successful path. Key order does not change encoded
record length or node count. If any guard could fail, or encoding itself fails,
the original ordered record measurement still runs so its precise error and
partial charge remain observable. This removes a second per-cell canonical
encoding pass for successful retained acquisition results. Its product Host and
three-target adapter regressions pass; the paired performance effect has not
yet been measured.

At clean revision `30e8d13d`, seven local paired observations of the same
registered wide/reuse case yielded an execution ratio interval of 1.311–1.555.
It still fails the 1.25 limit. The task traces showed about 1.6 seconds of
output callback time for each of the three wide retained tasks in one pair,
while the first resident import and two full input verifications also remained
material costs. The interval is directional only; it does not isolate the
output change from machine load or prove the final Linux result.

The retained Compute output stream now records each checked cell's byte and
node usage while emitting its required canonical retention bytes. When every
value and the shared budget fit, it charges those exact per-cell quantities
without constructing a second measurement writer for every cell. An output
failure or any potentially failing guard uses the original ordered measurement
to retain the first failing column, partial work charge, and error shape. This
also leaves the output CID, retained bytes, and independent Store seal intact.
The three-target execution-relation tests and real-DuckDB Host tests pass; a
paired assessment at this later revision is still pending.

The single registered wide/reuse comparison at clean `066c7ca56` still failed:
seven pairs gave an execution ratio interval of 1.401–1.545. Output callbacks
were roughly 0.7–1.0 seconds per wide task in that local run, but the comparator
also ran faster. This is not evidence that the ratio improved. The first
consumer still performed a full input value scan, and another later consumer
did so as well.

The canonical retention encoder can also preserve per-column value bytes,
nodes, maximum value size, and depth while it emits the required output once.
The source capture and retained Compute outputs now attach this summary only
to the exact sealed material generation. A receiving task may reuse it if the
current owner, representation, limits, authority and receipt all match; tighter
limits retain the original ordered scan and first failure. The value summary is
not a substitute for new comparison or join demand. A real standard-Host count
fixture now reuses values at all three consumers without another full scan,
including a projected input. The exact first-consumer and tighter-ceiling
regressions pass on all three MoonBit targets.

At clean revision `f83d2968`, the registered wide/reuse case completed seven
local paired observations with an execution ratio interval of 1.251–1.332.
The limit is 1.25, so the case still fails; the one-case run cannot establish
the full 27-case result. All three tasks reported reused input values, zero
full input scans, and one narrow comparison-demand scan each. The input
verification intervals fell to about 8–15 milliseconds per task in those
observations. First resident import remained about 0.85–1.04 seconds and wide
output callbacks about 0.7–1.0 seconds each. These measured residuals, plus
the separate small-case startup gap, set the next optimization priorities.

The controller's preparation cannot simply be dropped: its independently
checked task identities constrain the worker's completion claims before the
attempt is accepted. A prepared artifact shared across that process boundary
would need an exact issuer, Program, contract-pin, and lifetime binding. The
native standard Host has a promising lower-startup path, but currently commits
its materialized output before an independently durable file holding is
established. Its short diagnostic timing therefore cannot replace the
registered retained comparison until that completion boundary is implemented.

At clean `bbef1ad52`, the registered wide-reuse case
`retained-large-output-downstream-reuse/numeric-64/10000` completed seven
alternating equivalent-obligations pairs with ordinary candidate selection. It
still failed: the execution ratio was 1.7041, with a 95% interval of
1.5323–1.8611 against the 1.25 limit. This is one local case, not the 27-case
Linux result. In one product run the first resident import took about 2.25
seconds; the 10,000-by-64 native Appender alone took about 0.09–0.11 seconds
in a separate microbenchmark. The retained file's row-by-row MoonBit decode,
physical parameter encoding, and JS conversion therefore remain a stronger
candidate than native append for removing import cost. Different revisions
and machine loads prevent attributing the ratio change to one commit.

The next structural change stages eligible Number/Boolean/Text retained rows
through bounded native scalar batches, then scans the provisional DuckDB table
in insertion order through MoonBit's typed physical admission and the exact
retained-content verifier. No table becomes a resident input before the full
receipt matches and the transaction commits. Other shapes keep the existing
row importer. Direct native file import into a long-lived resident database was
not selected: DuckDB's file allowlist must be installed before external access
is disabled, and this resident environment can receive later retained inputs.
Re-enabling external access or leaving it open would weaken the existing
session boundary. The new staging path is a correctness-checked implementation
candidate, not yet a performance acceptance result.

The scalar staging path now verifies each retained row through the same MoonBit
content scan used by the typed importer before appending it. It finishes the
exact receipt after the Store read and native Appender finish, before the
resident table is committed. This removes the additional full DuckDB table
readback and its physical-result conversion. The physical adapter remains the
trusted in-process conversion boundary, as it is in the typed importer; the
Store digest, ordered row admission, exact receipt and later consumer checks
remain required. The real-DuckDB standard Host and three-target adapter tests
pass. Performance at this later revision is not yet an acceptance result.

At clean `c270e651b`, that first change did not establish a speed win. The
single wide/reuse case's seven pairs produced a broad 1.031–1.662 ratio
interval, and the first import still took roughly one second in a representative
pair. The row-level MoonBit decode and logical rehash replaced the removed
DuckDB readback. The next change therefore uses the installed Store's stronger
existing fact: these canonical bytes were sealed against the output receipt CID,
and a fulfilled Store read rehashes those exact bytes before it returns. For
eligible scalar rows, the Host checks the sealed CID before import, parses and
appends bounded rows, then matches the Store-verified byte count, framing row
count and live exact receipt after Appender finish. A noncanonical physical
copy keeps the typed scan path. No consumer receives the provisional table
before the transaction commits. This avoids another full semantic decode and
rehash of a trusted immutable copy; the fixed Host, Store and physical Appender
remain the explicit trust boundary. The 27-case gate remains outstanding.

At clean `e1432a428`, one registered wide/reuse case passed the unchanged
equivalent-obligations timing limit. Seven alternating pairs for
`retained-large-output-downstream-reuse/numeric-64/10000` gave a 95% execution
ratio interval of 0.742–1.213 against the 1.25 limit. The first resident import
used one SQL statement and took 0.17–0.69 seconds across those observations.
This is a local one-case result, not a Linux or full-matrix acceptance result;
the other 26 cases were not measured at this revision. The raw series and
assessment are in the workspace scratch directory
`.codex-scratch/perf-equivalent-wide-e1432a42`.

For each change, report actual input and output scans, cells, bytes, imports,
encodes, hashes, and physical holdings before and after. Include parent and
worker preparation separately. Keep overlapping intervals out of summed wall
time. Validate each isolated change against the same production fixture, then
run the fixed Linux paired assessment at a new SHA. Diagnostic ablations and
conditional-CID profiles must be reported separately from the registered
acceptance profile.

## Small-result execution-path decision

The registered narrow/100 case remains far outside the fixed startup limits.
In the last measured product sample, the controller spent about 173 ms on
preparation, process start about 100 ms, and the child another 176 ms on
preparation. The three selected Compute tasks together took about 34 ms. A
separate preparation probe found no single dominant checker operation after
module import: parsing, checking, lowering, contract admission, and hashing all
contribute. Shaving one helper cannot plausibly close a cold gap of more than
500 ms or the remaining warm gap.

The next structural implementation should use the existing native standard
Host as a single-process execution path for eligible bounded local cases.
This is a change of physical realization, not a change of the checked Program,
ordinary candidate selection, resource ceilings, required identity, or
completion semantics. The existing Node process profile remains useful when
process isolation is required. The native path must first establish the same
independent, immutable file holding **before** each common task completion is
made available to a downstream consumer. Its task-by-task entry point already
exists, but the present native diagnostic only checks the final CID and cleanup;
it does not meet this holding or fresh-reader obligation.

Implementation order for that path:

1. Give each selected task an exact native file-holding owner, separate from
   its DuckDB session or Local temporary rows. Reserve the registered byte
   ceiling before writing; export in bounded chunks; seal only after the
   complete ordered output and required CID/measurement have been established.
   A failed seal, unlink, or sync retains cleanup ownership and accounting.
2. Connect the sealed holding to the common task completion with the checked
   task/attempt/output binding. A Store digest is physical integrity evidence,
   not an execution success claim. No downstream input may see the provisional
   file or a completed task lacking its required holding.
3. Admit the next task through a fresh bounded reader of that exact holding.
   Preserve its current authority, logical work, full-read evidence, and
   independently confirmed release. Do not reopen the source database or
   recompute a producer solely to satisfy this reader.
4. Exercise the registered narrow and wide fixtures through the normal Host,
   including Local and DuckDB selections, negative ownership/tamper/cancel
   cases, and real cleanup. Extend the paired runner only to invoke this real
   product path and record the same fresh-process cold and task warm boundaries;
   never replace the direct comparator or the fixed thresholds.

The first meaningful timing checkpoint is after those four pieces are
connected. The native diagnostic's earlier roughly 22 ms median is only a
feasibility signal because it lacks independent retention. It is not a speed
claim for the completed path. The full 27-case Linux assessment and the other
registered comparator families remain the acceptance gate.
