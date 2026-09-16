///|
pub fn broad_captured_source(
  issuer : DuckDBQueryIssuer,
  attempt : DuckDBBroadAttempt,
  observation : DuckDBBroadObservation,
) -> Result[@query.CapturedInputSource, @query.CapturedSourceIssue] {
  let live = fn() {
    verify_duckdb_broad_records(issuer, attempt, observation.records) is Ok(_) &&
    attempt.state is Captured(actual) &&
    physical_equal(actual, observation)
  }
  if !live() {
    return Err(Unavailable)
  }
  let requirement = observation.records.retention.preparation.requirement
  @query.prepare_trusted_capture_port(
    @planning.query_material_owner(
      @planning.query_requirement_material(requirement),
    ),
    @planning.query_requirement_program(requirement),
    fn(proof : DuckDBBroadObservation) {
      if physical_equal(proof, observation) && live() {
        Some(
          (
            observation.records.retention.output,
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

///|
pub fn native_captured_source(
  material : DuckDBNativeOutput,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[@query.CapturedInputSource, @query.CapturedSourceIssue] {
  let output = match
    complete_duckdb_native_output(material, max_entries, max_name_bytes) {
    Ok(output) => output
    Err(issue) => return Err(Completion(issue))
  }
  let requirement = material.attempt.preparation.requirement
  @query.prepare_trusted_capture_port(
    @planning.query_material_owner(
      @planning.query_requirement_material(requirement),
    ),
    @planning.query_requirement_program(requirement),
    fn(proof : DuckDBNativeOutput) {
      if physical_equal(proof, material) &&
        duckdb_native_output_rows(proof) is Ok(_) {
        Some(
          (
            output,
            @duckdb.native_receipt_digest(
              material.observation.records.measurement.receipts,
              @duckdb.NativeResult,
            ).1,
          ),
        )
      } else {
        None
      }
    },
  ).bind(port => @query.capture_verified_source(port, material))
}

///|
pub fn native_retained_captured_source(
  issuer : DuckDBNativeIssuer,
  attempt : DuckDBNativeAttempt,
  observation : DuckDBNativeObservation,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[@query.CapturedInputSource, @query.CapturedSourceIssue] {
  let output = match
    complete_duckdb_native_retained_output(
      issuer, attempt, observation, max_entries, max_name_bytes,
    ) {
    Ok(output) => output
    Err(issue) => return Err(Completion(issue))
  }
  let requirement = attempt.preparation.requirement
  @query.prepare_trusted_capture_port(
    @planning.query_material_owner(
      @planning.query_requirement_material(requirement),
    ),
    @planning.query_requirement_program(requirement),
    fn(proof : DuckDBNativeObservation) {
      if physical_equal(proof, observation) &&
        verify_duckdb_native_observation(issuer, attempt, observation) is Ok(_) &&
        @execution.completed_output_available(output) {
        Some(
          (
            output,
            @duckdb.native_receipt_digest(
              observation.records.measurement.receipts,
              @duckdb.NativeResult,
            ).1,
          ),
        )
      } else {
        None
      }
    },
  ).bind(port => @query.capture_verified_source(port, observation))
}
