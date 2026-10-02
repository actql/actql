# Definition-keyed Property Graph: initial vertical

## Frontend handoff

The common machine constructor is `property_graph`, selected explicitly with
`version: "actql-property-graph-constructor/0.1"`. Its output is the separately
admitted `actql-property-graph-contract/0.1` Graph, not a legacy simple Graph.
The complete runnable input is
[`property-graph-parallel.program.json`](../../scripts/fixtures/property-graph-parallel.program.json).
It constructs two independently keyed parallel self-loop edges, performs a
definition-scoped MATCH and exposes the keys through a public Named Result.

The constructor contains ordered `nodes` and `edges` definitions. Each has a
definition `name`, resolved producer `from`, and nonempty ordered `key` column
list. Edge `source`/`target` identify a node definition and ordered endpoint
columns. Static label entries select declared properties independently of
label membership. See the normative
[constructor contract](../spec/language.md#property-graph-construction).

The common checker owns definition-domain issuance. Frontends must not invent
a domain, use a current input Artifact CID as provenance, or repeat Graph
validation. The initial vertical uses retained VALUES producer definitions;
an external schema/name alone is rejected as missing definition provenance.
Frontend syntax and name resolution are a separate responsibility.

Within one admitted domain, identity contains the definition, semantic key
types and complete key tuple. Properties, labels and endpoints are content,
not replacement identities. NULL element keys exclude elements. Duplicate
non-null keys reject even when their payloads match; duplicate edge keys are
checked before missing-endpoint exclusion. Missing or NULL endpoints exclude
an edge without inventing nodes. Independent edge keys preserve parallel edges.

MATCH requires the selected `definition`, optionally a static `label`, and
uses the existing predicates/projection. Optional identity/source/target
bindings retain complete typed identities. TRAIL uses `path_mode: "trail"`
and `emit: "paths"`; it tracks edge identities, not endpoint tuples. Other
unimplemented new-profile SGA operations fail closed.

## Snapshot and compatibility boundary

The existing bounded storage, traversal, snapshot, stop and cleanup owners are
reused. No new task-graph checker, Run state machine or capacity ledger is
introduced. Snapshot framing is separately identified as
`actql-property-graph-snapshot/0.1`; reload validates the full admitted
contract, typed identities, endpoint correspondence and content identity.
Constructor exclusions do not repair an invalid stored snapshot.

Legacy constructor bodies, snapshot framing and tuple edge identity retain
their meanings and CIDs. Explicit profile selection is required; a legacy
module claim is insufficient. No implicit migration or cross-domain mapping is
provided. Public Local/HTTPS Result publication is tested after MATCH/TRAIL;
that is not a claim that a durable Store Graph snapshot catalog is implemented.

## Executed regression evidence

Implementation checkpoint: `dc111614df6aadca1d58ae6eaef4893dc7fca421`.

- Constructor, domain, formal Plan, snapshot save/reload, Graph port and legacy
  Result regression sweep: **38/38 each on JS, Wasm and native**.
- Source Node surface, actual Local/HTTPS public SDK and legacy RelA boundary:
  **7/7**, Node 22.23.2. The Host cancellation test observes positive constructor
  work before a real timer abort, no partial Graph completion, and repeated
  close with no pending custody.
- Exact constructor control-work/workspace is independently counted as **45**;
  45 succeeds and 44 refuses under quanta 1 and 7. Cleanup cannot restart work.
- Repository-external packed Local/HTTPS acceptance: **2/2** before that
  checkpoint. Five packages were produced through normal prepack; the child
  resolves installed packages without a checkout or MoonBit lookup path.
  This is not final-SHA CI evidence.
- New-profile resource evidence cannot borrow legacy construction or Host
  cancellation evidence. Removing the dedicated cases/assurances or replacing
  the dispatch marker is required to fail the gate.

Initial verification failures are retained, not hidden: missing exact local
dependencies and an insecure endpoint were corrected with pinned dependencies
and real synthetic-CA HTTPS, not relaxed policies. A stale route-count negative
fixture was updated for the additive route. Full spec then passed its Local
coverage/resource checks but stopped at the required `MOON_HOME` environment
check. The pinned rerun exposed a generated Program-schema pin and a legacy
coverage-set assertion that had not distinguished the additive constructor;
both are corrected without changing the frozen legacy profile.

The new normative grammar/classification roots propagate through the Values
fixture's local Unit contract closure, proof, publication limits, Result Plan
and Run identity. `scripts/client-values-dependency-oracle.mjs` independently
authors these preimages from normative role bodies and the synthetic input;
it imports no compiler or issuer. Historical vectors retain their original
pins and literal CIDs. The new Run fixture is independently derived as
`sha256:f171d251195c262096577393afc6d51390ca7b4b7b63bda8b17c74a13a6d54f6`.
This global dependency impact does not change legacy Graph contract bodies,
tuple identities or snapshot framing. Final complete gates and Linux CI must
be reported against the submitted SHA in the PR.

## Deliberately not claimed

Full SGA, external producer-definition provenance, legacy migration, durable
Store Graph catalog publication and complete mechanized correspondence are
outside this initial retained-VALUES vertical. The additive AoA model/laws use
their distinct initial identifiers; executable conformance is not represented
as a proof of the entire implementation. A/B task splitting, carrier tasks and
Frontend implementation are not changed by this unit. The existing Graph
provider dispatch gains the checked constructor connection while retaining its
bounded sessions and owners; no parallel provider is introduced.
