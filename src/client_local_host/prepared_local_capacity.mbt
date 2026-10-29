///|
/// The same per-task envelopes offered by the retained Local module. Existing
/// predecessor reservations can remain live with accepted borrowers, so these
/// complete envelopes coexist until their original retirement, not merely
/// until a task reports a result. No factory or sequence is reconstructed.
fn client_prepared_local_configuration_capacity(
  original : ClientPreparedLocalConfiguration,
  policy : @resources.LedgerLimits,
) -> ClientLocalSequenceCapacity? {
  let graph = original.graph
  let first = original.capacity_plan.graph_offset
  let mut retained = 0L
  let mut executing = 0L
  for task in first..<@strategy.graph_task_count(graph) {
    guard @local_driver.local_dispatch_preparation_task_capacity(
        original.dispatch,
        task,
      )
      is Some(envelope) &&
      @execution.execution_capacity_inventory_add(
        retained,
        @execution.QuotedBytes,
        envelope.retained_bytes,
        1,
      )
      is Some(next_retained) &&
      @execution.execution_capacity_inventory_add(
        executing,
        @execution.QuotedBytes,
        envelope.execution_bytes,
        1,
      )
      is Some(next_executing) else {
      return None
    }
    retained = next_retained
    executing = next_executing
  }
  guard @local_driver.local_dispatch_preparation_transfer_bytes(
      original.dispatch,
    )
    is Some(transferred) else {
    return None
  }
  Some({
    limits: {
      ..policy,
      retained_bytes: retained,
      execution_bytes: executing,
      // Preserve the independent whole-Run output-transfer guard alongside
      // actual configured input occurrences; this is not a second grant.
      transfer_bytes: Int64::max(policy.transfer_bytes, transferred),
    },
    provider_retained: 0L,
    provider_execution: 0L,
    simultaneous: Some((retained, executing)),
  })
}
