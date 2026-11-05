///|
/// The closed Model owner supplies its actual completed task, held by its
/// original output use. Captured Sources keep their same original slots and
/// holdings; the saved Model input does not become a keyed observation.
pub fn open_multi_captured_effect_run_retained_model_dag(
  checked : CheckedEffectRunDAG,
  sources : Array[(Int, @query.CapturedInputSource)],
  ledger : @resources.Ledger,
  task : Int,
  model_step : Int,
  output : @execution.CompletedOutput,
) -> Result[CapturedEffectRunDAG, RunIssue] {
  let graph = checked.computation.graph_value()
  if sources.length() != graph.captured_prefix_value() ||
    !graph_keyed_model_plan_inputs_complete(graph, task, model_step) {
    return Err(ForeignCapture)
  }
  let dependencies = match
    effect_dependency_ports(checked.computation, 4096, 65536, 64) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let captured = match
    open_checked_dag(
      graph,
      sources,
      ledger,
      [],
      retained_model=Some((task, model_step, output)),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  for dependency in dependencies {
    captured.effect_dependency_outputs[dependency.task] = true
  }
  Ok({ checked, captured, })
}
