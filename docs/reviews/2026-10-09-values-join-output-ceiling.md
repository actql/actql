# Explicit Values JOIN output ceiling

Date: 2026-10-09. Scope: preserving the authored common JOIN argument.

## Adopted contract and baseline

Adopted main: `f8fbc50e5dcf1bd2b2558736f3a87f51fff04195`.
Parent #1132: `c8d5b4016d8476bfd9aa06fd642892e31b5e3db2`, still unmerged.
The final target remains main; retain the parent base until its dependencies land.

The optional MAX_OUTPUT_ROWS suffix retains the common max_output_rows author
guard (query-text.md, author guards). It must not be clamped or replaced by a Host
limit. The standalone uncaptured GeneratedValues JOIN specialization instead
calculated its cartesian reservation and ignored part.max_output_rows.

```aql
SELECT t.x AS x FROM t JOIN r ON t.x = r.k MAX_OUTPUT_ROWS 1
```

Inputs are independently fixed: t has (x,y)=(1,20),(2,10); r has k=1,2.
The equality JOIN has two actual rows. Its authored guard is 1, so successful
publication of those two rows would violate the guard. The independent complete
ordinary Program has the same sources, ports, keys, projection and guard 1.

Baseline `run-2gNggB` / `focused-test-NT1alS`: 1/4 passes. The complete
Program comparison shows the sole mismatched argument, generated 4 versus
independent 1. Guard 11 is accepted despite an admitted Frontend ceiling 10;
author guard 1 is rejected when that Frontend ceiling is 1 because the ignored
cartesian value 4 exceeds it. The no-suffix control retains its expected 4.
This proves the compiler defect, not a pre-repair public Host Run failure.

## Local correction

When a guard is authored, compile_join_query uses existing authored_join_bound,
which validates the safe integer, positivity and admitted Frontend maximum and
returns the exact specified value. Only suffix omission keeps the existing
cartesian derivation. The common JOIN owner enforces actual output; lowering does
not truncate, raise the guard, predict matches or manufacture uniqueness evidence.
The equivalent LEFT/CROSS specializations keep their guards as well. RIGHT and
captured/shared routes already use the existing argument path and remain intact.
No grammar, serialization, operation registry, identity law or checker/owner
contract is changed by this product correction. Program content identity follows
the correctly authored argument through ordinary canonical calculation.

The current main was normally merged before implementation. The only conflict
was four imports of the combined protocols/contracts document in spec-family.json.
The existing update-document-metadata.mjs --write generator derives their CIDs
from merged source; its read-only run reports no pending changes. Actual normative
import validation confirms all 23 imports. No old document CID was copied onto
changed text. Current main's diagnostics/Host/native code is adopted unchanged.

## Focused checks

- JS 17/17 (`run-neeibU`, `focused-test-y9KI2r`): five new guard obligations
  plus direct ordinary JOIN, RIGHT and captured-entry callers. Complete expected
  Programs independently fix bounds 1/5/10, rejection above the admitted maximum,
  the low-ceiling case and omitted-suffix behavior. INNER/LEFT/CROSS are checked.
- Node 10/10 (`run-ziH9gV`, `focused-test-GQ99Sw`): seven independent public
  fixture/registration cases and three machine import cases.
- Read-only metadata update passes with no pending writes; actual normative import
  validation passes (23).

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js \
  src/query_program/values_join_ceiling_test.mbt \
  src/query_program/join_order_test.mbt \
  src/query_program/right_join_test.mbt \
  src/query_program/captured_join_projection_test.mbt
node scripts/local-checks.mjs test node --timeout-seconds 120 -- \
  scripts/join-star-source-input.test.mjs scripts/spec-family-imports.test.mjs
node scripts/update-document-metadata.mjs
```

## Public boundary obligations

The existing JOIN public cohort adds a fully independent machine Program and
complete source using literal-only CTE relations. Guard 5 must publish the two
rows, non-NULL numeric x and its declared column order; comparison is a multiset
because no ORDER BY is authored. The otherwise identical guard 1 controls must
fail and expose neither rows nor describe metadata. Both need zero Source read
sessions and must not reacquire/recompute on resend, attach or Result reread.
The two expected execution failures are registered in normal CI and the existing
focused JOIN cohort, not excluded to obtain success.

The source's inline CTE binding uses the public shared compiler path, which already
preserved this argument before the fix. It is a public owner/semantic control, not
claimed evidence that the standalone Context with externally supplied
GeneratedValues was exercised by public SDK source routing. The complete compiler
Program equality provides the missing connection evidence for that specialization.
The published machine Program then verifies the same common execution contract.
No test modifies a generated Program to evade the intended guard.

Fresh clean-SHA Local/HTTPS receipt and original package digests remain pending at
this commit. Focused compilation and independent fixture tests alone are not public
execution success. Full Core, full packed/performance, other runtime targets and
live Google differential validation remain unverified. No manual CI retry or merge
is requested. The overall Frontend goal remains active.
