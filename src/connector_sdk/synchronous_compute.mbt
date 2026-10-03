///|
/// Conservative physical capacity for a no-I/O execution. This is a declaration
/// to be checked against the selected envelope and reserved by the Host, not an
/// allocation token or a replacement for the request's logical limits.
pub(all) struct SynchronousComputeCapacity {
  retained_bytes : Int64
  execution_bytes : Int64
}

///|
pub(all) enum SynchronousComputeFailure {
  Compute(FixedComputeIssue)
  MissingOutput
}

///|
/// Connector-author wiring for a synchronous, no-I/O realization. This is not
/// a success receipt or permission to bypass a Host's task admission. The exact
/// selected candidate and private payload remain bound across type erasure.
struct SynchronousCompute {
  candidate : FixedComputeCandidate
  capacity : SynchronousComputeCapacity
  join_output_ceilings : Array[(Int, Int64)]
  aggregate_output_ceilings : Array[AggregateOutputCeiling]
  analytic_envelopes : Array[AnalyticEnvelope]
  execute : () -> Result[@execution.CompletedOutput, SynchronousComputeFailure]
  mut started : Bool
}

///|
/// Only trusted installed connector code supplies execution. Ordinary Host
/// requests do not supply callbacks. A returned completion still needs common
/// owner, port, input-identity and retention checks before task publication.
pub fn[T] bind_synchronous_compute(
  choice : FixedComputeChoice,
  prepared : PreparedCompute[T],
  capacity : SynchronousComputeCapacity,
  join_output_ceilings : Array[(Int, Int64)],
  execute : (T) -> Result[@execution.CompletedOutput, SynchronousComputeFailure],
  aggregate_output_ceilings? : Array[AggregateOutputCeiling] = [],
  analytic_envelopes? : Array[AnalyticEnvelope] = [],
) -> Result[SynchronousCompute, FixedComputeIssue] {
  guard fixed_compute_choice_payload(choice, prepared) is Some(payload) else {
    return Err(NotSelected)
  }
  if capacity.retained_bytes < 0L || capacity.execution_bytes < 0L {
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
    execute: fn() { execute(payload) },
    started: false,
  })
}

///|
pub fn synchronous_compute_candidate(
  compute : SynchronousCompute,
) -> FixedComputeCandidate {
  compute.candidate
}

///|
pub fn synchronous_compute_capacity(
  compute : SynchronousCompute,
) -> SynchronousComputeCapacity {
  compute.capacity
}

///|
pub fn synchronous_compute_join_output_ceiling(
  compute : SynchronousCompute,
  step : Int,
) -> Int64? {
  step_ceiling(compute.join_output_ceilings, step)
}

///|
pub fn synchronous_compute_aggregate_output_ceiling(
  compute : SynchronousCompute,
  step : Int,
  aggregate : String,
  unit : AggregateOutputUnit,
) -> Int64? {
  find_aggregate_output_ceiling(
    compute.aggregate_output_ceilings,
    step,
    aggregate,
    unit,
  )
}

///|
pub fn synchronous_compute_analytic_envelope(
  compute : SynchronousCompute,
  step : Int,
) -> AnalyticEnvelope? {
  find_analytic_envelope(compute.analytic_envelopes, step)
}

///|
pub fn synchronous_compute_available(compute : SynchronousCompute) -> Bool {
  !compute.started && compute.candidate.registration.owner.live
}

///|
/// Called after reservation by the owning Host. No fresh source access or
/// asynchronous resource lifetime is permitted by this realization contract.
pub fn execute_synchronous_compute(
  compute : SynchronousCompute,
) -> Result[@execution.CompletedOutput, SynchronousComputeFailure] {
  if !synchronous_compute_available(compute) {
    return Err(Compute(NotSelected))
  }
  compute.started = true
  for input in compute.candidate.request.inputs {
    if !@execution.fixed_relation_read_available(input) {
      return Err(Compute(InputUnavailable))
    }
  }
  (compute.execute)()
}
