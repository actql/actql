# Managed direct-scan checkpoint

Date: 2026-09-17

Revision: `0e6a9aba3a4b2640c7778cd949c7743fc7034ead`

Profile: `actql-managed-retained-execution/0.1`

The standard managed DuckDB path now binds an adapter-compiled temporary view
to the exact Store-authorized file instead of copying the complete file into a
temporary table. DuckDB does not accept prepared parameters in `CREATE VIEW`,
so the Host-private session operation quotes and substitutes exactly one path
that was admitted when the session was created. Arbitrary paths and
Program-provided SQL remain unavailable.

The Store still pins the exact generation and performs one integrity pass per
distinct physical body. Duplicate logical input occurrences share that pass
and pin, but each native scan remains separately counted and charged. A file
digest is not treated as a logical CID, and the managed completion and current
consumer authorization remain mandatory.

## Registered matrix

The clean fixed revision ran:

```sh
node adapters/duckdb-node/bench/managed-profile-matrix.mjs
```

All 27 registered cases completed. The runner built the three required JS
packages with the pinned MoonBit `0.10.12+1634b282e` toolchain and used Node
`v22.23.2` on Darwin arm64. Fixture source creation remained outside each case
timer. Every case closed with zero held bytes and zero transfer, retention and
execution reservations.

| workload | cases | total ms | integrity passes | native scans | imports | JS output cells | frame encodes | logical CID |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| acquisition | 9 | 20,456.645 | 9 | 9 | 0 | 18 | 9 | 0 |
| join/count | 9 | 49,014.387 | 27 | 27 | 0 | 2,662,218 | 20,812 | 0 |
| downstream reuse | 9 | 205,274.189 | 9 | 9 | 0 | 9,482,200 | 10,405 | 0 |

The integrity and scan byte totals were equal for this registered matrix:
265 bytes for acquisition, 71,962,905 bytes for join/count and 162,719,730
bytes for downstream reuse. The equality is incidental to these fixtures,
which do not repeat the same physical body at two ports. The self-join
regression separately requires one integrity pass, two native scans and two
logical input charges.

The matrix establishes the direct-scan selection and functional coverage. It
does not establish a speed ratio. The large join and reuse outputs still cross
the native boundary as cells and are re-encoded into bounded Store frames.

## Immediate before/after diagnostic

Three registered cases were also run once on clean worktrees at the immediate
parent `33e5a6f5` and the direct-scan revision. Case order was alternated. These
are single diagnostic samples, not the registered alternating confidence run.

| case | before ms | direct-scan ms | delta | managed statements | managed command ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| reuse, numeric-64, 10,000 | 9,694.852 | 9,326.508 | -3.8% | 3 -> 2 | 325.765 -> 297.789 |
| join, narrow, 100,000 | 2,636.500 | 2,655.165 | +0.7% | 8 -> 5 | 313.037 -> 360.373 |
| reuse, narrow, 1,000,000 | 31,183.379 | 33,657.500 | +7.9% | 3 -> 2 | 1,257.004 -> 1,171.967 |

The statement reduction is deterministic: each managed input no longer needs
both table creation and import before the query. Wall time is not uniformly
better. Two single-input managed command phases improved by 8.6% and 6.8%, but
the join command phase regressed by 15.1%, and whole-case time ranged from a
3.8% improvement to a 7.9% regression. No performance acceptance is claimed.

## Remaining physical work

This checkpoint is direct file scanning, not resident relation reuse. A fresh
DuckDB session and one file scan per logical occurrence remain. Every distinct
body is still integrity-checked before native access. Managed outputs are still
materialized in JavaScript and encoded through the bounded Store writer; the
unsafe unbounded native `COPY` path remains disabled.

The next performance work therefore remains:

- reuse a live resident relation generation when the same DuckDB site owns it;
- reduce full-view measurement indexes to range or chunk summaries;
- provide a hard-bounded direct output path before removing JS output framing;
- run the registered alternating equivalent-obligation comparison before any
  performance pass or regression conclusion.

