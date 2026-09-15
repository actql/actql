///|
/// Exact shared-input admission for a single task. Construction neither
/// allocates an output nor claims the borrowers; common start owns both.
struct ResidentExecution {
  owner : StrategyOfferOwner
  task : Int
  candidate : @connector.FixedComputeCandidate
  inputs : ResidentInputs
  limits : @duckdb_compute.DuckDBComputeLimits
  transport : @duckdb.TransportColumnLimits
  retention : Int64
  scratch : Int64
  mut pending : ResidentPendingOutput?
}

///|
pub fn prepare_resident_execution(
  run : CapturedDAG,
  task : Int,
  choice : @connector.FixedComputeChoice,
  prepared : @connector.PreparedCompute[@duckdb.FixedCompute],
  inputs : ResidentInputs,
  limits : @duckdb_compute.DuckDBComputeLimits,
  transport : @duckdb.TransportColumnLimits,
) -> Result[ResidentExecution, RunIssue] {
  guard @connector.fixed_compute_choice_payload(choice, prepared)
    is Some(compute) &&
    resident_inputs_match(run, inputs, task, compute) else {
    return Err(ForeignCandidate)
  }
  guard @duckdb_compute.duckdb_task_retention_capacity(limits)
    is Some(retention) &&
    @duckdb_compute.duckdb_task_scratch_capacity(limits, transport)
    is Some(scratch) else {
    return Err(Physical(InvalidLimits))
  }
  Ok({
    owner: run.offer_owner,
    task,
    candidate: @connector.prepared_compute_candidate(prepared),
    inputs,
    limits,
    transport,
    retention,
    scratch,
    pending: None,
  })
}

///|
fn resident_execution_capacity(
  run : CapturedDAG,
  task : Int,
  candidate : @connector.FixedComputeCandidate,
  capacity : @connector.ExecutionCapacity,
  resident : ResidentExecution?,
) -> Result[Int64, RunIssue] {
  let selected = run.strategy.bind(revision => {
    strategy_resident_profile(revision, task)
  })
  match (selected, resident) {
    (None, None) => Ok(0L)
    (Some(selected), Some(resource)) => {
      guard physical_equal(resource.owner, run.offer_owner) &&
        resource.task == task &&
        physical_equal(resource.candidate, candidate) &&
        resource.pending is None &&
        resource.inputs.environment.profile is Some(actual) &&
        physical_equal(selected, actual) &&
        resident_inputs_match(
          run,
          resource.inputs,
          task,
          resource.inputs.compute,
        ) else {
        return Err(ForeignCandidate)
      }
      if capacity.retained_bytes < resource.retention ||
        capacity.scratch_bytes < resource.scratch {
        return Err(Physical(InvalidCharge))
      }
      Ok(
        @resources.shared_capacity_usage(resource.inputs.environment.capacity).capacity,
      )
    }
    _ => Err(ForeignCandidate)
  }
}

///|
fn activate_resident_execution(
  run : CapturedDAG,
  resource : ResidentExecution,
  retention : Int64,
) -> Result[Unit, RunIssue] {
  match
    prepare_resident_output(
      run,
      resource.inputs.environment,
      @duckdb.fixed_compute_query(resource.inputs.compute),
      retention,
      resource.limits,
      resource.transport.max_bytes,
    ) {
    Err(issue) => Err(issue)
    Ok(pending) => {
      resource.pending = Some(pending)
      Ok(())
    }
  }
}

///|
fn abandon_resident_execution(resource : ResidentExecution) -> Unit {
  if resource.pending is Some(pending) {
    @resources.retire_shared_capacity(pending.allocation)
    @resources.release_shared_capacity(pending.allocation) |> ignore
    resource.pending = None
  }
}
