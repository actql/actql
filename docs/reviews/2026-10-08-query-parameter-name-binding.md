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

## Main integration

Normally merged `05c6867d2d11915388ea14347a6da6ce29c75bd5`, including
#980 quoted aggregates and #975 retained evaluated NEAREST vector inputs.
The merge had no conflicts and preserves both corrections. The final submitted
HEAD and its limited integration checks are recorded in the PR body separately
from the earlier working-tree evidence above. No CI result or public execution
is inferred from the merge.

## Submitted package evidence and integrated refusal correction

Normal producer `run-zKKIXO` generated all five packages from clean submitted
`2d3362a02ba284ca5b4eb239ded13d0bccbf8221`. The original manifest is
`/private/tmp/actql-b-parameter-binding-2d3362a02-pack/packed-client-packages.json`.
All five tarball SHA-256 digests were checked before reuse. No skipped prepack,
adapter overlay, manifest rewriting or old-package fallback was used.

The existing `--limit-parameter-only` consumer passed on both Embedded Local
and real HTTPS: all **14 successes / 13 preparation refusals** per transport.
Receipt: `run-hYyePs`. Complete evidence:
`worktrees/.codex-scratch/public-query-evidence-vpQTbv/summary.json`, passed,
with no evidence errors and generated installations removed after recording.
The public runner retains complete described contracts/column order, expected
rows, NULL/duplicates, acquisition and retry/attach checks, and zero Run
admission/provider I/O on preparation refusals.

The same exact packages then ran the unfiltered frame cohort (`run-PcNIoN`,
`public-query-evidence-oMQOzc`). All eight Local successes passed, including
mixed-case shared windows and typed empty output. The first reversed-frame
refusal stopped on a stale expected code: `ClientProgramRejected` instead of
`ClientProgramInvalidInput`. HTTPS and the rest of the refusals were not reached;
this failed campaign is retained and is not successful full-frame acceptance.

The correction follows the already adopted common boundary, not the runtime
output alone. Common commit `e8347bc4e8` classifies
`Closure(Operations(Frames(InvalidFrame(_))))` as `InvalidInput` and fixes that
exact cause/category in `program_check/diagnostic_category_wbtest.mbt`.
`client_program_bridge.mbt` maps it to `check_invalid_input`, and the existing
Node preparation adapter maps that category to `ClientProgramInvalidInput`.
The original frame handoff also requested this invalid-input classification.
The four source/independent-JSON controls now require that exact public code;
inputs, parameters, Programs, rows, types, order and limits remain unchanged.
The source-to-checker test asserts the exact common category as well as cause.
Before correction the new bounded Node control failed **4/5** (`run-XiJUfL`,
`focused-test-M22cwU`); that failure is not a product rejection defect.

Normally merged main `6df5644df1070b2ed2509609d7214ccffde30795`, retaining
#981 QUALIFY and #963 NEAREST input controls, without conflicts. Earlier
`2d3362a02...` package results remain evidence of that SHA. Fresh integrated
packages and the remaining frame/UNNEST public consumers are still required;
no older successful campaign is relabeled as this newer HEAD's result.

Integrated working-tree verification: **17/17 JS** in `run-6RCjjC`,
`focused-test-Ii5G2M`, selecting parameter names, frame parameters, nullable
parameter UNNEST, script NEAREST and quoted QUALIFY. That guard's following
Node command had an incorrect wrapper kind and did not execute Node tests;
the whole guard is not reported as passed. The corrected Node-only selection
passed **11/11** (`run-Hcpc1B`, `focused-test-Ikq1yk`): analytic profile/typed
frame controls, LIMIT parameters and parameter UNNEST. No JS repetition, full
Core, proof, performance or manual CI rerun was added. Pinned direct moonfmt
and `git diff --check` passed.
