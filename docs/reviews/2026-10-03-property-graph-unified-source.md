# Frontend source separation for the unified Property Graph owner

Status: independent connection checkpoint, not public Graph execution acceptance.
Base: `0fd6332757176b88e8c4071e4a2cd0be3d6254e3`.

## Dependency withdrawal

The earlier #174 source at `d144e25567313168558750fa17d02cc20e55dcf6`
contains the provisional C implementation at
`321684933dce17afb0edc40f8877d2d7460c3da2` in both its source and ancestry.
It remains preserved on its original branch. Its successful packed runs and
CI remain historical evidence; they do not prove acceptance with the unified
Graph contract.

This checkpoint starts from current main and ports B-owned syntax, lowering
and independent expectations only. Neither old C revision is an ancestor of
this branch. No C Graph carrier, checker, kernel, provider, Host or snapshot
implementation is copied. The independent #184 Relation strategy correction
is adopted from `6685718f86b0e18518e2c53258f5129f0875447a`, preserving the
current main captured-prefix guard and using its existing checked owners.

The development integration now uses C public HEAD
`51376bca11d57b775aa22d42453176f8ad1f681b` from #164, together with B
`b19ed2cfb0bdce93832d47a8c3a7a8da95266c14`. Earlier candidate
`8c052888503e130e3d6c5f5a5ea74037be407e3f` is historical. The user authorized
connection and acceptance before C completes CI or merges. This is development
integration, not formal adoption GO. The provisional #174/#164 implementation
and unsubmitted worktrees remain unadopted.
This separation does not rewrite, force-push or replace published history.

## Boundaries retained for integration

| B entry or emission | Unified common owner required from C |
|---|---|
| `query_syntax.parse_query_script`, `PropertyGraphConstructor` | Bounded authored syntax; no checked or runtime evidence is issued here |
| `query_program.lower_property_graph_step` | Ordinary `property_graph` Program admission, construction typing and admitted definition domain |
| `query_program.compile_query_script` | Existing logical producer references; no added capture, persistence or placement boundary |
| `keyed_start_match`, `lower_script_keyed_graph_query` | Definition-scoped `match_nodes`, Graph-owned static labels and full element identity |
| Existing traversal Program emission | Independently keyed edge identity, WALK/TRAIL/ACYCLIC and exact Relation selector custody |
| `source_frontend.lower(Text)` | Existing Host preparation/checker/Run owner; DATA constructors lower to the unified ordinary Program |
| Ordinary Named Result declaration | Existing Result publication and `Result.describe`; no private identity slots are exported |
| Snapshot acceptance | C's public bounded save/reload owner; B adds source-path acceptance after handoff, not a snapshot codec |

The current `source_frontend.parse_query` API from main remains present and
unchanged. SDK/CLI transport, account authorization, request identity,
Run-start, cancellation, reconciliation and publication owners are reused.
JSON/YAML machine inputs retain their existing roles.

There is no `property_graph` -> old `graph` conversion or fallback. New
constructor source lowers through public preparation to the ordinary common
checker. Existing standalone Graph alias inputs remain refused; an explicit
label annotation does not reactivate their old property-label route. Unsupported
consumers must still fail before Run admission and provider I/O.
Ordinary Relation DATA remains separate from Graph acceptance.

## Independent evidence and next acceptance

`scripts/fixtures/property-graph-source-input.mjs` retains the independently
authored rows, declared column order/types/nullability, parallel-edge counts,
composite keys, label/property separation, NULL exclusions, refusal cases and
duplicate-key execution failures. No fixture expectation is regenerated from
the current compiler or old C output. The fixture is now connected to the existing external packed application,
including its narrow `--property-graph-source-only` selection. Packed execution
acceptance is still pending at this source checkpoint.

The parser/lowering tests compare authored expected Programs. C-dependent
checker and packed acceptance from the original branch are preserved there;
they are not silently reclassified as successful tests of this checkpoint.
The narrow public preparation tests assert ordinary keyed lowering, standalone
legacy alias refusal and unchanged public parser/Relation DATA behavior. They do not prove HTTP Run
admission/provider counters or snapshot roundtrip.

