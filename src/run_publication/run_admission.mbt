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
pub(all) enum RunProgramBindingIssue {
  RunProgramWrongDefinition
  RunProgramForeignPlan
  RunProgramForeignTemplate
  RunProgramForeignRun
  RunProgramInvalidLifetime
} derive(Eq, Debug)

///|
pub(all) enum EffectPreviewRunBindingIssue {
  PreviewRunWrongInvocation
  PreviewRunForeignTemplate
  PreviewRunForeignRun
  PreviewRunForeignPlan
  PreviewRunForeignInvocation
} derive(Eq, Debug)

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
pub fn run_publication_compiled_plan_cid(
  admission : RunPublicationAdmission,
) -> String {
  admission.compiled_plan_cid
}

///|
/// Bind an admitted Run to the exact checked Program identities supplied by
/// its owner. This closes the Plan, Template, and Run references; it does not
/// prove that execution or Effect application has occurred.
pub fn check_run_publication_program_binding(
  admission : RunPublicationAdmission,
  run_definition : PublicationContract,
  program_definition_cid : String,
  program_semantics_cid : String,
  check_environment_cid : String,
) -> Result[Unit, RunProgramBindingIssue] {
  if run_definition.name != "run_definition" {
    return Err(RunProgramWrongDefinition)
  }
  if contract_string(admission.compiled_plan, "program_definition_cid") !=
    Some(program_definition_cid) ||
    contract_string(admission.compiled_plan, "program_semantics_cid") !=
    Some(program_semantics_cid) {
    return Err(RunProgramForeignPlan)
  }
  if contract_string_from_value(
      admission.template.value,
      "program_definition_cid",
    ) !=
    Some(program_definition_cid) ||
    contract_string_from_value(
      admission.template.value,
      "check_environment_cid",
    ) !=
    Some(check_environment_cid) {
    return Err(RunProgramForeignTemplate)
  }
  if contract_string(run_definition, "compiled_plan_cid") !=
    Some(admission.compiled_plan_cid) ||
    contract_string(run_definition, "invocation_template_cid") !=
    Some(admission.template.identity) ||
    contract_string(run_definition, "authorization_context_cid") !=
    Some(admission.authorization_context_cid) {
    return Err(RunProgramForeignRun)
  }
  guard contract_string(run_definition, "created_at") is Some(created_at) &&
    contract_string(run_definition, "valid_until") is Some(valid_until) else {
    return Err(RunProgramInvalidLifetime)
  }
  if created_at >= valid_until || valid_until > admission.expires_at {
    return Err(RunProgramInvalidLifetime)
  }
  Ok(())
}

///|
/// Bind one private Preview to the exact Run and concrete Invocation identity.
/// ObservationSet closure, static Program closure, and current apply authority
/// are independently required by their own owners.
pub fn check_effect_preview_run_binding(
  admission : RunPublicationAdmission,
  run_definition : PublicationContract,
  invocation : PublicationContract,
  preview : EffectPreviewIdentity,
) -> Result[Unit, EffectPreviewRunBindingIssue] {
  match
    check_run_publication_program_binding(
      admission,
      run_definition,
      preview.program_definition_cid,
      preview.program_semantics_cid,
      preview.check_environment_cid,
    ) {
    Ok(_) => ()
    Err(RunProgramForeignPlan) => return Err(PreviewRunForeignPlan)
    Err(RunProgramForeignTemplate) => return Err(PreviewRunForeignTemplate)
    Err(_) => return Err(PreviewRunForeignRun)
  }
  if invocation.name != "run_invocation" {
    return Err(PreviewRunWrongInvocation)
  }
  if contract_string(invocation, "invocation_template_cid") !=
    Some(admission.template.identity) {
    return Err(PreviewRunForeignTemplate)
  }
  if preview.run_identity_cid != run_definition.identity {
    return Err(PreviewRunForeignRun)
  }
  if preview.compiled_plan_cid != admission.compiled_plan_cid {
    return Err(PreviewRunForeignPlan)
  }
  if preview.invocation_cid != invocation.identity {
    return Err(PreviewRunForeignInvocation)
  }
  Ok(())
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
