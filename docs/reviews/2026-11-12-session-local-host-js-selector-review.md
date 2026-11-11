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
The current map selects this exact reviewed successor; it does not admit the
prior descriptor as current or broaden support to other targets or toolchains.

The checks preserve every historical preimage, verify complete restoration,
and reject removed, renamed, or retargeted selectors and unrelated options.
This is a source-selection review only. It makes no runtime, ordinary package,
performance, or release qualification for the selected source.
