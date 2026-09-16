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
  material : ManagedRetainedOutput[T]
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
) -> Result[ManagedCompletionPort[P, T], TrustedOutputIssue] {
  let (_, _, bindings) = match
    validate_trusted_output_contract(
      preparation, target, max_entries, max_name_bytes, inputs,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({
    profile,
    preparation,
    target,
    bindings,
    inputs: inputs.map(values => values.copy()).unwrap_or([]),
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
  if inputs.length() != output.bindings.length() {
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
pub fn[T] managed_completed_output_matches_material(
  output : ManagedCompletedOutput[T],
  material : ManagedRetainedOutput[T],
) -> Bool {
  physical_equal(output.material, material) &&
  managed_completed_output_available(output)
}
