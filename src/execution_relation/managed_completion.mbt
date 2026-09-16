///|
/// An installed Host verifier for one managed execution attempt. The verifier
/// must cover demanded semantics/failures, selected identity obligations,
/// authorization, resource settlement and exact immutable output correspondence.
/// Receiving valid values or retaining a file alone cannot satisfy this port.
struct ManagedCompletionPort[P, T] {
  profile : ManagedExecutionProfile
  preparation : CompletionPreparation
  target : @pipeline.Target
  inputs : Array[ProducerRead]
  managed_inputs : Array[ManagedProducerRead[T]]
  bindings : Array[ProducerBindingIdentity]
  verify : (P) -> ManagedRetainedOutput[T]?
  mut open : Bool
  mut verifying : Bool
  mut revoked : Bool
}

///|
/// New-profile component completion, deliberately not CompletedOutput or a
/// legacy Artifact. No conversion exists by relabelling a physical digest.
/// Input provenance retains binding identities, not input read handles. The
/// material still owns backing storage needed by its particular representation.
struct ManagedCompletedOutput[T] {
  identity : Ref[Unit]
  profile : ManagedExecutionProfile
  preparation : CompletionPreparation
  target : @pipeline.Target
  bindings : Array[ProducerBindingIdentity]
  managed_bindings : Array[Ref[Unit]]
  material : ManagedRetainedOutput[T]
}

///|
/// Type-erased occurrence reference for common scheduling and lifetime
/// ownership. It is not content identity, a portable handle, read authority or
/// a replacement for the typed completed output. Only a verified managed
/// completion can create it.
struct ManagedCompletionReference {
  identity : Ref[Unit]
  available : () -> Bool
}

