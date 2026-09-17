///|
/// One managed-profile fixed Compute request. This is the exact receiving
/// use-site set plus its common logical capacity contract; it is not a legacy
/// CID-bearing request, a Store pin or dispatch authority.
struct ManagedFixedComputeRequest[T] {
  owner : @lower.BoundPrepared
  inputs : Array[@execution.ManagedProducerRead[T]]
  capacity : FixedComputeCapacity
  obligations : @execution.ManagedObligations
}

///|
/// Admit only a complete, ordered input set for one checked receiver. Logical
/// row/value ceilings remain consumer obligations even though producer value
/// evidence may be reused. Physical representation bytes do not replace them.
pub fn[T] prepare_managed_fixed_compute_request(
  inputs : Array[@execution.ManagedProducerRead[T]],
  capacity : FixedComputeCapacity,
  obligations : @execution.ManagedObligations,
) -> Result[ManagedFixedComputeRequest[T], FixedComputeIssue] {
  if capacity.contract_cid !=
    "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f" {
    return Err(CapacityContract)
  }
  if capacity.max_rows < 0 || capacity.max_value_bytes < 0 {
    return Err(InvalidLimits)
  }
  guard inputs.get(0) is Some(first) else { return Err(UnsupportedInputShape) }
  let owner = @execution.managed_producer_read_receiver(first)
  if !physical_equal(@execution.managed_obligations_owner(obligations), owner) {
    return Err(ForeignPreparation)
  }
  if capacity.common_fragment is Some(sequence) &&
    !physical_equal(@lower.sequence_requirements_owner(sequence), owner) {
    return Err(ForeignPreparation)
  }
  if @lower.preparation_input_count(@lower.bound_preparation(owner)) !=
    inputs.length() {
    return Err(UnsupportedInputShape)
  }
  for index in 0..<inputs.length() {
    let input = inputs[index]
    if !physical_equal(@execution.managed_producer_read_receiver(input), owner) {
      return Err(ForeignPreparation)
    }
    if @execution.managed_producer_read_input_index(input) != index {
      return Err(UnsupportedInputShape)
    }
    if !@execution.managed_producer_read_available(input) {
      return Err(InputUnavailable)
    }
    if @execution.managed_producer_read_row_count(input) > capacity.max_rows {
      return Err(CommonInputRows)
    }
  }
  Ok({ owner, inputs: inputs.copy(), capacity, obligations, })
}

///|
pub fn[T] managed_fixed_compute_request_obligations(
  request : ManagedFixedComputeRequest[T],
) -> @execution.ManagedObligations {
  request.obligations
}

///|
pub fn[T] managed_fixed_compute_request_capacity(
  request : ManagedFixedComputeRequest[T],
) -> FixedComputeCapacity {
  request.capacity
}

///|
pub fn[T] managed_fixed_compute_request_input(
  request : ManagedFixedComputeRequest[T],
  index : Int,
) -> @execution.ManagedProducerRead[T]? {
  request.inputs.get(index)
}

///|
pub fn[T] managed_fixed_compute_request_input_count(
  request : ManagedFixedComputeRequest[T],
) -> Int {
  request.inputs.length()
}

///|
/// Snapshot only the bounded immutable use-site handles. The request does not
/// copy the retained representation or confer permission to read it.
pub fn[T] managed_fixed_compute_request_inputs(
  request : ManagedFixedComputeRequest[T],
) -> Array[@execution.ManagedProducerRead[T]] {
  request.inputs.copy()
}

///|
pub fn[T] managed_fixed_compute_request_owner(
  request : ManagedFixedComputeRequest[T],
) -> @lower.BoundPrepared {
  request.owner
}
