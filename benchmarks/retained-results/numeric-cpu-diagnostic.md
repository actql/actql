# Numeric direct-path CPU diagnostic

This is a sampling diagnostic, not a formal paired acceptance measurement.
No fixture, capacity, timeout, selection estimate or performance gate changed.

## Reproduction and scope

- Before: `0b75ec54109fbfe451530e1d249e206ae9213c55`.
- After: `7ec0f29c1668bb2cdd49d80afbe3f10b8cbc0a60`.
- Case: `retained-large-output-downstream-reuse/numeric-64/10000`.
- Node: 22.23.2. Both controller and actual managed execution child were sampled
  using `node:inspector` Profiler at a requested 1,000 microsecond interval.
- Existing source: `/tmp/actql-resident-pairs-retry.ZCowPn/source-2.duckdb`.
  Source preparation and release builds were outside the timing.
- The `retained-case.mjs` diagnostic used resident enabled and the explicit
  `nativeMilliseconds=20` estimate. All three Compute tasks actually selected
  fresh `verified-file-native-read`. This is not calibrated normal-selection
  acceptance evidence and no existing resident copies were preloaded.
- Raw profiles, collector and reports are in
  `/tmp/actql-cpu-profile.vaAQJ5/`. `result-retry.json` is the completed before
  run; `result-after.json` is the completed after run. An earlier `result.json`
  failed because its holding parent directory was absent; it is not a sample.
- Clean source checks in the diagnostic passed before and after each completed
  run. The real typed-fixed-host test rebuilt the changed release package.

To reproduce the collector, preload a CommonJS script through `NODE_OPTIONS`
that connects an inspector Session, enables Profiler, sets its sampling interval
to 1000, and starts it. In a `process.once('exit', ...)` handler, stop Profiler
and synchronously save `{pid, argv, profile}` under a distinct PID filename.
The installed execution child inherits the preload without changing product
process-launch configuration. Its `argv` identifies `managed-worker.mjs`.

## Observations

Both successful runs produced the independent expected result:

`sha256:f0f9917156f2addb23984864ca96060363a2152a245424acaea9e6d0790848cd`

Both completed the comparator's retention, child exit and cleanup assertions.
Each of three Compute inputs verified 10,000 rows / 640,000 cells, with one
logical CID pass, no stored-row JSON reconstruction and no parameter INSERT.
Each held input file was 6,275,800 bytes. Verification has not been eliminated.

| Quantity | Before | After |
| --- | ---: | ---: |
| Profiled managed Host cycle | 9,177.90 ms | 9,450.03 ms |
| Execution-child profile duration | 8,888.08 ms | 9,144.54 ms |
| GC self samples | 1,364.75 ms | 1,425.16 ms |
| `admit_physical_usage` self samples | 728.12 ms | 186.75 ms |
| `hex_bits` self samples | 401.12 ms | 742.58 ms |
| `admit_utf8_window` self samples | 674.50 ms | 703.54 ms |
| `preflight_transport_columns` self samples | 303.92 ms | 297.96 ms |
| `decode_transport_columns` self samples | 296.67 ms | 310.92 ms |
| SHA-256 `compress_words` self samples | 256.75 ms | 267.92 ms |

Self samples are `timeDeltas` attributed to sampled leaf functions, aggregated
across nodes with the same function name. They are not instrumented phase
durations, not inclusive costs, and not an exhaustive classification. JIT
inlining can move attribution between callers and callees. In particular the
physical-admission/hex split changed substantially, so neither individual
function's delta establishes a performance result. SHA compression alone also
does not include canonical encoding and all hashing overhead.

The before controller was mostly idle (8,609.0 ms sampled). The execution child
instead spent considerable time in GC and transport/value conversion. Thus the
remaining work cannot be attributed solely to DB INSERT or SHA compression.

## Change and remaining work

`7ec0f29c` accumulates hexadecimal digits in 32-bit groups before widening to
UInt64. Previously every nibble used UInt64 operations (BigInt on the JS
target). Exact lower-case syntax, all 64 bit positions and special floating bit
patterns remain checked; no semantic admission, scan, guard or CID is omitted.

Adapter tests passed on JS/Wasm/native (20 each), and the real
`typed-fixed-host.test.mjs` passed. Formatting and diff checks passed. This is
not the full regression suite or an all-27 measurement.

The end-to-end diagnostic does **not** show a speedup. Retain this unfavorable
observation; do not advertise the local change as a measured overall gain.
Formal repeated measurements remain outstanding. The larger priorities remain
reducing repeated physical/typed transport and verification under exact owned
evidence, and direct output with verified logical-to-physical mapping. Merely
matching a physical file digest does not prove native JSON conversion preserves
the logical content and cannot authorize skipping that verification.
