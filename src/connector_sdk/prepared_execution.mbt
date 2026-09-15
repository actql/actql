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
/// Trusted installed implementation operations. The Host owns the lifecycle:
/// these report implementation facts, not permission to publish or free budget.
/// P is the Host's opaque, scoped publication authority, never a success Bool.
pub(all) struct ExecutionOperations[E, P] {
  cancel : () -> Unit
  dispose : () -> Unit
  settled : () -> Unit
  released : () -> Unit
  ready : () -> Result[Unit, E]
  finish : () -> Result[@execution.CompletedOutput, E]
  publish : (P) -> Result[Unit, E]
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
struct PreparedExecution[T, E, P] {
  candidate : FixedComputeCandidate
  capacity : ExecutionCapacity
  join_output_ceilings : Array[(Int, Int64)]
  prepare : () -> Result[(T, ExecutionOperations[E, P]), E]
  mut started : Bool
}

///|
/// Connector-author SDK, not a Program-supplied callback. Actual work must wait
/// until the owning Host reserves capacity and registers the returned attempt.
pub fn[T, E, P, U] bind_prepared_execution(
  choice : FixedComputeChoice,
  prepared : PreparedCompute[U],
  capacity : ExecutionCapacity,
  join_output_ceilings : Array[(Int, Int64)],
  prepare : (U) -> Result[(T, ExecutionOperations[E, P]), E],
) -> Result[PreparedExecution[T, E, P], FixedComputeIssue] {
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
  Ok({
    candidate: prepared.candidate,
    capacity,
    join_output_ceilings: ceilings,
    prepare: fn() { prepare(payload) },
    started: false,
  })
}

///|
pub fn[T, E, P] prepared_execution_candidate(
  prepared : PreparedExecution[T, E, P],
) -> FixedComputeCandidate {
  prepared.candidate
}

///|
pub fn[T, E, P] prepared_execution_capacity(
  prepared : PreparedExecution[T, E, P],
) -> ExecutionCapacity {
  prepared.capacity
}

///|
pub fn[T, E, P] prepared_execution_join_output_ceiling(
  prepared : PreparedExecution[T, E, P],
  step : Int,
) -> Int64? {
  step_ceiling(prepared.join_output_ceilings, step)
}

///|
pub fn[T, E, P] prepared_execution_available(
  prepared : PreparedExecution[T, E, P],
) -> Bool {
  !prepared.started && prepared.candidate.registration.owner.live
}

///|
/// Host implementation entry, after reservation. A rejected reservation must
/// not call this function and therefore does not consume the preparation.
pub fn[T, E, P] start_prepared_execution(
  prepared : PreparedExecution[T, E, P],
) -> Result[(T, ExecutionOperations[E, P]), ExecutionPreparationIssue[E]] {
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
