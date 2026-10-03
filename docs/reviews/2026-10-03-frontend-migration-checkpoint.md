# Frontend migration: independent source checkpoint

This ledger describes B's independent implementation at
`5221799a271e2cb838d1806ea4db9d38b7d43135`, based on main
`0fd6332757176b88e8c4071e4a2cd0be3d6254e3`. It separates source work from
public execution evidence. It does not declare the new Frontend migration
complete or adopt C's unfinished implementation.

## Implemented versus execution evidence

| Surface or boundary | Implemented checkpoint | Acceptance still required |
|---|---|---|
| Retired AQL/PROGRAM/STAGE and STEP/OP public entry | Typed refusal; no compatibility parser or formatter | Preserve existing SQL/Pipe and machine-input regressions when integrating the unified owner |
| JSON/YAML Program | Existing machine admission remains available | Machine execution is not evidence that replacement text executes |
| Relation DATA and explicit RESULT | Shared script parsing and lowering; public preparation retains named roots | Three authored source examples and the independent JSON control passed fresh packed Local/HTTP at `979b59605ab4ff2d52ca3e772cfd93827b1816fe`, as detailed below; this does not cover Graph DATA |
| Pure PROPERTY GRAPH | Bounded parsing and independently authored Program construction | Common unified constructor/checker, public execution, descriptions and snapshot roundtrip |
| Named SGA calls | Nineteen adopted names and argument roles parsed by the shared query parser; DATA aliases and normalize-before-MATCH lower to retained producers | Adapted common Carrier/schema contracts for remaining calls; all promised examples through Named Results |
| Public Graph source | Typed `QueryLowering(UnsupportedGraph)` before a Program is returned | Replace the dependency refusal after the formal unified owner is adopted; verify actual Run/admission and provider counters |
| Source INFER KEEP/AS | Frontend lowering and independent fixture work remain separate from common execution | Formal owner fix and smallest source-input Local/HTTP execution first, followed by NULL, keys and replay |
| Other target Effect, VecA and TEA surfaces | Adopted targets and machine capability are distinct from public syntax support | Feature-specific source, checker and real execution evidence; no bulk completion claim |

The public Graph refusal includes installed Graph aliases and pure constructors.
No retired property-label route, simple-Graph conversion or old consumer fallback
is enabled. Syntax-only normalization must not be reported as common Graph
checker or kernel acceptance.

## Evidence and handoff boundaries

The [unified-source separation record](2026-10-03-property-graph-unified-source.md)
lists the constructor, checker, Graph identity, MATCH/TRAIL and public snapshot
interfaces required from C. Its retained authored fixtures specify independent
schema, rows, parallel edges, composite keys, static labels and NULL exclusions.
The [named-call checkpoint](2026-10-02-sga-query-calls.md) records B's parser,
lowering and canonical identity tests; its provisional-dependency results are
explicitly historical.

`src/source_frontend/unified_dependency_test.mbt` verifies the current typed
refusal and Relation DATA/RESULT preparation. It does not observe Host counters,
deliver a Result or roundtrip a snapshot. Neither these tests nor a green CI run
can substitute for the missing Graph or source-INFER execution evidence.

C's public `125a186ae9396fbfc7865641922e8e8a4ffc87d9` is not adopted as a
unified owner. Integration requires a pushed complete SHA and the corresponding
unified/snapshot validation. No unpushed checkpoint is a release dependency.
When that handoff arrives, use fresh normally packed Local/HTTP installations,
record both owners' SHAs and package digests, and compare authored expectations
through Named Results. Keep old successful runs classified by their old inputs
and dependency SHAs.

The [architecture and migration obligations](../design/frontend-language-migration.md)
remain broader than this implementation checkpoint. Existing JSON/YAML inputs
are retained capabilities, not completed replacements for withdrawn text paths.

## Packed Relation DATA execution

Verified SHA: `979b59605ab4ff2d52ca3e772cfd93827b1816fe`. Its product sources
are unchanged from the checkpoint above; it adds the independent acceptance
fixtures and a narrow selection in the existing packed harness.

```sh
node scripts/test-packed-public-query.mjs --relation-data-only
```

The normal `npm pack`/prepack process built five packages from this clean SHA.
The installation was outside the checkout; the runtime had no MoonBit toolchain.
The ordinary installed Embedded Local and authenticated HTTPS Hosts both passed:

- Ordered DATA set input, hidden sort-slot reuse and LIMIT: `nodes = [{"id":1}]`.
- Quoted DATA reference and set ordering: `nodes = [{"id":1},{"id":2}]`.
- Explicit retained Results: `original` and `active` both contain `[{"id":2}]`.
- Independently authored two-root JSON Program with append, derive, sort,
  projection and LIMIT: `nodes = [{"id":1}]`.

Each transport passed **4/4** successful inputs and **3/3** preparation refusals
(forward DATA reference, duplicate DATA name and DATA supplied as SQL format).
For each success the harness compared exact Named Result rows and the complete
`Result.describe().columns`, including order and nullability. Hidden sort columns
were absent. Physical source-table reads were zero; attach, reread and identical
request resubmission did not increase admission or I/O counters. Each refusal
left those counters unchanged and request lookup returned `not_found`.

The independent JSON control also executes the formerly failing strategy shape.
It therefore supplies actual execution evidence beyond the earlier seven-task
preparation check; it is not a replacement for source acceptance. No strategy,
Graph carrier, provider, Host or common checker implementation was added by
this test commit. README Local/HTTPS quickstart and the packaged missing-wire
asset refusal also passed as the harness's existing controls.

| Normally packed artifact | SHA-256 |
|---|---|
| actql-client-wire-0.0.0-development.tgz | `5da98d3edb615f960f0511be9d6e61431cd34d02304a8bd6b6e576f7775f91a0` |
| actql-sdk-0.0.0-development.tgz | `9fd8d7c7019eafcd1401fa1804108644f13875b2197bb3d3e012abbb5428143e` |
| actql-run-host-core-0.0.0-development.tgz | `7360f0c9d09b8748cd0518df95045f509f14c62bd9da2cd9b2fb67f6d9ef7ad0` |
| actql-local-node-0.0.0-development.tgz | `6c204bb1c1ecb677fb350f9a491f7dd3f05be6e8829701cb2748009a3ce48798` |
| actql-node-0.0.0-development.tgz | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |

The harness retained command results/logs and these digests, then removed its
own successful temporary installation. This is local fixed-SHA acceptance;
it is not a same-SHA Linux CI result, Graph/snapshot acceptance or source-INFER
execution evidence.
