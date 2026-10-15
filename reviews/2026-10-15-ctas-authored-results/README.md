# Authored Results at a terminal Table write

The normal e19343c2 CTAS consumer passed its four original Effect-only cases and
failed the six retained-Result controls. SQL/AQL reached fresh-process recovery,
but exposed an additional `answer` beside the independent `before_write` Result.
The JSON controls failed earlier with `effect_start_failed/MoonBitHostFailure`;
that separate failure is not resolved by this frontend change. Preserve the
original failed Runs, DB/WAL, package cohort and receipts.

The integration owner's October 15 CTAS decision resolves the conflict between
the general nonterminal RESULT primary-tail rule and Table's private input rule.
A terminal CREATE/REPLACE exports only authored public Results. Its final
Relation feeds the existing private Table input. Save-only remains `results:{}`;
ordinary SQL and UPDATE keep their existing primary tails. Program identity
follows the changed normalized body; old identities are not reassigned.

The existing retained-Result helpers receive an explicit internal primary-export
choice only at the terminal Table caller. Earlier Results keep their exact
producer and projection, while the filtered final producer remains private.
No new execution, capture, Result or authorization owner is introduced.

The independent public expectation `[before_write]`, original input values,
predicate, schema, empty physical write and all ten CTAS controls are unchanged.
Focused tests cover CREATE/REPLACE before a filter, a terminal authored Result,
save-only controls, ordinary SQL primary-tail behavior and the existing UPDATE
counterexample. They are compiler evidence, not a new installed acceptance.

Use `prepared-checks.mjs <full-source> prepare` for a separate bounded cold JS
test build (300/TERM5, j1, existing pool admission). Then use the same recipe with
`test` for focused nonzero execution (60/TERM5, child30, j1). Build preparation
and actual test counts remain separate. Neither phase starts Host, Source,
Table, Provider, pack, Native, Wasm or full Core. The longer cold compilation
budget changes no runtime/product capacity, work or permission limit.
