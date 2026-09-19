///|
/// Trusted completion verifier for one typed non-Relation Carrier result.
struct CarrierManagedCompletionPort[P] {
  profile : ManagedExecutionProfile
  preparation : CompletionPreparation
  target : @pipeline.Target
  inputs : Array[CarrierManagedProducerRead]
  verify : (P) -> @managed_carrier.CompletionReference?
  obligations : ManagedObligations
  mut attempt : ManagedExecutionAttempt?
  mut open : Bool
  mut verifying : Bool
  mut revoked : Bool
}

///|
/// Common task completion for Graph, Events, or Vectors. The typed payload
/// stays in its Carrier runtime; this value proves the exact occurrence,
/// attempt, input use sites, retention, and selected managed profile.
struct CarrierManagedCompletedOutput {
  identity : Ref[Unit]
  reference : @managed_carrier.CompletionReference
  profile : ManagedExecutionProfile
  preparation : CompletionPreparation
  target : @pipeline.Target
  inputs : Array[CarrierManagedProducerRead]
  obligations : ManagedObligations
  attempt : ManagedExecutionAttempt?
}

///|
struct CarrierManagedCompletionReference {
  identity : Ref[Unit]
  available : () -> Bool
}

///|
struct CarrierManagedProducerRead {
  identity : Ref[Unit]
  receiver : @lower.BoundPrepared
  input_index : Int
  output : CarrierManagedCompletedOutput
  carrier_read : @managed_carrier.ProducerReadReference
}

