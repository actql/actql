# Sequence temporal diagnostic regression

The ordinary installed Sequence cohort at source
`5551a7035490769a0ac0ef7788b95cf320cdb614` reached all 18 Local normal
cases and five refusals. It stopped at the unchanged zero-`within` source:
`ClientProgramRejected` differed from the independent
`ClientProgramInvalidInput` expectation. HTTPS and fresh-process rereading
were not executed. The original failed receipt, installation and Runs remain
outside this source tree; this regression neither retries nor reads them.

The language requires a positive sequence window. The existing
`relation_typing` owner rejects zero as `Temporal(InvalidMilliseconds)`.
The common diagnostic classifier currently discards that known input fact
under `Temporal(_) => UnclassifiedFailure`. Public bound-input checking then
cannot establish an independently invalid input for disclosure.

The narrow tests retain the original source and expectation. They distinguish
invalid milliseconds, invalid checker settings and exhausted checking work,
while retaining unclassified behavior for other temporal causes. The public
counterexample uses both SQL and AQL-text through the existing bound-input
checker. No runtime, language, author limit, disclosure rule, wire code or
identity contract is changed by the tests.

Run each focused selection on a clean fixed source with the pinned toolchain:

```sh
node reviews/2026-10-15-sequence-temporal-diagnostics/prepared-checks.mjs <sha> category
node reviews/2026-10-15-sequence-temporal-diagnostics/prepared-checks.mjs <sha> public
```

Each command preserves the existing nonzero wrapper and its focused
270-second guard, 240-second child, TERM grace 5 and JS job count 1.
These checks establish no installed-product E2E success.
