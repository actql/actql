///|
/// Original publication authority retained for a completed dispatch. This
/// value grants neither compilation nor execution: the physical caller must
/// separately restore completed custody and inspect its current authority,
/// Site generation, cancellation and exclusive maintenance ownership.
pub struct RecordedRunPublication {
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