///|
fn validate_carrier_completion_target(
  preparation : CompletionPreparation,
  target : @pipeline.Target,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[@carrier.Kind, TrustedOutputIssue] {
  if max_entries < 0 || max_name_bytes < 0 {
    return Err(InvalidLimits)
  }
  let owner = completion_preparation_owner(preparation)
  let prepared = @lower.bound_preparation(owner)
  guard target is @pipeline.Step(index) &&
    index == @lower.sequence_count(preparation.sequence) - 1 &&
    @lower.node_at(prepared, index) is Some(node) &&
    @lower.preparation_carrier_at(prepared, target) is Some(carrier) else {
    return Err(InvalidTarget)
  }
  if preparation.retained_ids.length() != 1 ||
    preparation.retained_ids[0] != @lower.node_id(node) {
    return Err(NotRetained)
  }
  let mut bytes = max_name_bytes
  for name in [@lower.node_id(node), preparation.retained_ids[0]] {
    match @scalar.admit_utf8_length(name, bytes) {
      Ok(size) => bytes -= size
      Err(_) => return Err(Limit)
    }
  }
  if @lower.preparation_input_count(prepared) > max_entries {
    return Err(Limit)
  }
  let kind = @carrier.kind(carrier)
  if kind == @carrier.RelationKind {
    Err(InvalidTarget)
  } else {
    Ok(kind)
  }
}

///|
pub fn[P] prepare_carrier_managed_completion_port(
  profile : ManagedExecutionProfile,
  preparation : CompletionPreparation,
  target : @pipeline.Target,
  max_entries : Int,
  max_name_bytes : Int,
  verify : (P) -> @managed_carrier.CompletionReference?,
  inputs? : Array[CarrierManagedProducerRead],
  obligations? : ManagedObligations,
  attempt? : ManagedExecutionAttempt,
) -> Result[CarrierManagedCompletionPort[P], TrustedOutputIssue] {
  let kind = match
    validate_carrier_completion_target(
      preparation, target, max_entries, max_name_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if kind == @carrier.RelationKind {
    return Err(InvalidTarget)
  }
  let owner = completion_preparation_owner(preparation)
  // A supplied or Acquisition boundary may omit fixed producer evidence.
  // Once a managed input family is selected, every ordered input is required;
  // a partial prefix must never become successful provenance.
  let selected_inputs = inputs.unwrap_or([])
  if inputs is Some(_) {
    if selected_inputs.length() > max_entries ||
      selected_inputs.length() !=
      @lower.preparation_input_count(@lower.bound_preparation(owner)) {
      return Err(ForeignInputs)
    }
    for index, input in selected_inputs {
      if !carrier_managed_producer_read_matches_input(input, owner, index) ||
        managed_execution_profile_cid(input.output.profile) !=
        managed_execution_profile_cid(profile) {
        return Err(ForeignInputs)
      }
    }
  } else {
    let prepared = @lower.bound_preparation(owner)
    for index in 0..<@lower.preparation_input_count(prepared) {
      if @lower.preparation_input_is_produced(prepared, index) {
        return Err(ForeignInputs)
      }
    }
  }
  let selected = obligations.unwrap_or_else(() => {
    process_carrier_managed_obligations(owner)
  })
  if !physical_equal(managed_obligations_owner(selected), owner) ||
    managed_obligations_require_logical_identity(selected) {
    return Err(ForeignOutput)
  }
  Ok({
    profile,
    preparation,
    target,
    inputs: selected_inputs.copy(),
    verify,
    obligations: selected,
    attempt,
    open: true,
    verifying: false,
    revoked: false,
  })
}

///|
pub fn[P] bind_carrier_managed_completion_attempt(
  port : CarrierManagedCompletionPort[P],
  attempt : ManagedExecutionAttempt,
) -> Bool {
  if !port.open || port.attempt is Some(_) {
    return false
  }
  port.attempt = Some(attempt)
  true
}

///|
pub fn[P] cancel_carrier_managed_completion_port(
  port : CarrierManagedCompletionPort[P],
) -> Bool {
  if port.revoked || (!port.open && !port.verifying) {
    return false
  }
  port.open = false
  port.revoked = true
  true
}

///|
pub fn[P] complete_carrier_managed_output(
  port : CarrierManagedCompletionPort[P],
  proof : P,
) -> Result[CarrierManagedCompletedOutput, TrustedOutputIssue] {
  if !port.open {
    return Err(Unverified)
  }
  for input in port.inputs {
    if !carrier_managed_producer_read_available(input) {
      return Err(ForeignInputs)
    }
  }
  port.open = false
  port.verifying = true
  let verified = (port.verify)(proof)
  port.verifying = false
  if port.revoked {
    return Err(Unverified)
  }
  guard verified is Some(reference) &&
    @managed_carrier.completion_reference_matches_port(
      reference,
      completion_preparation_owner(port.preparation),
      port.target,
    ) &&
    @managed_carrier.completion_reference_kind(reference) !=
    @carrier.RelationKind &&
    @managed_carrier.completion_reference_storage_bytes(reference) is Some(_) else {
    return Err(ForeignOutput)
  }
  for input in port.inputs {
    if !carrier_managed_producer_read_available(input) {
      return Err(ForeignInputs)
    }
  }
  Ok({
    identity: Ref(()),
    reference,
    profile: port.profile,
    preparation: port.preparation,
    target: port.target,
    inputs: port.inputs.copy(),
    obligations: port.obligations,
    attempt: port.attempt,
  })
}

///|
pub fn prepare_carrier_managed_producer_read(
  receiver : @lower.BoundPrepared,
  input_index : Int,
  expected_producer : @lower.BoundPrepared,
  output : CarrierManagedCompletedOutput,
  carrier_read : @managed_carrier.ProducerReadReference,
) -> Result[CarrierManagedProducerRead, TrustedOutputIssue] {
  if !carrier_managed_completed_output_available(output) ||
    !@managed_carrier.completion_reference_matches_port(
      output.reference,
      expected_producer,
      output.target,
    ) ||
    !@managed_carrier.producer_read_reference_matches_input(
      carrier_read, receiver, input_index,
    ) ||
    !@managed_carrier.producer_read_reference_matches_output(
      carrier_read,
      output.reference,
    ) {
    return Err(ForeignInputs)
  }
  Ok({ identity: Ref(()), receiver, input_index, output, carrier_read, })
}

///|
pub fn carrier_managed_producer_read_available(
  value : CarrierManagedProducerRead,
) -> Bool {
  carrier_managed_completed_output_available(value.output) &&
  @managed_carrier.producer_read_reference_available(value.carrier_read)
}

///|
pub fn carrier_managed_producer_read_same(
  left : CarrierManagedProducerRead,
  right : CarrierManagedProducerRead,
) -> Bool {
  physical_equal(left.identity, right.identity)
}

///|
pub fn carrier_managed_producer_read_matches_input(
  value : CarrierManagedProducerRead,
  receiver : @lower.BoundPrepared,
  input_index : Int,
) -> Bool {
  physical_equal(value.receiver, receiver) &&
  value.input_index == input_index &&
  carrier_managed_producer_read_available(value)
}

///|
pub fn carrier_managed_producer_read_carrier_reference(
  value : CarrierManagedProducerRead,
) -> @managed_carrier.ProducerReadReference {
  value.carrier_read
}

///|
pub fn carrier_managed_completed_output_available(
  value : CarrierManagedCompletedOutput,
) -> Bool {
  @managed_carrier.completion_reference_available(value.reference)
}

///|
pub fn carrier_managed_completed_output_kind(
  value : CarrierManagedCompletedOutput,
) -> @carrier.Kind {
  @managed_carrier.completion_reference_kind(value.reference)
}

///|
pub fn carrier_managed_completed_output_obligations(
  value : CarrierManagedCompletedOutput,
) -> ManagedObligations {
  value.obligations
}

///|
pub fn carrier_managed_completed_output_storage_bytes(
  value : CarrierManagedCompletedOutput,
) -> Int64? {
  @managed_carrier.completion_reference_storage_bytes(value.reference)
}

///|
pub fn carrier_managed_completed_output_matches_port(
  value : CarrierManagedCompletedOutput,
  owner : @lower.BoundPrepared,
  target : @pipeline.Target,
) -> Bool {
  physical_equal(completion_preparation_owner(value.preparation), owner) &&
  value.target == target &&
  @managed_carrier.completion_reference_matches_port(
    value.reference,
    owner,
    target,
  )
}

///|
pub fn carrier_managed_completed_output_matches_attempt(
  value : CarrierManagedCompletedOutput,
  attempt : ManagedExecutionAttempt,
) -> Bool {
  value.attempt
  .map(selected => managed_execution_attempt_same(selected, attempt))
  .unwrap_or(false)
}

///|
pub fn carrier_managed_completed_output_matches_inputs(
  value : CarrierManagedCompletedOutput,
  inputs : Array[CarrierManagedProducerRead],
) -> Bool {
  if value.inputs.length() != inputs.length() {
    return false
  }
  for index, input in inputs {
    if !carrier_managed_producer_read_same(value.inputs[index], input) ||
      !carrier_managed_producer_read_available(input) {
      return false
    }
  }
  true
}

///|
pub fn carrier_managed_completed_reference(
  value : CarrierManagedCompletedOutput,
) -> CarrierManagedCompletionReference {
  {
    identity: value.identity,
    available: fn() { carrier_managed_completed_output_available(value) },
  }
}

///|
pub fn carrier_managed_completed_reference_available(
  value : CarrierManagedCompletionReference,
) -> Bool {
  (value.available)()
}

///|
pub fn carrier_managed_completed_reference_matches(
  reference : CarrierManagedCompletionReference,
  value : CarrierManagedCompletedOutput,
) -> Bool {
  physical_equal(reference.identity, value.identity) &&
  carrier_managed_completed_reference_available(reference) &&
  carrier_managed_completed_output_available(value)
}
