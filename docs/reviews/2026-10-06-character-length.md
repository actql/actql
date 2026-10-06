# GoogleSQL character-length spellings

## Scope and reference

Based on main `a3f551fd1f02cbb86aef45710311962df47bcd90`.
`CHAR_LENGTH(value)` and `CHARACTER_LENGTH(value)` now use the same common
`len` node as the existing query `LENGTH(value)`.
The selected [GoogleSQL STRING function reference](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/string_functions#char_length)
and [CHARACTER_LENGTH synonym](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/string_functions#character_length)
supply the source spellings. The common STRING contract counts retained Unicode
scalars, propagates SQL NULL and checks operand types before execution.

This closes missing query spellings, without a new evaluator, coercion, value
normalization or Host profile. Output remains the existing `number` contract
used by LENGTH; it is not a claim of complete GoogleSQL INT64 or BYTES support.
Quoted and qualified function names remain outside the closed query namespace.
Parser grammar, common expression bodies, schemas and canonical pins are
unchanged: all three spellings lower to the same existing expression node.

## Independent expectations

- Complete hand-written source-free Program: `len(literal("e\u0301😀"))`.
  All three spellings are compared against that entire Program and checked
  through the ordinary checker.
- Composed `é`: 1; decomposed `e\u0301`: 2; supplementary `😀`: 1.
  Combined decomposed plus supplementary text has 3 scalars, distinct from
  its UTF-8 byte count and UTF-16 length. No expected value is obtained from
  product len, a host string-length helper or the compiler.
- Empty STRING has length 0; SQL NULL has nullable number output. Typed empty
  Result retains its number schema and declared column order.
- Nullable source rows preserve duplicates and ordered IDs; the existing public
  harness also checks Result.describe, same-request identity, attach/re-read
  and no additional acquisition on replay.
- Wrong arity, numeric operand and undeclared parameter are preparation refusals
  with Run admission and provider I/O unchanged.

## Verification

Before the implementation, the two focused character-length tests failed on
main in `run-sor1yy` / `focused-test-UVOJA7`.
After connection, focused JS passed 26/26 in `run-lXnb7m` /
`focused-test-vWJq42` (query_expression plus character-length, IFNULL and
source-free Program caller tests).
Targeted Node passed 11/11 in `run-w9fPwj` / `focused-test-cka0qK`.
The packed route registration assertion for IFNULL was made tolerant of other
operands in the existing early-return condition; its inclusion/exclusion
obligation is preserved.

Public clean-HEAD packed Local/HTTPS acceptance is pending. The six positive
and four refusal fixtures are registered in normal packed acceptance and
`--character-length-only`; the selector does not change Host ceilings.
No full Core, Wasm/Native execution, full packed campaign or manual CI rerun
was performed. Draft CI remains separate from merge verification.

## Separate common dependency

A probe of row-dependent `IN` lists found that common expression admission
still only admits literal lists and whole parameters as membership RHS.
`id IN (amount + 1, id)` therefore needs the existing common dependency
[#577](https://github.com/actql/actql/issues/577), which already records that
boundary. The exploratory array lowering was not retained. No OR expansion,
frontend execution owner or relaxed admission is included in this PR.
Its failed probes remain under local `review-artifacts/b-expression-in-list-2026-10-06`;
this is not an executed public Run failure or a new defect in len.
