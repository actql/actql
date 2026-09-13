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
) -> Result[@execution.CompletedSequence, FixedComputeIssue] {
  guard fixed_compute_choice_payload(choice, prepared) is Some(sequence) else {
    return Err(NotSelected)
  }
  @execution.execute_fixed_producer_input(
    sequence,
    prepared.candidate.request.input,
    limits,
  ).map_err(issue => Execution(issue))
}
