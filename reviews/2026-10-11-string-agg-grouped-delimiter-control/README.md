# Grouped STRING_AGG delimiter: independent Frontend connection

Adopted main: `f17e9fb2c93c84d0008d09018692f2c0e3f90d17`.
Separate from #1451 PIVOT, the completed #1422 UNPIVOT unit and the untyped
NULL set-context/common expected-output-contract gap. No unmerged dependency.

## Counterexample and selected reference

```sql
SELECT STRING_AGG(name, ('|') ORDER BY payload.score NULLS LAST, id) AS names
FROM objects
```

The existing common Program represents this as the same `string_agg` delimiter
`"|"`. At the baseline, the Frontend rejects the first parenthesis with
`STRING_AGG delimiter must be literal`; its later literal-root check would also
reject a grouped literal. This is a source-inspected failure, not an executed
baseline test or a public Run failure.

The pinned GoogleSQL reference is
`d82db99a923a46571f543a13899dc791a7b6f743`. Its `STRING_AGG` signature requires
a non-NULL, non-aggregate delimiter and its resolver verifies a literal
(`googlesql/common/builtin_function_internal_2.cc`, STRING_AGG registration).
Grouping does not change the literal's value. The [aggregate reference](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/docs/aggregate_functions.md#string_agg)
defines NULL omission, empty/all-NULL results and delimiter semantics.
This unit admits grouped String literals within the existing profile; it does
not admit arbitrary constant expressions, parameters, BYTES or NULL delimiters.

## Implementation and independent obligations

`QueryParser::aggregate` admits a grouping token at the delimiter entry, parses
with the ordinary bounded expression parser and unwraps only `Parenthesized`
nodes before requiring `StringLiteral`. The same parser serves SQL, Pipe
AGGREGATE and window calls. No value evaluator, aggregate Owner, casts, transport,
storage or fallback is added. WHERE, ORDER, OVER/frame and output aliases are
retained, as are the decoded chunk values and original parser limits.

The existing complete ordinary aggregate Program and window Program are
independent controls. New SQL/Pipe/window source forms compare to those exact
Programs; normal common checking remains required. Grouped nonliteral
parameters, numbers, NULLs and concatenation retain the selected diagnostic.

Public fixtures add three ordinary normal cases (SQL, raw/decoded Pipe
separator and empty input), one window normal and four preparation refusals,
using existing normal/selected registrations. For ordinary input, the captured
predicate removes id=0, the duplicate id=2 occurs twice, NULL names are omitted,
and nullable property keys retain authored NULLS LAST/order. The independent
result is `b|b|a|c`, or with raw backslash+n then CR separators,
`b\n\rb\n\ra\n\rc`. Empty ordinary input yields one row with SQL NULL;
window frames retain NULL/duplicate behavior and ordered columns `id,names`.
All expected rows and full schemas are authored directly; no compiler/Host
output generates them. Existing acquisition-count expectations remain one.

The independently enumerated declared corpus has 3,890 occurrences, not 3,890
executed tests. No new public driver or selector is introduced.

## Identity and generated artifacts

Preserve `pre-string-agg-grouped-delimiter-values-identities.json`: the complete
adopted f17 grammar, Values dependencies and Run preimages. Only query rules
change for this unit, so the compiler's rules pin and grammar-bound Template,
Executable, Compiled and Run CIDs change. Program/semantic identity, Values
Unit/proof and ResultPlan are unchanged from adopted main. Current fixed CID
expectations use the independent hand-assembled oracle, never a product result.

Existing generators update manifests/compiler pins, metadata/family references
and canonical registration. The canonical generator also registers eight
already-present main Model/decision schemas missing from main's generated file;
these are main-source freshness, not new contracts authored by this change.
No workflow, historical declaration or common Model/Effect implementation is
modified. D confirmed the delimiter parser is outside its current edits.

## Verification status

Prepared source/Program/runtime tests are not executed evidence. No guarded
JS/Node runtime test, public Local/HTTPS, Wasm/Native runtime or CI result is
claimed. B's prior process-inspection guard refusal is neither retried nor
bypassed. Read-only freshness, static syntax and formatting are recorded
separately. An independently authorized owner can adopt the fixed commit into
its own clean worktree and use the prepared limited guard commands. Public
acceptance requires a separately coordinated Heavy slot and normal same-source
packages; none is started for this light preparation.

## Main 8305 integration

The second parent is main `8305fdb52a5bca8a41d7f5278077035705cb6e9e`; the
first parent is the submitted `d25a84d72965924e2dc30cfde46a3c4e02e0cf90`.
This normal merge preserves main's Python, Graph, Model capture, retirement and
publication changes without semantic edits outside the Frontend boundary.
The only conflict was `spec/spec-family.json`. Its main references were kept
and the existing compilation, metadata, family and canonical generators
updated the branch's query-document imports. The family generator also
records main's three pending INFER requirements; it does not claim their
implementation or runtime acceptance.

`f17-current-values-preimages.json` retains the old submitted preimages.
`main8305-identity-comparison.json` compares independently assembled full
identity inputs against both that file and the frozen main baseline. The
semantic preimages are unchanged; only recorded source-baseline metadata
changes. New static receipts are separate from `static-checks.json`.
No compile, guarded runtime, public acceptance, Heavy acquisition or CI
retry is performed by this integration. Prepared bounded commands are
tracked in `prepared-checks.json` for independent clean-worktree execution.
