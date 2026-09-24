# Retained execution cost review

The fixed `e09ffd716` Linux assessment remains the acceptance baseline. Its
registered 27-case matrix, resource ceilings, comparator obligations, and
identity rules must not change to make a performance result pass. This review
separates costs that can be removed from obligations that must remain.

## Measured diagnostic boundary

A local macOS arm64 diagnostic used the existing 10,000-row, 64-column retained
reuse fixture and the ordinary managed Host. This is a cost attribution probe,
not a paired Linux acceptance result. Each of its three DuckDB tasks used the
`verified-file-native-read` input representation. The task did not use the
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

For each change, report actual input and output scans, cells, bytes, imports,
encodes, hashes, and physical holdings before and after. Include parent and
worker preparation separately. Keep overlapping intervals out of summed wall
time. Validate each isolated change against the same production fixture, then
run the fixed Linux paired assessment at a new SHA. Diagnostic ablations and
conditional-CID profiles must be reported separately from the registered
acceptance profile.
