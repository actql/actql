# Local chain work boundary repair

Issue: [#498](https://github.com/actql/actql/issues/498).

Baseline: `7df035b21079379ca5bcdccaf45adb1b2091cd1e`.
This is a fixture/accounting alignment repair, not a product limit increase.

## Cause and independent derivation

`45f9b9d2a2792a70c3ccd8ee364bbdfb8b78c848` replaced synchronous output
charging in Values and row windows with the existing bounded row-charge cursor.
The two composed-chain fixtures retained their pre-cursor work expectations.
For a scalar row of width W, that cursor takes start + W name steps + W value
steps + commit: `2 + 2W`, instead of one synchronous commit. These are actual
bounded operations, not an extra charge per resume. The chain owner accumulates
each child's work delta once and charges one handoff between children.

### Values -> filter true -> select

Three one-column rows retain the authored order 3, 1, 2.

| Component | Independent phase count | Work |
| --- | --- | ---: |
| Values | 1 name + 3 * (begin 1 + cell 1 + row-charge 4) + finish 1 | 20 |
| Filter | input 6 + roots 3 + 3 * seven-step rows + finish 1 | 31 |
| Select | input 6 + 3 * four-step output rows + finish 1 | 19 |
| Child handoffs | Two completed child transitions | 2 |
| Total | 20 + 31 + 19 + 2 | 72 |

The old Values subtotal was 11. Its nine additional steps are exactly three
rows times three additional cursor steps. Filter and Select are unchanged.
The workspace peak remains 9: metadata 3 + input roots 3 + snapshot 1 +
predicate slots 2. Work 71 and workspace 8 still refuse with their own typed
causes, rather than accepting any execution failure.

### Values -> fixed window -> keyed window group

The input has three rows and two scalar columns. Window emits four columns;
the two output groups have counts 2 and 1 and preserve the fixture's fixed
NULL-first order.

| Component | Independent phase count | Work |
| --- | --- | ---: |
| Values | names 2 + 3 * (begin 1 + cells 2 + row-charge 6) + finish 1 | 30 |
| Window | schema 6 + input 3 * 3 + 3 * (begin 1 + membership 1 + cells 4 + row-charge 10) + finish 1 | 64 |
| General group | Derived below, unchanged | 213 |
| Child handoffs | Two completed child transitions | 2 |
| Total | 30 + 64 + 213 + 2 | 309 |

The former Values and Window subtotals were 15 and 37. Their changes are
`3 * (6 - 1) = 15` and `3 * (10 - 1) = 27`, respectively.

The general group uses the existing `BoundedGroup` owner, not global-count:

- Input charge: three rows times row + four cells = 15.
- Setup: supported profile 1; input-name charges/exhaustion 30;
  three key-name charges/exhaustion 27; count argument setup 5;
  four output-name charges/exhaustion 29. Total 92. Name charges are
  `1 + UTF-8 length`, with a separate phase-exhaustion step.
- Stable merge: setup/validation/source/target phases 17, merge orchestration
  6, first equal pair merge 17, singleton merge 3, final merge 13,
  transfer 1 = 57. Three equal scalar terms take 13 comparison steps;
  NULL/number short-circuit comparisons take 4. Both occur in fixed input
  order, independently of quantum.
- Group ranges: setup 1 + equal comparison 13 + unequal comparison 4 +
  two group appends 2 + final-position transition 1 = 21.
- Count/emit: for a group of M rows, start group, start aggregate, choose
  direct collection, M contributor steps, finish collection/count,
  aggregate exhaustion and emit take M + 6. Groups of 2 and 1 take 15,
  followed by group exhaustion and finalization 2: total 17.
- Managed output: two rows * (four scalar cells + commit) = 10, finish 1.

Thus group work is `15 + 92 + 57 + 21 + 17 + 10 + 1 = 213` without deriving
any expectation from the execution meter. The workspace boundary remains
37/36. Neither control accounting nor reservation ownership is changed.

## Evidence and scope

The unmodified baseline reproduced exactly two failures in five selected
exact-boundary tests (`run-6fEQUh`, `focused-test-vJYKmx`).
After the source-derived fixture repair, both complete owning files passed
9/9 (`run-nxjgPT`, `focused-test-tT4yun`):

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js \
  src/query_integration/local_window_group_chain_resource_wbtest.mbt \
  src/query_integration/local_retained_values_chain_wbtest.mbt
```

Exact and one-short work now run at quanta 1, 7 and 256 with identical total
work and independent expected rows. The existing workspace, positive-progress
cancellation, no premature output, stopped state, repeated cleanup and
ledger reservation/holding-zero assertions remain. Poll loops have finite
guards; changing quantum cannot hide nontermination.

These local receipts apply to the changed fixture source with unchanged
baseline product code. Full Core JS on the final integrated revision, other
backends, packed consumers and hosted CI were not executed locally; #498
remains subject to its integrated verification requirement.
