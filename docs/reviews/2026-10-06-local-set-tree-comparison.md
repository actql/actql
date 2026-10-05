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

## Public retained path: failure attribution and follow-up

Only `local-node` and `run-host-core` were rebuilt before the ordinary installed
Host diagnostic. The interval caller succeeded, but the new nested Set Program
did not publish (`run-PgLOqO`, `focused-test-SvttGu`, 1/2). Shortening the operands
also failed, so this is not evidence of a long-comparison work failure.

The first diagnostic was reported as task-zero `Execution(ForeignCandidate)`
(`run-Uji4Rs`, `focused-test-OS9GgJ`). That attribution was incorrect: reading
the full trace showed five completed tasks and the start of final Sort task 5.
The positive-incomplete-poll hook can remain silent for a small completed task;
its absence did not establish absence of Compute progress.

Subsequent test-process-only instrumentation checked the actual candidate and
ordered input bindings at every start; both checks passed for tasks 0 through 5.
Task 5 returned `Execution(Physical(RetentionLimit))` before lifecycle start.
The ledger held 188,434,240 bytes and attempted to reserve 37,686,848 more under
its 200,000,000-byte default floor (`run-HipDXL`, `focused-test-pfTJCO`). These
hooks added logging only and were never product code or passing acceptance.

[The ordinary Host regression](../../adapters/host-node/public-set-value-retention.test.mjs)
uses one Values prefix, a filtered right input, Set, Unnest, guaranteed scalar
projection and authored sort, followed by two consumer tasks. It contains the
four independent expected Result arrays. Its former pending reproduction failed
before the capacity follow-up; it now belongs to the normal installation suite.
No identity check, obligation, policy limit or publication order was weakened.

The [capacity follow-up](2026-10-06-local-retained-store-capacity.md) accounts
for the installed Store import/output envelope before opening the Run. It adds
ordinary nested Set retained publication evidence at its own source revision,
not retroactively at the comparison component's SHA. Its later test-only
follow-up certifies an actual nested UTF-16 scanning barrier and cancels the
ordinary public retained Run at that barrier, checking pre-stop input custody,
confirmed stop, unpublished Results, snapshot reclamation and no redispatch.
A full retained-route completion claim remains unestablished.
Wasm/native, packed/HTTP, full Core and integrated CI were not executed for this
unit. Registered targets are not executed results.

The base is the unmerged #506 interval comparison branch. Preserve that
dependency until main adopts it; the eventual merge target is main.

The missing-role Node regression passed 1/1 (`run-zp4v2P`,
`focused-test-DtxJRb`) with the `Set requires nested comparison` filter on
`scripts/check-local-resource-accounting.test.mjs`. The real accounting audit,
Workers/Node Host fixture freshness, changed MoonBit formatting, reproduction
syntax and `git diff --check` also passed. No tracked fixture/interface or
ignored runtime bundle needed committing. Tests ran before committing the
unchanged implementation tree; the PR records its exact clean source SHA.
