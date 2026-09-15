///|
pub fn mock_captured_source(
  issuer : MockQueryIssuer,
  attempt : MockQueryAttempt,
  observation : MockQueryObservation,
) -> Result[@query.CapturedInputSource, @query.CapturedSourceIssue] {
  let live = fn() {
    verify_mock_query_records(issuer, attempt, observation.records) is Ok(_) &&
    attempt.state is Captured(actual) &&
    physical_equal(actual, observation)
  }
  if !live() {
    return Err(Unavailable)
  }
  let requirement = observation.records.retention._requirement
  @query.prepare_trusted_capture_port(
    @planning.query_material_owner(
      @planning.query_requirement_material(requirement),
    ),
    @planning.query_requirement_program(requirement),
    fn(proof : MockQueryObservation) {
      if physical_equal(proof, observation) && live() {
        Some(
          (
            observation.records.retention.computation.output,
            @execution.row_wire_usage(observation.records.retention.output).0,
          ),
        )
      } else {
        None
      }
    },
  ).bind(port => @query.capture_verified_source(port, observation))
}
