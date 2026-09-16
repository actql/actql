# Bounded ASCII output diagnostic

Baseline: clean `7fb1d48f`, built from an isolated git archive. Candidate: that
revision plus the `encode_core` ASCII-span change and its tests. Both used the
pinned MoonBit release JS build of `benchmark_obligations`, imported separately
into one Node process. No product Host or DB was executed in this diagnostic.

The change emits printable, unescaped ASCII in at most 257-byte spans instead
of one builder append/buffer reservation per character. Measurement and hashing
sinks allocate no substring. Unicode, escaping, node counts and byte limits are
unchanged; a span inspects at most one byte beyond its remaining allowance.

Each invocation admitted, measured, encoded and hashed 4,096 rows in 32 batches
of 128. Transport JSON was prepared before timing. Numeric data comprised 64
columns `c0` through `c63`, all binary64 1. Text data comprised `id=1` and a
1,024-character ASCII `payload`. Each implementation had one warmup, followed
by three alternating-order pairs. Times include stream setup and finish, exclude
fixture generation/build, and are not paired end-to-end acceptance samples.

| Shape | Baseline ms | Candidate ms |
| --- | --- | --- |
| numeric-64 | 316.126, 334.526, 320.137 | 318.737, 319.809, 314.542 |
| text-1024 | 213.668, 214.004, 212.797 | 174.188, 160.543, 160.065 |

Every pair matched exact canonical bytes and CID:

- Numeric: 2,064,385 bytes;
  `sha256:2f5d02dcc1037e0965626ef9c081b3f1d4b21530e1c3da43a43eb0abacddd54c`.
- Text: 4,284,417 bytes;
  `sha256:6361a994dacfb36a61844a610461f870148447689d049cbc89252ed020e0a5fc`.

The text path improved in these samples; the numeric difference is small and
not established as a repeatable speedup. No registered threshold, timeout or
fixture changed. Product end-to-end benefit remains unmeasured. This does not
replace retained-material evidence reuse, native output, contract integration,
or formal equivalent-obligation comparison.

Validation: encoder package 34 tests on each of JS/Wasm/native; whole-repository
JS 4,338 tests. Added checks cover 255/256/257/258-byte boundaries, mixed
escapes/Unicode, all four sinks, exact byte ceilings, buffered limits, and limit
failure precedence before a later invalid surrogate. Whole-repository native
and Wasm, and the registered 27-case performance experiment, were not rerun.
