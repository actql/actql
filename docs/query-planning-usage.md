# Query strategy experiment

The source-checkout `query_planning` package compares and computes the two initial
mock query realizations. It does not dispatch a real Connector, issue acquisition
evidence, publish a captured result or construct a runnable Program/Plan.

1. Obtain `execution_relation.QuerySequence` from the shared query derivation and
   matching checked/lowered preparation. See [local usage](local-compute-usage.md).
2. Call `offer_mock_query` with `NativeQuery` or `BroadWithResidual`. Obtain cost
   slot meanings with `query_work_count` and `query_work_at`.
3. Supply serial estimate lines covering those slots, and separate optional
   transfer/retention bytes and money quantities. These are estimates, not limits.
4. Call `choose_query_strategy` for offers owned by that exact preparation.
   `Deferred` requires more information or explicit Host priority. `Proposed`
   contains a physical proposal whose runtime requirements are still pending.
5. For the local fixture only, use `prepare_mock_query_attempt` with the immutable
   source cursors and a preparation entry bound. Call `execute_mock_query` once
   with separate source, receipt and local computation limits.

The native route computes before receiving selected rows; the broad route applies
receipt limits before the local residual. Both validate the entire supplied source
under the shared checked semantics. A successful `MockQueryComputation` exposes
source/receipt/output counts but no consumer input handle. `mock_query_computation`
reports `NotComputed` before execution and retains typed failures afterward.
`cancel_mock_query` can withdraw an unstarted or awaiting-capture attempt. Use a
new attempt for a retry; it does not implicitly reread or choose another route.

Selection needs one candidate entry plus the common helper's duration/preference
entries: two offers require four entries without priority and six with a two-item
priority. Offer estimation separately budgets its work inventory, line count and
slot references before traversing them. Missing retention or other work makes
the estimate unknown. Duplicate transfer coverage is rejected.

The pending capture stage must implement the shared process-evidence profile
before this experiment can return a completed acquisition to a consumer. Input
relative order is not total-order evidence; this profile requires null source
order CID. Existing performance regressions remain accepted development debt,
not a passed performance gate. No performance improvement is claimed here.

See [design](design/query-physical-strategy.md) for ownership, scope and limitations.
