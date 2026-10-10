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

## First packed attempt and refusal classification

Normal five-package production at `979b1b5abcf5b3c4b615870f66770834fcafb1bc`
passed manifest revision and all tarball digest checks. Both Local and HTTPS
completed all eight normal cases. The cohort then failed because the new
BY NAME refusal inherited the generic invalid-input expectation. The existing
`client_check.mbt` maps `UnsupportedProjection` to `Limit("implementation_limit")`;
that is an implementation gap, not invalid syntax. Its fixture now explicitly
expects `ClientProgramImplementationLimit`. The private-field refusal instead
has `Expression(UnknownReference)`, classified by that same existing checker as
invalid input, and explicitly expects `ClientProgramInvalidInput`.

The failed receipt is
`worktrees/.codex-scratch/public-query-evidence-tbno5C/summary.json`, with logs
`010.stdout.log` and `010.stderr.log`. The terminal cohort status is one; the
sibling was cancelled, inventories are incomplete, and later refusals are not
claimed as executed. Artifacts were reclaimed after retaining evidence. This
fixture-only correction preserves source, expected rows/types/order and zero
admission/I/O obligations; it does not change the product error classifier.

The corrected refusal fixtures and independent registration digest passed the
same two targeted Node files: 40/40 (`run-ZPSO0F`, `focused-test-D68xBX`).
The first sandboxed wrapper attempt could not inspect its own process group and
executed no selected tests; the subsequent bounded run above is the evidence.

## Corrected-SHA public acceptance

Normal five-package production and the scoped consumer at
`e4fcc52a3305571bb8ff0ad432a2dd64c43a7151` passed (`run-QiBspJ`).
Embedded Local and authenticated HTTPS each completed all 13/13 registered
cases: eight normal cases and five preparation refusals. Both inventories
matched `b5bca61c94ef8b0842087728ea5157b72a7abbf145d4530861e8457dced0c327`;
both workers exited zero and no live child remained. These are the existing
Named Result rows/describe/column-order, hidden-field, resend/reread and
zero-admission/Source-I/O assertions, with no Program patch or limit override.

Receipt: `worktrees/.codex-scratch/public-query-evidence-twThwM/summary.json`;
transport logs and completion inventories are retained in that directory.
The receipt confirms `artifactsRemoved: true` and no evidence errors.
Five-package source manifest: `/private/tmp/actql-b-data-positional-e4fcc52a3-pack/packed-client-packages.json`.
All five tarball digests were independently checked against that manifest:

| Package | SHA-256 |
|---|---|
| client-wire | ca7aaf03f3f1d78aff24c42a4ebe94ae2136ce29ba3fdf8ed81478e359e3df60 |
| sdk | 64eca760cdce9f0da1ea53542ede457ec9f5c80603d9b13721077d90c7b91c1e |
| run-host-core | 712228cbe4c27f071c978c7ad7a7d1ad8867ea6fe8d0d5aae9df0552b9ff9c15 |
| local-node | 6bb30e6459359dd8e8a45ddcd611d24179283dd83a922cb9d01f21b294a4f06f |
| node | a77756e97078c7df0ea0a318e5ccd74bd7aee2891caa148da2688f9c3eb2d9eb |

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-data-positional-e4fcc52a3-pack
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-data-positional-e4fcc52a3-pack node scripts/test-packed-public-query.mjs --relation-data-only
```

The bounded wrapper uses the pinned Node/MoonBit environment, a 1,200-second
aggregate deadline and an exclusive heavy gate. It waited for the verified
other-owner gate to release before starting; it did not remove that lock.
This final evidence-recording commit changes this document only. The public
execution proof remains attributed to `e4fcc52a...`, not silently relabeled
as the later submitted HEAD. Full Core/Native/Wasm, the full packed corpus and
hosted CI remain unexecuted for this unit.
