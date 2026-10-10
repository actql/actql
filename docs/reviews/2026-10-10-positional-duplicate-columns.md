# Terminal positional set operands with duplicate column names

Adopted main: `42e8ad04f391218bc4ee36f61fba99f89c0bd327`. This is a
frontend projection repair using existing Program, alignment, checking and
execution owners. It does not change public duplicate-name policy, Graph
identity, capacity derivation, acquisition, grammar, wire or machine laws.

## Counterexample and selected existing meaning

```sql
SELECT 0 AS a, 0 AS b
UNION ALL
SELECT 1 AS x, 2 AS x
ORDER BY a, b
```

The independent result is `[{"a":0,"b":0},{"a":1,"b":2}]`. Each output
column is a nonnullable number. The ordinary named control uses right aliases
x/y. Before repair, duplicate x/x fails `DuplicateOutput`: focused JS
`run-eOLTdk`, `focused-test-MZ8FKt`, 0/1. This is a lowering rejection, not
an executed wrong result or capacity failure.

GoogleSQL's [positional set rules](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#set_operators)
match ordinals and use the first operand's output names. Its
[duplicate-alias rules](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#duplicate_aliases)
permit duplicate SELECT aliases when no other clause refers to their ambiguous
name. These references were inspected on 2026-10-10. No live Google service
execution is claimed. The repair is limited to an already positional right
operand's terminal projection, where no later authored alias reference exists.
It does not introduce the reference service's automatic top-level Result
renaming: current ActQL Named Results still require unique field names.

## Minimal connection and independent obligations

The two existing SELECT lowering branches keep each duplicate occurrence's
evaluated source in a fresh internal field before the existing duplicate
output check. Existing positional alignment replaces those physical names
with the left operand's names. Names use case-insensitive collision checks
and are reserved against physical/authored fields. No expression is inserted
or reevaluated by this renaming. Public, BY NAME and nonterminal projections
keep their existing checks. Input resolution and unknown/ambiguous references
still belong to the ordinary expression lowerer.

- An independently authored complete Values/derive/select/append Program
  is compared with DATA lowering and passes the ordinary checker. Its two
  right values remain distinct through unique internal fields and alignment.
- Named, implicit repeated-column and star-plus-column occurrences are
  checked. A scoped Pipe uses `original.x AS x, x AS X` after SET, retaining
  the original one and current two rather than collapsing either field.
- The ordinary SQL compiler entry is checked separately from script lowering.
- Exact `DuplicateOutput` refusals fix public duplicate columns, duplicate
  left output names, BY NAME inputs and an ambiguous operand ORDER reference.
- The existing normal and `--set-corresponding-only` public consumer gain
  five positive fixtures and three exact input refusals. Authored JSON is an
  ordinary Values/sort control, never generated from frontend output. Cases
  cover numeric values versus typed NULL, current versus immutable ranges,
  empty typed output and repeated Source rows. Shared Source uses one read;
  source-free cases use zero. Existing rows/describe/column order/hidden-field
  checks, same-request reuse, reread and refusal admission/I/O checks remain.

The scoped consumer now has 40 cases (25 normal, 15 refusal). All additions
are also registered in the ordinary public corpus. The inventory has 3,311
authored occurrences and SHA-256
`ae1a1c320217db945edc0cef7920bba127b97c6a039604f5690b56f0d73aba89`.
Its historical sourceBaseline is retained; it is not the adopted-main SHA.
This registration digest is computed from authored data, not product results.
No grammar/rule manifest or common-contract CID changes are needed for this
connection of existing syntax and semantics.

## Focused checks

- JS projection/DATA/name-matching/scope/aggregate callers: 20/20
  (`run-kU0SeS`, `focused-test-nxUJjT`).
- Additional ordinary SQL entry and all local regression tests: 4/4
  (`run-MTVHZl`, `focused-test-XgBPxq`).
- Node authored fixtures/normal registration: 39/39
  (`run-yeTZZP`, `focused-test-zvWwxw`).
- Changed-file MoonBit formatting and `git diff --check` passed.

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js src/query_program/positional_duplicate_columns_test.mbt src/query_program/data_positional_set_test.mbt src/query_program/set_corresponding_test.mbt src/query_program/pipe_set_target_scope_test.mbt src/query_program/positional_set_aggregate_test.mbt
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js src/query_program/positional_duplicate_columns_test.mbt
node scripts/local-checks.mjs test node --timeout-seconds 180 -- scripts/set-corresponding-source-input.test.mjs scripts/public-query-profiles.test.mjs
```

## Pending public acceptance and broader boundaries

### Current-main integration

Normal merge `f86f5b9d07999ce3401c4a2b606918f0f36454e4` adopts main
`c00439f4f1d4b942e16e4eece97990866c3ec02e`, including the separately
merged Graph-row set repair #1248 and updated core fixtures. The only
conflicts were the authored public inventory metadata and its count test.
Their resolved values were checked against actual authored registration:
3,323 occurrences, 2,103 normal, 1,173 refusal and 47 execution-failure
expectations; digest
`e005d979b379bc3131379c18e26a26496a7a44fbf0fa202e5341eb0b5f54784c`.
The final metadata preserves main's historical sourceBaseline
`ce027a937cf780f617d5ed98bb4d56ecbb010877`; the automatic cached resolution's
different baseline is not retained. No expected rows, types, scopes, limits,
Graph rejection behavior or CI workflows were changed in conflict resolution.
The initial counts above remain evidence of the earlier revision, not of
this integrated source. Post-integration focused JS positional/Graph-row
callers passed 24/24 (`run-zxzbJZ`, `focused-test-kRraU7`); Node authored
fixture/inventory checks passed 39/39 (`run-H453Yf`, `focused-test-VbAjBc`).
These commands used the merged product and final metadata; the follow-up
commit changes only this record and the baseline metadata correction.

Normal exact-SHA five-package production and the existing 40-case Embedded
Local/authenticated HTTPS consumer are the next check. Focused success alone
is not public execution evidence. Actual source revision, digests and receipts
will be recorded in the PR's acceptance status after execution; this paragraph
records the planned check when this source was committed. Full Core, Native/Wasm, complete packed
corpus and hosted CI have not been run locally. No manual CI rerun or merge.

This unit does not certify nonterminal duplicate projections, duplicate
GROUP/analytic alias tables or specialized JOIN/Graph entries. Their existing
refusals are not declared permanent language restrictions. #1243's actual
JOIN capacity reproduction and #1248's Graph-row set connection remain
independent. The wider frontend goal remains active.
