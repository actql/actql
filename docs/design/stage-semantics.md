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
