///|
/// Concrete eight-part Compute inventory. Resident shared work is represented
/// by the exact selected profile; it does not change the task work inventory.
/// Independent file output adds one work item and holding ceiling for either
/// realization. Its bytes are not part of the resident DB-copy allocation.
pub fn estimate_duckdb_task_offer(
  run : @strategy.CapturedDAG,
  task : Int,
  registration : @connector.CapabilityRegistration,
  lines : Array[@cost.SerialEstimateLine],
  capacity : @strategy.PhysicalEnvelope,
  max_work : Int,
  resident? : @strategy.ResidentProfile,
  retained_output? : (Int64, Int64?),
) -> Result[@strategy.TaskOffer, @strategy.SearchIssue] {
  let copy_bytes = capacity.retained_bytes
  let (lines, capacity, slots) = match retained_output {
    None => (lines, capacity, duckdb_dispatch_work_slots())
    Some((bytes, milliseconds)) => {
      if bytes <= 0L ||
        bytes > 2147483647L ||
        capacity.retained_bytes < 0L ||
        bytes > 9223372036854775807L - capacity.retained_bytes ||
        (milliseconds is Some(ms) && ms < 0L) {
        return Err(InvalidCapacity)
      }
      let with_file = lines.copy()
      with_file.push({
        work_slots: [duckdb_dispatch_work_slots()],
        milliseconds,
      })
      (
        with_file,
        { ..capacity, retained_bytes: capacity.retained_bytes + bytes, },
        duckdb_dispatch_work_slots() + 1,
      )
    }
  }
  let base = match
    @strategy.prepare_task_offer(
      run, task, registration, slots, lines, capacity, max_work,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match resident {
    Some(profile) =>
      @strategy.resident_task_offer(run, base, profile, copy_bytes)
    None => Ok(base)
  }
}

///|
pub fn duckdb_dispatch_work_slots() -> Int {
  8
}
