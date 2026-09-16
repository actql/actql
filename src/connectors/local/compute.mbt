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
    !@execution.generated_satisfies_requirements(sequence, common) {
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
/// Prepare this connector's execution and capacity without running admission or
/// calculation. The common task driver owns reservation and success publication.
pub fn prepare_local_compute_execution(
  choice : @connector.FixedComputeChoice,
  prepared : @connector.PreparedCompute[@execution.GeneratedSequence],
  limits : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  join_output_ceiling? : (Int, Int64)? = None,
) -> Result[@connector.SynchronousCompute, @connector.FixedComputeIssue] {
  guard @connector.fixed_compute_choice_payload(choice, prepared)
    is Some(sequence) else {
    return Err(NotSelected)
  }
  guard @execution.generated_sequence_capacity(sequence, limits, measurement)
    is Some(capacity) else {
    return Err(InvalidLimits)
  }
  let request = @connector.fixed_compute_candidate_request(
    @connector.prepared_compute_candidate(prepared),
  )
  guard @lower.preparation_output_target(
      @lower.bound_preparation(@connector.fixed_compute_request_owner(request)),
    )
    is Some(target) else {
    return Err(UnsupportedInputShape)
  }
  @connector.bind_synchronous_compute(
    choice,
    prepared,
    {
      retained_bytes: capacity.retained_bytes,
      execution_bytes: capacity.execution_bytes,
    },
    match join_output_ceiling {
      None => []
      Some(ceiling) => [ceiling]
    },
    fn(_sequence) {
      match
        execute_local_fixed_compute(
          choice,
          prepared,
          limits,
          measurement~,
          join_output_ceiling~,
        ) {
        Err(issue) => Err(Compute(issue))
        Ok(completed) =>
          match @execution.completed_output(completed, target) {
            Some(output) => Ok(output)
            None => Err(MissingOutput)
          }
      }
    },
  )
}

///|
pub fn execute_local_fixed_compute(
  choice : @connector.FixedComputeChoice,
  prepared : @connector.PreparedCompute[@execution.GeneratedSequence],
  limits : @execution.SequenceExecutionLimits,
  measurement~ : @execution.FixedInputGuardMeasureLimits,
  join_output_ceiling? : (Int, Int64)? = None,
  representations? : Array[@execution.CompletedOutput?],
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
  guard @lower.preparation_output_target(
      @lower.bound_preparation(@connector.fixed_compute_request_owner(request)),
    )
    is Some(target) else {
    return Err(UnsupportedInputShape)
  }
  let inputs = @connector.fixed_compute_request_inputs(request)
  if representations is Some(copies) {
    if copies.length() != inputs.length() {
      return Err(UnsupportedInputShape)
    }
    for index, copy in copies {
      if copy is Some(output) {
        match @execution.rebind_producer_representation(inputs[index], output) {
          Ok(read) => inputs[index] = read
          Err(_) => return Err(ForeignPreparation)
        }
      }
    }
  }
  @execution.execute_fixed_producers_guarded(
    sequence,
    inputs,
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
