///|
/// Facts obtained from the retained execution and trusted activation owners.
/// These are comparison inputs, not proof that an inventory is complete or
/// that its physical input is durable. The execution owner retains that proof.
pub(all) struct ModelInvocationBoundary {
  unit_id : String
  task_index : Int64
  strategy_revision : Int64
  inference_barrier_cid : String
  account_id : String
  configuration_cid : String
  entry_id : String
  principal : String
  connection : String
  resource : String
  context_cid : String
  installation_revision_cid : String
  configuration_contract_cid : String
  provider_configuration_cid : String
} derive(Eq, Debug)

///|
/// Deterministically linked immutable originals. This is neither a complete
/// prepared-call-set handle nor a dispatch permit. In particular, an empty
/// declared inventory does not establish that an executor has no calls.
pub struct BoundModelInvocationScope {
  priv admission : RunPublicationAdmission
  priv definition : PublicationContract
  priv scope : RunEvidenceValue
  priv provider : RunEvidenceValue
  priv input : RunEvidenceValue
  priv slots : Array[RunEvidenceValue]
  priv expected : ModelInvocationBoundary
}

///|
fn model_scope_count(value : @json.CanonicalValue, name : String) -> Int64? {
  match @json.object_field(value, name) {
    Some(@json.Number(number)) => @scalar.read_safe_integer(number)
    _ => None
  }
}

///|
fn model_scope_strings(
  value : @json.CanonicalValue,
  name : String,
) -> Array[String]? {
  guard @json.object_field(value, name) is Some(@json.Array(items)) else {
    return None
  }
  let result : Array[String] = []
  for index in 0..<@json.array_count(items) {
    guard @json.array_at(items, index) is Some(@json.String(text)) else {
      return None
    }
    result.push(text)
  }
  Some(result)
}

///|
/// Bind a scope to the original admitted Run and exact declared originals.
/// No caller-supplied PreparedInvocation identity can replace admission.prepared.
/// Actual fixed-input/call completeness, custody, limits, current authority and
/// provider installation are independently established by their owning ports.
pub fn bind_model_invocation_scope(
  admission : RunPublicationAdmission,
  definition : PublicationContract,
  scope : RunEvidenceValue,
  provider : RunEvidenceValue,
  input : RunEvidenceValue,
  ordered_slots : Array[RunEvidenceValue],
  expected : ModelInvocationBoundary,
) -> Result[BoundModelInvocationScope, RunEvidenceValueIssue] {
  if definition.name != "run_definition" ||
    scope.name != "model_invocation_scope" ||
    provider.name != "model_provider_binding" ||
    input.name != "model_input_artifact" ||
    ordered_slots.any(slot => slot.name != "model_call_slot") {
    return Err(UnknownRunEvidence)
  }
  if !model_template_requires_slots(admission.template) {
    return Err(RunEvidenceReferenceMismatch("model_scope.infer_profile"))
  }
  if expected.unit_id.is_empty() ||
    expected.task_index < 0L ||
    expected.strategy_revision < 0L {
    return Err(RunEvidenceReferenceMismatch("model_scope.occurrence"))
  }
  if check_run_publication_program_binding(
      admission,
      definition,
      contract_string_from_value(input.value, "program_definition_cid").unwrap(),
      contract_string(admission.compiled_plan, "program_semantics_cid").unwrap(),
      contract_string_from_value(
        admission.template.value,
        "check_environment_cid",
      ).unwrap(),
    )
    is Err(_) {
    return Err(RunEvidenceReferenceMismatch("model_scope.run_admission"))
  }
  for
    (field, identity) in [
      ("run_definition_cid", definition.identity),
      ("input_artifact_cid", input.identity),
      ("provider_binding_cid", provider.identity),
      ("inference_barrier_cid", expected.inference_barrier_cid),
    ] {
    if contract_string_from_value(scope.value, field) != Some(identity) {
      return Err(RunEvidenceReferenceMismatch("model_scope." + field))
    }
  }
  if model_scope_count(scope.value, "task_index") != Some(expected.task_index) ||
    model_scope_count(scope.value, "strategy_revision") !=
    Some(expected.strategy_revision) {
    return Err(RunEvidenceReferenceMismatch("model_scope.occurrence"))
  }
  for
    (field, identity) in [
      ("provider_id", expected.connection),
      ("installation_revision_cid", expected.installation_revision_cid),
      ("configuration_contract_cid", expected.configuration_contract_cid),
      ("configuration_cid", expected.provider_configuration_cid),
    ] {
    if contract_string_from_value(provider.value, field) != Some(identity) {
      return Err(
        RunEvidenceReferenceMismatch("model_provider_binding." + field),
      )
    }
  }
  guard @json.object_field(scope.value, "authorization_context")
    is Some(context) else {
    return Err(
      RunEvidenceReferenceMismatch("model_scope.authorization_context"),
    )
  }
  for
    (field, identity) in [
      ("account_id", expected.account_id),
      ("configuration_cid", expected.configuration_cid),
      ("entry_id", expected.entry_id),
      ("principal", expected.principal),
      ("connection", expected.connection),
      ("resource", expected.resource),
      ("operation", "infer"),
      ("boundary", "activation"),
      ("context_cid", expected.context_cid),
    ] {
    if contract_string_from_value(context, field) != Some(identity) {
      return Err(
        RunEvidenceReferenceMismatch(
          "model_scope.authorization_context." + field,
        ),
      )
    }
  }
  if model_scope_strings(scope.value, "model_call_slot_cids") !=
    Some(ordered_slots.map(slot => slot.identity)) {
    return Err(RunEvidenceReferenceMismatch("model_scope.model_call_slot_cids"))
  }
  for slot in ordered_slots {
    if contract_string_from_value(slot.value, "input_artifact_cid") !=
      Some(input.identity) ||
      contract_string_from_value(slot.value, "model_task_cid") !=
      Some(expected.resource) {
      return Err(RunEvidenceReferenceMismatch("model_scope.slot"))
    }
    for
      field in [
        "program_definition_cid", "unit_definition_cid", "effective_inputs_cid",
      ] {
      if contract_string_from_value(slot.value, field) !=
        contract_string_from_value(input.value, field) {
        return Err(RunEvidenceReferenceMismatch("model_scope.slot." + field))
      }
    }
    if model_scope_count(slot.value, "source_ordinal") !=
      model_scope_count(input.value, "source_ordinal") {
      return Err(
        RunEvidenceReferenceMismatch("model_scope.slot.source_ordinal"),
      )
    }
  }
  Ok({
    admission,
    definition,
    scope,
    provider,
    input,
    slots: ordered_slots.copy(),
    expected,
  })
}

