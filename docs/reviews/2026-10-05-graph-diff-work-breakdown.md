# Independent Graph diff work regression

This nonblocking follow-up to #446 preserves the existing measured-ceiling test
and adds a fixed expected total. It changes no runtime, work contract, API,
identity domain or physical resource proof.

## Independent fixture and inventory

The new provider fixture has zero nodes and zero edges, but retains the existing
independently authored `snapshot_fixture_schema()` declarations. Each snapshot is
the five-element canonical preimage with empty node/edge arrays. It is 824 ASCII
scalars/bytes. Its independently calculated SHA-256 is
`sha256:b432ac9e6035853bc1e8a7cfcdadd4a98f04f5aeefa279f4287204f33e9f0fec`.
Neither snapshot encoding nor a diff execution supplies the expected bytes/CID.

The authored JSON has 41 value nodes, 22 containers and 23 non-first children
(commas). Container arities, excluding object keys as value nodes:

| Container | Arity : count |
| --- | --- |
| Array | 0 : 4; 1 : 7; 5 : 1 |
| Object | 0 : 1; 1 : 2; 2 : 4; 5 : 1; 6 : 1; 7 : 1 |

Existing continuation rules yield the following count for **each** input:

| Stage | Independent arithmetic | Work |
| --- | --- | ---: |
| Empty snapshot emission | end nodes + finish; empty sort reports zero | 2 |
| Body phase starts | parser + decoder + JSON value admission | 3 |
| Parser preflight | 824 scalar visits + end check | 825 |
| Grammar | 41 value starts + 22 container deliveries + 23 separators | 86 |
| Decode | 41 visits + 40 child continuations + 22 container ends | 103 |
| JSON admission | 41 reads + 36 array continuations + 278 object continuations | 355 |

For JSON admission, each arity-n array adds `2*n + 1` next/append/end
continuations. Each arity-n object adds `4*n + 3 + sort_polls(n)`
key/name/next/append/end/sort continuations. The existing one-work merge sorter
has `sort_polls(n) = n + sum(ceil(n/(2*w)) + n + 1) + 1`, for powers of two
`w < n`; the final poll is included even if it reports zero sorter work.
For object arities 0, 1, 2, 5, 6, 7 the counts are 1, 2, 7, 30, 34, 39.
The enclosing JSON admission charges one work per resumed continuation.

There are no record comparisons or actions in this fixture. The complete Delta
has 13 value nodes and 9 containers: four text values, three objects and six
empty arrays. Its runtime recheck takes `13 + 12 + 9 + 1 = 35` continuations.

## End-to-end ledger

| Stage | Independent arithmetic | Work |
| --- | --- | ---: |
| Diff kernel | `2*(2 + 3 + 825 + 86 + 103 + 355) + assemble(1) + recheck(35)` | 2784 |
| Start row admission | Existing one-use preparation transition | 1 |
| Row admission | begin/read(2) + recheck(35) + name(1) + measure(31) + commit/end/seal(3) | 72 |
| Trusted completion | Existing completion transition | 1 |
| Total | All four stages | **2858** |

Value measurement visits 13 nodes and 12 container children. Each of the three
71-character CID strings requires two 64-unit text continuations, adding six.
The other value/key strings fit the existing inline text bound; the `delta`
column name uses one separate name continuation. These are control work counts,
not approval for billing and not a total Graph memory bound.

The test uses fixed limits 2784, 2785, 2857 and 2858: the first three must fail
without publishing; the last must complete with exactly 2858 cumulative work.
Both whole and selected managed providers are checked. Quantum 1 checks the
stage boundaries; quantum 64 checks cumulative/delta forwarding under batching.
Repeated cleanup must not change accounting or reclaim either borrowed input.
The returned Delta bytes are checked against the independently authored empty
actions with the fixed empty snapshot CID.

The older removal fixture and its execution-calibrated exact/one-short test
remain intact. The new fixed ledger supplements it; it does not replace the
larger fixture's ceiling and logical-workspace coverage.

## Mutation criterion

Individually omit one reported work unit at (1) kernel completion, (2) row-import
completion, and (3) trusted completion. The first two mutations apply only when
the poll reports more than one work unit, preserving positive Continue work and
valid progress. The third keeps a legal zero-work terminal poll. Keep the
existing internal budget, material checks and expected total unchanged.

