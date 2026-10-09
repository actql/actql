# Integrated aggregate membership ordering: public acceptance

## Adopted source and previous blocker

Verified clean main and normal five-package producer revision:
`1376a2ec4b0cb1944971b268f7c2c637fcc37e99`.
This acceptance adopts the merged common BETWEEN implementation and Frontend
connection, without another evaluator or a change to the independent fixtures.

| Boundary | Adopted identity |
|---|---|
| A's common BETWEEN implementation | `8085d49536b4230a0b65d2ee365e0bbbee8de99b` |
| Common repair main merge, #1088 | `f38bb61099a3a2decedeb1fb19b498453e3a4ed6` |
| B's Frontend membership-order repair | `baf6db97ce5d239eba5532ccf49e6ef8d53d995c` |
| Frontend connection main merge, #1081 | `9eebd17d3fcc73396860fbe32c9755609eec0f28` |

The [original source/handoff record](2026-10-09-aggregate-membership-order-source.md)
retains the failure at `3daf7fe1769575b13e0d3e1fc113c4917c4c2d85`: 85 Local
positives passed, then the BETWEEN case failed at common task compilation with
`ExpressionNotImplemented("between")`, surfaced as Host 500. Later cases and
HTTPS were not reached. That evidence is not rewritten as success.

The [common repair record](2026-10-09-between-common-execution.md) describes
the existing three-operand expression connection, once-only operand evaluation,
bounded comparisons, three-valued AND and retained roots. Its focused common
tests were performed by A; B did not repeat whole-Core or three-target tests.

## Unchanged independent obligations

The existing `--aggregate-property-order-only` cohort now contains 102 positive
cases, 44 preparation refusals and one expected execution failure per transport.
It retains the original membership obligations plus the independently integrated
DISTINCT collection-order cases. No failing case is excluded, no lower-level
Program is patched, and no expected rows, types, ordering or capacity ceilings
are changed for this acceptance.

In particular, the exact source cases that crossed the old failure boundary
retain these independently authored Named Results:

| Case | Expected answer |
|---|---|
| `aggregate-conditional-order-membership-between` | `[{"names":"a|b|b|c"}]` |
| `aggregate-conditional-order-membership-not-between` | `[{"names":"b|b|a|c"}]` |

Both use nullable object properties, retained duplicate source rows and explicit
NULL placement/ID tie keys. STRING_AGG keeps its nullable string Result contract.
The same corpus also covers IN/NOT IN, IN UNNEST and an empty list, null-safe
comparison, independent JSON controls, Pipe current versus original range
snapshots, typed parameters, masked argument failure, bounded ARRAY aggregation
with actual key assertions, and exact declared preparation-refusal codes.

The existing consumer compares published Named Result rows and
`Result.describe().columns`, including declared order, complete column contracts
and nullable/empty results. Source acquisition-session counts are retained.
Reread, reattach, resubmit and submission lookup must preserve the same Run and
counters. Preparation refusals must retain zero Run admission and zero Source
I/O. The demanded-expression failure must not publish a successful Result.

## Executed verification

Pinned Node `22.22.0`, MoonBit `0.10.12+1634b282e`, existing bounded/nonzero
guards and ordinary prepack hooks were used. Both checks below execute the clean
source revision stated above.

```sh
node scripts/local-checks.mjs test node --timeout-seconds 120 -- \
  scripts/aggregate-conditional-order-source-input.test.mjs \
  scripts/aggregate-signed-order-source-input.test.mjs \
  scripts/aggregate-property-order-source-input.test.mjs
```

Fixture/control/ordinary-corpus registration: **14/14 passed**,
`run-JrbmTT` / `focused-test-svY3v7`.

The retained bounded serial producer/digest/consumer orchestrator is
`/private/tmp/actql-b-membership-main-1376a2ec4-packed.mjs`; its execution
uses a 1,200-second limit and the existing shared heavy-check lock. It executes:

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-membership-main-1376a2ec4-pack
# Independently verify exact manifest revision and SHA-256 of all five tarballs.
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-membership-main-1376a2ec4-pack \
  node scripts/test-packed-public-query.mjs --aggregate-property-order-only
```

Producer/consumer guard: `run-kY6jzz`, terminal exit 0, completed normally.
Public consumer receipt: **`public-query-evidence-im2Fii`**, `passed`,
`complete: true`, all ten commands exit 0 with no signal or evidence errors.
Successful temporary installation cleanup completed (`artifactsRemoved: true`).

| Public transport | Positives | Preparation refusals | Expected execution failure |
|---|---:|---:|---:|
| Packed Embedded Local, standard profile | 102/102 | 44/44 | 1/1 |
| Packed remote HTTPS, standard profile | 102/102 | 44/44 | 1/1 |

Both exact BETWEEN markers, all later cases and final transport completion
markers occur in `010.stdout.log`. The driver profile controls passed 14/14;
its existing README Local/HTTPS quickstart and missing-generated-asset negative
control also passed.

Evidence root:
`/Users/t14i/workspace/20260822/worktrees/.codex-scratch/public-query-evidence-im2Fii`.
The receipt retains source/root/dirty state, child command identity, termination,
elapsed time, package digests and cleanup results. Public application output is
`010.stdout.log`, `010.stderr.log` and `010.result.json`.

## Exact distribution mapping

Normal producer directory:
`/private/tmp/actql-b-membership-main-1376a2ec4-pack`.
The clean-source manifest revision is the verified main SHA above. The hashes
below were independently recomputed from the actual tarballs before consumption.

| Package | SHA-256 |
|---|---|
| client-wire | `18762bb0bf434d939ff153d485e2aed28f0fa3c77c9d1e82eee4983765947905` |
| sdk | `c468fa4d31016b3d10539f1edc49a113241a52a67d34493ff165bfac30ed102c` |
| run-host-core | `b8e0798e72c0f2638a773d8c777dc4e985e66f098ca45f97a47ac01fc3b4bec0` |
| local-node | `53aa80d532bc11a4dee46fcd1c9f01bf8ef1f15e4e235bf08d2a14305d1578fe` |
| node | `2989926be6f87295d48551e3c83e64dd6fb26f7b943e4004ad69176e19b98cda` |

No old client-wire distribution, adapter overlay, explicit execution-budget
override, common-owner copy or compatibility fallback participates in this run.
The original failed receipt/tarballs/reproducer remain historical evidence.

## Completion and limits

The formerly blocked #1081 public ordering cohort is complete at the verified
fixed main source. The prior partial Local result and A's common tests are
separate evidence, not substitutes for this Local/HTTPS completion.

This is an acceptance-recording change only. Its submitted HEAD is not a newly
packed source revision; exact submitted-HEAD Actions status is reported separately
in the PR. Full Core, Wasm/native, proof, performance, full packed acceptance and
Cloud were not run locally. This does not claim the entire Frontend is complete,
or that main commits introduced after the producer started were executed.
