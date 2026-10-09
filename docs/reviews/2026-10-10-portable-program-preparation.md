# Portable parser-selected Program preparation

## Boundary

Ordinary Cloud submission needs to choose the existing Pure or Effect semantic
Owner before checking a Program. Checking as Pure and retrying as Effect would
interpret the same original submission through two semantic paths. Cloud must
also not parse Program stages or effect declarations independently.

`prepareProgram(document, format, environment, parametersJson?)` parses once
through the existing common parser, selects the Owner from its typed stages and
Effect names, then invokes the appropriate existing parsed preparation entry.
It returns a frozen discriminated union containing the existing branded Pure
or Effect handle. Neither branch adds acquisition, authorization, approval or
execution. Existing explicit `prepare` and `prepareEffect` APIs remain available.
Pure request identity and Effect compilation wires are preserved.

## Exact-source evidence

The tested implementation is
`220ffd3f333501b467b9acfaafad1ba264483ad7`, based on merged main
`040eed2b1a11a3d1f7bae81b68d956d1017fac05`. The later commit adds only this
report. Tests are registered with the ordinary run-host test and typecheck
entry points.

Focused source checks passed: Moon formatting, generated public interface,
scoped JS/runtime package build, 13/13 Node tests, both portable Effect and
Program-selection typechecks, and `git diff --check`.

Normal `npm pack` generated clean-source tarballs; a private offline consumer
installed those actual packages and executed 13/13 tests without skips. Strict
NodeNext typechecks passed. `node proofs/relation-pipeline/history.mjs --write`
passed without changing declarations or the validator.

| Package | SHA256 |
| --- | --- |
| client-wire | `ca7aaf03f3f1d78aff24c42a4ebe94ae2136ce29ba3fdf8ed81478e359e3df60` |
| run-host-core | `fbb918debb813254644a700fd29865678fd41f9959d89fabc72124e4854478ad` |

Local receipts and original output are retained in
`_build/portable-run-preparation-selected-1791566417791` and
`_build/portable-program-owner-packed-1791566526840`.
The packed gate records normal prepack, source SHA, artifact digests, actual
installation, test counts and bounded child-group completion.

## Counterexamples

- A row field named `effects` remains ordinary Pure data; it cannot select the Effect Owner.
- Invalid syntax, missing mapping, oversized/invalid parameters and foreign environment handles are rejected without fallback.
- Pure selection preserves the supplied parameters and original request identity.
- Effect selection preserves the checked two-task/one-acquisition/one-Effect shape and exact existing compilation wires.
- Passing either selected branded handle to the opposite compiler is rejected at runtime and by the type declarations.

## Remaining integration

No Cloud adoption, physical Provider I/O, Run waiting transition, approval,
restart, Effect apply or release is completed by these static API tests.
Formal Cloud adoption requires a merged main source and regenerated cohort.
Hosted CI remains disabled under the existing instruction; it was not started
or rerun. There is no new scheduler, ledger, semantic fallback or manual binding.
