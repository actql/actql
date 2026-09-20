///|
/// One managed-profile fixed Compute request. This is the exact receiving
/// use-site set plus its common logical capacity contract; it is not a legacy
/// CID-bearing request, a Store pin or dispatch authority.
struct ManagedFixedComputeRequest[T] {
  owner : @lower.BoundPrepared
  inputs : Array[@execution.ManagedProducerRead[T]]
  bindings : Array[@execution.ManagedInputBinding]
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
  match validate_managed_fixed_capacity(capacity) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard inputs.get(0) is Some(first) else { return Err(UnsupportedInputShape) }
  prepare_managed_fixed_compute_request_for_owner_validated(
    @execution.managed_producer_read_receiver(first),
    inputs,
    inputs.map(input => @execution.managed_relation_input_binding(input)),
    capacity,
    obligations,
  )
}

///|
/// Owner-explicit form for checked zero-input tasks. It preserves the same
/// exact owner, obligation, capacity, and ordered-port checks as the input-
/// derived entry without manufacturing a producer handle.
pub fn[T] prepare_managed_fixed_compute_request_for_owner(
  owner : @lower.BoundPrepared,
  inputs : Array[@execution.ManagedProducerRead[T]],
  capacity : FixedComputeCapacity,
  obligations : @execution.ManagedObligations,
) -> Result[ManagedFixedComputeRequest[T], FixedComputeIssue] {
  match validate_managed_fixed_capacity(capacity) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  prepare_managed_fixed_compute_request_for_owner_validated(
    owner,
    inputs,
    inputs.map(input => @execution.managed_relation_input_binding(input)),
    capacity,
    obligations,
  )
}

///|
/// Admit a complete ordered mixture of managed Relation and Carrier use sites.
/// Payload access remains in the selected implementation; the common request
/// retains only exact binding, capacity, and obligation evidence.
pub fn[T] prepare_managed_fixed_compute_request_for_bindings(
  owner : @lower.BoundPrepared,
  bindings : Array[@execution.ManagedInputBinding],
  capacity : FixedComputeCapacity,
  obligations : @execution.ManagedObligations,
) -> Result[ManagedFixedComputeRequest[T], FixedComputeIssue] {
  match validate_managed_fixed_capacity(capacity) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  prepare_managed_fixed_compute_request_for_owner_validated(
    owner,
    [],
    bindings,
    capacity,
    obligations,
  )
}

///|
fn validate_managed_fixed_capacity(
  capacity : FixedComputeCapacity,
) -> Result[Unit, FixedComputeIssue] {
  if capacity.contract_cid !=
    "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f" {
    return Err(CapacityContract)
  }
  if capacity.max_rows < 0 || capacity.max_value_bytes < 0 {
    return Err(InvalidLimits)
  }
  Ok(())
}

///|
fn[T] prepare_managed_fixed_compute_request_for_owner_validated(
  owner : @lower.BoundPrepared,
  inputs : Array[@execution.ManagedProducerRead[T]],
  bindings : Array[@execution.ManagedInputBinding],
  capacity : FixedComputeCapacity,
  obligations : @execution.ManagedObligations,
) -> Result[ManagedFixedComputeRequest[T], FixedComputeIssue] {
  if !physical_equal(@execution.managed_obligations_owner(obligations), owner) {
    return Err(ForeignPreparation)
  }
  if capacity.common_fragment is Some(sequence) &&
    !physical_equal(@lower.sequence_requirements_owner(sequence), owner) {
    return Err(ForeignPreparation)
  }
  if @lower.preparation_input_count(@lower.bound_preparation(owner)) !=
    bindings.length() {
    return Err(UnsupportedInputShape)
  }
  for index, binding in bindings {
    if !@execution.managed_input_binding_matches_input(binding, owner, index) {
      return Err(InputUnavailable)
    }
  }
  for input in inputs {
    let index = @execution.managed_producer_read_input_index(input)
    if index < 0 ||
      index >= bindings.length() ||
      !@execution.managed_input_binding_same(
        bindings[index],
        @execution.managed_relation_input_binding(input),
      ) {
      return Err(UnsupportedInputShape)
    }
    if !@execution.managed_producer_read_available(input) {
      return Err(InputUnavailable)
    }
    if @execution.managed_producer_read_row_count(input) > capacity.max_rows {
      return Err(CommonInputRows)
    }
  }
  Ok({
    owner,
    inputs: inputs.copy(),
    bindings: bindings.copy(),
    capacity,
    obligations,
  })
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
  request.bindings.length()
}

///|
pub fn[T] managed_fixed_compute_request_bindings(
  request : ManagedFixedComputeRequest[T],
) -> Array[@execution.ManagedInputBinding] {
  request.bindings.copy()
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
