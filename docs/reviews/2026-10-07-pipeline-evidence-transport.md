# Pipeline mutation original transport

Parent review unit: #815, `ce0da26a89bc044606359225fa07fc3f7e02977d`.
Final merge target is main. This unit preserves fresh-only pipeline policy.

## Editing boundary

Reuse the existing Actions origin authenticator in `proofs/ci-evidence/receipts.mjs`
with a code-selected pipeline family binding, retaining the existing Session
binding and all run/attempt/repository/job/digest checks. Add
`proofs/relation-pipeline/mutation-action-archive.mjs` and focused transport tests.
Share only controlled sample construction in `fixtures/mutation-action-sample.mjs`
with the existing adapter tests; update `ci-artifacts.test.mjs` for the consuming
workflow contract. Capture the existing checker output in `mutation-actions.mjs`; retain immutable
original reports/receipts and reconstruct the exact required/application plan
from those originals when consuming the archive. The existing final consumer
workflow writes the derived record and includes it in its existing artifact.
Protect the new source/tests through the existing history inventory and exact
source/parent/blob/mode declarations.

Fresh publication makes no API calls: it runs the existing full scientific audit
and exclusively writes a derived record with the actual workflow event context.
The consumer discovers the successful job from independent API facts.
The consumer requires independently supplied expected repository/run/attempt/SHA,
authenticates API facts before adopting archive bytes, and uses the bounded
read-only ZIP reader. No extraction, archive code execution or Actions token
forwarding to storage is introduced. Missing/expired transport is not accepted;
it remains distinct from invalid provenance/digest/plan data. This unit does not
authorize skipping an action, close the execution environment, or promote a
local archive into an Actions original. Required final whole-run acceptance and
shadow comparison remain separate qualification requirements.

## Acceptance

Exercise retained Session origin regressions and pipeline archive/run/attempt,
job, artifact digest and raw report/receipt substitution refusals. Execute the
existing pinned Lean checker for an accepted fresh plan and verify the retained
certificate's input/output binding; do not use an always-successful checker
mock. Keep feature-branch/PR originals ineligible for main-origin acquisition.
The workflow retains all existing scientific, target and capacity audits.
Local evidence establishes only decoder/transport/checker correspondence, not
new three-target campaigns, Linux isolation or actual hosted provenance.
