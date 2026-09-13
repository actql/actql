///|
/// One immutable completed input and its exactly bound consumer. This is an
/// internal realization request, not an alternative canonical Program or Plan.
struct FixedComputeRequest {
  input : @execution.ProducerRead
  capacity : FixedComputeCapacity
}

///|
/// Host-selected consumer contract, common to every realization of this owned
/// request. A common fragment is not an implementation-local fallback budget.
pub(all) struct FixedComputeCapacity {
  contract_cid : String
  max_rows : Int
  max_value_bytes : Int
  common_fragment : @execution.GeneratedSequence?
}

///|
pub(all) enum FixedComputeIssue {
  UnsupportedInputShape
  InputUnavailable
  ForeignPreparation
  ForeignRequest(Int)
  ForeignCapability(Int)
  CapabilityClosed
  ComputeUnsupported
  NotSelected
  InvalidLimits
  CapacityContract
  CommonInputRows
  CommonFragmentUnsupported
  PlanningLimit
  NegativeQuantity
  Cost(@cost.CostIssue)
  Compilation(@duckdb.NativeQueryIssue)
  Execution(@execution.SequenceRunIssue)
}

///|
pub fn prepare_fixed_compute_request(
  input : @execution.ProducerRead,
  capacity : FixedComputeCapacity,
) -> Result[FixedComputeRequest, FixedComputeIssue] {
  if capacity.contract_cid !=
    "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f" {
    return Err(CapacityContract)
  }
  if capacity.max_rows < 0 || capacity.max_value_bytes < 0 {
    return Err(InvalidLimits)
  }
  if !@execution.producer_read_available(input) {
    return Err(InputUnavailable)
  }
  let owner = @execution.producer_read_receiver(input)
  if capacity.common_fragment is Some(sequence) &&
    !physical_equal(@execution.generated_sequence_owner(sequence), owner) {
    return Err(ForeignPreparation)
  }
  if @pipeline.input_count(@lower.pipeline(@lower.bound_preparation(owner))) !=
    1 {
    return Err(UnsupportedInputShape)
  }
  // ProducerRead can only be made from a successfully bound CompletedOutput.
  // There is no source selector, connection, CID lookup or raw-row constructor.
  if @execution.producer_read_row_count(input) > capacity.max_rows {
    return Err(CommonInputRows)
  }
  Ok({ input, capacity, })
}

///|
pub fn fixed_compute_request_capacity(
  request : FixedComputeRequest,
) -> FixedComputeCapacity {
  request.capacity
}

///|
pub fn fixed_compute_request_input(
  request : FixedComputeRequest,
) -> @execution.ProducerRead {
  request.input
}
