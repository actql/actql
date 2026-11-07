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

///|
/// Model composes actual Local planning work, not the whole-Run policy ceiling.
/// This private configuration has exactly one installed Local implementation:
/// its estimate returns one non-resident offer per unstarted task. Each offer
/// charges slots + lines + line slots (one schedule line and optional IO lines).
/// Search therefore has one assignment; its charged retention scan is bounded
/// by tasks squared times edges. Keep all adaptive retries, including the one
/// refused revision, and both original input/output bindings when present.
/// No runtime counter is reset, policy widened, provider reconstructed or
/// reservation released by this DATA projection.
fn installed_mock_model_compute_limits(
  original : ClientPreparedLocalConfiguration,
  policy : @resources.LedgerLimits,
  occurrence : @publication_host.ClientInferOccurrence,
) -> @resources.LedgerLimits? {
  installed_mock_models_compute_limits(
    original,
    policy,
    if @publication_host.client_infer_occurrence_terminal(occurrence) {
      1L
    } else {
      2L
    },
  )
}

///|
// Singles and complete groups use this SAME configured Local charge path.
// Bindings are the complete checked input/output occurrences, not a policy
// multiplier or another Source/Model execution grant. Actual charges retain
// the same finite Ledger and are never reset, refunded or clamped here.
fn installed_mock_models_compute_limits(
  original : ClientPreparedLocalConfiguration,
  policy : @resources.LedgerLimits,
  bindings : Int64,
) -> @resources.LedgerLimits? {
  if bindings < 1L {
    return None
  }
  let count = @strategy.graph_task_count(original.graph)
  let first = original.capacity_plan.graph_offset
  let edges = @strategy.graph_data_count(original.graph)
  if first < 0 || first > count || edges < 0 {
    return None
  }
  // Other legacy modes keep their original conservative quote. The current
  // configured Model paths are adaptive single-root or fixed retained/two-root.
  if first != 1 && !original.retained_output && first != 2 {
    return Some(policy)
  }
  let n = count.to_int64()
  let tasks = (count - first).to_int64()
  let d = edges.to_int64()
  let maximum = 2147483647L
  let square = tasks * tasks
  if d > 0L && square > maximum / d {
    return None
  }
  let search = 2L * n + 2L * tasks + square * d + 2L
  // prepare_client_local_configuration always installs input IO; output IO is
  // exactly the retained-output choice used by that same preparation.
  let io = if original.retained_output { 2L } else { 1L }
  let slots = @local_driver.local_dispatch_work_slots().to_int64() + io
  let offer = 2L * slots + 1L + io
  let work = if first == 1 {
    // configure_adaptive_dispatch charges count once. Every rebuild charges
    // nodes/edges and the installed estimate work before its offers/search.
    // A revision-limit refusal may do that preflight once more before latching.
    let revision = n +
      d +
      client_local_estimate_work.to_int64() +
      tasks * offer +
      search
    n + (client_local_adaptive_revisions.to_int64() + 1L) * revision
  } else {
    tasks * offer + search
  }
  guard @execution.checked_preparation_add_product(
      first.to_int64(),
      bindings,
      work,
    )
    is Some(work) else {
    return None
  }
  if work < 0L || work > maximum || work > policy.planning_work.to_int64() {
    None
  } else {
    Some({ ..policy, planning_work: work.to_int(), })
  }
}
