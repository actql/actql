# Aggregate SELECT input scope

## Baseline and counterexample

Base: `8899d1041b390bb7c60742ce79277859e229da61` (main). The adopted
[query scope contract](../spec/query-text.md#scope-and-lowering) already says
that SELECT siblings resolve against the input snapshot. HAVING and final
ORDER BY use SELECT aliases; a subsequent Pipe operation consumes the completed
SELECT output. This repair adds no language contract or execution owner.

Main `c26339bed484c1965da78f6a9540333c2583ea31` is normally integrated at
`3e4a8c18341d22f4a4d8ea20e1d05c2bde9d23a6`. Two packed-runner registration
conflicts retain both the new scope corpus and main's ORDER-position corpus.

```sql
SELECT COUNT(*) AS n, n + 1 AS next FROM t
```

With only input columns `x,y`, the baseline incorrectly accepts this query by
binding `n + 1` to the new COUNT output. It also substitutes COUNT for an
ungrouped input when the alias collides, accepts a fabricated qualified `t.n`,
and leaks the same alias through a scoped three-input JOIN.

The independent rejection assertions failed **0/2** on the baseline
(`run-Rjxlse`). They require the existing expression `UnknownReference` reason,
rather than accepting any error. The expected complete Program for a valid
COUNT plus constant is authored directly as JSON and passes the ordinary checker.

Repeated GROUP keys were another investigated candidate. An exact-Program
comparison failed while its normal-checker control passed (`run-jXNdO1`). That
structural difference did not establish a semantic defect; no deduplication
change or product-derived expected-value replacement was made for it.

## Implementation boundary

`query_program/compile.mbt` retains the grouped input bindings separately from
new aggregate outputs. Ordinary expressions in the SQL SELECT use only those
bindings, in both ordinary and scoped JOIN lowering. Explicit aggregate
projections, HAVING and final ORDER BY keep their output bindings. Completion
of the SQL projection establishes the next Pipe's current row scope without
restoring old input ranges or reusing expressions over changed slots.

The common Program, checker, planner, Host, capacity policy, provider and wire
contracts are unchanged. No grammar/schema/law pins or public API change.
Queries that previously read a new SELECT alias from a sibling now reject under
the existing contract. Valid grouped expressions and subsequent Pipe expressions
continue through the ordinary execution path.

## Independent public corpus

`scripts/fixtures/group-select-scope-source-input.mjs` contains a hand-authored
JSON control, SQL and Pipe inputs, and explicit rows and ordered column contracts.
WHERE excludes ID 0; repeated ID 3 contributes twice to COUNT; NULL remains a
group key and nullable output. Empty global COUNT produces `n=0` with its schema.
The three-input JOIN preserves duplicate multiplicity without external I/O.

The existing installed consumer checks rows, complete `Result.describe()` column
contracts, one acquisition session per acquired input, and same-Run resubmission
without further acquisition. Invalid SELECT siblings must produce the existing
public input-error code with zero Run admission and provider I/O. These cases
are registered in the normal packed corpus; `--group-select-scope-only` is only
a local execution selection. No Program is corrected after lowering.

## Executed evidence

- Focused JS `*GROUP*`: **7/7** (`run-KPNfHQ`), including the five new tests.
- Existing JS `*group*` callers: **8/8** (`run-vKqO78`). These filters overlap;
  their counts are separate executions, not a unique-case total.
- After adding WHERE/SET/AS Pipe-scope controls, focused JS `*GROUP*` remains
  **7/7** (`run-dIOLub`). Node public-case controls pass **2/2** (`run-CLqmOH`).
- Focused JS `*GROUP*` after main integration: **7/7** (`run-LDDY3j`).
- Pinned Moon formatting, Node syntax and diff checks pass.
- Fresh normal tarballs from clean product SHA
  `3e4a8c18341d22f4a4d8ea20e1d05c2bde9d23a6`: **8 positives and 5
  pre-admission refusals per Embedded Local/authenticated HTTP transport pass**.
  The complete `public-query-evidence-XmyN0K` receipt has no evidence errors.
  Acceptance exits 0, signal null, with complete output (42.6s). The consumer
  runs outside the checkout without MoonBit or a test-side Program overlay.
  SHA, tarball digests and logs remain; its disposable installation is removed.
- Final submitted-HEAD automatic CI remains pending. The following evidence
  documentation commit does not relabel the packed product's verified SHA.
- Full local Core, all-target, proof and performance suites are not run.

Reproduce with the pinned toolchain:

```sh
node scripts/test-packed-public-query.mjs --group-select-scope-only
```

| Normally packed package | SHA-256 |
|---|---|
| actql-client-wire-0.0.0-development.tgz | `6b448edf6ff246e1865858e9ed654e6f973c602e60b65447bcd7bbdd0afaefde` |
| actql-sdk-0.0.0-development.tgz | `f3eeed5879e324f366d6da1c01ec58d27e1e5bda72e7963288c8f0046970fda4` |
| actql-run-host-core-0.0.0-development.tgz | `9ae236c22d7bc32bbd9e6751eee0686cf7f6e2f65735ce90b5cab30c8b80f919` |
| actql-local-node-0.0.0-development.tgz | `ead7f6cb9cb985a5a5f1ef20d9192cdf62c138664520a828f78e548515b71485` |
| actql-node-0.0.0-development.tgz | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |

This is a SELECT-scope defect repair, not completion of the full Frontend profile.
