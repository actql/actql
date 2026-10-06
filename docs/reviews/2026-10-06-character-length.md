# GoogleSQL character-length spellings

## Scope and reference

Based on main `a3f551fd1f02cbb86aef45710311962df47bcd90`.
`CHAR_LENGTH(value)` and `CHARACTER_LENGTH(value)` now use the same common
`len` node as the existing query `LENGTH(value)`.
The selected [GoogleSQL STRING function reference](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/string_functions#char_length)
and [CHARACTER_LENGTH synonym](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/string_functions#character_length)
supply the source spellings. The expected STRING semantics count retained Unicode
scalars and propagate SQL NULL. Ordinary checker tests establish operand typing;
public execution remains blocked at the common lowering boundary described below.

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
- Wrong arity, numeric operand and undeclared parameter have authored preparation
  refusal fixtures requiring Run admission and provider I/O unchanged; those
  public refusal checks have not yet executed.

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

Before adopting #648, the initial clean-HEAD packed acceptance failed at the first Local independent JSON
control, before any new source spelling was exercised. The SDK observed
`SubmissionUnknown` caused by `ClientHostFailure` (HTTP status 500) for request
`packed-local-character-length-json-control`. This is not a confirmed input
refusal or a successful character-length Result. Later Local cases, all four
refusal cases and the character-length HTTPS corpus were not reached.
The six positive and four refusal fixtures remained registered in normal packed
acceptance and `--character-length-only`; the selector did not change Host
ceilings or expected results. This is historical pre-integration evidence.

The pre-integration five-package producer used clean source
`5735ca3a38c37548b07626debd30d114ca388faf`; its temporary manifest and pack
were removed during the later disk cleanup. The later report-only commit did
not constitute a separately built distribution. The pre-integration tarball
SHA-256 identities were:

| Package | SHA-256 |
|---|---|
| client-wire | `04dff256ba4d6810f27dbb184b1bd3b0297ef8c988cae72e5fd2cb884e33792c` |
| sdk | `a4d00c42047342fcad8d4a74f470bae38ae303e4c0a532d6099c9056fc560174` |
| run-host-core | `0ec6f7f798a5b804092b81cf508a608a4fb2a89e51d1f2f66523e953991403cc` |
| local-node | `cb4c7ab7c01909ed0370e929bbb4ef5df6975bb05ee4b51de975114b2f136201` |
| node | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |

Executed commands, through the existing serial local-check guard:

```sh
node scripts/local-checks.mjs test moon -- --target js src/query_expression src/query_program/character_length_test.mbt src/query_program/ifnull_test.mbt src/query_program/source_free_test.mbt
node scripts/local-checks.mjs test node -- scripts/character-length-source-input.test.mjs scripts/ifnull-source-input.test.mjs scripts/public-query-profiles.test.mjs
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-character-length-pack-r0Jt0C node scripts/test-packed-public-query.mjs --character-length-only
```

Public attempt `run-yjOGY5` failed. Original receipts and command logs are in
`../.codex-scratch/public-query-evidence-G6qqNv`; the consumer's generated
installation was automatically removed after evidence preservation.
A subsequent same-package, fresh-consumer diagnostic (`run-g10xrd`) used an
in-memory HTTP catch logging loader and `--keep-artifacts`. It reproduced the
same symptom but did not expose its inner cause; it is not pristine acceptance.
Its retained installation and Stores are under
`../.codex-scratch/public-query-evidence-ao9O1W/artifacts`.
Copied logs, manifest, command receipt and diagnostic source are preserved locally
in `review-artifacts/b-character-length-2026-10-06` (untracked evidence).

An independent one-test common-boundary probe passed 1/1 in `run-yZErEQ` /
`focused-test-gDdGXW`: `len(literal("abc"))` passes pipeline checking, then
`lowering_relation.lower_expression` returns exactly
`ExpressionNotImplemented("len")`. The probe is retained as diagnostic source
in the local evidence directory, rather than turning missing execution into an
accepted product regression. Source inspection agrees: `expression_tag` in
`src/lowering_relation/expression.mbt` has no `len` case. This establishes a
common execution dependency; it does not establish that this is the sole cause
of the observed public 500. No common evaluator or Host error mapping was changed.

At that earlier revision, common `len` lowering/evaluation was still required.
No frontend evaluator or literal-only special case was used to bypass that
dependency. The integrated acceptance below supersedes the old pending status.
No full Core, Wasm/Native execution, full packed campaign or manual CI rerun
was performed. Draft CI remains separate from merge verification.

## Integrated common dependency and public acceptance

The common execution dependency was adopted by normal-merging #648; its merge
commit is `2a68ffdcb5698b6142d1acd50fa6a09d086bc439` and the fixed feature
SHA is `399991046fad6d61c1a6d4003ae341d8befdf209`. The resulting Frontend
branch HEAD used for the final source and package build was
`530794f22b877e3ae49115985261ead382e20ace`; the one-line parameter declaration
fixture correction is included in that HEAD.

From that committed HEAD, a normal five-package build was used with
`node scripts/packed-client-packages.mjs`, followed by
`node scripts/test-packed-public-query.mjs --character-length-only`.
Embedded Local and HTTPS both completed all six authored successes and four
preparation refusals. The successes include the independent JSON control,
composed/decomposed/supplementary Unicode, empty/SQL NULL, Pipe parameter,
typed empty output and nullable duplicate source rows. Named Result rows,
declared column contracts/order, attach/re-read identity and no extra source
acquisition on replay passed on both transports. The demanded invalid inputs
remained preparation refusals. The earlier Host 500 was therefore a missing
common execution dependency, not the final result for the adopted SHA.

The generated pack directory was removed after preserving the run outcome to
respect the repository's disk budget. It was not reused as a later evidence
source, and no package digest is claimed here. The exact source/package
association is the committed HEAD above; a fresh pack is required for any
future rerun.

## Separate common dependency

A probe of row-dependent `IN` lists found that common expression admission
still only admits literal lists and whole parameters as membership RHS.
`id IN (amount + 1, id)` therefore needs the existing common dependency
[#577](https://github.com/actql/actql/issues/577), which already records that
boundary. The exploratory array lowering was not retained. No OR expansion,
frontend execution owner or relaxed admission is included in this PR.
Its failed probes remain under local `review-artifacts/b-expression-in-list-2026-10-06`;
this is not an executed public Run failure or a new defect in len.
