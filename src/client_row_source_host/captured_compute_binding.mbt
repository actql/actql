///|
/// Observe the single captured Query input of its original shared Compute DAG.
/// The RowRun keeps its holding and cleanup; this allocates no inventory,
/// transfers no custody and establishes no permission or resource capacity.
pub fn check_row_capture_compute_binding(
  capture : RowSourceCapture,
  dag : @strategy.CapturedDAG,
  task : Int,
) -> Bool {
  let run = capture.run
  guard task == 0 &&
    @strategy.graph_captured_prefix(@strategy.captured_dag_graph(dag)) == 1 &&
    capture.observation is QueryObservation(_) &&
    run.configuration is DirectConfiguration(_) &&
    @strategy.captured_task_source_matches(dag, task, capture.source) else {
    return false
  }
  // Source availability can call the original transport verifier. Check the
  // actual custody after it returns, including synchronous close or failure.
  guard !run.closed &&
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