///|
/// Exact identity facts only; callers cannot use them as execution authority.
pub fn model_invocation_scope_cid(value : BoundModelInvocationScope) -> String {
  value.scope.identity
}

///|
pub fn model_invocation_scope_run(
  value : BoundModelInvocationScope,
) -> (String, String, String) {
  (
    contract_string(value.definition, "run_id").unwrap(),
    value.definition.identity,
    value.expected.unit_id,
  )
}

///|
pub fn model_invocation_scope_prepared_cid(
  value : BoundModelInvocationScope,
) -> String {
  value.admission.prepared.identity
}

///|
pub fn model_invocation_scope_input_cid(
  value : BoundModelInvocationScope,
) -> String {
  value.input.identity
}

///|
pub fn model_invocation_scope_provider_cid(
  value : BoundModelInvocationScope,
) -> String {
  value.provider.identity
}

///|
pub fn model_invocation_scope_slots(
  value : BoundModelInvocationScope,
) -> Array[String] {
  value.slots.map(slot => slot.identity)
}

///|
pub fn model_invocation_scope_boundary(
  value : BoundModelInvocationScope,
) -> ModelInvocationBoundary {
  value.expected
}

///|
/// The review describes the scope but preserves the actual original Run
/// PreparedInvocation. Its context and policy must come from that admission.
pub fn check_model_invocation_review(
  value : BoundModelInvocationScope,
  review : RunEvidenceValue,
) -> Result[Unit, RunEvidenceValueIssue] {
  if review.name != "run_review_projection" {
    return Err(UnknownRunEvidence)
  }
  for
    (field, identity) in [
      ("prepared_invocation_cid", value.admission.prepared.identity),
      ("execution_context_cid", value.admission.authorization_context_cid),
      ("host_policy_cid", run_publication_host_policy(value.admission)),
    ] {
    if contract_string_from_value(review.value, field) != Some(identity) {
      return Err(RunEvidenceReferenceMismatch("model_review." + field))
    }
  }
  guard @json.object_field(review.value, "displayed_scope") is Some(displayed) else {
    return Err(RunEvidenceReferenceMismatch("model_review.displayed_scope"))
  }
  if contract_string_from_value(displayed, "model_invocation_scope_cid") !=
    Some(value.scope.identity) ||
    model_scope_strings(displayed, "model_call_slot_cids") !=
    Some(model_invocation_scope_slots(value)) {
    return Err(RunEvidenceReferenceMismatch("model_review.displayed_scope"))
  }
  Ok(())
}

///|
pub fn model_invocation_review_expires_at(review : RunEvidenceValue) -> String? {
  if review.name == "run_review_projection" {
    contract_string_from_value(review.value, "expires_at")
  } else {
    None
  }
}

///|
pub fn model_invocation_scope_valid_until(
  value : BoundModelInvocationScope,
) -> String {
  contract_string(value.definition, "valid_until").unwrap()
}

///|
/// Historical Run-original linkage, without a current-clock or send decision.
pub fn check_model_original_run_binding(
  admission : RunPublicationAdmission,
  definition : PublicationContract,
) -> Result[Unit, RunEvidenceValueIssue] {
  match
    check_run_publication_program_binding(
      admission,
      definition,
      contract_string_from_value(
        admission.template.value,
        "program_definition_cid",
      ).unwrap(),
      contract_string(admission.compiled_plan, "program_semantics_cid").unwrap(),
      contract_string_from_value(
        admission.template.value,
        "check_environment_cid",
      ).unwrap(),
    ) {
    Ok(_) => Ok(())
    Err(_) => Err(RunEvidenceReferenceMismatch("model_scope.run_admission"))
  }
}

