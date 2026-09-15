///|
/// One already captured observation, shared by completed-input consumers.
/// No raw output getter: all handoff retains the exact observation's liveness.
struct CapturedInputSource {
  program : @context.ProgramSourceIdentity
  owner : QuerySequence
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
  Completion(@execution.TrustedOutputIssue)
  Storage(@execution.ProducerReadIssue)
}

///|
/// Read-only physical export of the completed capture, never a raw output that
/// bypasses observation liveness through ordinary producer binding.
pub fn captured_source_storage(
  source : CapturedInputSource,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[@execution.ProducerStorage, CapturedSourceIssue] {
  if !(source.live)() {
    return Err(Unavailable)
  }
  @execution.prepare_producer_storage(
    @execution.restrict_completed_output(source.output, source.live),
    max_entries,
    max_name_bytes,
  ).map_err(issue => Storage(issue))
}

///|
pub fn captured_source_matches(
  source : CapturedInputSource,
  program : @context.ProgramSourceIdentity,
  owner : @lower.BoundPrepared,
) -> Bool {
  (source.live)() &&
  physical_equal(source.program, program) &&
  physical_equal(query_sequence_owner(source.owner), owner)
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
    program: source.program,
    owner: source.owner,
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
    query_sequence_owner(source.owner),
    source.output,
    source.live,
  ).map_err(issue => Binding(issue))
}

///|
/// Trusted installed capture verifier, not a Program/Connector configuration
/// callback. P must be the implementation's exact completed observation proof.
/// The verifier returns owned completed material, never a success Bool or CID.
struct TrustedCapturePort[P] {
  owner : QuerySequence
  program : @context.ProgramSourceIdentity
  verify : (P) -> (@execution.CompletedOutput, Int)?
}

///|
pub fn query_program_matches(
  sequence : QuerySequence,
  program : @context.ProgramSourceIdentity,
) -> Bool {
  let query = query_sequence_requirement(sequence)
  let requests = @acquisition.query_acquisition_owner(query)
  guard @acquisition.pipeline_request_at(
      requests,
      @acquisition.query_acquisition_source_index(query),
    )
    is Some(@acquisition.Direct(mode, _)) else {
    return false
  }
  let declaration = @acquisition.declaration(@acquisition.mode_input(mode))
  @context.program_identity_stage_requests(program, declaration.stage_index)
  is Some(expected) &&
  physical_equal(expected, requests)
}

///|
/// Host-private wiring. Installation grants no observation or execution success.
/// The installed verifier must check records, exact attempt and issuer lifetime.
pub fn[P] prepare_trusted_capture_port(
  owner : QuerySequence,
  program : @context.ProgramSourceIdentity,
  verify : (P) -> (@execution.CompletedOutput, Int)?,
) -> Result[TrustedCapturePort[P], CapturedSourceIssue] {
  if !query_program_matches(owner, program) {
    return Err(Unavailable)
  }
  Ok({ owner, program, verify, })
}

///|
pub fn[P] capture_verified_source(
  port : TrustedCapturePort[P],
  proof : P,
) -> Result[CapturedInputSource, CapturedSourceIssue] {
  guard (port.verify)(proof) is Some((output, wire_bytes)) &&
    wire_bytes >= 0 &&
    @execution.completed_output_matches_port(
      output,
      query_sequence_owner(port.owner),
      @acquisition.query_acquisition_capture(
        query_sequence_requirement(port.owner),
      ),
    ) else {
    return Err(Unavailable)
  }
  let live = fn() {
    match (port.verify)(proof) {
      Some((current, bytes)) =>
        physical_equal(current, output) &&
        bytes == wire_bytes &&
        @execution.completed_output_matches_port(
          current,
          query_sequence_owner(port.owner),
          @acquisition.query_acquisition_capture(
            query_sequence_requirement(port.owner),
          ),
        )
      None => false
    }
  }
  Ok({ owner: port.owner, program: port.program, output, live, wire_bytes, })
}