///|
pub fn[P, T] prepare_managed_completion_port(
  profile : ManagedExecutionProfile,
  preparation : CompletionPreparation,
  target : @pipeline.Target,
  max_entries : Int,
  max_name_bytes : Int,
  verify : (P) -> ManagedRetainedOutput[T]?,
  inputs? : Array[ProducerRead],
  managed_inputs? : Array[ManagedProducerRead[T]],
) -> Result[ManagedCompletionPort[P, T], TrustedOutputIssue] {
  // A fixed-input set has one explicit provenance family, never a partial mix
  // that silently drops the remaining ports. Acquisition may omit both.
  if inputs is Some(_) && managed_inputs is Some(_) {
    return Err(ForeignInputs)
  }
  let (_, _, bindings) = match
    validate_trusted_output_contract(
      preparation, target, max_entries, max_name_bytes, inputs,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if managed_inputs is Some(values) {
    if values.length() > max_entries {
      return Err(Limit)
    }
    let owner = completion_preparation_owner(preparation)
    if values.length() !=
      @lower.preparation_input_count(@lower.bound_preparation(owner)) {
      return Err(ForeignInputs)
    }
    for index, input in values {
      if !physical_equal(input.receiver, owner) ||
        input.input_index != index ||
        input.output.profile.cid != profile.cid ||
        !managed_producer_read_available(input) {
        return Err(ForeignInputs)
      }
    }
  }
  Ok({
    profile,
    preparation,
    target,
    bindings,
    inputs: inputs.map(values => values.copy()).unwrap_or([]),
    managed_inputs: managed_inputs.map(values => values.copy()).unwrap_or([]),
    verify,
    open: true,
    verifying: false,
    revoked: false,
  })
}

///|
pub fn[P, T] cancel_managed_completion_port(
  port : ManagedCompletionPort[P, T],
) -> Bool {
  if port.revoked || (!port.open && !port.verifying) {
    return false
  }
  port.open = false
  port.revoked = true
  true
}

///|
pub fn[P, T] complete_managed_output(
  port : ManagedCompletionPort[P, T],
  proof : P,
) -> Result[ManagedCompletedOutput[T], TrustedOutputIssue] {
  if !port.open {
    return Err(Unverified)
  }
  port.open = false
  port.verifying = true
  let result = verify_managed_completion_material(port, proof)
  port.verifying = false
  if port.revoked {
    return Err(Unverified)
  }
  let material = match result {
    Ok(material) => material
    Err(issue) => return Err(issue)
  }
  Ok({
    identity: Ref(()),
    profile: port.profile,
    preparation: port.preparation,
    target: port.target,
    bindings: port.bindings,
    managed_bindings: port.managed_inputs.map(input => input.identity),
    material,
  })
}

///|
fn[P, T] verify_managed_completion_material(
  port : ManagedCompletionPort[P, T],
  proof : P,
) -> Result[ManagedRetainedOutput[T], TrustedOutputIssue] {
  for input in port.inputs {
    if !producer_read_available(input) {
      return Err(ForeignInputs)
    }
  }
  for input in port.managed_inputs {
    if !managed_producer_read_available(input) {
      return Err(ForeignInputs)
    }
  }
  let verified = (port.verify)(proof)
  if port.revoked {
    return Err(Unverified)
  }
  guard verified is Some(material) else { return Err(Unverified) }
  let receipt = material.receipt
  let owner = completion_preparation_owner(port.preparation)
  if !managed_output_value_receipt_matches(receipt, owner, port.target) {
    return Err(ForeignOutput)
  }
  guard @lower.preparation_schema_at(
      @lower.bound_preparation(owner),
      port.target,
    )
    is Some(schema) &&
    physical_equal(schema, receipt.schema) else {
    return Err(ForeignOutput)
  }
  let live = (material.available)()
  if port.revoked || !live {
    return Err(Unverified)
  }
  for input in port.inputs {
    if !producer_read_available(input) {
      return Err(ForeignInputs)
    }
  }
  for input in port.managed_inputs {
    if !managed_producer_read_available(input) {
      return Err(ForeignInputs)
    }
  }
  Ok(material)
}

///|
pub fn[T] managed_completed_profile_cid(
  output : ManagedCompletedOutput[T],
) -> String {
  output.profile.cid
}

///|
/// Historical occurrence identity, not content equality or current permission.
pub fn[T] managed_completed_same_occurrence(
  left : ManagedCompletedOutput[T],
  right : ManagedCompletedOutput[T],
) -> Bool {
  physical_equal(left.identity, right.identity)
}

///|
pub fn[T] managed_completed_output_available(
  output : ManagedCompletedOutput[T],
) -> Bool {
  (output.material.available)()
}

///|
/// Common schedulers retain only this occurrence reference. The concrete
/// representation remains owned by the installed Host and must be supplied at
/// each typed consumer boundary.
pub fn[T] managed_completed_reference(
  output : ManagedCompletedOutput[T],
) -> ManagedCompletionReference {
  {
    identity: output.identity,
    available: fn() { managed_completed_output_available(output) },
  }
}

///|
pub fn managed_completed_reference_available(
  reference : ManagedCompletionReference,
) -> Bool {
  (reference.available)()
}

///|
pub fn[T] managed_completed_reference_matches(
  reference : ManagedCompletionReference,
  output : ManagedCompletedOutput[T],
) -> Bool {
  physical_equal(reference.identity, output.identity) &&
  managed_completed_reference_available(reference) &&
  managed_completed_output_available(output)
}

///|
pub fn[T] managed_completed_output_storage_bytes(
  output : ManagedCompletedOutput[T],
) -> Int64? {
  managed_retained_output_storage_bytes(output.material)
}

///|
pub fn[T] managed_completed_output_row_count(
  output : ManagedCompletedOutput[T],
) -> Int {
  output.material.receipt.rows
}

///|
pub fn[T] managed_completed_output_matches_port(
  output : ManagedCompletedOutput[T],
  owner : @lower.BoundPrepared,
  target : @pipeline.Target,
) -> Bool {
  physical_equal(completion_preparation_owner(output.preparation), owner) &&
  output.target == target &&
  managed_completed_output_available(output)
}

///|
/// Historical input binding only; completed independent outputs do not borrow
/// current upstream liveness. New uses still need their own admission.
pub fn[T] managed_completed_output_matches_inputs(
  output : ManagedCompletedOutput[T],
  inputs : Array[ProducerRead],
) -> Bool {
  if !output.managed_bindings.is_empty() ||
    inputs.length() != output.bindings.length() {
    return false
  }
  for index, binding in output.bindings {
    if !physical_equal(inputs[index].bound.identity, binding) {
      return false
    }
  }
  true
}

///|
/// Historical checked managed use-sites. Does not require released upstream
/// storage to remain alive after an independent downstream output completes.
pub fn[T] managed_completed_output_matches_managed_inputs(
  output : ManagedCompletedOutput[T],
  inputs : Array[ManagedProducerRead[T]],
) -> Bool {
  if !output.bindings.is_empty() ||
    inputs.length() != output.managed_bindings.length() {
    return false
  }
  for index, binding in output.managed_bindings {
    if !physical_equal(inputs[index].identity, binding) {
      return false
    }
  }
  true
}

///|
pub fn[T] managed_completed_output_matches_material(
  output : ManagedCompletedOutput[T],
  material : ManagedRetainedOutput[T],
) -> Bool {
  physical_equal(output.material, material) &&
  managed_completed_output_available(output)
}
