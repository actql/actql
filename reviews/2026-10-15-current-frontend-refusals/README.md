# Current Frontend refusal fixture repair

G's immutable `7b93446cd66c6d91e1bf808ed89d8296cb3139da` Wasm campaign ran
14,216 tests: 14,214 passed and two failed. This unit fixes only the two active
test expectations, after separately reproducing their actual outcomes on JS.
It changes no parser, lowerer, checker, Owner, resource limit or product value.

1. `composition_controls_test.mbt` treated `SET (Name = y + 1)` as unsupported.
   The adopted pure-SET rule in `docs/spec/query-text.md` requires ordinary
   Relation evaluation before private Result capture. The same original text
   now checks the independent add operands `field:y` and `literal:1`, evaluation
   against the selected public Result, a single original Values producer,
   minimal ordered private fields, no private export, and field-only Effect
   delivery. Unknown Result, missing selector and duplicate target refusals
   retain their original inputs and require their specific existing causes.
   Unicode/CR/LF literal preservation remains checked.
2. `carrier_peer_scope_test.mbt` required `UnknownColumn` for the inner
   `candidate_rows AS (SELECT 1 AS unrelated)` counterexample. The actual
   ordinary expression owner rejects its missing role reference with
   `Expression(UnknownReference)`. This is the current scoped reference path,
   not an implementation-limit rescue. Reusing the outer peer would succeed
   and therefore fail the retained counterexample. All positive inner/outer
   peer and shared-source controls remain unchanged.

The original inputs and failure assertions were first retained with diagnostic
messages only: pure SET passed compilation, and the peer returned the exact
`UnknownReference` cause. Original G Wasm logs and these B failures remain in
workspace review evidence; none are promoted to latest-source success.
Additional test-authoring compile errors are retained separately.

The tracked recipe requires a clean complete SHA and explicit selection:

```sh
node reviews/2026-10-15-current-frontend-refusals/prepared-checks.mjs <SHA> files js
node reviews/2026-10-15-current-frontend-refusals/prepared-checks.mjs <SHA> files wasm
```

Only the two files are selected, with nonzero discovery, j1, child240 and the
existing nonHeavy outer270/TERM5 guard. This is a matching portable diagnostic,
not another full Core campaign, an installed product E2E, Native, Provider,
Hosted CI or formal publication. The original goal remains incomplete.
