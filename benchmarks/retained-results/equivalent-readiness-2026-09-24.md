# Equivalent-obligations comparator readiness (2026-09-24)

At clean revision `a7dfa0b9c5d832f913cda923827b4d2a513587fd`, the
independent DuckDB comparator completed all 27 registered workload cases.
The runner created one immutable fixture database per case and a fresh child
for its independent-obligation assembly. It reported 27/27
`diagnostic-completed` with no omitted or failed case. The largest observed
single comparator execution interval was 81,425.201 ms for
`retained-large-output-downstream-reuse/numeric-64/100000`.

```sh
TMPDIR=/Users/t14i/workspace/20260822/.codex-scratch \
  node adapters/connectors/duckdb/node/bench/equivalent-matrix.mjs
```

The raw summary is at
`workspace/.codex-scratch/actql-equivalent-matrix-v67eHi/summary.json`
(SHA-256 `3713af72213cccd8af3547b593f42a1ad381e546b1fccf9be8852d212cd57741`).
The runner log is at
`workspace/.codex-scratch/equivalent-matrix-a7dfa0b9c.log`
(SHA-256 `b48864e796e3be477d34419b1078e9e257b8220612edfb8db7b1dbecc004f5cb`).
Each case's full diagnostic record remains beside the summary.

This proves execution readiness of the independent comparator, not matched
obligation admission or performance acceptance. The retained product was not
run in the same alternating pair; its ordinary selection still needs an
independently calibrated estimate profile. The existing retained 27/27
readiness run used a different revision and timing boundary, so these two
matrices must not be divided into speed ratios. No registered confidence gate
has been evaluated from these observations.
