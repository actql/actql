# Named Graph match source connection

Date: 2026-10-05. Owner: B. Target: main. No unmerged code dependency.

Current integrated packed source:
`907e3af85cc77cea930404ed416f55e692bc40fa`; adopted main:
`4a63d0e699674df519c9d35a990080026000e560`. See the final integration section.
The earlier SHA/digest/check records below remain historical evidence.

Baseline: `9632c1d73327248ae1b6cbc4b9e76f281b587950`.
Packed source: `ee135a4f7fe809458e95c6f319e3c9ff6ae547d6` (clean).
This record is a later documentation-only change; its HEAD is not the packed
source SHA. No merge or manual CI rerun was performed.

## Problem and completion unit

The adopted named SGA surface already parses `match_nodes` and `match_edges`,
and the common checker accepts an independently authored Graph match Program.
The script lowerer nevertheless rejected either call at the Graph-to-Relation
boundary. The source regression failed before changing product code, while
the independent JSON checker control passed.

```aql
DATA n = SELECT 1 AS node_key, 7 AS p;
DATA g = PROPERTY GRAPH (
  NODE TABLES (n AS N KEY (node_key) LABEL Person PROPERTIES (p))
);
FROM g
  |> match_nodes(definition: 'N', label: 'Person',
                 where: {gt: [{field: 'p'}, {literal: 5}]}, fields: ['p'])
  |> SELECT p
  |> RESULT selected
```

The new module emits the existing operation body, producer reference and
authored field order. It reuses the typed named-argument builder and preserves
the call's source range. The common checker owns definition/label selection,
identity bindings, property presence, predicate typing and output contracts.
There is no additional predicate parser, Graph executor, acquisition path,
property-to-label adaptation or legacy Graph fallback.

The resulting Relation can bind DATA and use ordinary WHERE, SELECT and ORDER.
The operation is an ActQL SGA extension, not a claim of ISO GQL syntax.
This unit does not complete every Graph operation or the full query profile.

## Independent expectations and public acceptance

[The fixture](../../scripts/fixtures/graph-match-source-input.mjs) contains
authored complete JSON controls and literal rows/ordered column contracts.
Neither comes from compiler output or sampled Result rows.

The dedicated packed campaign passed **10 positive cases and 14 preparation
refusals on each of Embedded Local and HTTPS**. It checked:

- Node predicates whose omission changes the selected rows, nullable properties,
  typed empty output, typed parameters and case-insensitive definition/label lookup.
- Quoted DATA names and a normal Relation suffix after Graph match.
- Distinct parallel edge keys, edge predicate filtering and explicitly empty
  `types` selection; empty types were not replaced by an omitted/default selector.
- Named Result values and `Result.describe()` declaration-order contracts,
  including nullability, with no additional internal output columns.
- Reattach, Result reread and identical request resend returning the same Run
  without another accepted Run or external source read.
- Unknown definitions/labels/properties, invalid predicates/options, duplicate
  selected fields, identity/property collisions and Carrier mismatch refused
  with typed preparation errors before Run admission and provider I/O.

The cases also join the normal packed corpus; the dedicated flag only narrows
local execution. It does not replace ordinary CI coverage.

Receipt: `public-query-evidence-W7aGWm/summary.json`, status passed and complete.
Command `012` is the outside-checkout Local/HTTPS acceptance and exited 0.
The shared bounded guard receipt is `run-i9o98r`.
Normal `npm pack` ran producer prepack, followed by a private installation and
runtime without MoonBit or checkout imports. No installed adapter was overlaid.

| Package | SHA-256 of tarball |
|---|---|
| client-wire | `52fe3218df346cfb9dae0adc248071563fe68918bded16f8d733415e65584fc0` |
| sdk | `f81bf27c3bb42a007bc16b6f89a15542a89c7fb844e2893870d1161a8e8abc6d` |
| run-host-core | `53dc34d59bfe997113ff370b08169b1896daada5ce51bf9f7374bf698c6e4191` |
| local-node | `d32c1c5b2100a517fd4427e240b572e58ba4481f5ae41764cd1174006d186f8b` |
| node | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |

## Checks and identity impact

Executed with the pinned MoonBit toolchain and existing bounded wrappers:

```sh
node scripts/local-checks.mjs test moon -- --target js src/query_program/graph_match_rows_test.mbt src/query_program/graph_rows_test.mbt src/query_program/traversal_nodes_test.mbt src/run_publication_host/client_values_run_materials_wbtest.mbt
node scripts/local-checks.mjs test node -- scripts/compilation-manifests.test.mjs scripts/client-values-run-materials-vector.test.mjs scripts/public-query-cases.test.mjs
node scripts/compilation-manifests.mjs
node scripts/check-canonical-json.mjs
node scripts/check-actql-spec-family.mjs
node scripts/test-packed-public-query.mjs --graph-match-only --keep-artifacts
```

