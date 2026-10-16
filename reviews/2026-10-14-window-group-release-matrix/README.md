# Original window-group acceptance through the normal release

This prepares the existing F05 named `window_group` public completion unit for
the normal four release packages. The original nine normal cases and nine
refusals in `scripts/fixtures/window-group-source-input.mjs` retain their inventory,
rows and ordered schemas. The JSON capture wrapper now explicitly uses the
adopted scan/filter/select acquisition shape; its former select-only Programs
and failed installed cohort are retained separately. SQL and AQL-text are byte
unchanged. Window/aggregate expressions, DISTINCT, bounds and projections are
unchanged in all formats. The default
release IN/UNNEST entry and submitted Sequence entry are not edited.

## Installed input and existing Owners

The test-only installation uses the existing public RowSource declaration,
authorization, credential site, charged-page capture and connector-table APIs.
Its connector id remains the original `crm/main`, with resource `r` and query
alias `records`. The independent closed Number schema is `id` non-null and
`amount` nullable. Connector registration uses the existing identifier grammar
(`window_fixture`) rather than confusing the slash-containing connector id
with a registration name.

The supplier sends all four original rows, including the NULL amount and both
occurrences of id 3. It does not filter, aggregate, deduplicate, supply a score
or assert a candidate key. The empty variants supply an empty original extent
through the same authorized, charged page. The fixture's existing per-case
input change occurs before submission; replay/attach/lookup do not call it.
All evaluation and result-order decisions stay with the installed product.

The existing public query reader compares actual rows and full ordered schema
before recording them. Its existing receipt collector retains actual normal
and refusal observations, including replay counters. The independent audit
requires the full eighteen-entry inventory, twelve actual output rows per
transport, one acquisition per normal execution, no repeated acquisition on
replay, no admission/I/O for static refusals, and credential-site cleanup.

## Bounded preparation and public qualification

```sh
node reviews/2026-10-14-window-group-release-matrix/prepared-checks.mjs <source-sha>
```

The Node-only guard is non-Heavy, sixty seconds/TERM grace five seconds, with
a thirty-second focused child. Supplier and audit tests are component tests;
syntax checks do not restore a real declaration or execute the installed Host.

After allocation of each original shared public window:

```sh
node reviews/2026-10-14-window-group-release-matrix/prepared-release-public.mjs --producer <source-sha> <new-absolute-RC>
node reviews/2026-10-14-window-group-release-matrix/prepared-release-public.mjs --consumer <source-sha> <same-RC> <new-absolute-receipt.json>
```

Producer and consumer each retain three hundred seconds/TERM grace five
seconds. The consumer installs only the normal four unmodified archives and
copies eight test-only modules outside `node_modules`. Same clean source,
manifest/digests, retained failure/custody and ordinary prepack are required.
No checkout runtime, private captured input or post-lowering correction is used.

At installed source `ef5606fe2a598fbb43e89ca53354088bd4c505fc`, the first
JSON control was refused before Source I/O: its select-only capture is outside
the adopted exclusive scan/filter/select profile. The original failure is
preserved. A pure installed differential confirms `UnsupportedShape` for that
Program and successful requirement preparation with an explicit literal-true
filter. This does not execute window grouping. Corrected-control installed
Local/HTTPS nine-normal plus nine-refusal completion remains unverified.
No Moon/compiler, package producer or public consumer is run by the Node recipe.
The existing Vector publication failure and optional Calendar runtime gap are
separate unresolved boundaries, not claimed repaired by this preparation.
