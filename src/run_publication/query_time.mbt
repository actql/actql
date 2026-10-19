///|
/// Computation data retained by the same admitted Run. This is not an
/// authorization clock, a physical-start permit, or evidence of COMMIT.
struct QueryEvaluationTime {
  admission : RunPublicationAdmission
  definition : PublicationContract
  value : @admitted.CheckedValue
}

///|
/// Derive query time from the original admitted definition, after its existing
/// Program, Plan, Template and Run correspondence checks. A preparation sample
/// alone cannot construct an execution context through this entry.
pub fn bind_query_evaluation_time(
  admission : RunPublicationAdmission,
  definition : PublicationContract,
  program_definition_cid : String,
  program_semantics_cid : String,
  check_environment_cid : String,
) -> Result[QueryEvaluationTime, RunProgramBindingIssue] {
  match
    check_run_publication_program_binding(
      admission, definition, program_definition_cid, program_semantics_cid, check_environment_cid,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard contract_string(definition, "created_at") is Some(created_at) &&
    @admitted.checked_timestamp_value(
      created_at,
      @contract.primitive(@contract.TimestampType, nullable=false),
    )
    is Some(value) else {
    return Err(RunProgramInvalidLifetime)
  }
  Ok({ admission, definition, value, })
}

///|
pub fn query_evaluation_time_value(
  original : QueryEvaluationTime,
) -> @admitted.CheckedValue {
  original.value
}

///|
pub fn query_evaluation_time_definition(
  original : QueryEvaluationTime,
) -> PublicationContract {
  original.definition
}

///|
/// Equal wire identities do not replace either nominal admitted original.
pub fn query_evaluation_time_matches(
  original : QueryEvaluationTime,
  admission : RunPublicationAdmission,
  definition : PublicationContract,
) -> Bool {
  physical_equal(original.admission, admission) &&
  physical_equal(original.definition, definition)
}
