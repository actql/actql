///|
/// Lifecycle facts for a managed-profile installed execution. Managed output
/// verification/publication uses its typed completion port, so no legacy
/// CompletedOutput finisher or publication hook exists here.
pub(all) struct ManagedExecutionOperations[E] {
  cancel : () -> Unit
  dispose : () -> Unit
  settled : () -> Unit
  retention_released : () -> Bool
  released : () -> Unit
  ready : () -> Result[Unit, E]
}

///|
/// Selected managed private payload plus common physical capacity. Preparation
/// performs no external I/O; the Host reserves and registers the task before
/// calling the installed implementation.
struct PreparedManagedExecution[I, T, E] {
  candidate : ManagedFixedComputeCandidate[I]
  capacity : ExecutionCapacity
  join_output_ceilings : Array[(Int, Int64)]
  aggregate_output_ceilings : Array[AggregateOutputCeiling]
  analytic_envelopes : Array[AnalyticEnvelope]
  prepare : () -> Result[(T, ManagedExecutionOperations[E]), E]
  retained_bytes : () -> Result[Int64, E]
  mut started : Bool
}

///|
pub fn[I, T, E, P] bind_prepared_managed_execution(
  choice : ManagedFixedComputeChoice[I],
  prepared : PreparedManagedCompute[I, P],
  capacity : ExecutionCapacity,
  join_output_ceilings : Array[(Int, Int64)],
  prepare : (P) -> Result[(T, ManagedExecutionOperations[E]), E],
  retained_bytes? : () -> Result[Int64, E],
  aggregate_output_ceilings? : Array[AggregateOutputCeiling] = [],
  analytic_envelopes? : Array[AnalyticEnvelope] = [],
) -> Result[PreparedManagedExecution[I, T, E], FixedComputeIssue] {
  guard managed_fixed_compute_choice_payload(choice, prepared) is Some(payload) else {
    return Err(NotSelected)
  }
  if capacity.transfer_bytes < 0L ||
    capacity.retained_bytes < 0L ||
    capacity.scratch_bytes < 0L ||
    capacity.execution_bytes < capacity.scratch_bytes {
    return Err(InvalidLimits)
  }
  let owner = managed_fixed_compute_request_owner(
    managed_fixed_compute_candidate_request(prepared.candidate),
  )
  let steps = @pipeline.step_count(
    @lower.pipeline(@lower.bound_preparation(owner)),
  )
  guard snapshot_step_ceilings(join_output_ceilings, steps) is Some(ceilings) else {
    return Err(InvalidLimits)
  }
  guard snapshot_aggregate_output_ceilings(aggregate_output_ceilings, steps)
    is Some(aggregate_ceilings) else {
    return Err(InvalidLimits)
  }
  guard snapshot_analytic_envelopes(analytic_envelopes, steps)
    is Some(analytic_envelopes) else {
    return Err(InvalidLimits)
  }
  Ok({
    candidate: prepared.candidate,
    capacity,
    join_output_ceilings: ceilings,
    aggregate_output_ceilings: aggregate_ceilings,
    analytic_envelopes,
    prepare: fn() { prepare(payload) },
    retained_bytes: retained_bytes.unwrap_or(fn() {
      Ok(capacity.retained_bytes)
    }),
    started: false,
  })
}

///|
pub fn[I, T, E] prepared_managed_execution_retained_bytes(
  prepared : PreparedManagedExecution[I, T, E],
) -> Result[Int64, ExecutionPreparationIssue[E]] {
  if !prepared.started {
    return Err(Candidate(NotSelected))
  }
  match (prepared.retained_bytes)() {
    Err(issue) => Err(Implementation(issue))
    Ok(bytes) =>
      if bytes < 0L || bytes > prepared.capacity.retained_bytes {
        Err(Candidate(InvalidLimits))
      } else {
        Ok(bytes)
      }
  }
}

///|
pub fn[I, T, E] prepared_managed_execution_candidate(
  prepared : PreparedManagedExecution[I, T, E],
) -> ManagedFixedComputeCandidate[I] {
  prepared.candidate
}

///|
pub fn[I, T, E] prepared_managed_execution_capacity(
  prepared : PreparedManagedExecution[I, T, E],
) -> ExecutionCapacity {
  prepared.capacity
}

///|
pub fn[I, T, E] prepared_managed_execution_join_output_ceiling(
  prepared : PreparedManagedExecution[I, T, E],
  step : Int,
) -> Int64? {
  step_ceiling(prepared.join_output_ceilings, step)
}

///|
pub fn[I, T, E] prepared_managed_execution_aggregate_output_ceiling(
  prepared : PreparedManagedExecution[I, T, E],
  step : Int,
  aggregate : String,
  unit : AggregateOutputUnit,
) -> Int64? {
  find_aggregate_output_ceiling(
    prepared.aggregate_output_ceilings,
    step,
    aggregate,
    unit,
  )
}

///|
pub fn[I, T, E] prepared_managed_execution_analytic_envelope(
  prepared : PreparedManagedExecution[I, T, E],
  step : Int,
) -> AnalyticEnvelope? {
  find_analytic_envelope(prepared.analytic_envelopes, step)
}

///|
pub fn[I, T, E] prepared_managed_execution_available(
  prepared : PreparedManagedExecution[I, T, E],
) -> Bool {
  !prepared.started && prepared.candidate.registration.owner.live
}

///|
/// Called only after common reservation. Every exact managed input must still
/// be live; a selected candidate never freezes Store availability.
pub fn[I, T, E] start_prepared_managed_execution(
  prepared : PreparedManagedExecution[I, T, E],
) -> Result[(T, ManagedExecutionOperations[E]), ExecutionPreparationIssue[E]] {
  if !prepared_managed_execution_available(prepared) {
    return Err(Candidate(NotSelected))
  }
  prepared.started = true
  let request = prepared.candidate.request
  for input in request.inputs {
    if !@execution.managed_producer_read_available(input) {
      return Err(Candidate(InputUnavailable))
    }
  }
  match (prepared.prepare)() {
    Ok(value) => Ok(value)
    Err(issue) => Err(Implementation(issue))
  }
}
