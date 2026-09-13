///|
/// Serial inventory: preparation, receiving admission, computation, retained
/// output, cleanup. The existing driver still enforces selected fragment limits.
pub fn local_fixed_compute_candidate(
  registration : CapabilityRegistration,
  request : FixedComputeRequest,
  sequence : @execution.GeneratedSequence,
  estimates : Array[@cost.SerialEstimateLine],
  quantities : QueryQuantities,
  max_entries : Int,
) -> Result[PreparedCompute[@execution.GeneratedSequence], FixedComputeIssue] {
  if request.capacity.common_fragment is Some(common) &&
    !physical_equal(common, sequence) {
    return Err(ForeignPreparation)
  }
  if !physical_equal(
      @execution.generated_sequence_owner(sequence),
      @execution.producer_read_receiver(request.input),
    ) {
    return Err(ForeignPreparation)
  }
  bind_compute_candidate(
    registration, request, sequence, 5, estimates, quantities, max_entries,
  )
}

///|
pub fn execute_local_fixed_compute(
  choice : FixedComputeChoice,
  prepared : PreparedCompute[@execution.GeneratedSequence],
  limits : @execution.SequenceExecutionLimits,
  measurement~ : @execution.FixedInputGuardMeasureLimits,
) -> Result[@execution.CompletedSequence, FixedComputeIssue] {
  guard fixed_compute_choice_payload(choice, prepared) is Some(sequence) else {
    return Err(NotSelected)
  }
  let request = prepared.candidate.request
  let pipeline = @lower.pipeline(
    @lower.bound_preparation(@execution.producer_read_receiver(request.input)),
  )
  let count = @pipeline.step_count(pipeline)
  let target : @pipeline.Target = if count == 0 {
    Input(0)
  } else {
    Step(count - 1)
  }
  @execution.execute_fixed_producer_guarded(
    sequence,
    request.input,
    target,
    limits,
    max_rows=request.capacity.max_rows,
    max_value_bytes=request.capacity.max_value_bytes,
    measurement,
  ).map_err(issue => {
    match issue {
      Execution(failure) => FixedComputeIssue::Execution(failure)
      _ => Guard(issue)
    }
  })
}
