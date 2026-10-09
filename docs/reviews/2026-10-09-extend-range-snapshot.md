# First EXTEND and immutable range membership

Date: 2026-10-09. Scope: existing Pipe name-resolution semantics.

## Adopted inputs and independent counterexample

Adopted main: `efe9453fd44b8b0d6f550df8158d45580185bc37`.
Parent #1134: `07b776044a845ae609bc29df4566cc8bbb330654`, unmerged.
Keep the parent base until its dependencies land; the final target is main.
This unit normally merges current main before implementation. The only conflict
is four normative protocol document imports. The existing metadata generator
derives the actual merged-source identity and reports no pending changes;
neither parent's conflicting import CID is accepted without that derivation.
Main's Source, Effect and observation owner changes are imported unchanged.

Pipe ranges bind immutable input columns/values. EXTEND adds current columns;
it does not extend a preceding range's membership (query-text.md, Pipe range
rules and JOIN range preservation). AS is the explicit rebinding operation.

```aql
FROM pair AS old |> EXTEND x + 1 AS z |> SELECT old.z
```

The independent input has x=7,y=9. The current z is 8, but old contains only
x and y. The first ordinary EXTEND left both scope flags clear. A subsequent
SELECT therefore used resolve_column with all active fields and treated z as
a member of old. The equivalent path following AS/SET/window EXTEND already
used the saved range bindings.

Baseline `run-SfnID5` / `focused-test-zkd6S1` is 3/4 passed, one failed:
the exact UnknownReference obligation above is incorrectly accepted. The loop
stops at this first counterexample; it does not prove that every later refusal
was observed pre-repair. Original-column/current-column and fresh-AS controls
already pass. This is source-to-Program evidence, not a pre-repair public Run
claim.

## Minimal correction

After the first ordinary EXTEND, compile_steps retains pipe_rebound=true.
The existing scoped lowerers then read pipe_visible for current names and
pipe_ranges for immutable ranges. Physical derived names and values are kept;
no extra final identity projection is introduced solely to activate scope.
This does not clear old ranges, change row values, expose private slots,
invent evidence, introduce an execution owner or add a compatibility fallback.
No parser, grammar, registry, contract, schema or law is changed.

The independent complete Program fixes values, add expression, original/current
slot mapping, column order and Result. It passes the ordinary checker. Positive
bare/backtick controls match the complete Program, not a product-generated
oracle. Fresh AS explicitly includes z. Invalid old.z in SELECT, WHERE, EXTEND
and ORDER reaches exact Expression(UnknownReference).

The first repair diagnostic selected UnsupportedOrdering for ORDER based on the
old unscoped branch. The existing scoped expression path instead gives the
precise UnknownReference. That expected diagnostic was corrected from source
inspection; the invalid reference was never allowed as a workaround. The
intermediate 24/25 result is retained as a test-classification observation.

## Focused verification

- JS 25/25: `run-RmkSDj` / `focused-test-7THPiJ`; four new tests plus existing
  AS, SELECT range lifetime and analytic EXTEND callers.
- Node 6/6: `run-YHdLT4` / `focused-test-MhZpLU`; independent public fixture,
  normal/focused registration and machine imports.

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js \
  src/query_program/extend_range_snapshot_test.mbt \
  src/query_program/pipe_scope_test.mbt \
  src/query_program/select_range_lifetime_test.mbt \
  src/query_program/pipe_extend_window_test.mbt
node scripts/local-checks.mjs test node --timeout-seconds 120 -- \
  scripts/pipe-join-ranges.test.mjs scripts/spec-family-imports.test.mjs
