# Existing-contract identity reuse diagnostic at 48ec97dc

This is a single-run diagnostic, not formal performance acceptance and not a
managed-profile execution measurement. The complete raw results are in
[direct-matrix-fixed-48ec97dc.json](direct-matrix-fixed-48ec97dc.json).

## Reproduction and scope

- Clean source: `48ec97dc230bdaf281c487f1220e50289ef8b226`.
- Runner: `node adapters/duckdb-node/bench/direct-matrix.mjs`, using the release
  builds exercised by the native-file identity-reuse smoke tests.
- Source stamp checked before and after each case:
  `4c7b2c0598704514812c2b21631ed23f9851761a98f39a01690b541f343ed3ea`.
- All 27 registered cases, including all 21 large cases, completed. Existing
  capacities and the 1 GiB retention ceiling were not changed.
- Each case starts with a separate fixture database and no resident copies.
  The controller process is reused. Selection uses the uncalibrated example
  estimates (`resident: true`, `nativeMilliseconds: "1"`).

The comparator checks independent expected final row CID and count, completed
tasks, retained outputs and child exit. Completion is recorded after cleanup
checks no pending cleanup and no retained final completion. Archived Store
snapshots precede cleanup and are not post-cleanup leak measurements.

Execution includes Host preparation, process startup, acquisition, validation,
Compute, mandatory identities, holding and child exit. Source construction,
builds and independent oracle work are excluded; cleanup is separate. Controller
memory is sampled and does not prove non-row-scaling memory usage.

## Observations

All 99 reported Compute input phases reused admitted identity. Each reported
zero logical CID passes, zero stored-row JSON decodes and zero parameter INSERT
rows. Each still validated its complete input row count. Physical integrity and
native import remain. Acquisition and output CID generation are not removed:
this is reuse of an existing mandatory identity, not optional identity.

| Registered case | Earlier 46c5b033 seconds | This run seconds | Cleanup ms |
| --- | ---: | ---: | ---: |
| Join/count, narrow, 1,000,000 rows | 21.084 | 18.489 | 3.959 |
| Downstream reuse, narrow, 1,000,000 rows | 23.490 | 20.762 | 3.948 |
| Downstream reuse, numeric-64, 100,000 rows | 76.335 | 68.388 | 6.954 |
| Downstream reuse, text-1024, 100,000 rows | 39.407 | 33.637 | 9.044 |

These historical single samples are descriptive, not paired estimates of the
change's effect. No accepted speed ratio or confidence interval is claimed.
The low-selectivity acquisition case at 1,000,000 rows took 2.896 seconds versus
2.880 previously: its downstream inputs have only two rows, so removing their
hashes does not address its dominant acquisition cost.

The numeric-64 reuse case still validated 19,200,000 cells across three inputs.
Its input intervals were 7.189, 6.844 and 7.224 seconds, versus 9.023, 9.018 and
8.980 previously. Long-text intervals were 2.888, 2.681 and 2.872 seconds versus
4.680, 4.685 and 4.650. These intervals include integrity, import and typed
validation, not isolated validation CPU time; they are nested in total time.

## What remains

The scoped native conversion rule and its trusted-implementation boundary are
documented in [native-file-identity-reuse.md](native-file-identity-reuse.md).
All cells still cross the typed validation path; per-value measurement,
consumer demand and guards remain. Output canonical encoding and holding also
remain. The result is a measured removal of duplicate identity work, not the
completion of retained execution.

Managed-profile real dispatch, issuer integration, finite row-transform evidence
transfer and Local/DuckDB shared execution remain separate implementation work.
The original alternating paired experiment and equivalent-obligations acceptance
are still outstanding. No comparator, performance threshold, capacity, wire or
identity preimage was relaxed for this diagnostic.
