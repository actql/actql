///|
/// Restore Compute from the exact independent receiver holding, preserving
/// the original Effect candidate and dependency pins. This grants no apply
/// permission and performs no acquisition. Current physical custody and the
/// exclusive consumer start claim remain with the existing calling owners.
pub fn open_retained_effect_task_dag(
  checked : CheckedEffectRunDAG,
  projection : RetainedTaskProjection,
  output : @execution.CompletedOutput,
  ledger : @resources.Ledger,
  canonical_wire_bytes~ : Int,
) -> Result[CapturedEffectRunDAG, RunIssue] {
  if !physical_equal(projection.original, checked.computation.graph_value()) ||
    projection.producer != 0 ||
    projection.consumer != 1 {
    return Err(ForeignCandidate)
  }
  match prepare_retained_effect_task_projection(checked) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let dependencies = match
    effect_dependency_ports(checked.computation, 4096, 65536, 64) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let captured = match
    open_retained_task_dag(projection, output, ledger, canonical_wire_bytes~) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // This limited view preserves both original task coordinates exactly.
  for dependency in dependencies {
    captured.effect_dependency_outputs[dependency.task] = true
  }
  Ok({ checked, captured, })
}

///|
/// The caller retains the independently admitted predecessor and its charged
/// physical custody. The existing DAG owns only this consumer's execution.
pub fn open_retained_task_dag(
  value : RetainedTaskProjection,
  output : @execution.CompletedOutput,
  ledger : @resources.Ledger,
  canonical_wire_bytes~ : Int,
) -> Result[CapturedDAG, RunIssue] {
  if canonical_wire_bytes < 0 ||
    !retained_task_projection_matches_output(value, output) {
    return Err(ForeignCapture)
  }
  open_checked_dag(
    value.graph,
    [],
    ledger,
    [],
    completed=[(0, output)],
    root_wire_bytes=Some(canonical_wire_bytes),
  )
}

///|
pub fn prepare_retained_task_projection(
  original : CheckedDAG,
  consumer : Int,
) -> Result[RetainedTaskProjection, RunIssue] {
  match @graph.prepare_retained_task_projection(original, consumer) {
    Ok(value) => Ok(value)
    Err(UnsupportedGraph) => Err(UnsupportedGraph)
  }
}

///|
pub fn prepare_retained_effect_task_projection(
  checked : CheckedEffectRunDAG,
) -> Result[RetainedTaskProjection, RunIssue] {
  match @graph.prepare_retained_effect_task_projection(checked) {
    Ok(value) => Ok(value)
    Err(UnsupportedGraph) => Err(UnsupportedGraph)
  }
}
