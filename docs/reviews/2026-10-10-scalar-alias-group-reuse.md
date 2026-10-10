# Reuse evaluated GROUP keys across installed scalar aliases

Inspected main: `584b3a6144d4a8053ca4a541ef042a6e17c674e9`.
This is a Frontend connection repair, not a common evaluator or new SQL function.

## Independent discrepancy and selected reference

```sql
SELECT COUNT(*) + CHARACTER_LENGTH(name) AS n
FROM objects
GROUP BY CHAR_LENGTH(name)
```

The original function-name comparison rejects the SELECT with
`Expression(UnknownReference)`: the pre-group text column has been dropped,
and the existing evaluated key is not recognized under its function alias.
An independently authored complete Values Program measures the nullable text
once with common `len`, groups that slot, then adds the checked COUNT result.
Both the independent Program and the same-spelling source control check normally.

The selected GoogleSQL registry at
[`d82db99a923a46571f543a13899dc791a7b6f743`](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/common/builtin_function_internal_3.cc)
registers `character_length` as the alias of `char_length`.
`LENGTH` is a separate function registration; matching output or a shared
ActQL wire operator is insufficient to establish public function identity.
The earlier exploratory LENGTH/CHAR_LENGTH grouping candidate was therefore
discarded, rather than widening grouping equivalence from value similarity.
The selected [CEILING reference](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/mathematical_functions#ceiling)
also defines CEILING as a synonym of CEIL. This is reference inspection, not
a live Google-service differential execution or complete overload conformance.

## Existing owner connection

The existing scalar-call registry now retains the public function identity,
ordinary operation and accepted arity together. Lowering still emits the same
operation and validates the same arguments. The expression reuse matcher may
recognize installed aliases through that registry; it still compares argument
count, operand trees and each receiver in its original clause scope.

CHAR_LENGTH/CHARACTER_LENGTH and CEIL/CEILING share identity. LENGTH/CHAR_LENGTH,
IFNULL/COALESCE, different operations, unknown namespaces and strict/custom
CONCAT do not acquire identity merely from similar results or shared wire tags.
No input column is restored after GROUP, no alias scope is bypassed, and no
extra evaluation, key evidence, sort, acquisition or runtime owner is invented.
Grammar, normative pins and independently retained Run preimages are unchanged.

## Focused evidence

Restoring the exact original comparison in `same_expression` makes the final
three-test regression fail **2/3**, at the source above. The temporary mutation
was removed after the gate became terminal. Its evidence is
`run-NxVmiS` / `focused-test-m3pFle`. The preceding exploratory LENGTH candidate
and temporary test compilation failures are not the proof of this defect.

The repaired boundary and its direct callers passed **25/25 JS**:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js \
  src/query_expression/scalar_function_identity_test.mbt \
  src/query_expression/character_length_test.mbt \
  src/query_expression/ceiling_test.mbt \
  src/query_program/scalar_alias_group_reuse_test.mbt \
  src/query_program/repeated_group_key_test.mbt \
  src/query_program/sql_grouped_subexpression_test.mbt \
  src/query_program/order_property_receiver_reuse_test.mbt \
  src/query_program/window_key_receiver_reuse_test.mbt
```

Evidence: `run-dJ31NM` / `focused-test-vHE5Jz` in the B-owned
`worktrees/actql-frontend-qualify-group-aggregate-slots` checkout. These focused
checks are not complete Core, public Host execution or hosted CI evidence.

The fixture registration and consuming script checks passed **20/20 Node**:

```sh
node scripts/local-checks.mjs test node --timeout-seconds 180 -- \
  scripts/scalar-alias-group-source.test.mjs \
  scripts/repeated-group-key-source.test.mjs \
  scripts/public-query-profiles.test.mjs \
  scripts/compilation-manifests.test.mjs
```

Evidence: `run-ONnJGP` / `focused-test-COnOgZ`. The generated interface was
checked with the pinned toolchain's `moon info --target js,wasm,native
src/query_expression` through the bounded guard (`run-nvwIK2`, exit zero).
This establishes selected-package interface compilation, not Wasm/native
runtime execution.

## Public obligations

The normal group-ordinal public corpus includes eight new positive cases and
three exact `ClientProgramInvalidInput` refusals. Independent JSON controls
remain machine inputs; no test rewrites compiler output. Authored text covers
SQL and Pipe, quoted aliases, nullable text, supplementary and decomposed Unicode,
duplicate rows, negative/fractional numeric ceilings and typed empty results.
The Source predicate `id > 0`, independent rows/types/column order and NULLS LAST
are retained. Different receivers, a removed range and invalid arity must fail
before Run admission or Source I/O.

Existing packed acceptance checks Named Result rows, Result.describe contracts,
private-column absence, stream completion, one Source session and repeated
read/attach/same-request resend without another acquisition. The selected
`--group-ordinal-only` corpus contains 25 positives and nine refusals per
Embedded Local and authenticated HTTPS, retaining the preceding 17/6 cases.

The first clean-HEAD campaign (`5d922090af733a13512753a1c8feab4d2806f743`,
`run-95WFHs`, public receipt `public-query-evidence-iQHP6U`) passed 22 Local
positives, including the five new text cases, then rejected the authored
ceiling JSON control before admission. That control mistakenly used `ceil`
as a common expression operator. Existing CEIL lowering instead composes
`negate(floor(subtract(0, operand)))`. The independent control is corrected
to that existing finite-number contract; rows, types and SQL remain unchanged.
This was a fixture defect, not evidence of a product sorting or ceiling bug.
The failed receipt and its unchanged tarball digests remain retained; HTTPS
and the refusal cohort were not reached in that campaign.

After correction, the selected alias identity and complete checked GROUP
Program tests passed **5/5 JS** (`run-EnZKVP` / `focused-test-6S71WX`):

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js \
  src/query_program/scalar_alias_group_reuse_test.mbt \
  src/query_expression/scalar_function_identity_test.mbt
```

The same four Node files listed above passed **20/20** again after the fixture
correction (`run-YjSCnB` / `focused-test-b0SVWQ`). No product implementation
was changed to accept the mistaken JSON operator.

Final clean-HEAD five-package production, tarball digests and public
execution are pending at this preparation commit. Record their exact source SHA
and receipt in the PR; do not relabel earlier-SHA evidence. Required hosted CI,
Wasm/native execution, Cloud and remaining Frontend coverage are unverified.
The common subscript gap (#1195) is a separate dependency and is not bypassed
by this repair. No manual CI rerun or PR merge is performed.