///|
pub fn model_invocation_scope_slot(
  value : BoundModelInvocationScope,
  ordinal : Int,
) -> (String, String, String)? {
  value.slots
  .get(ordinal)
  .map(slot => {
    (
      slot.identity,
      contract_string_from_value(slot.value, "model_task_cid").unwrap(),
      contract_string_from_value(slot.value, "fixed_request_cid").unwrap(),
    )
  })
}

///|
/// Immutable attempt/authority linkage for the scoped delegated path. This
/// does not validate the physical retry contract, permit another attempt,
/// classify a failure, or establish current authority. Those owners must
/// additionally check the one-based original index before each actual send.
/// Historical checks remain valid after cancellation or authority expiry.
pub fn check_model_invocation_attempt(
  scope : BoundModelInvocationScope,
  ordinal : Int,
  attempt : RunEvidenceValue,
  authority : RunEvidenceValue,
  attempt_index : Int64,
) -> Result[Unit, RunEvidenceValueIssue] {
  if attempt.name != "model_call_attempt" ||
    authority.name != "model_dispatch_authority" {
    return Err(UnknownRunEvidence)
  }
  guard scope.slots.get(ordinal) is Some(slot) else {
    return Err(RunEvidenceReferenceMismatch("model_attempt.ordinal"))
  }
  if attempt_index < 1L ||
    model_scope_count(attempt.value, "attempt") != Some(attempt_index) {
    return Err(RunEvidenceReferenceMismatch("model_attempt.attempt"))
  }
  for
    (body, field, identity) in [
      (attempt, "slot_cid", slot.identity),
      (attempt, "authority_evidence_cid", authority.identity),
      (attempt, "run_definition_cid", scope.definition.identity),
      (attempt, "provider_id", scope.expected.connection),
      (authority, "run_definition_cid", scope.definition.identity),
      (
        authority,
        "run_authorization_cid",
        scope.admission.authorization.identity,
      ),
      (
        authority,
        "execution_context_cid",
        scope.admission.authorization_context_cid,
      ),
      (
        authority,
        "host_policy_cid",
        run_publication_host_policy(scope.admission),
      ),
      (authority, "model_invocation_scope_cid", scope.scope.identity),
      (authority, "account_configuration_cid", scope.expected.configuration_cid),
      (authority, "entry_id", scope.expected.entry_id),
      (authority, "principal", scope.expected.principal),
      (authority, "connection", scope.expected.connection),
      (authority, "resource", scope.expected.resource),
      (authority, "operation", "infer"),
      (
        authority,
        "program_definition_cid",
        contract_string_from_value(scope.input.value, "program_definition_cid").unwrap(),
      ),
    ] {
    if contract_string_from_value(body.value, field) != Some(identity) {
      return Err(RunEvidenceReferenceMismatch("model_attempt." + field))
    }
  }
  for body in [attempt, authority] {
    for field in ["model_task_cid", "fixed_request_cid"] {
      if contract_string_from_value(body.value, field) !=
        contract_string_from_value(slot.value, field) {
        return Err(RunEvidenceReferenceMismatch("model_attempt." + field))
      }
    }
  }
  // These are historical authority originals, never a current send permit.
  // An ordinary Account allow has no answering authority or approval claims;
  // a delegated Host permit must retain its exact approved invocation claim.
  let claims = model_scope_strings(authority.value, "satisfied_claims").unwrap()
  let answering = contract_string_from_value(
    authority.value,
    "answering_authority",
  )
  match contract_string_from_value(authority.value, "basis") {
    Some("account_allow") =>
      if answering is Some(_) || !claims.is_empty() {
        return Err(RunEvidenceReferenceMismatch("model_attempt.account_allow"))
      }
    Some("host_permit") =>
      if answering is None || !claims.contains("invocation_scope_approved") {
        return Err(RunEvidenceReferenceMismatch("model_attempt.approval"))
      }
    _ =>
      return Err(RunEvidenceReferenceMismatch("model_attempt.authority_basis"))
  }
  Ok(())
}

///|
/// Authenticate a saved attempt against the same original Run admission and
/// exact fixed slot. Current dispatch permission is deliberately separate.
pub fn bind_model_invocation_saved_call(
  value : BoundModelInvocationScope,
  ordinal : Int,
  capture : RunEvidenceValue,
  attempt : RunEvidenceValue,
  accounting : RunEvidenceValue,
  outcome : RunEvidenceValue,
  authority : RunEvidenceValue,
) -> Result[BoundModelSlotCapture, RunEvidenceValueIssue] {
  guard value.slots.get(ordinal) is Some(call) else {
    return Err(RunEvidenceReferenceMismatch("model_scope.slot"))
  }
  match check_model_invocation_attempt(value, ordinal, attempt, authority, 1L) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let binding = match bind_model_slot_capture(call, capture) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  match
    bind_model_slot_attempt_evidence(
      binding,
      attempt,
      accounting,
      outcome,
      authority,
      value.admission,
      value.definition,
    ) {
    Err(issue) => Err(issue)
    Ok(_) => Ok(binding)
  }
}
