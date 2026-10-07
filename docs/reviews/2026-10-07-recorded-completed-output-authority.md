# Original authority for completed Output recovery

A completed resident dispatch can retain a sealed payload while its Output
report remains unacknowledged. Rebuilding its Program with a newer compiler
can issue a different Invocation Template and correctly fail admission of the
original prepared invocation. Recovery must neither weaken this admission nor
replace the original Run, authority or deadlines.

## Connection

`prepare_recorded_run_publication()` takes evidence already admitted by the
existing canonical owners. It closes the original Plan, Template, Run and
Result references and returns a publication-only opaque value. It cannot be
passed to Program preparation, task binding or execution. Original Run and
authorization deadlines remain effective.

`prepare_resident_recorded_output()` binds that value to the exact dispatch in
the existing Site journal. It checks the original attempt, Run and input
binding, and requires byte-for-byte equality with the original prepared
invocation and authorization retained in the materials. Another valid or
renewed admission is not a substitute.

The caller still supplies current Site identity/generation, runtime binding,
delegation and exclusive maintenance ownership. Cancellation and the original
lifetime are checked again at each existing Output continuation boundary.
These are separate from structural restoration of the saved evidence.

Both the freshly checked and recorded callers use one completion gate:
`restore_remote_runtime_completed_custody()` must admit the original journal
record, completed evidence, subject and measurement. The exact reserved
Output intent and pending payload responsibility must also be present.
Acceptance or a payload file alone cannot pass this gate.

The existing Output, Publication Store and Transfer owners retain custody.
Recovery queries the original Transfer, retains the real Output report before
delivery and keeps pending cleanup responsibilities. It does not acquire
Source, open an executor, issue an attempt, upload the payload again or write
a terminal state directly.

## Compatibility and remaining work

This adds portable authority checks and a Native caller API. It introduces no
wire format, identity domain, state alias, compiler-manifest fallback or new
ledger. Existing execution admission is unchanged. A historical Run is not
reinterpreted as a newly compiled Run, including across Graph identity changes.

The maintenance CLI requires `recover-output --publication-custody-root`.
The custody directory contains six exact, original Owner-issued wires:
`bound-template.json`, `compiled-plan.json`, `prepared-invocation.json`,
`run-authorization.json`, `run-definition.json` and `result-definition.json`.
Each is read through the existing bounded-file owner and admitted through the
canonical evidence/contract owners before the exclusive maintenance slot is
acquired. The CLI never reconstructs missing evidence with the current
compiler. It uses the existing authenticated durable report/ACK client after
the original completed-custody and current-authority checks.

Cloud persistence/transport of these original wires is not included. A caller
must obtain the exact original Owner-issued evidence and current trusted
authority; this API does not infer either from an arbitrary archive. Formal
Cloud adoption requires a reviewed, merged OSS source and matching package and
Native artifacts. Real report/ACK delivery, publication and formal cleanup
remain separate acceptance obligations; structural restoration alone does
not establish them.

## Focused evidence

Portable tests cover original canonical evidence restoration, original
deadlines, foreign Result/Run references, changed Template bytes, substituted
authorization and an attempted deadline extension. The Native envelope caller
test covers the exact original dispatch and refusal of another attempt/Run or
missing original authority. It exercises admission only and does not establish
Native I/O recovery or public acceptance.

A protected operator diagnostic also admitted the original failed Run's
actual Owner-issued Template, Plan, authorization, Run and Result through the
current portable owners. It preserved their identities and refused use past
the original deadline. The diagnostic performs no execution, state mutation,
report delivery or cleanup, and its private evidence is not checked in.
