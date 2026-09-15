///|
/// The reservation is real; an environment is usable only after trusted
/// provision confirms the selected profile. No future DB handle is fabricated.
struct ResidentEnvironment {
  owner : StrategyOfferOwner
  capacity : ResidentCapacity
  revision : StrategyRevision
  mut ready : Bool
  mut settled : Bool
  tables : Array[ResidentTable?]
  mut next_table : Int
  allocations : Array[ResidentAllocation]
  mut importing : Bool
  profile : ResidentProfile?
}

///|
pub fn begin_resident_environment(
  run : CapturedDAG,
  task : Int,
  database_bytes : Int64,
) -> Result[ResidentEnvironment, RunIssue] {
  if run.stopped {
    return Err(Stopped)
  }
  if next_captured_task(run) != Some(task) {
    return Err(NotReady)
  }
  if run.resident_environment is Some(_) {
    return Err(NotReady)
  }
  guard run.strategy is Some(revision) else { return Err(ForeignCandidate) }
  guard strategy_resident_profile(revision, task) is Some(profile) else {
    return Err(ForeignCandidate)
  }
  guard strategy_task_envelope(run, task) is Some(envelope) else {
    return Err(ForeignCandidate)
  }
  if database_bytes != profile.database_bytes ||
    database_bytes > envelope.execution_bytes {
    return Err(Physical(InvalidCharge))
  }
  let capacity = match reserve_resident_capacity(run.ledger, database_bytes) {
    Ok(value) => value
    Err(issue) => return Err(Physical(issue))
  }
  let environment = {
    owner: run.offer_owner,
    capacity,
    revision,
    ready: false,
    settled: false,
    tables: Array::make(run.graph.owners.length(), None),
    next_table: 0,
    allocations: [],
    importing: false,
    profile: Some(profile),
  }
  run.resident_environment = Some(environment)
  Ok(environment)
}

///|
fn owns_resident_environment(
  run : CapturedDAG,
  env : ResidentEnvironment,
) -> Bool {
  physical_equal(run.offer_owner, env.owner) &&
  run.resident_environment is Some(owned) &&
  physical_equal(owned, env)
}

///|
fn resident_provision_pending(run : CapturedDAG) -> Bool {
  run.resident_environment is Some(env) &&
  ((!env.ready && !env.capacity.closing && !env.settled) || env.importing)
}

///|
/// Trusted resource-provider acknowledgement. Numeric equality alone cannot
/// attach another environment: the exact run-owned provision intent is required.
pub fn confirm_resident_environment(
  run : CapturedDAG,
  env : ResidentEnvironment,
  database_bytes : Int64,
) -> Result[Unit, RunIssue] {
  if !owns_resident_environment(run, env) {
    return Err(ForeignCandidate)
  }
  if run.stopped || env.capacity.closing || env.settled {
    return Err(Stopped)
  }
  if env.ready || database_bytes != env.capacity.capacity {
    return Err(Physical(InvalidCharge))
  }
  guard run.strategy is Some(revision) && physical_equal(revision, env.revision) else {
    return Err(ForeignCandidate)
  }
  env.ready = true
  run.generation += 1
  Ok(())
}

///|
pub fn resident_environment_available(
  run : CapturedDAG,
  env : ResidentEnvironment,
) -> Bool {
  owns_resident_environment(run, env) &&
  env.ready &&
  !env.capacity.closing &&
  !env.settled
}

///|
/// Invalidates only the DB representation. Independently completed Host results
/// are untouched. Cleanup acknowledgement is a separate operation.
pub fn close_resident_environment(
  run : CapturedDAG,
  env : ResidentEnvironment,
) -> Result[Unit, @resources.LedgerIssue] {
  if !owns_resident_environment(run, env) {
    return Err(ForeignOwner)
  }
  if env.settled {
    return Ok(())
  }
  if !env.capacity.closing {
    if !env.ready {
      // Failed or abandoned provision is not loss of a previously usable copy.
      // Preserve reservation/cleanup, but never reopen dispatch via reselection.
      stop_captured_dag(run)
    }
    env.ready = false
    // A lost site cannot leave a prepared dispatch authorized by stale costs
    // and residency assumptions. Existing completions and history survive.
    run.strategy = None
    run.generation += 1
    close_resident_capacity(env.capacity)
  } else {
    Ok(())
  }
}

///|
pub fn settle_resident_environment(
  run : CapturedDAG,
  env : ResidentEnvironment,
) -> Result[Unit, @resources.LedgerIssue] {
  if !owns_resident_environment(run, env) {
    return Err(ForeignOwner)
  }
  if env.settled {
    return Ok(())
  }
  if !env.capacity.closing {
    return Err(InvalidCharge)
  }
  if env.importing {
    return Err(InvalidCharge)
  }
  // Confirmed DB destruction also removes provisional tables whose task failed
  // before publication. Do not orphan their reservations with disposed attempts.
  for allocation in env.allocations {
    if allocation.readers != 0 {
      return Err(InvalidCharge)
    }
  }
  for allocation in env.allocations {
    if !allocation.released {
      retire_resident_capacity(allocation)
      release_resident_capacity(allocation) |> ignore
    }
  }
  match settle_resident_capacity(env.capacity) {
    Err(issue) => Err(issue)
    Ok(_) => {
      env.settled = true
      env.allocations.clear()
      for i in 0..<env.tables.length() {
        env.tables[i] = None
      }
      run.resident_environment = None
      run.generation += 1
      Ok(())
    }
  }
}
