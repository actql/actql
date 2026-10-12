# Retain adversarial Carrier controls after the existing Content fusion scan

This unit repairs eight independently budgeted Carrier controls and one Graph
Plan contract assertion from the original G frontend checkpoint. Product code,
logical work rules, installed-source inputs, physical capacity and Host limits
are unchanged.

`ff6ee1561a4aeda3d46bb9ede04cd2ac33041f13` introduced the bounded Content
fusion probe in `physical_strategy/carrier_tasks.mbt::carrier_segment_prefix_end`:
a noncaptured Stage without an intermediate root Result visits every Step until
Serialize is found. Each visit charges the existing work balance. None of these
original Programs contains Serialize, so the full relevant Step count is charged.
The former assertions omitted that scan. Captured stages exit before the probe.

| Original case | Original budget | Independent additional visits | Current bound |
|---|---:|---|---:|
| No-expansion predecessor classification | 13 | Two compute Steps | 15 |
| Source-free single Values | 7 | One Values Step | 8 |
| Bounded captured binary rejoin | 21 | Four compute Steps | 25 |
| Analytic, later Values | 73 | Four compute Steps | 77 |
| Analytic, later binary consumer | 75 | Four compute Steps | 79 |
| Repeated analytic | 92 | Five compute Steps | 97 |
| Analytic, later Carrier | 46 | Six compute Steps | 52 |
| Retained external Relation selector | 209 | rows 2 + selections 2 + query 3 | 216 |

The analytic formula is consequently `21 + 6N + 4P + 2R`, from the existing
`21 + 5N + 4P + 2R` plus this complete N-Step scan. Neither the counts nor bounds
are generated from a product work getter or a search for a successful budget.
Keep every former budget as a WorkLimit refusal and add each new one-short bound.
Keep all original task shape, typed ports, ownership, order, operation inventory,
Result bindings and Program comparisons. The only additional test helper prints
the existing typed GraphIssue on an unexpected rejection.

The separate Graph Plan assertion used historical AoA CID
`sha256:08826f64b2224dc908b42b6fbb94b1c1e989c6e8f64185d36c108028ff4e0b45`.
Its current expected CID is independently hashed from sorted-key normative
`spec/contracts/actql-aoa.json` (52,055 ASCII bytes), using Node crypto and no
compiler/runtime APIs. The independent Node test fixes both this preimage byte
count and CID. It is not an expectation copied from the compiled plan. Old Git
source and original failed receipts retain the previous assertion unchanged.

`run-QqowxR` retained 13/23 passes. The typed diagnostic overlay, original
budgets unchanged, was `run-J4t16z`: **12/21**, eight WorkLimit failures and the
one contract assertion failure, exit2. Its complete flag remains false and its
actual terminal/Owner/lock closure is separately retained. `run-tCxxfx` executed
zero cases due to the diagnostic helper initially using Show rather than Debug.
Final clean-source results are recorded separately; these failures are not PASS.

Run `node reviews/2026-10-13-frontend-core-checkpoint/carrier-prepared-checks.mjs`
with the pinned toolchain: existing nonzero wrapper, 60s / TERM5, non-Heavy.
Installed public E2E, full Core, Heavy, Native/Wasm execution, package/provider
campaign and Hosted CI: **0**. Other original frontend checkpoint cases remain open.
