///|
/// Expose an exact retained Salesforce observation to the common captured
/// input boundary. The source remains live only while its issuer, attempt,
/// transport evidence, and captured observation still agree.
pub fn salesforce_broad_captured_source(
  issuer : SalesforceBroadIssuer,
  attempt : SalesforceBroadAttempt,
  observation : SalesforceBroadObservation,
) -> Result[@query.CapturedInputSource, @query.CapturedSourceIssue] {
  let live = fn() {
    verify_salesforce_broad_records(issuer, attempt, observation.records)
    is Ok(_) &&
    attempt.state is Captured(actual) &&
    physical_equal(actual, observation)
  }
  if !live() {
    return Err(Unavailable)
  }
  let requirement = attempt.preparation.requirement
  @query.prepare_trusted_capture_port(
    @planning.query_material_owner(
      @planning.query_requirement_material(requirement),
    ),
    @planning.query_requirement_program(requirement),
    fn(proof : SalesforceBroadObservation) {
      if physical_equal(proof, observation) && live() {
        Some(
          (
            observation.records.retention.completion.output,
            @execution.row_wire_usage(
              observation.records.retention.measured.output,
            ).0,
          ),
        )
      } else {
        None
      }
    },
  ).bind(port => @query.capture_verified_source(port, observation))
}
