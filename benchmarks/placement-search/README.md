# Bounded placement search diagnostic

`measure-built-tests.mjs` repeatedly runs the existing seven-task Carrier
placement fixtures from the built `query_integration` JS whitebox test bundle.
Build that bundle with the pinned MoonBit toolchain, then run:

```sh
node benchmarks/placement-search/measure-built-tests.mjs 100
```

Each profile is run once in a fresh process and then 100 times in another
fresh process. The reported incremental fixture interval is the difference in
process elapsed time divided by 99. It includes fixture construction, offer
preparation, search, assertions and test-runner overhead. The one/two-offer
profile runs both configurations per repetition. `maxRssKiB` is the whole
process peak, including the large generated test bundle and runtime; it is not
planner allocation or an estimate of deployed Host memory. Neither number is
an acceptance threshold. The exact in-process frontier counters are asserted
by the MoonBit tests separately.

At clean product revision `6e5e11a267836676a65c64463d408eaaa99d09aa`
on macOS arm64, Node 22.23.2, three 100-repetition runs produced:

| Profile | Incremental fixture ms (three runs) | 100-repeat process peak RSS KiB (three runs) |
| --- | --- | --- |
| Seven tasks, five offers each | 16.653, 16.965, 17.694 | 368256, 356624, 360688 |
| Seven tasks, one and two offers | 31.539, 32.498, 34.026 | 474896, 473456, 476928 |

The second profile runs twice as many complete fixtures in each repetition;
these rows are not a relative search-speed comparison. The raw local JSON
records are under `workspace/.codex-scratch/placement-search-6e5e11a-run[1-3].json`
with SHA-256 values `cf5ecb7f3ebab1ca08a365035170f0b3289f97299e9c30ff3938ede7ace121c8`,
`9a8a0c2fa2ebe33e7023424a8519058b341fdd531f5353174e2cb23016f77d94`
and `b572292d4d6af946588a0636d5b69a685d6dbe20d9bf64ea6bfe2a01caa4706a`.

This shows a finite observed execution cost for the seven-task bounded
fixture. A release Host profile at larger task counts and with actual provider
capabilities is still required to close PERF-2; this diagnostic must not be
used as its substitute.
