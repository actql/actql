///|
/// Concrete eight-part Compute inventory. Resident shared work is represented
/// by the exact selected profile; it does not change the task work inventory.
pub fn estimate_duckdb_task_offer(
  run : @strategy.CapturedDAG,
  task : Int,
  registration : @connector.CapabilityRegistration,
  lines : Array[@cost.SerialEstimateLine],
  capacity : @strategy.PhysicalEnvelope,
  max_work : Int,
  resident? : @strategy.ResidentProfile,
) -> Result[@strategy.TaskOffer, @strategy.SearchIssue] {
  let base = match
    @strategy.prepare_task_offer(
      run, task, registration, 8, lines, capacity, max_work,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match resident {
    Some(profile) =>
      @strategy.resident_task_offer(run, base, profile, capacity.retained_bytes)
    None => Ok(base)
  }
}
