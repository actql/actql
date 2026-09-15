///|
/// Local connector inventory: preparation, receiving admission, computation, retained
/// output, cleanup. The existing driver still enforces selected fragment limits.
pub fn local_fixed_compute_candidate(
  registration : @connector.CapabilityRegistration,
  request : @connector.FixedComputeRequest,
  sequence : @execution.GeneratedSequence,
  estimates : Array[@cost.SerialEstimateLine],
  quantities : @connector.QueryQuantities,
  max_entries : Int,
) -> Result[
  @connector.PreparedCompute[@execution.GeneratedSequence],
  @connector.FixedComputeIssue,
] {
  if @connector.fixed_compute_request_capacity(request).common_fragment
    is Some(common) &&
    !physical_equal(common, sequence) {
    return Err(ForeignPreparation)
  }
  if !physical_equal(
      @execution.generated_sequence_owner(sequence),
      @connector.fixed_compute_request_owner(request),
    ) {
    return Err(ForeignPreparation)
  }
  @connector.bind_compute_candidate(
    registration, request, sequence, 5, estimates, quantities, max_entries,
  )
}

///|
pub fn execute_local_fixed_compute(
  choice : @connector.FixedComputeChoice,
  prepared : @connector.PreparedCompute[@execution.GeneratedSequence],
  limits : @execution.SequenceExecutionLimits,
  measurement~ : @execution.FixedInputGuardMeasureLimits,
  join_output_ceiling? : (Int, Int64)? = None,
) -> Result[@execution.CompletedSequence, @connector.FixedComputeIssue] {
  guard @connector.fixed_compute_choice_payload(choice, prepared)
    is Some(sequence) else {
    return Err(NotSelected)
  }
  let request = @connector.fixed_compute_candidate_request(
    @connector.prepared_compute_candidate(prepared),
  )
  let sequence = match join_output_ceiling {
    None => sequence
    Some((step, ceiling)) =>
      match
        @execution.constrain_generated_join_output(sequence, step, ceiling) {
        Ok(sequence) => sequence
        Err(issue) => return Err(Execution(issue))
      }
  }
  let pipeline = @lower.pipeline(
    @lower.bound_preparation(@connector.fixed_compute_request_owner(request)),
  )
  let count = @pipeline.step_count(pipeline)
  let target : @pipeline.Target = if count == 0 {
    Input(0)
  } else {
    Step(count - 1)
  }
  @execution.execute_fixed_producers_guarded(
    sequence,
    @connector.fixed_compute_request_inputs(request),
    target,
    limits,
    max_rows=@connector.fixed_compute_request_capacity(request).max_rows,
    max_value_bytes=@connector.fixed_compute_request_capacity(request).max_value_bytes,
    measurement,
  ).map_err(issue => {
    match issue {
      Execution(failure) => @connector.FixedComputeIssue::Execution(failure)
      _ => Guard(issue)
    }
  })
}
