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
    requirement.material.owner,
    requirement.program,
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
    requirement.material.owner,
    requirement.program,
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
    requirement.material.owner,
    requirement.program,
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
