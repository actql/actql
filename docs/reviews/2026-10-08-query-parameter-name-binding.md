# Query parameter name binding

## Requirement and counterexample

Base: `5253816b4ccd6c4d1899d745b6c79f659c1e62fa`. The selected GoogleSQL
reference is `d82db99a923a46571f543a13899dc791a7b6f743`.
[`Resolver::ResolveParameterExpr`](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/analyzer/resolver_expr.cc#L2418)
folds a named parameter with `AsciiStrToLower` before declaration lookup.
Quoted names are decoded identifiers in the same namespace. Source inspection
of that fixed checkout is not live Google-service conformance.

With the independently declared number parameter `p`, this source previously
left `$param: "P"` in ordinary take operands:

```sql
SELECT id, amount FROM orders ORDER BY id LIMIT @P OFFSET @P
```

The independent full expected Program uses `$param: "p"`. The expected
Program and lowercase control pass the ordinary checker before the uppercase
case fails. The explicit pre-fix result is **0/1** in
`_build/local-checks/attempts/run-BGLvpJ`, focused receipt
`_build/focused-evidence/focused-test-t0IotC`.
A previous guard preflight failed before test execution and is not red evidence.

## Implementation boundary

- Build one bounded source-name index from already admitted declarations. Bind
  ASCII case variants to the exact declaration spelling. Fold collisions reject
  the source context with `InvalidContext`; no declarations or values merge.
- Share that index through existing Construction owners and expression-lowering
  callbacks. Whole LIMIT/OFFSET, analytic boundary/navigation operands and named
  graph-operation arguments use the same source lookup. No Program rewriting
  after lowering and no inference of types or values.
- ARRAY/STRUCT UNNEST probes receive the same binding before ordinary expression
  typing. Receiver/member/nullability checks still belong to common owners.
- Source expression reuse and analytic window comparison use the same parameter
  namespace. Equivalent spellings do not recompute SELECT expressions or split
  one analytic window. Different frame boundary kinds remain different.
- Machine declarations and bound-value keys remain exact. Missing, extra,
  invalid-domain and type checks remain ordinary checker responsibilities;
  unknown names are not supplied a value or a default. Literal strings and
  non-ASCII code points are not case-folded.
- The selected query-expression interface is regenerated with `moon info
  src/query_expression`. No common Program schema, grammar manifest, canonical
  contract, registry or runtime Owner changed. The design mapping documents the
  source binding separately from machine identity.

## Independent expectations and actual checks

Complete independently authored Program comparisons cover scalar references,
SQL/Pipe take operands, shared analytic frames, DISTINCT expression reuse,
nullable parameter property/UNNEST projections and navigation offsets. The
exact declaration `P` retains its spelling while source `@p` binds to it;
values keyed by `p` still fail ordinary checking. Fold-colliding declarations
and bounded index work retain explicit refusals.

Two corrected intermediate runs found real remaining connection gaps:
`run-BKZYHE` was **12/13** because frame comparison still split equivalent
windows; `run-18DDCC` was **18/19** because the UNNEST type probe did not bind
its parameter. These failures are preserved; expected Programs were not changed
to accept the incorrect lowering.

Corrected working-tree checks: **34/34 JS**, **8/8 Node**, receipt
`_build/local-checks/attempts/run-rKIItm`. Focused receipts:
`focused-test-uOdGbR` and `focused-test-8m2PxG`. Selection:

```text
moon --target js
  src/query_program/parameter_reference_case_test.mbt
  src/query_program/limit_parameter_test.mbt
  src/query_program/analytic_frame_parameter_test.mbt
  src/query_program/unnest_parameter_path_test.mbt
  src/query_program/distinct_order_output_test.mbt
  src/query_program/grouped_analytic_offset_test.mbt
  src/query_expression/lower_test.mbt
node
  scripts/limit-parameter-source-input.test.mjs
  scripts/unnest-parameter-path-source-input.test.mjs
  scripts/public-query-cases.test.mjs
```

These selections run through the existing bounded guard and nonzero wrappers,
not unwrapped full-suite commands. Formatting uses the pinned direct moonfmt;
`git diff --check` passes. Working-tree evidence is not relabeled as a clean
published-HEAD run or CI success.

## Public acceptance obligations

New cases extend existing ordinary cohorts and their unchanged packed consumer:

- LIMIT: **14 successes / 13 preparation refusals** per transport, including
  uppercase/quoted/escaped references, uppercase admitted declaration names,
  wrong-case machine value keys and folded declaration collisions.
- Analytic frame: add the mixed-spelling equivalent-window case to the existing
  frame consumer, retaining its full independently expected columns and rows.
- Parameter property UNNEST: add uppercase and quoted receiver cases to the
  existing normal cohort, retaining NULL parents/elements, duplicates, offsets,
  empty schema and no Source acquisition.

Original expectations and cases remain. The consumer checks public Named Result,
complete describe contracts and column order, hidden-column absence, stream
completion, retry/attach identity and source acquisition counts; refusals must
have no Run admission or provider I/O.

Normal clean-HEAD five-package producer/digests and packed Embedded Local/HTTPS
execution are **not yet verified** for this unit. The shared heavy slot is in
use by another worktree; no parallel producer, lock bypass, overlay, old package
fallback or selective failure exclusion was introduced. Full Core, Wasm/Native
execution, three-target API gate and CI remain unverified. This is an independent
Frontend correction; it does not close all public language coverage.
