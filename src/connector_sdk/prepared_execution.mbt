///|
/// Required task-local capacity, not an estimate or an allocation token. Shared
/// resource capacity is admitted separately by the owning Host.
pub(all) struct ExecutionCapacity {
  transfer_bytes : Int64
  retained_bytes : Int64
  scratch_bytes : Int64
  execution_bytes : Int64
}

///|
pub(all) enum ExecutionPreparationIssue[E] {
  Candidate(FixedComputeIssue)
  Implementation(E)
}

///|
/// The selected private payload is captured without casts or provider tags.
/// T is the implementation's transport handle; the common driver need not
/// inspect or retain it. Construction and preparation perform no external I/O.
struct PreparedExecution[T, E] {
  candidate : FixedComputeCandidate
  capacity : ExecutionCapacity
  join_output_ceilings : Array[(Int, Int64)]
  aggregate_output_ceilings : Array[AggregateOutputCeiling]
  analytic_envelopes : Array[AnalyticEnvelope]
  prepare : () -> Result[(T, ExecutionLifecycleOperations[E]), E]
  retained_bytes : () -> Result[Int64, E]
  mut started : Bool
}

///|
/// Bind materializing work without granting a Connector its own finish or
/// publication authority. The Host receives the exact typed output separately
/// at the common completion boundary.
pub fn[T, E, U] bind_prepared_materializing_execution(
  choice : FixedComputeChoice,
  prepared : PreparedCompute[U],
  capacity : ExecutionCapacity,
  join_output_ceilings : Array[(Int, Int64)],
  prepare : (U) -> Result[(T, ExecutionLifecycleOperations[E]), E],
  retained_bytes? : () -> Result[Int64, E],
  aggregate_output_ceilings? : Array[AggregateOutputCeiling] = [],
  analytic_envelopes? : Array[AnalyticEnvelope] = [],
) -> Result[PreparedExecution[T, E], FixedComputeIssue] {
  guard fixed_compute_choice_payload(choice, prepared) is Some(payload) else {
    return Err(NotSelected)
  }
  if capacity.transfer_bytes < 0L ||
    capacity.retained_bytes < 0L ||
    capacity.scratch_bytes < 0L ||
    capacity.execution_bytes < capacity.scratch_bytes {
    return Err(InvalidLimits)
  }
  let steps = @pipeline.step_count(
    @lower.pipeline(@lower.bound_preparation(prepared.candidate.request.owner)),
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
/// Installed implementation accounting after preparation, before holding
/// attachment. The original reservation remains intact until settlement.
/// This reports physical capacity, not output validity or completion evidence.
pub fn[T, E] prepared_execution_retained_bytes(
  prepared : PreparedExecution[T, E],
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
pub fn[T, E] prepared_execution_candidate(
  prepared : PreparedExecution[T, E],
) -> FixedComputeCandidate {
  prepared.candidate
}

///|
pub fn[T, E] prepared_execution_capacity(
  prepared : PreparedExecution[T, E],
) -> ExecutionCapacity {
  prepared.capacity
}

///|
pub fn[T, E] prepared_execution_join_output_ceiling(
  prepared : PreparedExecution[T, E],
  step : Int,
) -> Int64? {
  step_ceiling(prepared.join_output_ceilings, step)
}

///|
pub fn[T, E] prepared_execution_aggregate_output_ceiling(
  prepared : PreparedExecution[T, E],
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
pub fn[T, E] prepared_execution_analytic_envelope(
  prepared : PreparedExecution[T, E],
  step : Int,
) -> AnalyticEnvelope? {
  find_analytic_envelope(prepared.analytic_envelopes, step)
}

///|
pub fn[T, E] prepared_execution_available(
  prepared : PreparedExecution[T, E],
) -> Bool {
  !prepared.started && prepared.candidate.registration.owner.live
}

///|
/// Host implementation entry, after reservation. A rejected reservation must
/// not call this function and therefore does not consume the preparation.
pub fn[T, E] start_prepared_execution_lifecycle(
  prepared : PreparedExecution[T, E],
) -> Result[(T, ExecutionLifecycleOperations[E]), ExecutionPreparationIssue[E]] {
  if !prepared_execution_available(prepared) {
    return Err(Candidate(NotSelected))
  }
  prepared.started = true
  for input in prepared.candidate.request.inputs {
    if !@execution.producer_read_available(input) {
      return Err(Candidate(InputUnavailable))
    }
  }
  match (prepared.prepare)() {
    Ok(value) => Ok(value)
    Err(issue) => Err(Implementation(issue))
  }
}
