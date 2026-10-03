# Native Client: authored Property Graph source acceptance

## Fixed source and boundary

Verified clean source: `48690bf47a1be429838d5282f65b2a827df632b7`.
The underlying Frontend source is #235's
`fd44ca93cf1e3f108ec996620cca2b3c0d1fa593`, on #233's
`0d33eccd495329f89955e7514771c0f4c1c9451e`. Its unified common Graph
dependency remains C `51376bca11d57b775aa22d42453176f8ad1f681b`, #164.
No later C revision, old Graph fallback or separate frontend runtime is used.
This record does not establish formal dependency adoption or full migration.

The native binary is the existing Node-free **HTTP transport Client**, not an
embedded native Local Host. It submits the exact authored source and explicit
format to an installed HTTPS Host, whose ordinary preparation, common checker,
Run owner and Graph execution produce Named Results. The source is not converted
to JSON by the test before submission. Local/HTTP SDK acceptance is separate
[base evidence](2026-10-03-property-graph-public-acceptance.md).

## Reproduction

Use the pinned repository toolchain and normal dependencies:

```sh
node scripts/test-packed-public-query.mjs --property-graph-native-only
```

The driver normally prepacked five packages, installed them outside the checkout,
and built only `src/cmd/native_client` for native. The installed consumer runs
without MoonBit on its PATH. The isolated corpus uses Values producers and the
standard Host environment; it does not require an external alias profile or
inject a test-only schema into the public request.

The ordinary full packed application also invokes this native acceptance, with
its historical JSON Program control kept distinct from source cases. The narrow
command avoids rerunning the whole SQL/Pipe application and snapshot corpus.

## Executed evidence

Invocation `public-query-evidence-ZGa0ZQ` records a clean verified SHA, **13
successful driver commands**, complete outputs and successful temporary-install
reclamation. `native-sga.log` retains the binary digest and all **140 native
Client command outcomes** (including **14 expected nonzero preparation refusals**).
The enclosing native acceptance command succeeds only after validating every
case; an expected rejected child is not recorded as a successful submission.

- **22 authored source successes:** 3 Relation DATA controls and 19 keyed Graph
  cases. Independent fixtures cover parallel edges and WALK/TRAIL/ACYCLIC
  multiplicity, composite keys, Graph-owned static labels, NULL-key and unmatched
  endpoint exclusions, empty Results, quoted property/label lookup, explicit
  projection/star, multiple node definitions and definition-scoped endpoint
  identities.
- Native `aql` submits source; `wait` must succeed; native `read` must return the
  independent Named Result rows after the normal complete-stream validation.
  Unordered Relations are compared as multisets, preserving duplicates.
- The installed SDK attaches to the same native-created Run only to obtain
  `Result.describe()`. Declared column order, complete type contracts and
  nullability must match authored expectations, including empty Results.
- Identical native resubmission and request lookup must retain the original Run
  reference. Reading, metadata access and resubmission leave the actual request
  journal count, dispatch observations and physical DuckDB stream count unchanged.
- **14 typed preparation refusals:** unsupported consumers, retired constructor,
  hidden-slot exposure, missing names/properties, unsupported Graph exports,
  incompatible closed bindings, unsupported endpoint labels and invalid DATA
  binding/format cases. Each native failure must preserve a registered input-error
  code rather than `SubmissionUnknown`; lookup returns `not_found`. The same
  actual counters remain unchanged, proving no Run admission, dispatch or observed
  provider execution on refusal.
- Syntax checks for both touched scripts, `git diff --check`, and existing packed
  evidence/dependency guards **22/22** passed. No local whole Core, Salesforce or
  broader native protocol suite was repeated for this test-only change.

An earlier dirty setup attempt was interrupted after source inspection identified
an invalid test-side package export lookup. It is not successful acceptance
evidence. The fixed clean run above uses the package's public entry for dependency
resolution and passes. No installed shared dependency was changed.

## Artifact correspondence

Native binary SHA-256:
`04a3053c2a05aaa8f6c1d6fea4b1a0183fbe6704cb42a09817b76d5d04ed343b`.
This is the locally built platform artifact, not a Linux binary digest.

| Normally packed package | SHA-256 |
|---|---|
| actql-client-wire-0.0.0-development.tgz | `5da98d3edb615f960f0511be9d6e61431cd34d02304a8bd6b6e576f7775f91a0` |
| actql-sdk-0.0.0-development.tgz | `2fc910067348e421346945ced1e728e107bbe6fa455ee00f9d71da46e8123c5b` |
| actql-run-host-core-0.0.0-development.tgz | `89b73b4d874d2972586eccc4ebde2b6af810c3c1b548dfeef11dc4ccc8a5bf30` |
| actql-local-node-0.0.0-development.tgz | `dfc8bbed3569d07a1d7211738e69ad3b82943420030c6f762e817b3f9ad0911b` |
| actql-node-0.0.0-development.tgz | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |

These match the underlying #235 acceptance packages. Only acceptance scripts and
documentation changed; no public API, wire, grammar, canonical preimage, common
Graph/INFER owner or generated runtime payload is revised here.

## Remaining migration obligations

Required final-SHA CI and review remain separate. This verifies the selected
authored Graph source through native HTTPS; it does not assert a native Local
provider backend, a separate source-constructor exact snapshot CID oracle, all
SGA consumers, external installed Graph aliases or source-INFER execution.
Unsupported forms remain explicit refusals and implementation gaps, not permanent
language restrictions. The [full migration obligations](../design/frontend-language-migration.md)
remain open. No main merge or package publication was performed.
