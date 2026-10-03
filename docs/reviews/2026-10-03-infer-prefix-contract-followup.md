# Source-INFER prefix: published contract follow-up

This is read-only source inspection of A's published #223 at
`61b0760d303d054b76f3444e9abab6181e3d52e4`, not adoption of that SHA or a
new packed execution result. The formally selected source-free owner remains
`8f906009fd3d64b5873f227bc24ec993938023be`. Preserve the earlier uncertain
Runs and their evidence; do not redispatch them to test this connection.

The [original packed prefix handoff](https://github.com/actql/actql/blob/f9ff4778b3d0572ea35ae91d398835465bdc8d94/docs/reviews/2026-10-02-infer-source-prefix-handoff.md)
retains the independent source, expected rows/types, failing prefix and successful
JSON control. The published acquired-input continuation adds contract arguments,
but it does not establish the missing source-free connection:

| Existing boundary at the inspected SHA | Source-free omission | Required owner connection |
|---|---|---|
| `adapters/host-node/infer-operation.mjs::openNodeInferOperation` receives `fragment` and `ordered` | Physical source-free and restored source-free calls omit both; acquired calls pass them | Thread the already installed exact bodies on the existing physical and replay routes |
| `src/connectors_builtin_node/client_infer_bridge.mbt` exports `clientProgramStartScopedInferExecution`, `clientProgramStartInferReplay`, `clientProgramStartRestoredInferReplay`, `clientProgramStartRestoredInferSlotReplay` and `clientProgramStartInferExecution` | Source-free bridges accept registry/Values bodies only | Extend these existing bridges to forward the same admitted fragment/ordered bodies; update generated interfaces and adapter calls together |
| `src/client_infer_host/execution.mbt::start_owned` accepts optional `fragment_body` and `ordered_body` | `acquired_input = Some` forwards both; `None` calls `start_client_infer_input` without them | Forward both through the source-free branch without fabricating an acquired-input owner |
| `src/client_local_host/infer_input.mbt::start_client_infer_input` | Already accepts both and passes them to `prepare_client_infer_prefix` | Reuse this existing input owner and its checked Program/step binding |

All physical and replay operations converge on the same `start_owned` boundary.
Fixing only the acquired branch, only the suffix, or only its outer signature
does not complete the source-free prefix path. The exact admitted bodies must
reach the existing sequence preparation; registry and Values bodies cannot
substitute for fragment/ordered operation contracts.

This follow-up does not claim a runtime failure reproduced on #223. No new Run,
provider call, capture, package build or full gate was performed for the source
inspection. No common owner or Host implementation was edited by B.

After A supplies the complete pushed handoff SHA and minimal installed ModelTask
registration, B resumes with the smallest authored source through packed Local
and HTTPS to Named Result. Then verify KEEP/AS, nested nullable object projection,
complete descriptions, capture persistence and fresh-process replay with zero
provider calls. Keep this source acceptance separate from #223's acquired JSON
Program successes and from Frontend lowering-only checks.
