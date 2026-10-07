///|
/// Original publication authority retained for a completed dispatch. This
/// value grants neither compilation nor execution: the physical caller must
/// separately restore completed custody and inspect its current authority,
/// Site generation, cancellation and exclusive maintenance ownership.
struct RecordedRunPublication {
  admission : RunPublicationAdmission
  definition : PublicationContract
  result : ResultDefinition
}

///|
/// Close the original Template, Plan, Run and Result references without
/// preparing the Program with a newer compiler. Inputs must first be admitted
/// by the existing bounded evidence and publication-contract owners.
pub fn prepare_recorded_run_publication(
  admission : RunPublicationAdmission,
  definition : PublicationContract,
  result : ResultDefinition,
) -> Result[RecordedRunPublication, RunProgramBindingIssue] {
  let program = result_definition_program_cid(result)
  guard contract_string(admission.compiled_plan, "program_semantics_cid")
    is Some(semantics) &&
    contract_string_from_value(
      admission.template.value,
      "check_environment_cid",
    )
    is Some(environment) else {
    return Err(RunProgramForeignPlan)
  }
  match
    check_run_publication_program_binding(
      admission, definition, program, semantics, environment,
    ) {
    Ok(_) => Ok({ admission, definition, result, })
    Err(issue) => Err(issue)
  }
}

///|
pub fn recorded_run_publication_run_cid(
  recorded : RecordedRunPublication,
) -> String {
  publication_contract_identity(recorded.definition)
}

///|
pub fn recorded_run_publication_result_cid(
  recorded : RecordedRunPublication,
) -> String {
  result_definition_cid(recorded.result)
}

///|
/// Match the exact authority retained in the original dispatch envelope.
/// Another valid preparation or renewed authorization for the same context
/// is not a replacement for the original evidence.
pub fn recorded_run_publication_has_original_evidence(
  recorded : RecordedRunPublication,
  prepared_wire : String,
  authorization_wire : String,
) -> Bool {
  run_evidence_value_json(recorded.admission.prepared) == prepared_wire &&
  run_evidence_value_json(recorded.admission.authorization) ==
  authorization_wire
}

///|
/// Original deadlines remain effective. Structural restoration does not
/// refresh authority, and this check does not establish current external
/// authorization or permission to start an executor.
pub fn recorded_run_publication_current(
  recorded : RecordedRunPublication,
  at : String,
) -> Bool {
  run_publication_start_current(recorded.admission, recorded.definition, at)
}

///|
/// Match the original scope and lifetime for cleanup only. This is not a
/// current execution authorization and does not extend either deadline.
pub fn recorded_run_publication_has_original_context(
  recorded : RecordedRunPublication,
  scope_id : String,
  run_id : String,
  created_at : String,
  valid_until : String,
) -> Bool {
  contract_string(recorded.definition, "scope_id") == Some(scope_id) &&
  contract_string(recorded.definition, "run_id") == Some(run_id) &&
  contract_string(recorded.definition, "created_at") == Some(created_at) &&
  contract_string(recorded.definition, "valid_until") == Some(valid_until)
}

///|
/// Bind a checked graph to the original admitted Plan for cleanup. A newer
/// Template or executable Plan is neither issued nor substituted. Matching
/// these facts grants no execution, borrow, publication or capacity return.
pub fn recorded_run_publication_matches_cleanup_graph(
  recorded : RecordedRunPublication,
  program_definition_cid : String,
  program_semantics_cid : String,
  check_environment_cid : String,
  parameter_values_cid : String,
  invocation_bindings_cid : String,
  aoa_logical_cid : String,
) -> Bool {
  check_run_publication_program_binding(
    recorded.admission,
    recorded.definition,
    program_definition_cid,
    program_semantics_cid,
    check_environment_cid,
  )
  is Ok(_) &&
  run_definition_has_empty_initial_input_artifact_set(recorded.definition) &&
  contract_string_from_value(
    recorded.admission.template.value,
    "parameter_values_cid",
  ) ==
  Some(parameter_values_cid) &&
  contract_string_from_value(
    recorded.admission.template.value,
    "invocation_bindings_cid",
  ) ==
  Some(invocation_bindings_cid) &&
  contract_string(recorded.admission.compiled_plan, "aoa_logical_cid") ==
  Some(aoa_logical_cid)
}
