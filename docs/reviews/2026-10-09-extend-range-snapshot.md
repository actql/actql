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
All previous range/JOIN cases remain unchanged, including their existing exact
refusal codes. These cases run in normal packed CI and its same focused cohort;
no new acceptance framework or post-lowering Program rewrite is added.

Fresh exact-SHA normal five-package production and Local/HTTPS execution remain
pending at this commit. Compilation and fixture success are not execution
success. Full Core, full packed/performance, other targets, CI and live Google
differential validation remain unverified. No manual retry, Ready transition or
merge is performed. The full Frontend completion objective remains active.
