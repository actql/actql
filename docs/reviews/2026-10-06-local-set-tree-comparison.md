# Bounded Set admitted-value comparison

## Scope and counterexample

This unit partitions actual EXCEPT/INTERSECT comparison scanning, not value
measurement or Store copying. The checked/lowered Object -> Array -> long Text
fixture originally spent the recursive comparison charge inside one quantum-one
poll. The red attempt passed 0/1 (`run-BnNG0Y`, `focused-test-rVnxPr`). Its bound
was one unit; the final bound allows two on the first poll because entering the
logical merge action also costs one. The old recursive scan exceeds both.

`complete_tree_comparison.mbt` retains borrowed admitted roots in accounted
continuation frames. Array elements, Object names/values and Vector dimensions
advance separately; Text uses the existing UTF-8 charge / UTF-16 comparison
cursor. Child frames are reserved before allocation. Set keeps the same logical
merge action pending, so exposing more polls does not repeat its action charge.
The scalar and flat Text paths keep their existing implementation.

Cancellation leaves roots and scratch reachable until the bounded session
confirms stop. Cleanup closes the pending cursor once without disposing caller
inputs. There is no new scheduler, ledger, comparison domain, public API,
canonical preimage or fallback. Other recursive complete-value consumers remain
outside this change. D's Run cancellation finalization is not modified.

## Focused executed evidence

The JS selection passed 19/19 (`run-r7ydR1`, `focused-test-DfnZTM`):

```sh
node scripts/local-checks.mjs test moon -- --target js \
  src/execution_relation/bounded_set_nested_comparison_wbtest.mbt \
  src/execution_relation/bounded_set_wbtest.mbt \
  src/execution_relation/bounded_binary_output_wbtest.mbt \
  src/execution_relation/semantic_rows_budget_wbtest.mbt
```

- EXCEPT and INTERSECT, ALL and DISTINCT, finish within fixed polling bounds at
  quanta one and seven with independently authored survivors and identical
  cumulative control work. Completed input provenance and left output order stay
  intact.
- Cancellation during sorting and merging, in both Text charging and scanning,
  retains scratch and live inputs until `Stopped`; no partial output is accepted.
  Repeated cleanup releases no extra workspace and charges no extra work.
- The isolated admitted pair requires work 521/520, slots 4/3 and frames 3/2.
  Its work is wrapper 1 + Object 1 + two name bytes 2 + Array 1 + Text node 1 +
  two 257-byte operands 514 + NULL node 1. These are comparison-only limits,
  not a sampled whole-Run budget.
- Independent Array/Object/scalar/Unicode vectors agree with the existing
  comparator and literal work totals. Negative zero is not admitted as a new
  value domain. Vector admission preserves the existing full-dimension charge
  before comparison, while paying it incrementally.
- Existing scalar Set work boundaries and binary output failure/cleanup cases
  remain selected. Both production route entries require the three new roles;
  a regression removes each role separately and requires rejection.

## Public retained path: unresolved

Only `local-node` and `run-host-core` were rebuilt before the ordinary installed
Host diagnostic. The interval caller succeeded, but the new nested Set Program
did not publish (`run-PgLOqO`, `focused-test-SvttGu`, 1/2). Shortening the operands
also failed, so this is not evidence of a long-comparison work failure.

An isolated test-process module hook exposed the actual existing exception:
`CapturedRunPublicationFailed` wraps `StrategyNotComplete`; its execution has
`MoonBitHostFailure` caused by `Execution(ForeignCandidate)`. The first prepared
task has index zero and fails at `strategyModule_local_Dispatch`, before positive
Compute progress (`run-Uji4Rs`, `focused-test-OS9GgJ`). Product modules were not
edited, and the hook is not retained in the reproduction.

[The pending reproduction](../../adapters/host-node/public-set-value-retention.reproduction.mjs)
uses one Values prefix, a filtered right input, Set, Unnest, guaranteed scalar
projection and authored sort, followed by two consumer tasks. It contains the
four independent expected Result arrays. Run it explicitly through the focused
Node wrapper; it currently fails the success assertion. It is deliberately not
imported by the passing installation suite or cited as execution evidence.
The earlier two-Values-prefix form fails at the same boundary. No identity
check, obligation, policy limit or publication order was weakened to pass it.

Next work is to isolate which exact candidate/input binding fails at the zero
task start, then connect the existing Owner. This unit does not establish
ordinary nested Set retained publication, public comparison-phase cancellation,
or a completed retained route. Wasm/native, packed/HTTP, full Core and integrated
CI were not executed for this unit. Registered targets are not executed results.

The base is the unmerged #506 interval comparison branch. Preserve that
dependency until main adopts it; the eventual merge target is main.

The missing-role Node regression passed 1/1 (`run-zp4v2P`,
`focused-test-DtxJRb`) with the `Set requires nested comparison` filter on
`scripts/check-local-resource-accounting.test.mjs`. The real accounting audit,
Workers/Node Host fixture freshness, changed MoonBit formatting, reproduction
syntax and `git diff --check` also passed. No tracked fixture/interface or
ignored runtime bundle needed committing. Tests ran before committing the
unchanged implementation tree; the PR records its exact clean source SHA.
