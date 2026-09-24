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
the first Local sequence operation and the registered
`rows * 2048` cumulative text ceiling as the next accounting boundary to
inspect. It does not yet prove whether the charge is a duplicate obligation
or a genuinely ineligible Local candidate. The instrumented diagnostic was
removed; the registered ceiling and matrix remain unchanged.

For each change, report actual input and output scans, cells, bytes, imports,
encodes, hashes, and physical holdings before and after. Include parent and
worker preparation separately. Keep overlapping intervals out of summed wall
time. Validate each isolated change against the same production fixture, then
run the fixed Linux paired assessment at a new SHA. Diagnostic ablations and
conditional-CID profiles must be reported separately from the registered
acceptance profile.