Each mutation must compile and fail the new test's `used == total` assertion
with **2857 != 2858**, rather than passing, failing compilation, timing out, or
relying on a malformed provider report. Restore production source between
mutations. No mutant is submitted as product implementation.

Run the new test with the existing bounded/nonzero wrapper:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- \
  --target js src/query_integration \
  --filter '*independent kernel row admission*'
```

The affected caller selection, including the preserved tests, is
`--filter '*Graph diff*'`. This is focused JS evidence, not Core-wide, packed,
Wasm/Native execution or GitHub CI success.

## Local diagnostic attempts

All attempt directories below are under the isolated follow-up worktree's
`_build/local-checks/attempts/`. Its absolute root is
`/Users/t14i/workspace/20260822/worktrees/actql-c-graph-diff-work-breakdown`.
They retain the original statuses and stdout/stderr; successful reruns do not
overwrite earlier attempts.

| Attempt | Observation |
| --- | --- |
| `run-d2a6s6` | Compile-only failure: raising assertion used in a non-raising fixture helper; changed it to an explicit abort guard. No test executed. |
| `run-EHWEm0` | 6/7 passed. The initial handwritten ledger omitted parser scalar preflight. Source inspection added the fixed 824 visits + end check for each input, not an execution-calibrated total. |
| `run-hREVnz` | Affected selection 7/7 passed before adding the output-byte assertion. |
| `run-faXLVA` | Mutant preparation did not compile: Complete's positional argument was omitted in a pattern. Not a detected accounting mutation. |
| `run-E4iISX` | Test fixture assertion failed before the intended mutation observation: String.replace replaced only the first CID. Corrected both independently specified base and target CIDs. Not a detected accounting mutation. |
| `run-Gx5Zel` | Corrected baseline 1/1 passed, including independent output bytes. |
| `run-FPxfBS` | Kernel-completion under-report mutant: 0/1 passed; expected assertion `2857 != 2858`. |
| `run-mmtgVx` | Row-admission-completion under-report mutant: 0/1 passed; expected assertion `2857 != 2858`. |
| `run-FrPuEk` | Trusted-completion under-report mutant: 0/1 passed; expected assertion `2857 != 2858`. |

One bounded-wrapper invocation could not inspect its owned process group in
the sandbox and launched no test. The same bounded/nonzero wrapper was used
with that process-inspection capability; its guard was not removed.

The temporary mutations changed only `src/local_sga/delta_diff.mbt`, one at a
time, and were fully restored after each run:

- GeneratingDelta's final Continue: report `work - 1` only for
  `poll is @delta.Complete(_, ..) && work > 1L`; otherwise report work unchanged.
- ImportingDeltaRows' successful final Continue: report
  `if work > 1L { work - 1 } else { work }` instead of work.
- CompletingDeltaRows' successful Complete: report zero instead of one.

Each compiled mutant reached successful execution completion and failed the
new test's independent total assertion. No input/output expectations, internal
budgets, positive-Continue validation or completion authority were weakened.
This establishes sensitivity to even a single lost unit in each of the three
forwarding stages. It does not exhaust all possible accounting mutations or
prove work totals for nonempty action sets.

## Typed JSON and bounded Text recheck integration

The original 2,858-work evidence above remains tied to its original source.
With the current bounded Text recheck and explicit JSON value domain, the
independent fixture requires 2,873 physical control-work units. Neither its
logical value work nor the configured production ceilings change.

Each recheck adds seven Text polls: the version needs one, and each of the
three 71-unit CIDs needs two 64-unit chunks. The diff kernel and output import
each run a recheck, adding fourteen units. Import measurement additionally
walks the JSON domain marker in one separate `SteppedRead` frame; the payload
continues to be measured exactly once. Thus kernel=2,791, row import=80, row
start=1 and trusted completion=1. Their total is **2,873**.

The test retains kernel-only, row-start, one-short and exact ceilings and both
whole/selected providers. Its output expectation is an independently ordered
Delta envelope, with `$json` around the column payload and no marker around
the Relation row. No product encoder constructs the expected bytes.

All seven preserved Graph diff provider cases passed on the integrated JSON
diagnostic source through the bounded JS wrapper (`run-25K9cE`). This is a
working-tree diagnostic; it does not replace the old mutation receipts or
establish a published-head, packed, cross-target or hosted-CI pass.
