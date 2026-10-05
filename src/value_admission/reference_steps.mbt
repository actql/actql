///|
priv enum ReferenceAdmissionPhase {
  ReferenceCanonical
  ReferenceWriter
  ReferenceEmit
  ReferenceFinishWire
  ReferenceIssueValue
  ReferenceFinished
} derive(Eq)

///|
/// A staged operation of the existing reference owner, not an issuance bypass.
/// Canonical admission and emission are resumed; only the original issuer can
/// authorize a completed exact envelope or resolve its original authority.
struct ReferenceAdmission {
  issuer : ReferenceIssuer
  contract : @contract.Contract
  limits : ReferenceLimits
  mut phase : ReferenceAdmissionPhase
  mut admission : @identity.CursorAdmission?
  mut envelope : @identity.CanonicalValue?
  mut writer : @encode.Writer?
  mut emission : @identity.CanonicalEmit?
  mut wire : String?
  mut nodes : Int
  mut text_bytes : Int
}

///|
pub enum ReferenceAdmissionPoll {
  ReferenceAdmissionContinue
  ReferenceAdmissionComplete(CheckedValue, Int, Int)
  ReferenceAdmissionFailed(ReferenceIssue)
  ReferenceAdmissionTerminal
}

///|
pub fn start_reference_admission(
  issuer : ReferenceIssuer,
  contract : @contract.Contract,
  cursor : @decode.Cursor,
  limits : ReferenceLimits,
) -> Result[ReferenceAdmission, ReferenceIssue] {
  guard @identity.start_cursor_admission(
      cursor,
      limits.max_nodes,
      limits.max_depth,
      limits.max_text_units,
      limits.max_bytes,
    )
    is Some(admission) else {
    return Err(InvalidLimits)
  }
  Ok({
    issuer,
    contract,
    limits,
    phase: ReferenceCanonical,
    admission: Some(admission),
    envelope: None,
    writer: None,
    emission: None,
    wire: None,
    nodes: 0,
    text_bytes: 0,
  })
}

///|
fn reference_admission_fail(
  value : ReferenceAdmission,
  issue : ReferenceIssue,
) -> ReferenceAdmissionPoll {
  cancel_reference_admission(value)
  ReferenceAdmissionFailed(issue)
}

///|
pub fn advance_reference_admission(
  value : ReferenceAdmission,
) -> ReferenceAdmissionPoll {
  if value.phase == ReferenceFinished {
    return ReferenceAdmissionTerminal
  }
  match value.phase {
    ReferenceCanonical => {
      guard value.admission is Some(admission) else {
        return reference_admission_fail(value, InvalidWire)
      }
      match @identity.advance_cursor_admission(admission) {
        @identity.CursorAdmissionContinue => ()
        @identity.CursorAdmissionComplete(envelope, nodes, text) => {
          value.envelope = Some(envelope)
          value.nodes = nodes
          value.text_bytes = text
          value.admission = None
          value.phase = ReferenceWriter
        }
        _ => return reference_admission_fail(value, InvalidWire)
      }
    }
    ReferenceWriter => {
      let writer = @encode.writer(
        value.limits.max_bytes,
        value.limits.max_nodes,
        value.limits.max_depth,
      ) catch {
        _ => return reference_admission_fail(value, InvalidWire)
      }
      value.writer = Some(writer)
      value.emission = Some(
        @identity.start_emit(value.envelope.unwrap(), writer),
      )
      value.phase = ReferenceEmit
    }
    ReferenceEmit => {
      let complete = @identity.advance_emit(value.emission.unwrap()) catch {
        _ => return reference_admission_fail(value, InvalidWire)
      }
      if complete {
        value.emission = None
        value.phase = ReferenceFinishWire
      }
    }
    ReferenceFinishWire => {
      value.wire = Some(
        @encode.finish(value.writer.unwrap()) catch {
          _ => return reference_admission_fail(value, InvalidWire)
        },
      )
      value.writer = None
      value.phase = ReferenceIssueValue
    }
    ReferenceIssueValue => {
      let checked = match
        admit_reference_envelope(
          value.issuer,
          value.contract,
          value.envelope.unwrap(),
          value.wire.unwrap(),
        ) {
        Ok(checked) => checked
        Err(issue) => return reference_admission_fail(value, issue)
      }
      cancel_reference_admission(value)
      return ReferenceAdmissionComplete(checked, value.nodes, value.text_bytes)
    }
    ReferenceFinished => return ReferenceAdmissionTerminal
  }
  ReferenceAdmissionContinue
}

///|
pub fn cancel_reference_admission(value : ReferenceAdmission) -> Unit {
  if value.admission is Some(admission) {
    @identity.cancel_cursor_admission(admission)
  }
  if value.emission is Some(emission) {
    @identity.cancel_emit(emission)
  }
  if value.writer is Some(writer) {
    @encode.cancel_writer(writer)
  }
  value.admission = None
  value.emission = None
  value.writer = None
  value.envelope = None
  value.wire = None
  value.phase = ReferenceFinished
}
