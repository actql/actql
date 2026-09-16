# Exact retained measurement reuse

This is an existing-contract optimization, not the new execution profile and
not the registered 27-case performance acceptance result. Baseline source is
`0764a0f7`; the experiment below compares forced ordinary measurement with the
new reuse path in the same JS release binary.

## Boundary and implementation

Core records successful canonical per-value measurement on the exact retained
material generation after a complete producer scan passes identity verification.
Each material owns at most one summary, containing ordered projected columns,
successful value-size and depth bounds, and exact work/byte/node totals. It
does not retain rows, ancestor materials, or an unbounded consumer cache.

Reuse requires the existing trusted representation proof to remain live, the
same column sequence, compatible bounds and sufficient remaining budgets. A
weaker summary does not prove a tighter requirement or a violation: it selects
the original ordered measurement path. Thus its failure and partial-accounting
frontiers remain available. The summary is not a maximum-value location and
cannot be used to synthesize a first-failure diagnostic.

On the reuse path the per-row measurement encoder is not called. The existing
consumer accounting totals are applied after complete scan verification. These
are preserved budget charges, **not a report that the skipped physical work was
executed**. Typed admission, live checks, row-count and identity checks, join
obligations, and the scan itself still run. This increment does not claim to
remove decoding or the entire consumer scan. New physical generations do not
inherit the summary merely because their CID matches.

## Reproduction and scope

```sh
ACTQL_RETAINED_MEASUREMENT_DIAGNOSTIC=1 moon test src/execution_relation --target js --release --filter '*retained measurement*' --deny-warn
```

The fixture retains two rows of two checked scalar values. Each timed leg
constructs, consumes and finishes 10,000 receiving scans of that same material.
Both paths use trusted identity reuse; the baseline clears only the measurement
summary before each scan. Fixture construction is outside timing; scan setup,
admission, projection, measurement or evidence reuse, and completion are inside.
Both legs assert independently known charges of 6 work units, 12 canonical
value bytes and 4 nodes per scan. The first pair is warm-up; seven pairs alternate
execution order. Clock output is microseconds; this table uses milliseconds.

| Pair | Ordinary measurement | Evidence reuse |
| --- | ---: | ---: |
| 1 | 16.265208 | 13.738541 |
| 2 | 15.954625 | 13.511125 |
| 3 | 16.064750 | 12.796708 |
| 4 | 15.875208 | 12.808750 |
| 5 | 15.902417 | 12.806416 |
| 6 | 16.046708 | 12.658875 |
| 7 | 15.969250 | 12.912583 |
| Median | 15.969250 | 12.808750 |

The ratio of medians is about 0.802 (19.8% less elapsed time for this isolated
scan experiment). It is not a large-input DuckDB speedup, cold-process result,
memory measurement, or proof of the <=1.25 direct-DuckDB acceptance criterion.

Correctness cases cover repeated positive reuse, unchanged consumer charges,
tighter work/byte/node/value bounds, exact failure positions and remaining
budgets versus ordinary measurement, partial scans, revocation, lack of trusted
representation authority and separate physical generations.

Verification: `execution_relation` passed 403 tests on each of JS, Wasm and
native. The four new scoped tests were rerun on all three targets after adding
the authority/generation controls. Public API checks, generated Node/Workers
fixture checks, `npm run check:docs`, document links and the real DuckDB standard Host integration
also passed. The integration is a regression check; it does not independently
establish a large-case speedup from this summary cache.

The new profile, view-preservation/inclusion rules beyond exact columns and
weaker bounds, delegated lifecycle acceptance, and the formal unchanged
1 GiB / 27-case comparison remain separate required work. See the agreed
[design](../../docs/design/physical-result-contract-review.md) and the
[prior rejected component experiment](checked-row-measurement-diagnostic.md).
