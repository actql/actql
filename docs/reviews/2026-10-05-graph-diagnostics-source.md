# Graph diagnostic source acceptance

## Fixed source and scope

Initial main: `bf2865b0ad20f988ac00ce05d512faa94ce49ea1`. The feature commit is
`7233e6b9be13c7af2e3a4f9393e5dd8ef9e0e6da`. A normal merge adopts main
`1c370a0aa1e619391895026c3c30029e0f5351ab`, including #403, without conflicts.
The clean integrated source and fresh package acceptance is
`6fa8b2231dbcb17e7ebdb7a5cc6bff9a3b80b7bb`. The subsequent commit adds only
this evidence document; it is not a second pack or test of a new product tree.

This completion unit connects existing `degree`, `graph_bounds` and `components`
calls on constructor-bound Property Graphs to ordinary Relation operations.
These ActQL named calls already parse, and independently authored machine
Programs already pass the normal checker. The source previously failed in
Graph-to-Relation lowering. It now emits the same logical operations and exact
authored bodies. It adds no kernel, strategy, authorization, owner, storage
format, legacy Graph fallback or physical placement requirement. Other Graph
consumers and all backend conformance remain separate.

## Counterexample and implementation

`FROM g |> degree(direction: "both") |> SELECT degree, node` is the smallest
source failure. Complete independent expected Programs also cover zero bounds
and strong components with an explicit output guard. Baseline evidence
`run-C4ma7t` passes the independent JSON control and fails the source test (1/2).

`graph_diagnostics_program.mbt` emits existing bodies, including `$param`, using
the shared typed SGA argument builder. It retains the authored call source span.
The only routing change is in `graph_rows_program.mbt`: recognize the three
Graph-to-Relation operations and expose their existing field names. Types,
identity, component choice, order, body/range validation, selected capacity
and guard enforcement remain with the normal checker/common owner. DATA
reuses the producer; old Graph columns and subsequent Graph calls are refused.

## Executed evidence

Focused checks ran in the pre-commit working tree subsequently captured by
`7233e6b9be13c7af2e3a4f9393e5dd8ef9e0e6da`. They are working-tree evidence,
not tests launched with that clean HEAD. The clean packed runs below separately
verify the committed and integrated product:

```sh
node scripts/local-checks.mjs test moon -- --target js src/query_program/graph_diagnostics_test.mbt src/query_program/graph_rows_test.mbt src/query_program/traversal_nodes_test.mbt src/run_publication_host/client_values_run_materials_wbtest.mbt
node scripts/local-checks.mjs test node -- scripts/compilation-manifests.test.mjs scripts/client-values-run-materials-vector.test.mjs scripts/public-query-cases.test.mjs
```

- JS 14/14 (`run-hYGvpD`); targeted Node 9/9 (`run-PSQRGV`).
- Manifest freshness, 368 canonical vectors, specification family (10 owners,
  255 machine imports, 23 document imports), changed Moon formatting, script
  syntax and whitespace checks pass.
- No full Core, Wasm/native, proof campaign or performance run.

Clean integrated source `6fa8b2231dbcb17e7ebdb7a5cc6bff9a3b80b7bb`:

```sh
node scripts/test-packed-public-query.mjs --graph-diagnostics-only --keep-artifacts
```

The existing shared heavy guard (`run-AuZVTp`) is complete/passed, exit 0, with
complete output and released locks. Receipt `public-query-evidence-blPF4D`
records clean source, all 12 child commands successful, complete stdout/stderr
and no evidence errors. Five packages use normal prepack; the application
installs outside the checkout and has no compiler on its runtime PATH. No
generated Program correction or runtime overlay is used.

| Boundary | Embedded Local | Authenticated HTTP |
| --- | --- | --- |
| Independent JSON controls and authored source positives | 13 passed | 13 passed |
| Preparation refusals, no Run admission/provider I/O | 14 passed | 14 passed |
| Component output author guard exceeded, failed Run/no Result | 1 passed | 1 passed |

All positives compare independent rows and `Result.describe()` column order,
full contracts and nullability, including an empty typed Graph/result. Re-read,
attach, resend and request lookup retain the same Run without extra admission
or acquisition. The full ordinary packed corpus also includes these cases; the
focused flag selects existing acceptance rather than a separate product path.

Two node definitions over the same key yield two distinct identities. The
fixture has `N -> M` and an `N -> N` self-loop: total degrees are M=1/N=3,
in-degrees M=1/N=1 and out-degrees M=0/N=2. Weak components have size 2 and
canonical root M; strong components have size 1. Bounds preserve node/edge
violations with explicit NULL `node_id`, the N degree violation, exact satisfied
limits and a bound parameter of zero. JSON and SELECT producers intentionally
have different independently derived definition domains. Named identities
are compared against their complete authored canonical definition preimages.

The first pre-integration clean acceptance (`public-query-evidence-OtvuQD`,
`run-2gcFev`) passes the same matrix at `7233e6b9be13c7af2e3a4f9393e5dd8ef9e0e6da`.
That historical package set is separate from the integrated acceptance.

### Integrated tarball SHA-256

- `actql-client-wire-0.0.0-development.tgz`: `52fe3218df346cfb9dae0adc248071563fe68918bded16f8d733415e65584fc0`
- `actql-sdk-0.0.0-development.tgz`: `f81bf27c3bb42a007bc16b6f89a15542a89c7fb844e2893870d1161a8e8abc6d`
- `actql-run-host-core-0.0.0-development.tgz`: `775c04423d162705440fd6fa43953efd636e96da9c8fdfed4d7a04dcbbde3bca`
- `actql-local-node-0.0.0-development.tgz`: `52d409417c4e65cbf85fcd275d411b978b4dad79e2408beee21c367d48d40f52`
- `actql-node-0.0.0-development.tgz`: `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64`

## Identity impact and pending coverage

Query EBNF and operation/Graph schemas are unchanged. Updating the query rules
changes Grammar Manifest CID from
`sha256:8ac5a6bdc47a98eca02efae3ca1ceadc613bc930bb523c0013fc73a9bb81dcdc` to
`sha256:5ece7453ce5f14cae14389ce1f999bff6fbc1a65cb0f1a3d719c438818795cb9`.
Generated pins, canonical vectors, normative imports and the independent Values
Run vector follow the exact bodies. The independently calculated new fixture
Run CID is `sha256:d93f8e21b7eae3d9efc48616b4a641f0c063bd9ccad0f5fd71cfa095a3bcd687`.
The prior grammar/Run vector remains immutable. Contract versions remain 0.1;
old stored identities are not retagged as new.

Submitted-HEAD automatic CI is recorded in the PR body. Local results are
not CI success. This unit does not close all Graph/Frontend coverage or the
separate common equality ORDER/evidence gap in #414.
