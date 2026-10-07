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
from those originals when consuming the archive. The pipeline producer writes
the derived record; the global required check consumes the dedicated original
through `mutation-action-final.mjs` and retains its acceptance separately.
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
local archive into an Actions original. Actual hosted transfer/acceptance and
historical shadow comparison remain unverified qualification requirements.

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

This Draft includes `mutation-action-final.mjs` and its consuming tests.
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
Those results establish the earlier transport implementation only. They are not
relabelled as results of the following required-check connection.

## Required consumer: fixed-source local results

Implementation: `5cf1516c39804a25a553d39b25f3a1a15e334e31`.
Declaration and tested clean source: `3e76c4458d3ec35e50b8bc10673c01b8ed2b605e`.
[Preserved raw summaries, stdout and foundation](evidence/2026-10-07-pipeline-required-consumer-local-acceptance.json)
bind each artifact's compressed and original bytes, command and executed source.

The bounded/nonzero archive test ran the actual pinned Lean once to construct
the 36-obligation certificate and exercised the actual required consumer:
32/32 passed. The selected existing pipeline/Session workflow, aggregate, Draft
selection and actual committed-input checks passed 11/11. A preceding
dirty-tree archive/downloader diagnostic passed 37/37 and is recorded separately.

The first clean-source archive invocation failed its shared setup with
`spawnSync lean ETIMEDOUT` at the unchanged 30-second checker limit. No test was
accepted and no timeout was counted as a mutation detection. One bounded rerun
passed without source, pin, checker or timeout changes. Host CPU/memory load was
observed but is not established as the cause. Keep both raw results.

The actual full repository foundation validator first reached its 360-second
local bound. A timed diagnostic then passed in 584.889 seconds with a
600-second outer bound. Its local preload invoked every original Git call
unchanged and observed durations; it did not replace roots, parents, blobs,
modes, declaration rules or verdicts. The preload bytes and both invocations
are retained. The diagnostic recorded 5,937 real Git calls and about 404.939
seconds within those calls, including 3,342 `ls-tree` calls (230.702 seconds)
and 1,536 `merge-base` calls (105.519 seconds). This loaded local observation is
not a controlled before/after comparison or hosted net-saving result.

The global check now consumes the saved original after the existing job-verdict
gate, using exact producer artifact ID/digest and independent required coverage.
It rechecks the real run/attempt after all member/plan/certificate processing.
The complete diagnostic archive, producer assignments, scientific/capacity
audits and Draft/target selection remain. No action is skipped.

The next units are actual execution isolation, independent full-main
qualification and fresh shadow comparison, limited activation, related-input
fresh execution, and collection/transfer/authentication-inclusive net savings.
Linux guarded publication and live Actions transfer/required acceptance remain
unverified. No Actions were polled, dispatched or retried for this local unit.
