# Positional JOIN set operands: shared SELECT connection

## Counterexample and existing meaning

Initial main: `ab69cd06a94b1c5a998521435e61c9f201a5c9a9`.
Initial implementation parent: #1240,
`ca6436aae9b14267052cdca2b3761358bdad0207`.

```aql
SELECT 0 AS n
UNION ALL
SELECT l.x + r.k FROM t AS l JOIN r ON l.x = r.k
ORDER BY n
```

For `t.x = [1,2]` and `r.k = [1,2]`, the independently expected ordered
result is `[{"n":0},{"n":2},{"n":4}]`, with a nonnullable number column.
The named right-operand control (`AS n`) passes the ordinary checker. The
anonymous operand fails with `UnsupportedJoin` before the patch
(`run-gBU6om`, `focused-test-hD4H1i`). This establishes a frontend connection
defect, not an execution-owner failure.

The adopted [GoogleSQL set-operator rules](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax.md#set_operators)
pair ordinary set operands positionally, retain the first operand's names, and
preserve UNION ALL multiplicity. No new public name or alias rule is introduced.

## Minimal repair and independent controls

Forward the existing positional-output flag through the script JOIN entry and
JOIN-chain tail into the shared SELECT compiler. Only a positional operand with
an anonymous terminal SELECT needs to leave the existing single-JOIN named
projection specialization. Named ordinary JOINs retain their specialized path.
The first operand, BY NAME, nonterminal anonymous projections and unrelated
CTE definitions receive no new permission.

The product changes twelve lines and removes one in
`query_script_program.mbt`, `query_join_bindings.mbt` and
`query_join_chain.mbt`. Existing JOIN, expression, ordinal alignment, append,
sort, checker and execution owners retain their contracts. No acquisition,
physical task, wire, grammar, limit or fallback implementation is added.

- An independently authored complete Values/JOIN/derive/append/sort Program
  fixes the same `0,2,4` result. It is checked directly; it is not generated from
  or appended to frontend output.
- CTE, DATA and two-JOIN lowering controls preserve every explicit test ceiling
  of seven and pass the ordinary checker.
- BY NAME asserts `UnsupportedJoin` specifically. Final references to `l.x`,
  `r.k` and the actual internal `aql_chain_column_2` assert `UnknownReference`.
- Public controls retain the original Source rows, one shared acquisition,
  key equality and JOIN ceiling ten. The anonymous right side selects
  `l.id + r.id, r.amount + 0` under `l.id >= 2`. The independent sorted rows are
  one `{id:1,amount:10}`, four `{id:4,amount:20}`, and one
  `{id:6,amount:null}`. Incorrect alias alignment, duplicate elimination,
  predicate loss or NULL substitution changes these results.
- Independent JSON, named text, anonymous text, CTE output and typed empty
  controls use the existing public registration and packed consumer. BY NAME
  and private-slot refusals retain their exact existing public classifications
  and zero Run admission/provider I/O requirements. Rows, describe contracts,
  declared column order, hidden-field absence, resend and reread are checked
  by the existing harness, without patching generated Programs.

## Focused verification before main integration

- JS JOIN/set/DATA/chain callers: 22/22 (`run-D9LkXb`,
  `focused-test-ebl4VC`).
- Node fixture/profile registration: 41/41 (`run-RONL7E`,
  `focused-test-Yy1JXB`).
- Final actual-private-slot refusal and independent Program selection: 4/4
  (`run-0ZMp5m`, `focused-test-u7eYAS`).

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js src/query_program/positional_join_set_test.mbt src/query_program/set_join_entry_test.mbt src/query_program/data_join_test.mbt src/query_program/join_chain_test.mbt
node scripts/local-checks.mjs test node --timeout-seconds 180 -- scripts/set-join-source-input.test.mjs scripts/set-corresponding-source-input.test.mjs scripts/public-query-profiles.test.mjs
```

The existing `--set-corresponding-only` consumer now contains 39 cases: 25
normal and 14 refusal cases. All are also registered in ordinary packed
acceptance. Normal clean-SHA five-package production and this scoped
Embedded Local/authenticated HTTPS consumer remain required; parser/checker
success above is not public execution evidence. Main integration, actual
package identities and public receipts are recorded separately below.
Full Core, Wasm/Native, the complete packed corpus and hosted CI have not been
run locally for this unit. The wider frontend goal remains active.