Development integration and acceptance sequence:

1. Integrate the pushed unified owner, preserving current main changes.
2. Reconcile constructor body, Carrier projection, MATCH/TRAIL and definition
   identity interfaces; use C's owners without a compatibility layer.
3. Replace the temporary constructor refusal with the ordinary common checker
   connection, and restore the independent checker acceptance tests.
4. Normally prepack fresh external Local and HTTP installations at one fixed
   source SHA. Check all original fixture obligations through Named Results,
   actual descriptions and independent rows, plus refusal counters and replay.
5. Use C's snapshot save/reload entry and validate source-to-restored execution.
   Record package digests, the B/C SHAs, failures and unexecuted coverage.

The selected Graph source execution and common public snapshot controls now
pass at the [fixed acceptance source](2026-10-03-property-graph-public-acceptance.md).
Native CLI, required CI, remaining SGA consumers and full Frontend migration
remain incomplete. No merge or package publication is requested.

## Local checkpoint validation

- Query syntax: 71/71 JS; query Program construction: 146/146 JS.
- Public preparation: 10/10 JS; the five dependency-boundary tests pass on
  Wasm and native. The initial DATA diagnostic-classification failure was
  corrected without restoring a retired constructor or changing SQL routing.
- The independent ordered DATA machine Program prepares seven checked tasks,
  with exact task targets and a six-task refusal: 1/1 JS. This is preparation
  evidence, not a new packed execution claim.
- Existing Values Run material issuance agrees with the independent complete
  preimage: 1/1 JS. The Values Unit is unchanged; the updated Grammar Manifest
  changes Invocation Template, Executable Plan, Compiled Plan and Run identities.
  The current-main and earlier vectors are retained with their original pins.
- Independent manifest/profile tests: 13/13 Node; independent Values Run
  preimage: 1/1 Node. Metadata regeneration reports no outstanding changes.
- Three-target public API verification passed. The generated current Grammar
  Manifest canonical vector passed on Wasm/native; generation also verified
  all fixed input preimages independently of product output.
- `npm run check:spec` completed successfully once after regenerating the
  grammar, compiler pins and canonical vectors. Subsequent source changes
  tighten the legacy Graph refusal and have their focused preparation tests;
  subsequent Values expectation updates have their independent oracle and
  actual Run material issuance test. The aggregate gate is not presented as
  a second clean final-SHA run or required Linux CI.
- No full Core/Client gate, fresh packed Graph acceptance or new Linux CI was
  run for this incomplete dependency checkpoint. Historical #174 green CI
  and packed results do not fill those gaps.

## Development integration validation

- Public source boundary: 5/5 JS; keyed lowering and property predicates: 4/4 JS.
- Independent historical/current Run preimages: 2/2 Node. Current merged Grammar
  Manifest is `sha256:f8803129b22ca89d078e90e530aaf6238bb3aa8a1da02555fd67a1c5929029b3`;
  dependent compiler pins, metadata and canonical vectors were regenerated from
  the merged source, with Workers fixtures generated before Node Host fixtures.
- `check:spec` was attempted on the integration source. Relation execution
  passed 1,094/1,094; the aggregate was intentionally interrupted at
  `check-local-resource-accounting.test.mjs` after prolonged lack of progress
  under high machine load. The full gate is **incomplete**, not successful.
  No guard was disabled, no test expectation relaxed, and no whole Core gate
  was added. The interruption is not classified as a semantic product failure.
- Three-target public API consistency passed. Common Run material issuance
  passed 1/1 JS against the independent Run preimage. `check:contracts` passed
  after independently updating the integrated grammar expectation from the
  normative body; no compiler output was used as the expected digest.
- Packed Graph source and common snapshot acceptance passed at
  `a6675aa5945389e66aa15978c9ed0ae66cbe69a1`; see the separate acceptance
  record for exact counts and package digests. Required final-SHA CI is pending.
