///|
/// Immutable authority admitted before one durable Run starts. The value keeps
/// the exact preparation, authorization, and Invocation Template together so
/// later publication cannot substitute their CIDs while issuing a Run
/// Definition.
struct RunPublicationAdmission {
  template : RunEvidenceValue
  prepared : RunEvidenceValue
  authorization : RunEvidenceValue
  compiled_plan : PublicationContract
  compiled_plan_cid : String
  authorization_context_cid : String
  expires_at : String
}

///|
pub(all) enum RunPublicationAdmissionIssue {
  RunAdmissionWrongEvidence
  RunAdmissionWrongPlan
  RunAdmissionCheckedProgramMismatch
  RunAdmissionTemplateMismatch
  RunAdmissionPreparedMismatch
  RunAdmissionExecutionContextMismatch
  RunAdmissionHostPolicyMismatch
  RunAdmissionDecisionMismatch
  RunAdmissionInvalidLifetime
  RunAdmissionEncoding
  RunAdmissionContract(PublicationContractIssue)
} derive(Eq, Debug)

///|
/// Bind the admitted publication evidence to an already checked Program.
/// The caller must derive these identities from that opaque checked
/// owner; this check does not turn arbitrary plan CIDs into compilation proof.
pub fn admit_checked_run_publication(
  template : RunEvidenceValue,
  prepared : RunEvidenceValue,
  authorization : RunEvidenceValue,
  compiled_plan : PublicationContract,
  program_definition_cid : String,
  parameter_values_cid : String,
  program_semantics_cid : String,
  check_environment_cid : String,
) -> Result[RunPublicationAdmission, RunPublicationAdmissionIssue] {
  if contract_string_from_value(template.value, "program_definition_cid") !=
    Some(program_definition_cid) ||
    contract_string_from_value(template.value, "parameter_values_cid") !=
    Some(parameter_values_cid) ||
    contract_string_from_value(template.value, "check_environment_cid") !=
    Some(check_environment_cid) ||
    contract_string(compiled_plan, "program_definition_cid") !=
    Some(program_definition_cid) ||
    contract_string(compiled_plan, "program_semantics_cid") !=
    Some(program_semantics_cid) {
    return Err(RunAdmissionCheckedProgramMismatch)
  }
  admit_run_publication(template, prepared, authorization, compiled_plan)
}

///|
/// Admit the exact authority that permits a Run to start. A syntactically
/// valid deny decision or an unapproved review never becomes execution
/// authority.
pub fn admit_run_publication(
  template : RunEvidenceValue,
  prepared : RunEvidenceValue,
  authorization : RunEvidenceValue,
  compiled_plan : PublicationContract,
) -> Result[RunPublicationAdmission, RunPublicationAdmissionIssue] {
  if template.name != "bound_invocation_template" ||
    prepared.name != "prepared_invocation" ||
    authorization.name != "run_authorization" {
    return Err(RunAdmissionWrongEvidence)
  }
  if compiled_plan.name != "compiled_plan" {
    return Err(RunAdmissionWrongPlan)
  }
  if contract_string_from_value(prepared.value, "invocation_template_cid") !=
    Some(template.identity) {
    return Err(RunAdmissionTemplateMismatch)
  }
  if contract_string_from_value(authorization.value, "prepared_invocation_cid") !=
    Some(prepared.identity) {
    return Err(RunAdmissionPreparedMismatch)
  }
  guard contract_string_from_value(prepared.value, "compiled_plan_cid")
    is Some(compiled_plan_cid) &&
    contract_string_from_value(prepared.value, "execution_context_cid")
    is Some(execution_context_cid) &&
    contract_string_from_value(prepared.value, "host_policy_cid")
    is Some(host_policy_cid) &&
    contract_string_from_value(prepared.value, "expires_at") is Some(expires_at) else {
    return Err(RunAdmissionWrongEvidence)
  }
  if compiled_plan.identity != compiled_plan_cid {
    return Err(RunAdmissionPreparedMismatch)
  }
  guard contract_string_from_value(template.value, "program_definition_cid")
    is Some(program_definition_cid) else {
    return Err(RunAdmissionWrongEvidence)
  }
  if contract_string(compiled_plan, "program_definition_cid") !=
    Some(program_definition_cid) {
    return Err(RunAdmissionWrongPlan)
  }
  if contract_string_from_value(authorization.value, "execution_context_cid") !=
    Some(execution_context_cid) {
    return Err(RunAdmissionExecutionContextMismatch)
  }
  if contract_string_from_value(authorization.value, "host_policy_cid") !=
    Some(host_policy_cid) {
    return Err(RunAdmissionHostPolicyMismatch)
  }
  let prepared_decision = contract_string_from_value(
    prepared.value,
    "policy_decision",
  )
  let authorized_decision = contract_string_from_value(
    authorization.value,
    "decision",
  )
  match (prepared_decision, authorized_decision) {
    (Some("allow"), Some("allowed")) => ()
    _ => return Err(RunAdmissionDecisionMismatch)
  }
  Ok({
    template,
    prepared,
    authorization,
    compiled_plan,
    compiled_plan_cid,
    authorization_context_cid: execution_context_cid,
    expires_at,
  })
}

///|
pub fn run_publication_prepared(
  admission : RunPublicationAdmission,
) -> RunEvidenceValue {
  admission.prepared
}

///|
pub fn run_publication_authorization(
  admission : RunPublicationAdmission,
) -> RunEvidenceValue {
  admission.authorization
}

///|
/// Issue the immutable Run Definition from previously admitted authority. The
/// initial input set is fixed here and cannot later be replaced by captured
/// observations.
pub fn issue_run_definition(
  admission : RunPublicationAdmission,
  scope_id : String,
  run_id : String,
  input_artifact_set_cid : String,
  created_at : String,
  valid_until : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, RunPublicationAdmissionIssue] {
  if created_at >= valid_until || valid_until > admission.expires_at {
    return Err(RunAdmissionInvalidLifetime)
  }
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(RunAdmissionEncoding)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "authorization_context_cid")
    @encode.string_value(writer, admission.authorization_context_cid)
    @encode.key(writer, "compiled_plan_cid")
    @encode.string_value(writer, admission.compiled_plan_cid)
    @encode.key(writer, "created_at")
    @encode.string_value(writer, created_at)
    @encode.key(writer, "input_artifact_set_cid")
    @encode.string_value(writer, input_artifact_set_cid)
    @encode.key(writer, "invocation_template_cid")
    @encode.string_value(writer, admission.template.identity)
    @encode.key(writer, "run_id")
    @encode.string_value(writer, run_id)
    @encode.key(writer, "scope_id")
    @encode.string_value(writer, scope_id)
    @encode.key(writer, "valid_until")
    @encode.string_value(writer, valid_until)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-run-definition/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(RunAdmissionEncoding)
  }
  let body = @encode.finish(writer) catch {
    _ => return Err(RunAdmissionEncoding)
  }
  match
    seal_publication_contract(
      "run_definition", body, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => Ok(value)
    Err(issue) => Err(RunAdmissionContract(issue))
  }
}
