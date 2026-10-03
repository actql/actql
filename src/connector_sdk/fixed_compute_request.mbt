///|
/// Immutable completed inputs and their exactly bound consumer. This is an
/// internal realization request, not an alternative canonical Program or Plan.
struct FixedComputeRequest {
  owner : @lower.BoundPrepared
  inputs : Array[@execution.FixedRelationRead]
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
  Ok({
    owner,
    inputs: inputs.map(@execution.fixed_completed_relation_read),
    capacity,
  })
}

///|
/// Prepare one checked physical operation whose ordered receiving ports differ
/// from the enclosing Stage's input declaration. Each read must match that
/// exact operation edge; the caller cannot substitute equal row contents.
pub fn prepare_selected_fixed_compute_request(
  owner : @lower.BoundPrepared,
  step : Int,
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
  let prepared = @lower.bound_preparation(owner)
  guard @lower.node_at(prepared, step) is Some(node) &&
    @lower.node_input_count(node) == inputs.length() else {
    return Err(UnsupportedInputShape)
  }
  if capacity.common_fragment is Some(sequence) &&
    !physical_equal(@lower.sequence_requirements_owner(sequence), owner) {
    return Err(ForeignPreparation)
  }
  for index, input in inputs {
    if !physical_equal(@execution.producer_read_receiver(input), owner) {
      return Err(ForeignPreparation)
    }
    if !@execution.producer_read_available(input) {
      return Err(InputUnavailable)
    }
    if !@execution.producer_read_matches_operation_input(
        input, owner, step, index,
      ) {
      return Err(UnsupportedInputShape)
    }
    if @execution.producer_read_row_count(input) > capacity.max_rows {
      return Err(CommonInputRows)
    }
  }
  Ok({
    owner,
    inputs: inputs.map(@execution.fixed_completed_relation_read),
    capacity,
  })
}

///|
/// Admit the exact ordered mixture of retained and Host-supplied Relation
/// inputs for one checked selected operation. Other realizations may refuse
/// this request; a supplied read is never represented as a producer output.
pub fn prepare_selected_fixed_compute_request_with_inputs(
  owner : @lower.BoundPrepared,
  step : Int,
  inputs : Array[@execution.FixedRelationRead],
  capacity : FixedComputeCapacity,
) -> Result[FixedComputeRequest, FixedComputeIssue] {
  if capacity.contract_cid !=
    "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f" {
    return Err(CapacityContract)
  }
  if capacity.max_rows < 0 || capacity.max_value_bytes < 0 {
    return Err(InvalidLimits)
  }
  let prepared = @lower.bound_preparation(owner)
  guard @lower.node_at(prepared, step) is Some(node) &&
    @lower.node_input_count(node) == inputs.length() else {
    return Err(UnsupportedInputShape)
  }
  if capacity.common_fragment is Some(sequence) &&
    !physical_equal(@lower.sequence_requirements_owner(sequence), owner) {
    return Err(ForeignPreparation)
  }
  for index, input in inputs {
    if !@execution.fixed_relation_read_matches_operation_input(
        input, owner, step, index,
      ) {
      return Err(UnsupportedInputShape)
    }
    if @execution.fixed_relation_read_row_count(input) > capacity.max_rows {
      return Err(CommonInputRows)
    }
  }
  Ok({ owner, inputs: inputs.copy(), capacity, })
}

///|
/// Admit the exact checked Stage input set, including supplied rows. This
/// neither creates a producer completion nor authorizes dispatch by itself.
pub fn prepare_fixed_compute_request_with_inputs(
  owner : @lower.BoundPrepared,
  inputs : Array[@execution.FixedRelationRead],
  capacity : FixedComputeCapacity,
) -> Result[FixedComputeRequest, FixedComputeIssue] {
  if capacity.contract_cid !=
    "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f" {
    return Err(CapacityContract)
  }
  if capacity.max_rows < 0 || capacity.max_value_bytes < 0 {
    return Err(InvalidLimits)
  }
  if @lower.preparation_input_count(@lower.bound_preparation(owner)) !=
    inputs.length() {
    return Err(UnsupportedInputShape)
  }
  if capacity.common_fragment is Some(sequence) &&
    !physical_equal(@lower.sequence_requirements_owner(sequence), owner) {
    return Err(ForeignPreparation)
  }
  for index, input in inputs {
    if !@execution.fixed_relation_read_matches_input(input, owner, index) {
      return Err(UnsupportedInputShape)
    }
    if @execution.fixed_relation_read_row_count(input) > capacity.max_rows {
      return Err(CommonInputRows)
    }
  }
  Ok({ owner, inputs: inputs.copy(), capacity, })
}

///|
/// The checked zero-input task supplies the request owner when no producer
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
  request.inputs.get(index).bind(@execution.fixed_relation_read_completed)
}

///|
pub fn fixed_compute_request_relation_input(
  request : FixedComputeRequest,
  index : Int,
) -> @execution.FixedRelationRead? {
  request.inputs.get(index)
}

///|
pub fn fixed_compute_request_has_supplied_input(
  request : FixedComputeRequest,
) -> Bool {
  request.inputs.any(input => {
    @execution.fixed_relation_read_supplied(input) is Some(_)
  })
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
  let inputs = []
  for input in request.inputs {
    guard @execution.fixed_relation_read_completed(input) is Some(read) else {
      return []
    }
    inputs.push(read)
  }
  inputs
}

///|
pub fn fixed_compute_request_relation_inputs(
  request : FixedComputeRequest,
) -> Array[@execution.FixedRelationRead] {
  request.inputs.copy()
}

///|
pub fn fixed_compute_request_owner(
  request : FixedComputeRequest,
) -> @lower.BoundPrepared {
  request.owner
}
