# DATA positional set operands: existing SELECT connection

## Counterexample and scope

Adopted main: `d4c8ed4987e8e25d4fc4f408b98705d90e7b7f53`.

```aql
DATA e = SELECT 10 AS id UNION ALL SELECT 11;
FROM e |> SELECT id
```

The independently expected multiset is `[{"id":10},{"id":11}]`, with one
nonnullable number column. The named right-operand control passes; the anonymous
right operand fails with `UnsupportedProjection` (`run-4Owoll`,
`focused-test-ImK20s`). Root positional-set lowering already passes the existing
`positional_set_output` flag, but DATA set lowering omits it.

Forward that flag from each positional right operand through
`lower_script_relation` and its ordinary term to `compile_steps`. Do not forward
it into unrelated CTE definitions or the first operand. BY NAME still needs
actual names. The shared terminal SELECT, ordinal alignment, append, duplicate,
expression, ORDER and Result owners retain their existing meaning. No new
syntax, grammar pin, acquisition or storage/physical boundary is introduced.
The product diff is six connection lines in two frontend modules.

## Independent obligations

- A complete authored expected Program fixes seed, literals 10/11, ordinal
  select/alignment, append and final public field `id`. The initial expected
  private-name suffix was one instead of zero (`run-5KMuq7`); source-free
  `query_columns` is empty and the existing allocator starts at its reserved
  array length, zero. Correcting this internal-name expectation changes no
  literal, predicate, operation, public field, type or order.
- Public duplicates/order/LIMIT: `[2,1+0,1]` sorted ascending and limited to two
  retains `[{"id":1},{"id":1}]`.
- Typed NULL source and independently authored JSON Values/sort control both
  produce `[{"id":null},{"id":2}]`; the public number column is nullable.
- A shared CTE over source-free value two feeds both operands; the right
  expression subtracts one, producing sorted `[1,2]`.
- BY NAME cannot use an anonymous private field. The actual private name
  `aql_set_anonymous_0` is unavailable after alignment into DATA's public `id`.
  The focused refusal asserts `Expression(UnknownReference)` specifically.

All public cases use the existing Relation DATA registration and scoped packed
runner, with actual Named Result rows, describe contracts, internal-field
absence, resend/reread and zero admission/Source I/O for refusals. Independent
JSON is a control input, not a patch of generated Program. Prior cases and
ceilings are retained. The inventory adds four normal and two refusal
registrations, reaching 3,294 authored occurrences.

## Executed checks and remaining work

- First connection check: 4/4 (`run-ZqZlMF`, `focused-test-tshGe0`).
- Final JS DATA/set/CTE/alignment callers: 14/14 (`run-VxGwCq`,
  `focused-test-ZewNr0`).
- Fixture/deduplication/inventory Node checks: 39/39 (`run-biwJTk`,
  `focused-test-Dau3Zk`).

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js src/query_program/data_positional_set_test.mbt src/query_program/data_set_test.mbt src/query_program/data_cte_test.mbt src/query_program/query_set_projection_wbtest.mbt
node scripts/local-checks.mjs test node --timeout-seconds 180 -- scripts/public-query-cases.test.mjs scripts/public-query-profiles.test.mjs
```

Normal fixed-SHA five-package production and `--relation-data-only` Local/HTTPS
execution remain required at this implementation record. Their receipts belong
to the actually tested source SHA and are recorded separately after completion.
No whole Core, Native/Wasm, full packed corpus or hosted CI success is claimed.
Anonymous JOIN output handling, aggregate outputs (separate #1237), nonterminal
anonymous scopes and public anonymous names remain separate unfinished coverage.
The wider frontend goal remains active; this unit has no unmerged dependency.
