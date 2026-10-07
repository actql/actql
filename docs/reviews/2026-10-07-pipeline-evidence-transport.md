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

## Final required-check connection boundary

Extend this same Draft with `mutation-action-final.mjs` and its consuming tests.
The existing required `check` authenticates the current pipeline job's exact
artifact ID/digest and reconstructs the independent plan before succeeding.
Keep the existing job-verdict gate first and preserve Draft/target selection.

Retain the entire original pipeline archive for diagnostics. Publish only the
derived action record and unchanged mutation part reports/raw receipt JSON in a
small `pipeline-actions-<run>-<attempt>-<tested SHA>` artifact, using the existing
64 MiB bounded transport instead of transferring unrelated capacity reports or
raising transport limits. The reader's code-selected pipeline namespace changes
to this dedicated original; no alternative/old-name fallback is introduced.
The existing pinned uploader exposes its artifact ID/digest to `check`.
No producer execution, exploration/capacity corpus or original bytes are removed.

The final reader's API/digest failures are mandatory current-evidence failures,
distinct from an optional historical main comparison. The latter cannot block
fresh production, and this connection still does not authorize pipeline reuse.

## Fixed-source local results

Implementation: `10008d8007bca70cfb0225dc83ee71bfbdc4833c`.
Declaration and tested clean source: `7bc3c7ae06aa7e982e5996d61ba00da10dfb6d4e`.
[Preserved summaries and stdout](evidence/2026-10-07-pipeline-transport-local-acceptance.json)
bind each compressed and uncompressed artifact independently.

At the clean tested source, the existing bounded/nonzero Node wrapper ran the
archive, original adapter and scientific-audit caller tests: 63/63 passed.
The changed workflow and existing final aggregate contract tests passed 4/4.
The actual full repository foundation validator completed successfully in about
280 seconds. This is local execution time, not hosted net savings. The earlier
dirty-tree diagnostic passed 50/50, including all 23 retained Session origin
tests; it is labelled separately rather than attributed to the later clean SHA.

The actual checker used the existing Lean pin with explicit local `-j 1` on
macOS arm64 and the unchanged production 30-second timeout. Controlled reports
and API/ZIP fixtures do not establish actual Actions execution or a current
three-target mutation campaign. The Actions-only publication guard was not
bypassed for local testing. Fresh publication calls no API; original acquisition
failures cannot become a prerequisite of the fresh scientific audit.

The inherited owned-version scan failure in the Native negative fixture at
`retained_task_input_wbtest.mbt:782` remains disclosed in #815. This unit changes
neither that fixture nor the scanner and does not repeat or waive that failure.
The archive reader is exported and locally exercised; the global required check
still requires the pipeline job verdict. Wiring that check to consume the saved
original/certificate is a separate remaining unit, not implied by this result.
The next units remain that consumer connection, actual execution isolation, independent full-main
qualification and fresh shadow comparison, limited activation, related-input
fresh execution, and collection/transfer/authentication-inclusive net savings.
