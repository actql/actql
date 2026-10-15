# F07: normal-release input for the original composition consumer

The existing composition harness submitted the independently authored JSON and
WITH text, but could only choose development archives. This unit admits an
explicit normal four-package RC into that same harness. It changes no parser,
lowering, Model, Source, Effect, authorization, expected row, schema or limit.

`--release-dir /absolute/fixed-normal-RC --composed-infer --keep-artifacts`
keeps the original JSON/text selection, two installed Sources, deterministic
Model, publication/approval, same-Run restart, duplicate/NULL refusals and
cleanup assertions. Normal release admission uses the existing verifier and
checks clean matching source before Site/Run creation. Invalid release input
does not fall back to development packing. All four normal archives are
installed by npm outside the checkout and their export/dependency closure is
audited. The manifest, archives and source are checked again after acceptance.

The tests build small synthetic normal packages with an independent exported
value, install all four outside their committed source, and exercise dirty or
foreign source, changed archives and post-admission manifest mutation. These
are package-admission tests, not ActQL Model/Effect execution or a product E2E.
The same tests are registered in the existing `client-ci.test.mjs` owner.

Run the tracked preparation from this worktree with pinned Node:

```sh
node reviews/2026-10-15-frontend-composition-normal-release/prepared-checks.mjs <full-source-sha> deps
node reviews/2026-10-15-frontend-composition-normal-release/prepared-checks.mjs <full-source-sha> node
```

Each uses the existing non-Heavy 60-second / TERM5 guard. The focused Node
selection retains its 30-second child and nonzero-discovery check. No compiler,
prepack, Host, Provider or existing Run/DB operation is part of preparation.

Physical composition acceptance remains unexecuted by this unit. It needs a
normal RC from the exact source adopted with these harness changes, bounded
consumer execution, independent original rows/schema and actual acquisition,
Model/write, restart, Result and release receipts. Existing RCs, failure records
and unresolved custody are preserved; no source qualification is transferred
to a later main or another release manifest.
