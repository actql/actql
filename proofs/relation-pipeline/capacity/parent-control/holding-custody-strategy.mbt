///|
/// Retain only the diagnostic token alias. This does not acquire a Result pin,
/// extend the allocation's Ledger liveness, or establish physical destruction.
pub fn native_holding_custody_token(
  run : CapturedDAG,
  task : Int,
  output : @execution.ManagedCompletedOutput[Int],
) -> @resources.Holding? {
  guard managed_task_output_reference(run, task) is Some(reference) &&
    @execution.managed_completed_reference_matches(reference, output) &&
    run.resources.get(task).bind(value => value) is Some(resource) &&
    resource.holding is Some(holding) &&
    @resources.holding_available(run.ledger, holding) else {
    return None
  }
  Some(holding)
}

///|
pub fn native_holding_custody_observation(
  run : CapturedDAG,
  task : Int,
  token : @resources.Holding,
  output : @execution.ManagedCompletedOutput[Int],
  phase : String,
) -> String {
  let resource = run.resources.get(task).bind(value => value)
  let same_token = match resource {
    Some(resource) =>
      match resource.holding {
        Some(actual) => physical_equal(actual, token)
        None => false
      }
    None => false
  }
  let slot_matches = match managed_task_output_reference(run, task) {
    Some(reference) =>
      @execution.managed_completed_reference_matches(reference, output)
    None => false
  }
  let mut children = 0
  for child in run.resources {
    if child is Some(child) && child.parents.contains(task) {
      children += 1
    }
  }
  let running = run.running is Some((active, _)) &&
    run.graph.data.any(edge => edge.consumer == active && edge.producer == task)
  "ACTQL_HOLDING_CUSTODY:{\"phase\":\"" +
  phase +
  "\",\"task\":" +
  task.to_string() +
  "," +
  @resources.native_holding_custody_details(run.ledger, token) +
  ",\"resourcePresent\":" +
  (resource is Some(_)).to_string() +
  ",\"sameToken\":" +
  same_token.to_string() +
  ",\"slotMatches\":" +
  slot_matches.to_string() +
  ",\"portLive\":" +
  run.lifetimes[task].live.to_string() +
  ",\"pins\":" +
  run.lifetimes[task].pins.to_string() +
  ",\"children\":" +
  children.to_string() +
  ",\"runningConsumer\":" +
  running.to_string() +
  ",\"schedulerGeneration\":" +
  run.generation.to_string() +
  ",\"outputAvailable\":" +
  @execution.managed_completed_output_available(output).to_string() +
  ",\"outputBytes\":" +
  @execution.managed_completed_output_storage_bytes(output)
  .unwrap_or(-1L)
  .to_string() +
  ",\"heldBytes\":" +
  @resources.ledger_usage(run.ledger).held_bytes.to_string() +
  "}"
}
