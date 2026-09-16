# Existing-contract direct-path diagnostic at 46c5b033

This is diagnostic coverage, not formal performance acceptance and not a
new-profile execution measurement. Raw results are in
[direct-matrix-fixed-46c5b033.json](direct-matrix-fixed-46c5b033.json).

## Reproduction and scope

- Source: `46c5b03349901fdf54422d51264c62dae488b73d`, clean worktree.
- Runner: `node adapters/duckdb-node/bench/direct-matrix.mjs` after release JS
  builds of `connectors/duckdb/host_node`, `retained_host_bridge`,
  `process_host_bridge`, `connectors_builtin_node`, and `physical_strategy_example`.
- All 27 registered cases, including all 21 large cases, completed.
- The runner checked the source stamp before and after every case:
  `8a863deeec0155ccf928e2827020d1840f7cb5e3701da7539411ea7edffe0ca2`.
- Existing fixture capacities and the 1 GiB retention ceiling were unchanged.
- Each source database was constructed separately before timing. There were no
  preexisting resident copies. The controller process was reused across cases.
- Selection enabled resident candidates, but used the existing uncalibrated
  example estimates (`nativeMilliseconds: "1"`). This is not cost-calibrated
  candidate-selection acceptance.

The comparator asserts independent expected final row CID and count, completed
tasks, retained outputs, and child exit. It awaits cleanup, checks no cleanup
pending, and checks that the final completion is no longer retained. A case is
recorded as completed only after these assertions pass. The archived Store
snapshot is taken before cleanup; its retained bytes are not a post-cleanup leak
measurement.

Execution includes Host preparation, process startup, acquisition, validation,
Compute, required identities, independent holding, and child exit. Build, source
setup, and independent oracle work are excluded. Cleanup is measured separately.
Controller memory is sampled, not a proof of a non-row-scaling memory bound;
prior-case allocator state and peaks between samples remain limitations.

## Selected elapsed times

| Registered case | Execution seconds | Cleanup milliseconds |
| --- | ---: | ---: |
| Join/count, narrow, 1,000,000 rows | 21.084 | 2.855 |
| Downstream reuse, narrow, 1,000,000 rows | 23.490 | 9.642 |
| Downstream reuse, numeric-64, 100,000 rows | 76.335 | 6.343 |
| Downstream reuse, text-1024, 100,000 rows | 39.407 | 8.398 |

These are single samples, not alternating pairs or confidence intervals. Do not
infer an accepted speed ratio from historical diagnostic runs. The original
experiment and its equivalent-obligations comparison remain outstanding.

## What actually ran

Every reported Compute input used `verified-file-native-read`, with zero
parameter INSERT rows and zero stored-row JSON decodes. This removes the old
parameterized import path, but does not remove the typed validation scan.

The wide reuse case still validated 6,400,000 cells for each of three inputs:
19,200,000 cells in total, with three logical CID passes. Its input intervals
were 9.023, 9.018, and 8.980 seconds (about 27.022 seconds combined). These
intervals include physical integrity checking, native file import, and typed
validation; they are not isolated validation CPU measurements.

The long-text reuse case likewise had three input scans and CID passes, taking
4.680, 4.685, and 4.650 seconds respectively. These nested timings must not be
added to total execution time a second time.

The resident-only evidence-reuse fast path was not used for these fresh-file
inputs. Thus this matrix does not measure that optimization or the managed
profile's CID-optional completion components. In particular, the new component
APIs do not yet establish end-to-end managed-profile execution.

## Next implementation boundary

Fresh-file import currently performs `read_json` conversion followed by a full
typed scan and required CID validation. Skipping that scan requires an adopted,
scoped preservation rule for the actual conversion and exact immutable material,
view, producer, and attempt; a source file hash alone does not establish it.
Consumer-specific demand, guard, logical accounting, and current use rights must
remain. This work must be measured separately from changing identity obligations
under the new profile. No resource limit or performance gate is relaxed here.
