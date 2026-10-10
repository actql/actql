# Strict CONCAT expression reuse

## Contract and pre-change counterexamples

Baseline: `584b3a6144d4a8053ca4a541ef042a6e17c674e9` (`origin/main`).
The selected [GoogleSQL CONCAT reference](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/docs/string_functions.md#concat)
describes strict NULL propagation and the corresponding STRING `||` spelling.
The existing query lowerer already maps both `CONCAT(x,y)` and `x || y` to
the same ordered two-child `concat_strict` expression. This change adds no
conversion, BYTES/ARRAY overload, numeric law or public grammar.

```sql
SELECT x || y AS value, COUNT(*) AS n FROM t GROUP BY CONCAT(x,y)
SELECT DISTINCT CONCAT(x,y) AS value FROM t ORDER BY x || y NULLS LAST
```

The previous syntax-tree reuse comparison treated Call and Binary as unrelated
kinds. GROUP had already removed the ungrouped input columns; DISTINCT could
not restore the unselected columns for ORDER. Both source counterexamples
therefore failed compilation although the independent ordinary Program was
checked successfully. Pre-change evidence: `run-MOVQm7` /
`focused-test-VRpSjH`, 0/2. A preceding test-authoring syntax failure
(`run-p7Jar0`) did not execute tests and is not product evidence.

## Minimal repair and preserved boundaries

`query_concat_expression.mbt` recognizes only a two-argument unqualified
CONCAT call or binary `||`. `same_expression` pushes their corresponding
children through its existing comparison stack. The installed function
namespace, quoted function decoding, parentheses and clause-aware reference
callbacks remain unchanged. No operand is evaluated by this comparison.

The comparison does not flatten associative trees, reorder operands, turn
three-argument calls into two arguments, or equate `ACTQL.CONCAT` with strict
concatenation. The existing GROUP, selected-expression, DISTINCT, ORDER and
property receiver checks remain responsible for actual slot meanings.
An output alias and the original qualified input still name different values.
No hidden ORDER field is included in DISTINCT or the public Result.

Complete independently authored expected Programs cover GROUP and DISTINCT.
Focused tests also cover the reverse spelling, quoted functions, grouped
parentheses, qualified input, Pipe SELECT, NULL typing and exact
`UnsupportedOrdering` refusals for unproven equivalence. The initial DISTINCT
expected Program included a redundant terminal identity SELECT; the existing
normal form names the terminal SORT instead. That structural expectation was
corrected without changing rows, NULLs, order or scope (`run-6mN4SE`, 21/22).

## Public acceptance fixture

`concat-expression-reuse-source-input.mjs` authors two ordinary JSON control
Programs, source queries, rows and ordered full column contracts independently.
The 14 positive cases cover both spellings, GROUP counts, DISTINCT, Pipe,
quoted/qualified operands, WHERE, LIMIT/OFFSET and empty inputs. Four refusal
cases keep the existing typed implementation-limit diagnostic and preparation
checks. All cases enter the existing ordinary packed campaign as well as its
selected `--concat-expression-reuse-only` entrance.

The receiver collision deliberately reverses order:

```sql
SELECT id, CONCAT(x,y) AS original, y AS x FROM pieces
ORDER BY x || y NULLS LAST, id
```

Output-alias resolution yields IDs `2,3,1,4`. `ORDER BY pieces.x || y`
instead yields `1,2,3,4`. This detects accidental SELECT-slot reuse, including
when the selected original expression uses the other concatenation spelling.
Expected rows retain the duplicate `za` observation and nullable values.
The shared Source is acquired once; ordinary same-request resubmission,
Result attach and rereading checks remain in the public harness.

## Focused verification and identity

Pinned Node 22.22.0 and MoonBit 0.10.12+1634b282e:

```sh
node scripts/local-checks.mjs test moon -- --target js \
  src/query_program/concat_expression_reuse_test.mbt \
  src/query_program/group_ordinal_test.mbt \
  src/query_program/distinct_order_output_test.mbt \
  src/query_program/join_order_test.mbt \
  src/query_program/group_property_keys_test.mbt
node scripts/local-checks.mjs test node -- \
  scripts/concat-expression-reuse-source-input.test.mjs \
  scripts/distinct-order-member-source-input.test.mjs \
  scripts/compilation-manifests.test.mjs
node scripts/compilation-manifests.mjs
```

- JS: 33/33, `run-6WzVNm` / `focused-test-oTmCaj`.
- Node: 12/12, `run-2WBTJc` / `focused-test-pw9ZC3`.
- Existing grammar and barrier manifest freshness checks pass. The selected
  grammar, rules and common contracts are unchanged, so their pins and
  independent identity vectors need no rewriting.
- Changed MoonBit formatting, Node syntax checks and `git diff --check` pass.

Normal clean-HEAD five-package packing, Local/HTTPS execution, tarball digests
and exact submitted-SHA CI are recorded separately in the PR after execution.
Focused success alone does not establish public execution, Wasm/native or full
Frontend conformance. No full Core, manual CI retry or merge is performed.