The focused precommit tree later committed as `cdda69cc9123e77adc70982e5b5347c880ed1a11`
passed MoonBit **13/13** (`run-NrCBHN`) and Node **9/9** (`run-YtkBYB`).
Canonical validation passed 368 vectors; specification validation passed
10 documents, 1,329 requirements, 23 document imports and 255 machine imports.
Formatting, JavaScript syntax and `git diff --check` passed. The packed command
was run through the shared heavy guard with a 1,200-second budget.

The query-text body update changes Grammar Manifest CID from
`sha256:8ac5a6bdc47a98eca02efae3ca1ceadc613bc930bb523c0013fc73a9bb81dcdc` to
`sha256:f2bfb4752851d8bf2d92ccb6a239800ffa662d49a60903f6bc9aee7247f8bfad`.
Dependent generated pins and normative document references are updated from
their bodies. Contract versions remain 0.1. The independent Values Run vector
uses the new manifest preimage and yields
`sha256:d5bd82839e01d0e9866db382b248ce9ed02d24a83dc17f1165403bac604fa5c2`.
The historical vector under the previous grammar remains explicitly retained;
stored identities are not retagged as new data.

## Prior failures and unverified coverage

`public-query-evidence-EuRUka` at `cdda69cc...` failed on the first JSON control:
the authored endpoint mapping used incorrect member names. The normative
`source`/`target`, `key`/`references_key` correction changed no expected rows.
At `0d8c0e89907521880fea783c5140f2d497ca138e`, receipt `public-query-evidence-cwPNxb`
passed all match cases on both paths, then the driver's incomplete dedicated
flag registration entered an unrelated String restart without a retained
String Run. The final packed receipt above closes both fixture/driver failures.
Neither prior overall campaign is reported as passed.

Not executed: full Core, Wasm/native, all packed cases, proofs or performance.
Focused identity-binding checker coverage is not broad backend/runtime identity
conformance. CI evidence for the submitted documentation HEAD is recorded in
the PR separately; local acceptance is not CI success.

## Main integration and repeated changed-boundary acceptance

Main's Graph equality/diagnostics, ORDER property, SDK row checks and common
execution changes were normally merged at
`907e3af85cc77cea930404ed416f55e692bc40fa`. The conflict resolution retains
both parents' Graph routing branches, source rules, packed registrations and
focused flags. Main's workflows and foundation declarations are preserved.
The remaining conflicts were generated pins and their independent expected
identities; these were rebuilt from the integrated bodies, not product output.

The integrated focused tree passed **26/26** MoonBit JS (`run-KNszEa`,
`focused-test-iY9RRw`): new matches, Graph rows, traverse, equality, diagnostics
and the fixed Values identity. Node **9/9** passed (`run-OVOyhr`,
`focused-test-99VBK3`). All three read-only manifest/canonical/spec-family
validators passed again with the counts above. This was not a full Core run.

The same unchanged **10 positive / 14 preparation refusal** corpus then passed
on **each** of packed Embedded Local and HTTPS at the clean merge SHA.
Receipt `public-query-evidence-MoC39z` is passed and complete; guard `run-FdleFs`.
No installed overlay was used. The later evidence-only commit is not relabeled
as the tested packed revision.

| Integrated package | SHA-256 of tarball |
|---|---|
| client-wire | `a8d1f2a63ed08d3378765fbee905fb72233d19e66e8ce77d6f1398ae45dbe8b7` |
| sdk | `a42baf2456b366d3a761f01cce27292ae1dcee13c8ce6113a3b70896bedd4e97` |
| run-host-core | `ba3edaccd2ad4107adf42cf3e271b1519855ae2dc89bc17006b3bba557d24bf8` |
| local-node | `e861d151b9ef1ecd7c2bcb88c65a50e42555a54eb132befa484b4c538b67aeb1` |
| node | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |

Main's Grammar CID `sha256:eb1e2c6f90ed75c3bd443ce1a5f91097c41e13e7a6cc08ccc04bdbdf57476c10`
becomes `sha256:2afc5d41a26a51589b3ad3b647c08dae6ebdb8f135834c227ab97bfd6197bf8a`
after retaining the new match rules. The full manifest body CID is
`sha256:61eaa081e6fbd246bf050f38eb1ba238fbd57d651601a669b46bf8273d592530`.
The integrated independent Run vector is
`sha256:975bce1f654d8967d1f28f3370e3a89cf27c40745749f99d5bebca82bc5d7e15`.
Both actual merge parents' grammar-bound vectors remain explicitly checked.
Versions remain 0.1; no stored identity or prior evidence is rewritten.
