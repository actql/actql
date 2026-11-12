# Local Host JS Request selector review

This review covers only `src/client_local_host/moon.pkg` at source
`112a38375c2f57f33424f018456f25f9920a044b`. Its 10,649 bytes have SHA-256
`1f51429964f1bd98f0089a0f62b19d0f53bf1f0ea50c87b5ce80ac408af70946`.

The complete prior descriptor at
`4c6c5793f750577c21724f75b09380e598f7a4c2` remains retained: 10,392 bytes,
SHA-256 `5af382fee097e2f379cb3a50727ea88d0fc462f6d0beab3f15d0affb39971363`.
Removing exactly these four literal `"js"` selector lines from the successor
restores that prior descriptor byte for byte:

- `collection_request_finalization_js_wbtest.mbt` (63 bytes).
- `preparation_request_large_literal_js_wbtest.mbt` (65 bytes).
- `preparation_request_query_selection_js_wbtest.mbt` (67 bytes).
- `preparation_request_work_calls_js_wbtest.mbt` (62 bytes).

Each named file is an actual regular `100644` Git blob in the selected source.
The 257-byte difference contains no production or whitebox import changes,
Native options, dependency aliases, commands, or other selector changes. The
existing JS rule still binds full literal import closure and source membership.
That review does not admit the
prior descriptor as current or broaden support to other targets or toolchains.

The checks preserve every historical preimage, verify complete restoration,
and reject removed, renamed, or retargeted selectors and unrelated options.
This is a source-selection review only. It makes no runtime, ordinary package,
performance, or release qualification for the selected source.

## Completed-task provenance successor

The current map selects the descriptor at
`705b8689c5a75e1c1a52aa33f178237bc7f2df3d`: 10,706 bytes, SHA-256
`6ecd1471fc3ab3904b1d7cf2520bc4834c4fe3f3b257cc11663ac7baf927af55`.
Removing only the 57-byte literal `"js"` selector for
`completed_task_provenance_js_wbtest.mbt` restores the complete 10,649-byte
Request-selector descriptor above. The new test is a regular `100644` Git blob
in that revision and remains part of the keyed and physically staged source
cohort. Every import, alias, other target selector and option is unchanged.

The prior Request-selector descriptor remains a historical preimage, not a
second current review. Tests reject its reuse and removal, renaming or
retargeting of the new selector, unknown imports/options, and foreign
target/toolchain inputs. This extends only the exact source-configuration
review; it does not qualify new runtime or scientific experiment results.


## READ Request fixture successor

The descriptor at `5d46f7839bab1146ce3763d6e8b08f57f5daab6c` contains
10,836 bytes with SHA-256
`f6711ed47a6251f7f3c6bc75191c1f4b4215b050ee05594b24f70a683aa1972b`.
Removing exactly these two literal JS selectors restores the complete
10,706-byte `705b8689c5a75e1c1a52aa33f178237bc7f2df3d` descriptor above:

- `preparation_request_result_metadata_js_wbtest.mbt`.
- `preparation_request_result_read_js_wbtest.mbt`.

Both existing test files call `request_parent_fixture`, whose original supplier
is the explicitly JS-selected `preparation_request_parent_js_wbtest.mbt`.
That fixture uses `extern "js"` to retain the actual original Node resource
supplier through `ordinary-node-resource-runtime.cjs`. The two READ tests
therefore belong to the same JS target. Their bodies, assertions, fixture and
all production code remain unchanged. The common READ implementation and every
other test selector remain shared exactly as before.

The current review accepts only this exact descriptor and the existing pinned
JS toolchain. The prior revision and digest remain historical inputs, not
current evidence. Regression checks reconstruct the complete prior descriptor,
retain complete source membership, and reject either selector's removal,
renaming or retargeting together with unrelated import/option changes.
This source-selection correction supplies no new runtime, ordinary package,
performance or release qualification.
