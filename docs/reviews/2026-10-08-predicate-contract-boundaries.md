# BETWEEN and LIKE: source, common contract and execution boundaries

Date: 2026-10-08. Inspected main: `ad7fd0f88791a3fec4cd0a5164699a7048fbcda5`.
This is an independent common-owner handoff. No evaluator, runtime admission,
normative contract, pin or execution limit is changed by this submission.

## Independent controls

[Eight complete inputs](fixtures/predicate-boundary-input.json) contain authored
SQL, independent complete JSON Programs and standard-derived rows or errors.
The Programs and expectations are not compiler/runtime output. The source test
compares each entire generated Program with an independently written Program;
the normal Program checker is also called on both inputs. Seven pairs check;
the NULL-pattern pair rejects with the existing `InvalidInput` category.
Those checks establish source wiring and current admission, not execution.

| Input | Expected GoogleSQL result | Current observed boundary |
| --- | --- | --- |
| `2 BETWEEN 1 AND 3` | TRUE | Checks; common expression lowering rejects `ExpressionNotImplemented("between")` |
| `2 NOT BETWEEN 1 AND 3` | FALSE | Checks; unchanged `not(between(...))` Program |
| `3 BETWEEN 4 AND NULL` | FALSE | Checks; operands remain 3, 4, NULL; execution unverified |
| `3 NOT BETWEEN 4 AND NULL` | TRUE | Checks; unchanged negation; execution unverified |
| `'abc' LIKE 'a%'` | TRUE | Checks; common expression lowering rejects `PendingValidation(PatternValidation("like"))` |
| `'abc' NOT LIKE 'a%'` | FALSE | Checks; unchanged `not(like(...))` Program |
| `NULL LIKE 'a%'` | Demanded expression error | Checks; same pending pattern refusal as non-NULL value |
| `'abc' LIKE NULL` | Demanded expression error | Normal Program checking rejects as `InvalidInput`; execution not reached |

The diagnostic uses the existing `lowering_relation` pipeline, preparation and
binding helpers. It executes the non-NULL BETWEEN/LIKE and NULL-left LIKE controls
without the query Frontend. It therefore demonstrates a common boundary rather
than a text-only spelling or operand-loss failure. This low-level diagnostic does
not establish the first failure of the complete public Host path.

## Selected reference and common-contract conflict

The selected GoogleSQL checkout is `d82db99a923a46571f543a13899dc791a7b6f743`.
Its [operator reference](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/docs/operators.md)
and the [official operator reference](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/operators)
define BETWEEN using the two comparisons joined by three-valued AND, while
evaluating the tested operand once. Thus FALSE AND NULL is FALSE in the two
NULL-boundary controls; a blanket null-propagating three-argument implementation
would not suffice. Do not expand the tested operand into two independent copies,
especially inside a lazy conditional.

The selected LIKE reference explicitly makes a NULL value or pattern an error.
Current `docs/spec/language.md`, scalar LIKE pattern validation, instead specifies
ordinary nullable predicate semantics for a NULL value operand. The common
`expression_typing/signatures.mbt` signature likewise returns nullable Boolean
when a LIKE operand is nullable. Pattern NULL already has a preparation refusal;
that does not resolve the separate NULL-value conflict or prove that failure
timing agrees with lazy GoogleSQL conditional evaluation.

This conflict is established by source/contract inspection and checker probes.
No incorrect public LIKE row is claimed: execution currently stops earlier.
The correct standard-derived expectation is an error, not a successful NULL row.
Changing a golden row to NULL, or merely implementing the historical scalar law,
would preserve the wrong public meaning.

## Ownership and required connection

A owns common expression lowering/evaluation; coordinate normative changes and
dependent pins with dot. B retains the source, independent Programs and result
obligations. No other owner's worktree was edited.

- BETWEEN: connect the existing typed three-operand occurrence to the common
  bounded expression frame. Retain one evaluated tested value, typed ordering,
  the three-valued result, demand/retention and cleanup. Preserve empty inputs,
  cancellation and the enclosing IF/CASE demand mask.
- LIKE: pass the existing checked pattern owner/evidence from
  `pipeline_check_context::check_patterns` / `check_like_patterns` through common
  executable lowering. Do not delete `PendingValidation`, manufacture discharged
  evidence or invoke another regex/pattern implementation from the Frontend.
  Non-NULL literals, bound parameters, Unicode scalars, escaping, malformed/null
  patterns and NULL values require distinct independent controls.
- Resolve the public LIKE NULL-value semantics against the common law before
  claiming GoogleSQL alignment. Keep source spelling, machine semantics and
  backend execution support separate. Do not change a normative body under its
  old CID or reuse old identity vectors for a new preimage.
- After an executable fixed SHA is available, submit the saved SQL and JSON
  controls through normal five-package Local/HTTPS acceptance. Verify Named
  Result values/types, no partial publication on errors, empty input and lazy
  branches, plus request/result reuse without extra acquisition. This submission
  does not substitute a hand-built successful Program or omit a failing case.

## Focused evidence and limits

Repository MoonBit `0.10.12+1634b282e`, Node `22.22.0`. The final working-tree
selection on the inspected main passed **2/2 JS tests**: eight complete source/
Program pairs and a three-input common-lowering diagnostic. The diagnostic prints:

```text
PREDICATE_BOUNDARY between ExpressionNotImplemented(between)
PREDICATE_BOUNDARY like PendingValidation(PatternValidation(like))
PREDICATE_BOUNDARY like-null-left PendingValidation(PatternValidation(like))
```

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 120 -- \
  --target js src/query_program/predicate_contract_boundary_test.mbt \
  src/lowering_relation/predicate_boundary_diagnostic_test.mbt
```

Evidence in `worktrees/actql-frontend-nearest-script-inputs`:
`_build/local-checks/attempts/run-Gmk9FJ` and
`_build/focused-evidence/focused-test-rcH7Gt`. The temporary diagnostic is retained
[here](fixtures/predicate-boundary-diagnostic.mbt) and was removed from `src` after
the process completed. To reproduce, copy it to the unused test path above,
execute the command, then remove only that copy after terminal completion.

The final source test restores the tested admission checks after an unsuccessful
attempt to inspect the nested NULL-pattern error with an overly specific pattern
and then a non-Debug exception. Those diagnostic-attempt failures are retained in
`run-KCT2HP` / `run-8v371Z`; they are not additional product failure claims.
The NULL-pattern test verifies the stable public category, not a fabricated
precise nested cause.

No clean submitted-SHA execution, packed Local/HTTPS, Wasm/native, full Core,
proof/performance, external Google-service differential test or CI rerun was
performed. No public acceptance or overall Frontend completion is claimed.
