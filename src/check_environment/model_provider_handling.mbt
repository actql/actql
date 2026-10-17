///|
/// An integrity-checked original request_data_handling Envelope in the SAME
/// installed configuration's model profile. This is DATA, not registry/Account
/// membership, geographical processing evidence or an installation grant.
struct ModelProviderHandling {
  envelope : ContractEnvelopeData
  constraints : ModelDataHandling
}

///|
fn model_provider_handling_read(
  root : @decode.Cursor,
  budget : ModelTaskBudget,
) -> ModelProviderHandling raise ModelTaskStop {
  // The existing envelope reader performs two complete bounded emissions.
  // Reserve their declared maxima before either writer/hash is allocated.
  // These finite work bounds are not physical workspace reservation.
  for _ in 0..<2 {
    model_task_charge(budget, budget.limits.bodies.max_bytes, root)
    model_task_charge(budget, budget.limits.bodies.max_nodes, root)
  }
  let envelope = match
    read_contract_envelope_data(root, budget.limits.bodies, 0) {
    Ok(value) => value
    Err(ContractIssue::IdentityMismatch(_)) =>
      model_task_fail(IdentityMismatch, root)
    Err(BudgetExceeded) => model_task_fail(BodyLimit, root)
    Err(_) => model_task_fail(InvalidBody, root)
  }
  if envelope.kind != "request_data_handling" {
    model_task_fail(InvalidBody, root)
  }
  let object = model_task_object(
    envelope.body,
    ["accepted_classifications", "allowed_regions", "retention", "training_use"],
    budget,
  )
  let constraints = model_task_handling_constraints(
    object,
    envelope.body,
    budget,
    envelope.cid,
  )
  { envelope, constraints, }
}

///|
pub fn model_provider_handling_identity(
  value : ModelProviderHandling,
) -> String {
  value.constraints.cid
}

///|
/// Project the exact verified policy original for saved material admission.
/// The caller's bounded writer owns output/workspace and its lifetime.
pub fn emit_model_provider_handling_original(
  value : ModelProviderHandling,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  emit_except(value.envelope.original, writer, None)
}

///|
/// The existing ModelTask form retains the same policy CID and constraints.
/// Do not copy a Host JSON policy or invent defaults during this projection.
pub fn emit_model_provider_handling(
  value : ModelProviderHandling,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  for index in 0..<4 {
    let (key, child) = @decode.field_at(value.envelope.body, index).unwrap()
    if index == 2 {
      @encode.key(writer, "contract_cid")
      @encode.string_value(writer, value.constraints.cid)
    }
    @encode.key(writer, key)
    emit_except(child, writer, None)
  }
  @encode.end_object(writer)
}
