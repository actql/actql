# DISTINCT output-expression ORDER connection

## Selected boundary and baseline

Base main: `0c01f539f3e367b4a0c09f4ec4d07c235f9b983b`.
This is a new implementation unit after the completed semantic audit.
The existing [query scope contract](../spec/query-text.md#scope-and-lowering)
requires ORDER expressions to resolve SELECT aliases before colliding inputs,
and requires DISTINCT ordering to depend on selected expressions or aliases.
No new syntax or semantic decision is introduced.

| Boundary inspected | Existing common/public support | Action |
|---|---|---|
| Graph rows definition/label selectors and traverse node output | Integrated #316/#323 source connections | Retain; do not reimplement |
| DISTINCT followed by an expression over its evaluated output alias | Common Relation projection, DISTINCT, derive, sort and take exist; ordinary SELECT rejects the expression | Selected repair |
| Source capture, CTE predicate ownership, assertions and Effect arguments | Existing D-owned connections and #325 repair | No parallel implementation |
| Other Graph consumers and direct installed traversal selector Sources | Separate common/acquisition dependencies or unconnected source forms | Remain separate; no fallback or execution owner added |

The concrete counterexample is:

```sql
SELECT DISTINCT -x AS x FROM t ORDER BY -x
```

The ordinary SELECT branch previously materialized DISTINCT but then sent ORDER
to the input-order branch, which rejects a new expression without a deferred
projection. The existing projected Pipe branch already supports this operation.
The new focused file fails 2 of 4 tests against the unmodified product; the
selected-expression reuse and unselected-input refusal controls pass.

## Repair and independent obligations

`query_program/compile.mbt::compile_steps` connects ordinary DISTINCT to the
existing projected ORDER path. It retains the SELECT input scope only for exact
selected-expression correspondence. Live range references are closed after
DISTINCT, so an original physical name cannot masquerade as an overwritten
public alias. The same closure applies to the existing scoped Pipe path. Direct selected
input columns retain correspondence to their evaluated output slot, including
qualified references after an alias rename; arbitrary removed inputs do not.
A focused follow-up catches the initially over-broad range closure before this
correspondence is connected.

The selected expression is evaluated once; equivalent ORDER occurrences share
one helper. DISTINCT compares only public selected columns. The helper is
derived afterward and removed before publication. Unselected input ordering
still reports UnsupportedOrdering; other expression failures retain the original
expression diagnostic rather than being flattened to that classification.

`distinct_order_output_test.mbt` includes an independently authored complete
Program, common-checker admission, evaluation-count controls, selected-expression
reuse, and unselected/qualified input refusals. The first post-repair comparison
exposed an authoring error in the expected helper suffix: the existing reserved
pool contains both copies of `x`, so its length is 2. Only that private suffix
was corrected; the expected operators, references and Result contract were
unchanged. This is not counted as a second product defect.

The public fixture independently writes a JSON Program and SQL/Pipe sources.
Its input contains duplicate amount 2, amount 1, NULL, and amount 99 on ID 0.
WHERE excludes ID 0. DISTINCT output is NULL, -1, -2 in the declared ORDER;
LIMIT 2 OFFSET 1 returns -1, -2. Resolving the ORDER expression through the
input instead of the projected alias reverses those last two rows. A separate
unlimited case detects duplicate leakage, and an empty case retains nullable
column metadata. Exact rows and ordered type contracts are authored constants.

An independent SQLite calculation over an explicitly projected subquery checks
that arithmetic/order expectation. A single SQLite SELECT resolves this
colliding name differently; it is not used as a GoogleSQL name-resolution oracle.
The adopted scope contract, not SQLite's single-query alias behavior, determines
the expected result. No expected values are generated from the product lowerer.

## Evidence and remaining work

Focused JS ORDER checks pass 32/32, including existing scoped Pipe, JOIN and CTE
ORDER regressions. Before-repair evidence is `run-UBzUTJ`; the repaired broad
selection is `run-2zd8OS`. Earlier 31/31 selections are predecessor evidence;
`run-2NZbLt` fixes the selected-column correspondence counterexample before
its follow-up repair. Public-case deduplication controls pass 2/2 in Node. Pinned Moon formatting and diff checks pass.

The existing packed public-query runner includes six positive cases (machine
control, SQL/Pipe limits, NULL/duplicates, selected qualified columns, empty) and three pre-admission refusals
on each of Embedded Local and authenticated HTTP. Its existing helper compares
Result rows and descriptions, complete reads, one Source session and identical
Run identity/counters on repeat read, attach and resubmit. Refusals require zero
Run admission/provider I/O. `--distinct-order-only` selects this corpus without
running unrelated Graph/native/restart campaigns.

Fresh packed acceptance passed at product SHA
`34aad88d157c9f75973577f917302b2df0ec5e05`: six positives and three typed
refusals on **each** of Embedded Local and authenticated HTTP. Evidence
`public-query-evidence-2X49VP` is complete/passed, with no evidence errors;
the acceptance child exits 0 with complete output. Successful temporary
installations were removed after logs and digests were retained. The preceding
five-case run at `81c02c0144e0a0ef711dc9a98074d28ca47b06f4` remains predecessor
evidence, not validation of the later selected-column follow-up.

| Normally packed package | SHA-256 |
|---|---|
| actql-client-wire-0.0.0-development.tgz | `6b448edf6ff246e1865858e9ed654e6f973c602e60b65447bcd7bbdd0afaefde` |
| actql-sdk-0.0.0-development.tgz | `494cafc4a5e4615dc47bba3b46bfd3c163c06690a258c8e619cc13a4198b2123` |
| actql-run-host-core-0.0.0-development.tgz | `26032d6a2baa9798a093dc5be5293b757fd75232eb817368cef9f5aa012c8d91` |
| actql-local-node-0.0.0-development.tgz | `4a058a57b817d3f1994bb3b0967683380c93893ec3d1b874598759c5aef6aba9` |
| actql-node-0.0.0-development.tgz | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |

Reproduce the selected public corpus with the repository-pinned toolchain:

```sh
node scripts/test-packed-public-query.mjs --distinct-order-only
```

Latest main `605d42356c29ff926e046e73a87a54cf3a420f0a` was subsequently normally merged without conflicts.
It includes D's optional-Effect observations and additive Session CI records.
The Frontend repair/test/independent fixture bytes are unchanged by that merge;
the public Host gains D's separate acquisition diagnostic calls. Its new CI
and history settings/declarations are retained. No full local suite or repeated
packed campaign was added solely for this integration. Exact submitted-HEAD
integration and public acceptance remain for automatic PR CI; the pre-merge
Local/HTTP result above is not relabeled as final-HEAD evidence.

No common checker, planner, provider, Run owner, remote protocol or SDK is changed.
Normative grammar, contract versions, schemas and pins are unchanged; newly
accepted queries acquire their ordinary generated Program identities. Historical
accepted-input identities and stored data are not reinterpreted. No full Core,
all-target, proof, performance or manual CI rerun is part of local verification.
