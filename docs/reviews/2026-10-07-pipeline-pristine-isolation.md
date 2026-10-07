# Pipeline pristine execution isolation

G; final target main; parent #828. Adopt current main
`71f7a205c1839872c9fdb7c108e993ec2aa53e3b` through normal merge
`34f9aa80fd9bf7ad778808b3c01bebba06f58663`. Preserve the parent originals,
fresh obligations and required final check. This unit does not activate reuse.

## Public editing boundary

Extend `proofs/relation-pipeline/execute.mjs` with an explicit target set for a
scoped execution owner. Normal producers continue to require JS/Wasm/Native.
An explicitly JS-only owner must refuse other targets before starting a tool;
its identity does not require C/C++ tools that cannot run in that profile.
Keep the full Moon distribution and exact source/fixture/runtime/binary checks.

Add `proofs/relation-pipeline/pristine-replay.mjs` using the existing executor,
reviewed partition, independent fixed regressions, registry and semantic oracle.
It replays all four assigned L-M0 fixed minima as actual fresh JS observations,
retains original receipts, checks source preservation and closes its fixture.
It is a pristine phase, not a mutated detection/restoration campaign or complete
three-target part. The required audit must still reject an incomplete part.

Extend existing source/image staging and validation only as needed to execute
this registered pristine phase in the existing read-only, networkless scratch
image. Proposed connections are `proofs/ci-evidence/isolation.mjs`,
`isolated-runtime.mjs`, `isolated-execution.mjs`, and the explicit local
acceptance entry point, plus a pipeline child and corresponding consuming tests.
Keep Session's existing image, contract, collector and admission scope unchanged.
Do not accept arbitrary archive-provided commands/entry points or reinterpret
local observations as Actions provenance. Actual image execution remains an
acceptance requirement, not something proved by source staging tests.

Protect new pipeline execution files with the existing exact source/parent/blob/
mode declarations; retain all real merge bases and actual inherited obligations.
No product Owner, CI selector, production campaign or required-check policy is
edited. Later changes to pipeline action registration must bind the entire
execution/source/runtime contract before permitting any reused phase.

## Acceptance and next boundary

Use the existing executor/workspace tests for stale binaries, changed tools,
cross-owner substitution, nonzero execution, source preservation and cleanup.
Add scoped-target refusals while retaining Native's C/C++ requirements.
Run the four independent fixed cases through the real pinned JS executor and
record clean source, commands and raw receipts; that local run alone does not
establish image isolation or main qualification.

Then execute the same cases in the actual immutable image, inspect its physical
inputs/environment and compare scientific observations with the normal fresh
run. Preserve the missing mutated/restored/other-target obligations, and the
full fresh pipeline audit. Compatible full-main comparison, limited activation,
related-input fresh execution and inclusive net savings remain goal requirements.
