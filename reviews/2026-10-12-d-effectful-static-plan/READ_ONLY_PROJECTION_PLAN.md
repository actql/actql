# X02: original Effectful static projection

Status: computation component implemented; public X02 acceptance incomplete. Fixed investigation
source: `5aa1e9296d3d9796ad3218795c88151bf309a000`. This independent branch
does not modify submitted #1696 (`5802b59c40166a749f4a7c1343e6563995bfbfc6`).

## Existing authority and custody

`PreparedClientEffectComputation` in
`src/run_publication_host/client_effect_program.mbt` retains the parsed Program,
the existing checked static Effect candidate and checked computation DAG.
`client_effect_program_view` is a private view of that same Owner. It does not
recheck an Effectful Program as a publicly admitted Effect-free Program.

`issue_prepared_client_effect_compilation` in
`client_effect_compilation.mbt` retains the original Effect Owner, the existing
`ClientTaskCompilation`, and the optional normalization profile. Compilation
alone issues neither an allowed Run nor permission to apply an Effect.

The existing `issue_client_static_plan_view` supplies the computation map from
the retained checked/compiler Owner. A narrow first seam can check physical
Owner equality and reuse that issuer. It must use the retained compilation,
not a second preparation or a new graph. This computation component alone
does not establish full X02 coverage: it does not yet describe the Effect set
or required gates.

## Closed envelope direction

Keep all existing PlanView fields, canonical bytes, version and CID unchanged.
Do not add Effect nodes to its closed operator vocabulary. The Effectful
response will be a separate closed envelope containing that existing
computation PlanView and a bounded static Effect/gate relation projection.
No fabricated RunRef is needed for a static request.

The relation projection will be issued from the same checked Effect candidate,
bound to the original Program/compiled Plan/LogicalMap identities, and carry
its own canonical identity. Relations must refer to original checked
occurrences and formal ports. Array order, matching names or current runtime
configuration cannot supply a missing relation. Missing supported evidence is
explicit unavailable, never an invented edge or an empty complete inventory.

Exact relation fields and their independent canonical vectors are the next
contract hunk. They will be reviewed together with the existing checked
candidate accessor. No public schema has been changed by this component.

## Gate, Preview and permission semantics

- A declared approval requirement is a static requirement, not a saved
  Checkpoint, currently granted approval, or evidence that an operation is
  permitted. Any unavailable gate correspondence stays unavailable.
- Static target/selector/change declarations remain distinct from concrete
  resolved runtime values. The static read does not evaluate input expressions
  by running Source, Model or Effect work.
- A concrete Preview may be exposed only from the existing sealed Review
  Owner under its existing current disclosure authorization. Without that
  evidence, resolved targets, values and diff remain unknown. Normalization
  metadata is not a sealed Preview.
- Reading the projection does not issue normalization custody, an allowed Run,
  execution materials, grant, approval, publication or a resume claim. It
  neither advances Run state nor alters Unknown/reconciliation responsibility.
- Existing checking/compilation/encoding bounds and current read authorization
  apply. Invalid limits, foreign physical compilation and unsupported carrier
  contracts retain typed refusal; no larger bounds or permission are inferred.

## Limited regression and public connection plan

First verify the readonly computation issuer with an existing Salesforce-update
fixture: original physical Owner succeeds, an equal-document foreign Owner
fails, invalid/tiny limits refuse, repeated bytes match, and optional
normalization remains absent. Independently verify the relation bytes and
original occurrence binding before advertising Effectful static support.

At the Host seam, use the existing preparation/Compiler supplier. Do not
remove the current `effect_free` guard until the complete closed response is
available. An Effectful static request must perform zero Source/Model/Effect
I/O, zero Run admission and zero Preview execution. Authorization reads are
separate from business I/O. No legacy facade or independent Debug controller
is introduced.

The preparatory `run-JNxSTX` failed during compilation: the new issuer is
absent, and the draft test also used incorrect JSON field-access aliases and
an ambiguous issue constructor. Actual executed cases: **0**. This is retained
as preparation evidence, not a completed before/after behavioral regression.
The subsequent `run-vLVkh4` and `run-iS2WhK` also exposed test pattern syntax
errors; both remain compile failures with **0** executed cases. Those errors
were corrected without changing the source Program or independent expectations.

`run-UcsMvL` executed the new three cases successfully. The precommit
`run-uiUNk4` then executed the three component cases and three existing
static Plan regressions successfully, with Native Common compiler/API,
owned-contract scan and whitespace checks. Native execution and public
Effectful Plan cases remain **0**. These are precommit observations, not
evidence for an untested later submitted SHA.

No new Native producer, Heavy lane, pack, installed consumer or Hosted CI was
started for X02.

Model continuation/current-consumption and journal startup remain A-owned.
This projection does not edit A's Model files or turn Model journal cuts into
a second Debug progress authority.
