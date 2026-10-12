# Frontend Core repair: Graph source argument-role fixtures

Base main: `08ba746aa8e4d7fba819fbd6f3ed6051a3160647`.
G's original full-Core source `d62f4de55f98badeb37af933f6fdb0e5dbfeae22` and 92-failure record
remain unchanged. `failure-scope.json` tracks the 55 assigned frontend failures;
five are covered here, while 50 need separate current-main diagnosis.

## Adopted contract

The WITH revision LANGUAGE_CHANGES.md “Unified operation roles” requires
FieldRef identifiers/paths and OutputName identifiers. Literal IDs, definitions,
labels and literal subtrees remain data. The installed independent
`src/query_syntax/sga_role_contract_test.mbt` fixes the AST roles and explicitly
rejects retired reference strings.

Four positive source fixtures still passed Strings to `apply_graph_delta.field`,
`subgraph.nodes.id`, MATCH bindings or MATCH fields. Only those source spellings
now use backtick identifiers. All independently authored JSON Programs and
existing checker/schema assertions are unchanged, including predicates, NULLs,
keys and output column order. No product, grammar, contract, pin or limit changed.

## Exact evidence

- `82261898c0bea3c111a54839256ff148a7b2261d`: current-main parser caller failed 1/6 (`run-MdswDZ`);
  MATCH vocabulary failed 2/3 (`run-KlCc0v`). These failures remain failures.
  The first plan's subsequent unexecuted steps are not passes.
- `97e8eaaffbfc57fb42bdd403d7307f4380b774d6`: `run-qsnrdh` completed exit 0, JS 21/21 across
  the four changed files and existing SGA-role acceptance/refusal file
  (6 + 3 + 1 + 5 + 6). Independent complete node Program equality and ordinary
  common checking were executed. This does not establish Host execution.
- `cf1b518af6973e5b9cb32d3df3bc95bc3142b707`: `run-8sM886` completed exit 0 for read-only
  pinned `moon fmt --check` on the four changed MoonBit files.
- Guards retained timeout 60 seconds / grace 5 seconds, nonHeavy. Locks released;
  successful-test Owner 46506 was also directly observed absent after termination.

Use the pinned environment and `node reviews/2026-10-12-frontend-core-repair/prepared-checks.mjs`
with explicit test files. Add `--format` before filenames for read-only format.
Original logs and receipts are retained locally at
`/Users/t14i/workspace/20260822/reviews/2026-10-12-b-frontend-core-repair-evidence`;
`evidence-hashes.json` records verified-copy hashes without publishing log bytes.

## Unverified and remaining

No Local/HTTPS, package producer, Provider, Native/Wasm execution, Hosted CI,
full-Core or all-feature checks were run. The 21/21 belongs to the repair SHA
above, not the later documentation HEAD. #1608 is frozen; unpublished lag remains
separate. Root's FieldReference-copy repair is untouched. Remaining CTE/topology,
scope and refusal failures will be diagnosed and repaired in finite separate units.
