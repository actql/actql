# Parenthesized original-source range fields

Date: 2026-10-09. Frontend connection repair, not a new expression evaluator.

## Contract and counterexample

Baseline: `b08ccd38bc77731b9195c31fd0a15380d1b2869d`, stacked on #1053.
The common Program accepts ordinary field arithmetic. Authored source
`SELECT ((p)).x + 0 AS value FROM pair p ORDER BY value` parses but fails
lowering. The initial focused gate `run-MJnJAJ` / `focused-test-Bk803Y` is 1/2:
independent Program accepted, source refused. This is compiler evidence, not a
published Run failure or a backend differential test.

GoogleSQL [range variables](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#range_variables)
refer to table rows, and [field access](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/operators#field_access_operator)
selects a field from a STRUCT expression. Parentheses retain the receiver.
This unit connects field access to existing range slots; standalone whole-row
STRUCT construction is separate coverage. Existing adopted name resolution,
value/range distinctions and common property typing are retained.

## Repair

The bounded binding prepass already used by scoped Pipe expressions is shared
with ordinary source expressions. It resolves an existing receiver/member slot
only when the receiver does not name a visible value. Ambiguous value names
also block range substitution. Authored private-looking names cannot be captured.
The source AST owner remaps exact subtrees with original locations; expression
and Graph macro lowering continue through their existing owners. Nested members
remain ordinary nullable property access. Unknown or removed ranges and work
exhaustion remain explicit refusals. No row object, runtime owner, fabricated
type/key evidence, extra Source acquisition or compatibility fallback is added.

## Independent acceptance obligations

The existing computed-object corpus gains seven successes and three exact
pre-admission refusals, without a new consumer/Host profile. Source JSON control,
SQL, unchanged Pipe, quoted range and empty input preserve `id > 0`, ordinary
`amount + 0`, duplicates, typed NULL, explicit order and complete Result columns.
Nested object access and a same-named object/range contrast retain value receiver
semantics. Refusals cover a missing field, scalar receiver member and displaced
range alias. Named Result read/describe, attach and same-submission replay retain
the existing acquisition/admission assertions. The fixture Program is never
patched after lowering, and expected rows/contracts are independently authored.

## Evidence and remaining scope

Initial repair scope/property/ORDER JS gate: 16/16 (`run-533RVG`,
`focused-test-1CLotr`). Expanded scope/JOIN/property/ORDER JS gate: 24/24 (`run-8rNTaD`,
`focused-test-58JvjX`). Fixture/profile Node gate: 14/14 (`run-L2yDnT`,
`focused-test-vUbrDy`). Formatting and `git diff --check` pass.
Normal five-package Local/HTTPS acceptance remains to be completed. Their exact source SHA, package digests and
receipt must be recorded separately from preparation evidence. Full Core,
Wasm/Native, proofs, performance and required CI are not established here.
#1053 remains an unmerged dependency until its current public status changes.
