///|
/// Observe a captured Query input of its original shared Compute DAG.
/// The RowRun keeps its holding and cleanup; this allocates no inventory,
/// transfers no custody and establishes no permission or resource capacity.
pub fn check_row_capture_compute_binding(
  capture : RowSourceCapture,
  dag : @strategy.CapturedDAG,
  task : Int,
) -> Bool {
  guard task >= 0 &&
    task < @strategy.graph_captured_prefix(@strategy.captured_dag_graph(dag)) &&
    capture.observation is QueryObservation(_) &&
    capture.run.configuration is DirectConfiguration(_) &&
    @strategy.captured_task_source_matches(dag, task, capture.source) else {
    return false
  }
  check_row_capture_compute_original(capture, dag, task)
}

///|
/// Callback-free SAME live DAG port and Row custody census. Source availability
/// and Account currentness remain separate checks, not cached permission here.
pub fn check_row_capture_compute_original(
  capture : RowSourceCapture,
  dag : @strategy.CapturedDAG,
  task : Int,
) -> Bool {
  let run = capture.run
  // Source availability can call the original transport verifier. This pure
  // census can also fence every earlier port after all such callbacks return.
  guard !run.closed &&
    capture.observation is QueryObservation(_) &&
    run.configuration is DirectConfiguration(_) &&
    @strategy.captured_task_source_original_matches(dag, task, capture.source) &&
    run.physical is Some(physical) &&
    physical_equal(physical.ledger, @strategy.captured_dag_ledger(dag)) &&
    physical.dag is None &&
    physical.holding is Some(holding) &&
    @resources.holding_available(physical.ledger, holding) &&
    !@resources.reservation_pending(physical.reservation) else {
    return false
  }
  true
}

///|
/// Callback-free live nominal Query capture/RowRun correspondence only. This
/// observes no transport/Account currentness and issues no permission, stop
/// acknowledgement or transfer. The caller still checks the actual DAG/source
/// binding and keeps this same RowRun through downstream cleanup.
pub fn check_row_query_capture_run(
  capture : RowSourceCapture,
  run : RowRun,
) -> Bool {
  guard physical_equal(capture.run, run) &&
    !run.closed &&
    capture.observation is QueryObservation(observation) &&
    run.configuration is DirectConfiguration(_) &&
    run.attempt.state is Captured(actual) &&
    physical_equal(actual, observation) else {
    return false
  }
  true
}
