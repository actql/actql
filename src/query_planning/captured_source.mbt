///|
/// One already captured observation, shared by completed-input consumers.
/// No raw output getter: all handoff retains the exact observation's liveness.
struct CapturedInputSource {
  requirement : QueryRequirement
  output : @execution.CompletedOutput
  live : () -> Bool
  wire_bytes : Int
}

///|
/// Already measured canonical row-wire size, not transport frames, allocator
/// bytes, an admission exemption or a physical capacity bound.
pub struct CapturedSourceStatistics {
  rows : Int
  canonical_wire_bytes : Int
}

///|
pub fn captured_source_statistics(
  source : CapturedInputSource,
) -> CapturedSourceStatistics? {
  if !(source.live)() {
    return None
  }
  Some({
    rows: @execution.completed_row_count(source.output),
    canonical_wire_bytes: source.wire_bytes,
  })
}

///|
pub(all) enum CapturedSourceIssue {
  Unavailable
  Binding(@execution.ProducerBindingIssue)
  NativeCompletion(@execution.TrustedOutputIssue)
}

///|
pub fn captured_source_matches(
  source : CapturedInputSource,
  program : @context.ProgramSourceIdentity,
  owner : @lower.BoundPrepared,
) -> Bool {
  (source.live)() &&
  physical_equal(source.requirement.program, program) &&
  physical_equal(
    @query.query_sequence_owner(source.requirement.material.owner),
    owner,
  )
}

///|
pub fn captured_source_available(source : CapturedInputSource) -> Bool {
  (source.live)()
}

///|
/// Restrict an already owned capture without replacing its original liveness
/// checks or copying its retained data. This cannot construct a new observation.
pub fn restrict_captured_source(
  source : CapturedInputSource,
  available : () -> Bool,
) -> CapturedInputSource {
  {
    requirement: source.requirement,
    output: source.output,
    live: fn() { available() && (source.live)() },
    wire_bytes: source.wire_bytes,
  }
}

///|
pub fn captured_source_row_count(source : CapturedInputSource) -> Int? {
  if (source.live)() {
    Some(@execution.completed_row_count(source.output))
  } else {
    None
  }
}

///|
pub fn bind_captured_source(
  source : CapturedInputSource,
  receiver : @lower.BoundPrepared,
  input : Int,
) -> Result[@execution.BoundProducerInput, CapturedSourceIssue] {
  if !(source.live)() {
    return Err(Unavailable)
  }
  @execution.bind_live_completed_input(
    receiver,
    input,
    @query.query_sequence_owner(source.requirement.material.owner),
    source.output,
    source.live,
  ).map_err(issue => Binding(issue))
}

///|
pub fn mock_captured_source(
  issuer : MockQueryIssuer,
  attempt : MockQueryAttempt,
  observation : MockQueryObservation,
) -> Result[CapturedInputSource, CapturedSourceIssue] {
  let live = fn() {
    verify_mock_query_records(issuer, attempt, observation.records) is Ok(_) &&
    attempt.state is Captured(actual) &&
    physical_equal(actual, observation)
  }
  if !live() {
    return Err(Unavailable)
  }
  Ok({
    requirement: observation.records.retention._requirement,
    output: observation.records.retention.computation.output,
    live,
    wire_bytes: @execution.row_wire_usage(observation.records.retention.output).0,
  })
}

///|
pub fn broad_captured_source(
  issuer : DuckDBQueryIssuer,
  attempt : DuckDBBroadAttempt,
  observation : DuckDBBroadObservation,
) -> Result[CapturedInputSource, CapturedSourceIssue] {
  let live = fn() {
    verify_duckdb_broad_records(issuer, attempt, observation.records) is Ok(_) &&
    attempt.state is Captured(actual) &&
    physical_equal(actual, observation)
  }
  if !live() {
    return Err(Unavailable)
  }
  Ok({
    requirement: observation.records.retention.preparation.requirement,
    output: observation.records.retention.output,
    live,
    wire_bytes: @execution.row_wire_usage(
      observation.records.retention.measured.output,
    ).0,
  })
}

///|
pub fn native_captured_source(
  material : DuckDBNativeOutput,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[CapturedInputSource, CapturedSourceIssue] {
  match complete_duckdb_native_output(material, max_entries, max_name_bytes) {
    Err(issue) => Err(NativeCompletion(issue))
    Ok(output) =>
      Ok({
        requirement: material.attempt.preparation.requirement,
        output,
        live: fn() { duckdb_native_output_rows(material) is Ok(_) },
        wire_bytes: @duckdb.native_receipt_digest(
          material.observation.records.measurement.receipts,
          @duckdb.NativeResult,
        ).1,
      })
  }
}
