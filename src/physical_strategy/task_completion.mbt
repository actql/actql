///|
/// The common success boundary for synchronous and asynchronous realizations.
/// This stays private: the caller must already own a verified execution and its
/// allocation. Connector-specific publication runs only after exact output-port
/// and input-binding checks, and cannot expose a DAG success without retention.
fn publish_task_completion(
  run : CapturedDAG,
  task : Int,
  output : @execution.CompletedOutput,
  holding : @resources.Holding,
  mismatch : RunIssue,
  publish : (@execution.CompletedOutput) -> Result[Unit, RunIssue],
) -> Result[Unit, RunIssue] {
  if run.stopped {
    return Err(Stopped)
  }
  guard captured_task_target(run, task) is Some(target) &&
    @execution.completed_output_matches_port(
      output,
      run.graph.owners[task],
      target,
    ) &&
    captured_output_inputs_match(run, task, output) else {
    return Err(mismatch)
  }
  if !@resources.holding_available(run.ledger, holding) {
    return Err(Physical(InvalidCharge))
  }
  match publish(output) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  // No connector callback or fallible operation splits retention attachment
  // from success. Completed descendants do not borrow upstream availability.
  run.resources[task] = Some({
    holding: Some(holding),
    parents: task_parents(run, task),
  })
  run.completed[task] = Some(output)
  run.done[task] = true
  clear_captured_inputs(run, task)
  run.generation += 1
  Ok(())
}
