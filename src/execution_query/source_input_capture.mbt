///|
/// Trusted installed Source wiring under the existing capture owner. No public
/// Source/provider configuration may install its own proof verifier.
struct SourceInputCapturePort[P] {
  context : SourceInputCaptureContext
  verify : (P) -> (@execution.SuppliedRelationRead, Int)?
}

///|
priv struct SourceInputCaptureContext {
  contracts : @execution.RegisteredRelationContracts
  sequence : @lower.PreparedSequence
  acquisition : @acquisition.SourceAcquisition
  program : @context.ProgramSourceIdentity
  max_fields : Int
  max_name_bytes : Int
}

///|
priv struct SourceInputCapture {
  context : SourceInputCaptureContext
  read : @execution.SuppliedRelationRead
}

///|
fn source_input_program_matches(
  acquisition : @acquisition.SourceAcquisition,
  program : @context.ProgramSourceIdentity,
) -> Bool {
  let stage = @acquisition.declaration(
      @acquisition.mode_input(@acquisition.source_acquisition_mode(acquisition)),
    ).stage_index
  @context.program_identity_stage_requests(program, stage) is Some(requests) &&
  physical_equal(requests, @acquisition.source_acquisition_owner(acquisition))
}

///|
/// Same-original preparation correspondence only, never physical admission.
pub fn source_input_capture_preparation_matches(
  sequence : @lower.PreparedSequence,
  acquisition : @acquisition.SourceAcquisition,
  program : @context.ProgramSourceIdentity,
) -> Bool {
  let owner = @lower.sequence_owner(sequence)
  if !source_input_program_matches(acquisition, program) ||
    !physical_equal(
      @lower.pipeline(@lower.bound_preparation(owner)),
      @acquisition.source_acquisition_pipeline(acquisition),
    ) {
    return false
  }
  let parameters = @acquisition.request_parameter_values(
    @acquisition.pipeline_requests_parameters(
      @acquisition.source_acquisition_owner(acquisition),
    ),
  )
  match @lower.parameter_bindings(owner) {
    Some(bound) => physical_equal(bound, parameters)
    None => @parameter.bound_value_count(parameters) == 0
  }
}

///|
/// Bind the original Source request, invocation Parameters and checked input
/// before installing the custody verifier. No residual/Step is synthesized.
pub fn[P] prepare_trusted_source_input_capture_port(
  contracts : @execution.RegisteredRelationContracts,
  sequence : @lower.PreparedSequence,
  acquisition : @acquisition.SourceAcquisition,
  program : @context.ProgramSourceIdentity,
  max_fields : Int,
  max_name_bytes : Int,
  verify : (P) -> (@execution.SuppliedRelationRead, Int)?,
) -> Result[SourceInputCapturePort[P], CapturedSourceIssue] {
  if max_fields < 0 || max_name_bytes < 0 {
    return Err(Completion(InvalidLimits))
  }
  if !source_input_capture_preparation_matches(sequence, acquisition, program) {
    return Err(Unavailable)
  }
  Ok({
    context: {
      contracts,
      sequence,
      acquisition,
      program,
      max_fields,
      max_name_bytes,
    },
    verify,
  })
}

///|
/// Only the installed issuer's exact completed input occurrence crosses this
/// boundary. The original read and row arrays stay borrowed through capture;
/// another read of equal rows cannot replace it after the verifier returns.
pub fn[P] capture_verified_source_input(
  port : SourceInputCapturePort[P],
  proof : P,
) -> Result[CapturedInputSource, CapturedSourceIssue] {
  guard (port.verify)(proof) is Some((read, wire_bytes)) &&
    wire_bytes >= 0 &&
    @acquisition.source_acquisition_input(port.context.acquisition)
    is @pipeline.Input(input) &&
    @execution.supplied_relation_read_matches_input(
      read,
      @lower.sequence_owner(port.context.sequence),
      input,
    ) else {
    return Err(Unavailable)
  }
  let output = match
    @execution.capture_supplied_source_input(
      port.context.contracts,
      port.context.sequence,
      read,
      port.context.max_fields,
      port.context.max_name_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Completion(issue))
  }
  let live = fn() {
    match (port.verify)(proof) {
      Some((current, bytes)) =>
        physical_equal(current, read) &&
        bytes == wire_bytes &&
        @execution.completed_source_input_matches_read(output, current)
      None => false
    }
  }
  if !live() {
    return Err(Unavailable)
  }
  Ok({
    owner: InputCapture({ context: port.context, read, }),
    program: port.context.program,
    output,
    live,
    wire_bytes,
  })
}

///|
pub fn captured_source_matches_input_acquisition(
  source : CapturedInputSource,
  acquisition : @acquisition.SourceAcquisition,
) -> Bool {
  (source.live)() &&
  source.owner is InputCapture(input) &&
  physical_equal(input.context.acquisition, acquisition)
}

///|
/// Borrow the same native input for the existing Compute owner. The original
/// Source verifier remains in the restricted read; no captured row is copied
/// and the input cannot complete a Compute Step on its own.
pub fn captured_source_original_input_read(
  source : CapturedInputSource,
) -> @execution.SuppliedRelationRead? {
  guard (source.live)() && source.owner is InputCapture(input) else {
    return None
  }
  Some(@execution.restrict_supplied_relation_read(input.read, source.live))
}

///|
/// Immutable acquisition provenance only. The completed identity retains the
/// original supplied binding even after its input was consumed. This compares
/// no wire/CID substitute and grants no availability, read or execution right.
pub fn captured_source_relation_identity_has_input_binding(
  identity : CapturedSourceRelationIdentity,
  read : @execution.SuppliedRelationRead,
) -> Bool {
  match identity.origin.owner {
    InputCapture(input) =>
      @execution.supplied_relation_read_same_binding(input.read, read)
    QueryCapture(_) => false
  }
}
