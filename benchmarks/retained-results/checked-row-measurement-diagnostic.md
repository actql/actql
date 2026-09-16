# Checked-row measurement diagnostic

This component experiment does not satisfy or change the registered 27-case
acceptance experiment. It tests removing the intermediate `Array[Value]` made
from already checked input cells for consumer measurement. It removes no
semantic validation, canonical size measurement, logical charge or identity.

Source baseline: `0764a0f7`, with regenerated Node/Workers fixtures for the
rebased public checker API. Candidate and baseline run in the same JS release
test binary. The candidate is deliberately test-only after the negative result.

## Reproduction

With the repository's pinned MoonBit toolchain on PATH:

```sh
ACTQL_CHECKED_ROW_DIAGNOSTIC=1 moon test src/execution_relation --target js --release --filter '*checked row measurement paired diagnostic*' --deny-warn
```

Fixture setup is outside the timer: 64 checked cells alternating the numeric
value `1` and string `é`, reused for 10,000 measured rows per leg. Each leg
performs 650,000 work units, 1,600,000 canonical UTF-8 bytes and 640,000 scalar
nodes, asserted against independent totals. One warm-up pair is excluded;
seven measured pairs alternate execution order. Times below are milliseconds
(the clock reports microseconds). This is a deliberately isolated synthetic
component, not a fresh-process, cold-source or DuckDB throughput experiment.

| Pair | Existing copied array | Borrowed checked cells |
| --- | ---: | ---: |
| 1 | 19.938166 | 20.301500 |
| 2 | 18.564875 | 20.458167 |
| 3 | 17.680333 | 19.743250 |
| 4 | 17.682584 | 19.854333 |
| 5 | 17.593125 | 19.776084 |
| 6 | 17.578542 | 19.689416 |
| 7 | 17.595958 | 19.609125 |
| Median | 17.682584 | 19.776084 |

The borrowed version is slower in this diagnostic (ratio of medians about
1.118). The experiment does not establish the cause or end-to-end impact.
Do not ship the candidate based merely on fewer array allocations. The
production measurement path is unchanged. The next substantive optimization
is scoped measurement/validation evidence reuse, not this container rewrite.

Correctness controls compare both readers over work/byte/node/ceiling boundary
sweeps and assert the independently known UTF-8 totals. Existing reused-identity
tests also retain per-consumer measurement and failure checks.

## Completion status

The Q1–Q11 agreement is recorded in
[the design review](../../docs/design/physical-result-contract-review.md).
The following remain required, not implied complete by this experiment:

- Connect the now registered managed-retained profile and its pinned
  obligation/identity/evidence contract to runtime admission and execution,
  preserving old contracts. Registration alone does not complete this work.
- Implement finite inclusion and view-preservation rules, bounded composition,
  failure-selection requirements and subject-limited issuance authority.
- Connect supported projection/filter/derive/sort/take chains, repeated
  join/group-result use, and managed delegation to actual evidence reuse.
- Verify pins, use authority, cancellation, independent relocation and confirmed
  reclamation, including positive reuse and negative race/failure cases.
- Record theorem assumptions, checked bridges where claimed, and trusted
  backend/codec/FFI boundaries; no blanket mechanized-conformance claim.
- Finish the same-obligation comparator and formal old-contract 27-case runs
  under the unchanged 1 GiB and performance conditions. Register new-profile
  measurements separately and include preparation, holding and cleanup.

The rebase's generated-fixture build break was repaired by regenerating from
the new owned checker fixture. Before moving the experimental reader to tests,
three-target checks and execution_relation tests passed (398 each), JS
query_integration passed 271, Node installation/boundary tests passed 16 and
the real DuckDB standard Host integration passed. These are scoped checks, not
the full new-profile or formal performance acceptance suite.