```

## Public obligations and remaining evidence

The existing immutable-range cohort adds a separate independently authored JSON
Program and complete source. Input includes duplicates and a nullable amount;
expected ordered rows are (original,current,amount)=(1,11,NULL),(2,12,20),
(2,12,20). Declared columns are original/current non-NULL number, then nullable
number amount. Bare/backtick original ranges, explicit fresh AS and empty
typed output are positive controls. Five invalid old.z consumers require
ClientProgramInvalidInput, zero Run admission and zero Source I/O.
All previous range/JOIN source, rows, types and limits remain unchanged. Their
four old generic refusal-code expectations need the current diagnostic mapping,
as recorded below. These cases run in normal packed CI and its same focused cohort;
no new acceptance framework or post-lowering Program rewrite is added.

At the initial product commit, fresh exact-SHA normal five-package production
and Local/HTTPS execution were pending. The completed campaign below supersedes
that pending state; compilation and fixture success alone are not execution
success. Full Core, full packed/performance, other targets, CI and live Google
differential validation remain unverified. No manual retry, Ready transition or
merge is performed. The full Frontend completion objective remains active.

## First packed campaign and stale diagnostic expectations

Clean SHA `045e741e6e783f5cfa3012b76f8d79d488dbc58a` normally produced all five
packages (`run-iAS51P`, receipt `public-query-evidence-IYcJTT`). Local completed
all 16 positive cases, including the five new independent/source/quoted/fresh-AS/
empty controls. The first old dropped-current refusal then stopped the campaign:
its fixture expected generic ClientProgramRejected, while the current preparation
returned ClientProgramInvalidInput. HTTPS and later refusals were not reached.

The correction is derived from existing contracts, not by copying the failure
value: query_join_chain resolves missing/displaced JOIN references as
AmbiguousColumn; client_source_preparation_issue_code projects that typed fact to
source_invalid_input; client-program-preparation.mjs maps it to
ClientProgramInvalidInput. Exact common-lowerer controls cover all four original
DROP/RENAME/displaced-range/CTE-range shapes. Only those obsolete public code
expectations change; source, independent rows, types, limits and zero-admission/
I/O assertions remain intact. This is separate from the first-EXTEND product fix.

Exact refusal controls and existing JOIN callers pass JS 8/8 (`run-RLIHoO`,
`focused-test-8fpFFH`), selecting extend_range_snapshot_test.mbt and
pipe_join_ranges_test.mbt. The corrected public fixture/registration checks pass
Node 3/3 (`run-YDw6rR`, `focused-test-2qaRkG`). The earlier 25/25 and 6/6 checks
retain their own source-state scope; the new diagnostic expectation does not
change product implementation. Public completion requires the new exact-SHA
campaign recorded below.

## Completed normal-package Local/HTTPS campaign

Tested clean product/fixture SHA: `27e95a8e676f6e026d94ac8853e0f61ef39df3c1`.
The later submission commit only adds this English evidence record.
The normal five-package producer and independent revision/original-digest
verification pass under `run-zXYfM0`. Pinned tools are Node 22.22.0 and MoonBit
0.10.12+1634b282e; no overlay, manifest relabeling or producer bypass is used.

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-extend-range-27e95a8e6-pack
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-extend-range-27e95a8e6-pack \
ACTQL_TEST_NPM_CACHE=/private/tmp/actql-b-group-key-slot-collision-integrated-pack/npm-cache \
node scripts/test-packed-public-query.mjs --pipe-join-ranges-only
```

The wrapper is `/private/tmp/actql-b-extend-range-27e95a8e6-packed.mjs`. Receipt
`worktrees/.codex-scratch/public-query-evidence-slnv3X` is outside this checkout,
relative to the workspace root. It records exact clean revision, passed/complete,
ten zero-exit commands with complete output, no signal/error/evidence error and
artifactsRemoved=true. Temporary successful install/Host Store are removed after
preserving receipt and logs. README Local/HTTPS and the deliberate missing
generated-asset check also pass.

Embedded Local and HTTPS each complete **16 positive and nine exact-code refusal
cases**. This includes all previous 11 positive/four refusal inputs and the five
new positive/five refusal controls. No known failure is excluded. Named Results
retain independent rows/types/nullability/declared column order, NULLs, duplicates
and private-field absence. Source acquisition is once per admitted Source case;
same-Run resend/attach/Result reread adds no execution or acquisition. Every refusal
retains ClientProgramInvalidInput and zero Run admission/Source I/O.
The earlier partial campaign remains historical evidence, not HTTPS success.

| Original package | SHA-256 |
|---|---|
| client-wire | `9b29e7833f9c542bb966432d0889dc10b96e35a66e74b55afcafd546ca7f9e9e` |
| sdk | `a0d29d13e2c2ccb867de88f31b923c44c7cb7224a392a2df0161bcf2a381c96a` |
| run-host-core | `013f20a6e6c63f57781b6c9c931aec19bfad8a9958670ad2b2a45f16d9917b9e` |
| local-node | `5a064a6f77c25dbd53a2b0e9bb77dc5beea9f314c819f81e767d5e8d270e2c2e` |
| node | `029a16952028cf162eeb31a9ef2ee9074c337389569e23e8e4a7750d5adf5487` |

Submitted-HEAD CI remains separate from this clean-product local evidence.

## Main integration after the parent merged

Parent #1134 is now merged. Main `321db1b2c82f7c584e64920fa007c56204862a2c`
was normally merged as `1e97dabcc5d8338805140812574477f4c55c2a72` without conflicts.
The diff against main contains only the five authored Frontend/test/evidence
files. The read-only document metadata generator reports no changes.

At that integration SHA, the bounded JS selection of
`extend_range_snapshot_test.mbt` and `pipe_join_ranges_test.mbt` passes **8/8**:
`run-e0AFDn` / `focused-test-Qow4CH`. `git diff --check` also passes.
No fresh packed campaign or full target/CI verification was repeated just for
the merge. The packed evidence above belongs to its recorded earlier clean SHA,
not the integrated submission. Retarget this PR to main, keep Draft, and record
the exact submitted-HEAD workflow state independently; local success is not CI
success or merge GO.
