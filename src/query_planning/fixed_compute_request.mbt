///|
/// One immutable completed input and its exactly bound consumer. This is an
/// internal realization request, not an alternative canonical Program or Plan.
struct FixedComputeRequest {
  input : @execution.ProducerRead
}

///|
pub(all) enum FixedComputeIssue {
  UnsupportedInputShape
  ForeignPreparation
  ForeignRequest(Int)
  ForeignCapability(Int)
  CapabilityClosed
  ComputeUnsupported
  NotSelected
  InvalidLimits
  PlanningLimit
  NegativeQuantity
  Cost(@cost.CostIssue)
  Compilation(@duckdb.NativeQueryIssue)
  Execution(@execution.SequenceRunIssue)
}

///|
pub fn prepare_fixed_compute_request(
  input : @execution.ProducerRead,
) -> Result[FixedComputeRequest, FixedComputeIssue] {
  let owner = @execution.producer_read_receiver(input)
  if @pipeline.input_count(@lower.pipeline(@lower.bound_preparation(owner))) !=
    1 {
    return Err(UnsupportedInputShape)
  }
  // ProducerRead can only be made from a successfully bound CompletedOutput.
  // There is no source selector, connection, CID lookup or raw-row constructor.
  Ok({ input, })
}

///|
pub fn fixed_compute_request_input(
  request : FixedComputeRequest,
) -> @execution.ProducerRead {
  request.input
}
