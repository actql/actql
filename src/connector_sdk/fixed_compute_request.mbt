///|
/// Immutable completed inputs and their exactly bound consumer. This is an
/// internal realization request, not an alternative canonical Program or Plan.
struct FixedComputeRequest {
  owner : @lower.BoundPrepared
  inputs : Array[@execution.ProducerRead]
  capacity : FixedComputeCapacity
}

///|
/// Host-selected consumer contract, common to every realization of this owned
/// request. A common fragment is not an implementation-local fallback budget.
pub(all) struct FixedComputeCapacity {
  contract_cid : String
  max_rows : Int
  max_value_bytes : Int
  common_fragment : @lower.SequenceRequirements?
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
  LogicalIdentityUnsupported
  PlanningLimit
  NegativeQuantity
  Cost(@cost.CostIssue)
  Execution(@execution.SequenceRunIssue)
  Guard(@execution.FixedInputGuardIssue)
}

///|
pub fn prepare_fixed_compute_request(
  inputs : Array[@execution.ProducerRead],
  capacity : FixedComputeCapacity,
) -> Result[FixedComputeRequest, FixedComputeIssue] {
  if capacity.contract_cid !=
    "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f" {
    return Err(CapacityContract)
  }
  if capacity.max_rows < 0 || capacity.max_value_bytes < 0 {
    return Err(InvalidLimits)
  }
  guard inputs.get(0) is Some(first) else { return Err(UnsupportedInputShape) }
  let owner = @execution.producer_read_receiver(first)
  if capacity.common_fragment is Some(sequence) &&
    !physical_equal(@lower.sequence_requirements_owner(sequence), owner) {
    return Err(ForeignPreparation)
  }
  if @lower.preparation_input_count(@lower.bound_preparation(owner)) !=
    inputs.length() {
    return Err(UnsupportedInputShape)
  }
  // ProducerRead can only be made from a successfully bound CompletedOutput.
  // There is no source selector, connection, CID lookup or raw-row constructor.
  for index in 0..<inputs.length() {
    let input = inputs[index]
    if !physical_equal(@execution.producer_read_receiver(input), owner) {
      return Err(ForeignPreparation)
    }
    if @execution.producer_read_input_index(input) != index {
      return Err(UnsupportedInputShape)
    }
    if !@execution.producer_read_available(input) {
      return Err(InputUnavailable)
    }
    if @execution.producer_read_row_count(input) > capacity.max_rows {
      return Err(CommonInputRows)
    }
  }
  // Copy only the bounded handle array. Caller mutations cannot replace ports;
  // immutable backing storage remains shared, without new admission or copying.
  Ok({ owner, inputs: inputs.copy(), capacity, })
}

///|
/// The checked zero-input root supplies the request owner when no producer
/// read exists. This grants no execution; common strategy and admission still
/// select and start the task.
pub fn prepare_source_free_fixed_compute_request(
  owner : @lower.BoundPrepared,
  capacity : FixedComputeCapacity,
) -> Result[FixedComputeRequest, FixedComputeIssue] {
  if capacity.contract_cid !=
    "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f" {
    return Err(CapacityContract)
  }
  if capacity.max_rows < 0 || capacity.max_value_bytes < 0 {
    return Err(InvalidLimits)
  }
  if @lower.preparation_input_count(@lower.bound_preparation(owner)) != 0 {
    return Err(UnsupportedInputShape)
  }
  if capacity.common_fragment is Some(sequence) &&
    !physical_equal(@lower.sequence_requirements_owner(sequence), owner) {
    return Err(ForeignPreparation)
  }
  Ok({ owner, inputs: [], capacity, })
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
  index : Int,
) -> @execution.ProducerRead? {
  request.inputs.get(index)
}

///|
pub fn fixed_compute_request_input_count(request : FixedComputeRequest) -> Int {
  request.inputs.length()
}

///|
/// Snapshot only the bounded immutable input handles. The caller cannot replace
/// owned ports; retained row storage is shared without copying or re-admission.
pub fn fixed_compute_request_inputs(
  request : FixedComputeRequest,
) -> Array[@execution.ProducerRead] {
  request.inputs.copy()
}

///|
pub fn fixed_compute_request_owner(
  request : FixedComputeRequest,
) -> @lower.BoundPrepared {
  request.owner
}
