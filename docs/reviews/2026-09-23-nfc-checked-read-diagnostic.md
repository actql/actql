# Checked producer NFC diagnostic

This diagnostic compares the pinned Unicode 16.0 NFC quick check with the
preceding full-normalization path. It uses the same opt-in white-box fixture at
both revisions. The fixture constructs a real completed Relation producer and
a real managed producer bridge, then calls `producer_read_checked_cell` 100,000
times per sample. Each sample alternates between two immutable rows. Setup is
outside the timed region. Pair zero warms the runtime; pairs one through seven
are reported.

| Target and read | Before median, µs | Quick-check median, µs | Ratio |
| --- | ---: | ---: | ---: |
| JS, Japanese ordinary producer | 131,058 | 54,408 | 2.41× |
| JS, managed bridge | 2,974 | 2,897 | 1.03× |
| Native release, Japanese ordinary producer | 121,185 | 39,915 | 3.04× |
| Native release, managed bridge | 7,882 | 4,432 | 1.78× |

The before revision is scratch worktree commit `3e5559877` (base
`ae3d421a5` plus the diagnostic-only change); the after revision is
`1d8cb4f26`. Both use the pinned MoonBit
toolchain `0.10.12+1634b282e`. The ordinary producer holds two Japanese Text
rows. The bridge holds the existing non-ASCII Text fixture (`é` and `😀`).
The same cells and checked read call count are used in each comparison. The
diagnostic also passes without timing enabled on JS and Wasm; native release
passes with timing enabled.

The comparison establishes a per-cell checked-read improvement, not an entire
10,000-row acquisition or end-to-end Run improvement. It does not measure
allocations, transfer cost, setup, or GC independently. The managed bridge
already returns admitted values through a different source representation, so
its ratio must not be extrapolated to ordinary Text producers. Native and JS
absolute times are not interchangeable. A representative large-row producer
and allocation profile remain necessary before making a whole-path performance
claim.

To reproduce, set `ACTQL_NFC_READ_DIAGNOSTIC=1` and run the diagnostic file with
`moon test --target js` or `moon test --target native --release` using the pinned
toolchain. The diagnostic is disabled by default in the normal test suite.
