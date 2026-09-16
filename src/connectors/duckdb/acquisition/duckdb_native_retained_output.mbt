///|
pub fn stream_duckdb_native_output(
  attempt : DuckDBNativeAttempt,
  max_rows : Int,
  retention : @execution.ValueLimits,
  wire : @execution.RowWireLimits,
  max_batch_bytes : Int,
  max_chunk_rows : Int,
) -> Result[Unit, DuckDBNativeAttemptIssue] {
  if !(attempt.state is Receiving) {
    return Err(InvalidState)
  }
  match
    @duckdb.stream_native_output(
      attempt.receiver,
      max_rows,
      retention,
      wire,
      max_batch_bytes,
      max_chunk_rows,
    ) {
    Err(issue) => Err(Receiving(issue))
    Ok(_) => {
      attempt.streaming_output = true
      Ok(())
    }
  }
}

///|
pub fn drain_duckdb_native_output(
  attempt : DuckDBNativeAttempt,
) -> Result[String?, DuckDBNativeAttemptIssue] {
  native_attempt_receive(attempt, () => {
    @duckdb.drain_native_output_row(attempt.receiver)
  })
}

///|
pub fn finish_duckdb_native_output_stream(
  attempt : DuckDBNativeAttempt,
) -> Result[
  (@execution.AdmittedOutputStreamReceipt, String)?,
  DuckDBNativeAttemptIssue,
] {
  native_attempt_receive(attempt, () => {
    @duckdb.finish_native_output_stream(attempt.receiver)
  })
}

///|
/// Trusted Store wiring supplies actual holding, not replacement content or a
/// completion verdict. Normal capture still checks settled transport and guards.
pub fn stage_duckdb_native_output_material(
  attempt : DuckDBNativeAttempt,
  material : @execution.RetainedOutputMaterial,
) -> Result[Unit, DuckDBEvidenceIssue] {
  if !(attempt.state is Receiving) ||
    !attempt.streaming_output ||
    attempt.retained_material is Some(_) {
    return Err(InvalidRetainedLayout)
  }
  if !@duckdb.native_output_stream_material_matches(attempt.receiver, material) {
    abort_duckdb_native_attempt(attempt)
    return Err(InvalidRetainedLayout)
  }
  attempt.retained_material = Some(material)
  Ok(())
}

///|
/// Normal common completion from one exact captured observation and held output.
/// Logical observation revocation and physical copy availability remain separate.
pub fn complete_duckdb_native_retained_output(
  issuer : DuckDBNativeIssuer,
  attempt : DuckDBNativeAttempt,
  observation : DuckDBNativeObservation,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[@execution.CompletedOutput, @execution.TrustedOutputIssue] {
  let query = @planning.query_material_owner(
    @planning.query_requirement_material(attempt.preparation.requirement),
  )
  let port = match
    @execution.prepare_trusted_retained_output_port(
      @execution.generated_completion_preparation(
        @query.query_generated_sequence(query),
      ),
      @pipeline.Step(1),
      max_entries,
      max_name_bytes,
      fn(_proof : Unit) {
        if verify_duckdb_native_observation(issuer, attempt, observation)
          is Err(_) {
          return None
        }
        guard attempt.retained_material is Some(material) &&
          @duckdb.native_output_stream_material_matches(
            attempt.receiver,
            material,
          ) else {
          return None
        }
        Some(material)
      },
    ) {
    Ok(port) => port
    Err(issue) => return Err(issue)
  }
  @execution.complete_trusted_retained_output(port, ()).map(output => {
    @execution.restrict_completed_output(output, fn() {
      verify_duckdb_native_observation(issuer, attempt, observation) is Ok(_)
    })
  })
}
