# Stage semantics identity

The normative owner is [Canonical identities](../spec/language.md#canonical-identities);
the registered envelope is `schemas.stage_semantics` in
[stage contracts](../../spec/contracts/actql-stage-contracts.json).

`program_references.stage_semantics_at` selects an owned stage from a checked
whole-Program declaration-use inventory. Its emitter combines the existing
annotation-free local-body projection, stage-local used Parameter/Binding
declarations, and canonical reference enumeration. References stay unbound.
Other stages' declarations and concrete runtime values are not embedded.
Stage ID, `after`, annotations, internal owner handles and source indices do not
enter this envelope. Imported input references remain semantic source data.

The pinned expression contract CID and `actql-stage-semantics/0.1` domain are
explicit envelope members. `check-stage-semantics.mjs` validates the expression
body against its AoA pin and verifies generated constants and fixed vectors.
Text, measurement and CID use one bounded canonical emitter; the hash path
does not materialize the serialized envelope as a String or Bytes. Independent
byte/node/depth caps are output limits, not whole-heap limits.

`pipeline_check_context.program_sources_stage_semantics` selects the same
projection through the source-check assembly's exact owned inventory. Computing
this preimage is not complete Input/Effect admission, issuer or authorization
validation, a Stage/Unit Definition envelope, or executable Program readiness.
Those gates remain distinct from reproducible source identity. The fixed corpus
contains source-projection fixtures, not claims that its partial source bodies
are executable Programs.

## Program composition

`prepare_program_semantics` builds the registered `schemas.program_semantics`
envelope from that same checked declaration-use inventory. It retains stage
order, stable stage names, normalized `initial`/`completed`/`accepted` laws,
explicit Result/receipt imports and root exports. Imports and exports are
emitted in UTF-16 key order. The template contains descriptors and stage CIDs,
not a second source-body tree. Root references use decoded source pointers;
stage-local pointers remain local to their stage envelopes.

Preparation charges retained descriptor/import/export entries and name units
in addition to existing declaration-use work. Stage hash byte and node caps
are cumulative across stages; hash depth is bounded independently per envelope.
No partially prepared result escapes a failed stage hash. These logical budgets
do not measure sorting comparisons or total heap allocation. The final Program
emitter has its own byte/node/depth limits and shares text, measurement and hash
semantics without materializing serialized stage bodies.

`program_sources_semantics` uses the exact inventory owned by source-check
assembly. Source semantics still excludes concrete bindings, internal handles,
the root Program ID and execution evidence. Program Definition separately binds
the Program ID to this semantics CID; computing source semantics is not a
substitute for that definition or the complete checked Program boundary.

## Program Definition

`prepare_program_definition` hashes the owned Program semantics and retains it
with the resulting CID. Its constructor accepts neither a replacement Program
ID nor a caller-provided semantics CID. The ID comes from the same admitted
source inventory; equal source bytes from another owner cannot be substituted
into the retained preparation. The exact normative envelope is
`{version: "actql-program-definition/0.1", id, program_semantics_cid}`.
Renaming the Program changes this Definition without changing source semantics.

Preparation reports the logical bytes and nodes hashed for Program semantics,
separately from stage hashes and final Definition output. Callers can account
for these phases without repeating serialization. Final text, measurement and
CID share a bounded emitter. Neither preparation nor output failure exposes a
partial identity. The handle is immutable and supports repeated bounded output.
Definition identity is not issuer evidence, authorization, Invocation binding,
or completion of the checked Program's static and runtime obligations.

## Stage Definition

The closed `schemas.stage_definition` envelope binds the authored stage ID to
its stage semantics CID. Its three-member shape mirrors Program Definition;
this makes the previously specified association exact without importing parent
revision or position. The reference implementation at
`sketch@87dc7144138edfcba108cdc59dc485ac976ba976` supplies local-unit encoders,
not an exact Stage Definition envelope; it is not used as a replacement wire
contract. Unit namespace and incoming contracts remain a different boundary.

`prepare_stage_definition` accepts only owned StageSemantics, hashes it under
explicit limits and obtains the ID from that same source. ID and CID cannot be
supplied independently. Preparation reports hashed bytes/nodes; final emission
has separate limits and shares text, measurement and hash sinks. The source
owner is retained internally but neither owner identity nor ordinal enters the
preimage. A renamed parent or unrelated sibling cannot change the local hash.
This identity is not an execution permit or completed Unit extraction.
