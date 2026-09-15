///|
/// Exact shared-input admission for a single task. Construction neither
/// allocates an output nor claims the borrowers; common start owns both.
struct ResidentExecution {
  owner : StrategyOfferOwner
  task : Int
  candidate : @connector.FixedComputeCandidate
  inputs : ResidentInputs
  prepare_output : (Int) -> Result[
    (@execution.CompletedOutput) -> Result[@execution.ProducerStorage, RunIssue],
    RunIssue,
  ]
  retention : Int64
  scratch : Int64
  mut pending : ResidentPendingOutput?
}

///|
pub fn[T, P] prepare_resident_execution(
  run : CapturedDAG,
  task : Int,
  choice : @connector.FixedComputeChoice,
  prepared : @connector.PreparedCompute[P],
  inputs : ResidentInputs,
  retention : Int64,
  scratch : Int64,
  prepare_output : (Int) -> Result[T, RunIssue],
  bind_output : (T, @execution.CompletedOutput) -> Result[
    @execution.ProducerStorage,
    RunIssue,
  ],
) -> Result[ResidentExecution, RunIssue] {
  guard @connector.fixed_compute_choice_payload(choice, prepared) is Some(_) &&
    resident_inputs_match(
      run,
      inputs,
      task,
      @connector.prepared_compute_candidate(prepared),
    ) else {
    return Err(ForeignCandidate)
  }
  if retention < 0L || scratch < 0L {
    return Err(Physical(InvalidLimits))
  }
  Ok({
    owner: run.offer_owner,
    task,
    candidate: @connector.prepared_compute_candidate(prepared),
    inputs,
    prepare_output: fn(ordinal) {
      prepare_output(ordinal).map(plan => {
        fn(output) { bind_output(plan, output) }
      })
    },
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
        resident_inputs_match(run, resource.inputs, task, resource.candidate) else {
        return Err(ForeignCandidate)
      }
      if capacity.retained_bytes < resource.retention ||
        capacity.scratch_bytes < resource.scratch {
        return Err(Physical(InvalidCharge))
      }
      guard run.strategy.bind(revision => {
          revision.choices.get(task).bind(value => value)
        })
        is Some(offer) &&
        resource.retention <= offer.resident_output_bytes else {
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
) -> Result[Unit, RunIssue] {
  match
    prepare_resident_output(
      run,
      resource.inputs.environment,
      resource.retention,
      resource.prepare_output,
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
