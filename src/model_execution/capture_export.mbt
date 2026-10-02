///|
/// Installed serialization bounds, not changes to the model language. Each
/// response is already checked; nested traversal remains a bounded child.
pub(all) struct ModelCaptureExportLimits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_chunk_bytes : Int
  max_work : Int
}

///|
priv enum CaptureExportPhase {
  Begin
  SelectCapture
  Evidence
  Response(@admitted.WireEmitCursor)
  EndCapture
  EndPass
  Done
}

///|
struct CaptureExportState {
  capture : VerifiedModelCapture
  limits : ModelCaptureExportLimits
  mut writer : @encode.Writer
  mut phase : CaptureExportPhase
  mut index : Int
  mut pass : Int
  mut identity : String?
  mut chunk : String
  mut work : Int
}

///|
/// The exact schema body is emitted twice: first to its identity sink, then
/// with bundle_cid to a bounded provisional chunk sink. No whole response
/// array or bundle-sized JSON string is synthesized by the model owner.
pub struct ModelCaptureExport {
  state : CaptureExportState
  session : @bounded.Session[CaptureExportState, String, ModelExecutionIssue]
  control : @bounded.Control
  mut token : @bounded.Token
  mut accepted : Bool
  mut reclaimed : Bool
}

///|
pub fn start_model_capture_export(
  capture : VerifiedModelCapture,
  limits : ModelCaptureExportLimits,
) -> Result[ModelCaptureExport, ModelExecutionIssue] {
  if limits.max_bytes < 1 ||
    limits.max_nodes < 1 ||
    limits.max_depth < 1 ||
    limits.max_chunk_bytes < 1 ||
    limits.max_work < 1 {
    return Err(InvalidLimits)
  }
  let writer = @encode.hashing_writer(
    limits.max_bytes,
    limits.max_nodes,
    limits.max_depth,
  ) catch {
    _ => return Err(InvalidLimits)
  }
  guard retain_verified_model_capture(capture) is Some(retained) else {
    return Err(OutputIdentity)
  }
  let state : CaptureExportState = {
    capture: retained,
    limits,
    writer,
    phase: Begin,
    index: 0,
    pass: 0,
    identity: None,
    chunk: "",
    work: 0,
  }
  let control = @bounded.control()
  let (session, token) = @bounded.start(
    control,
    state,
    advance_capture_export,
    _ => true,
    _ => true,
  )
  Ok({ state, session, control, token, accepted: false, reclaimed: false, })
}

///|
fn emit_capture_export_step(
  state : CaptureExportState,
) -> Unit raise @encode.EncodeFailure {
  let writer = state.writer
  let owner = state.capture.owner.state
  match state.phase {
    Begin => {
      @encode.begin_object(writer)
      @encode.key(writer, "barrier_receipts")
      @encode.begin_array(writer)
      @encode.end_array(writer)
      if state.pass == 1 {
        @encode.key(writer, "bundle_cid")
        @encode.string_value(writer, state.identity.unwrap())
      }
      @encode.key(writer, "captures")
      @encode.begin_array(writer)
      state.phase = SelectCapture
    }
    SelectCapture =>
      if state.index == owner.captures.length() {
        state.phase = EndPass
      } else {
        @encode.begin_object(writer)
        @encode.key(writer, "evidence")
        state.phase = Evidence
      }
    Evidence => {
      // Invocation evidence is a flat admitted 16-KiB/1,024-node document.
      // This cap does not permit an entire response subtree in one step.
      let document = @publication.run_evidence_value_document(
        owner.invocation_evidence[state.index],
        16384,
        1024,
        16,
      )
      @encode.emit_document(writer, document)
      let slot = owner.captures[state.index]
      @encode.key(writer, "model_call_slot_cid")
      @encode.string_value(writer, slot.slot_cid)
      @encode.key(writer, "semantic_request_cid")
      @encode.string_value(writer, slot.fixed_request_cid)
      @encode.key(writer, "structured_response")
      state.phase = Response(
        @admitted.start_wire_emit(owner.responses[state.index], writer),
      )
    }
    Response(cursor) =>
      if @admitted.advance_wire_emit(cursor) {
        state.phase = EndCapture
      }
    EndCapture => {
      @encode.end_object(writer)
      state.index += 1
      state.phase = SelectCapture
    }
    EndPass => {
      @encode.end_array(writer)
      @encode.key(writer, "version")
      @encode.string_value(writer, "actql-model-capture-bundle/0.1")
      @encode.end_object(writer)
      if state.pass == 0 {
        state.identity = Some("sha256:" + @encode.finish_hash(writer))
        state.writer = @encode.buffered_hashing_writer(
          state.limits.max_bytes,
          state.limits.max_nodes,
          state.limits.max_depth,
          state.limits.max_chunk_bytes,
        )
        state.pass = 1
        state.index = 0
        state.phase = Begin
      } else {
        state.phase = Done
      }
    }
    Done => ()
  }
}

///|
fn advance_capture_export(
  state : CaptureExportState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[String, ModelExecutionIssue] {
  state.chunk = ""
  if @bounded.stop_requested(reader) is Some(reason) {
    return @bounded.Stopped(reason, 0, 0)
  }
  if quantum < 1 {
    return @bounded.Failed(InvalidLimits, 0, 0)
  }
  if state.work >= state.limits.max_work {
    return @bounded.Failed(WorkLimit, 0, 0)
  }
  if state.capture.released || state.capture.owner.state.reclaimed {
    return @bounded.Failed(OutputIdentity, 0, 0)
  }
  state.work += 1
  let pass = state.pass
  emit_capture_export_step(state) catch {
    _ => return @bounded.Failed(OutputValue, 1, 1)
  }
  if pass == 1 {
    state.chunk = @encode.drain_hash_output(state.writer) catch {
      _ => return @bounded.Failed(OutputValue, 1, 1)
    }
  }
  if state.phase is Done {
    // The transported document includes its self field; its hash is not the
    // semantic bundle CID, which was established by the first pass.
    let _ = @encode.finish_hash(state.writer) catch {
      _ => return @bounded.Failed(OutputValue, 1, 1)
    }
    @bounded.Complete(state.identity.unwrap(), 1, 1)
  } else {
    @bounded.Continue(1, 1)
  }
}

///|
/// Chunks are provisional. Only a terminal accepted CID can bind Store
/// custody, and Store durability must still be acknowledged separately.
pub fn advance_model_capture_export(
  active : ModelCaptureExport,
  quantum : Int,
) -> Result[(Bool, String, Int64), ModelExecutionIssue] {
  match @bounded.advance(active.session, active.token, quantum) {
    Err(issue) => Err(Session(issue))
    Ok(@bounded.ContinueWith(token, work~, ..)) => {
      active.token = token
      Ok((false, active.state.chunk, work))
    }
    Ok(@bounded.Completed(_, work~, ..)) => {
      active.accepted = true
      Ok((true, active.state.chunk, work))
    }
    Ok(@bounded.FailedWith(issue, ..)) => Err(issue)
    Ok(@bounded.StoppedWith(_, ..)) => Err(Cancelled)
  }
}

///|
pub fn model_capture_export_identity(active : ModelCaptureExport) -> String? {
  if active.accepted && !active.reclaimed {
    active.state.identity
  } else {
    None
  }
}

///|
/// A physical progress observation, not evidence or a completion token.
pub fn model_capture_export_response_pending(
  active : ModelCaptureExport,
) -> Bool {
  !active.reclaimed &&
  !@bounded.session_stopped(active.session) &&
  active.state.pass == 0 &&
  active.state.phase is Response(_)
}

///|
pub fn cancel_model_capture_export(active : ModelCaptureExport) -> Bool {
  if active.accepted ||
    active.reclaimed ||
    @bounded.session_stopped(active.session) {
    return false
  }
  @bounded.request_cancel(active.control)
}

///|
pub fn cleanup_model_capture_export(
  active : ModelCaptureExport,
) -> Result[Bool, ModelExecutionIssue] {
  if active.reclaimed {
    return Ok(true)
  }
  if !@bounded.session_stopped(active.session) {
    return Ok(false)
  }
  match @bounded.cleanup(active.session) {
    Err(issue) => Err(Session(issue))
    Ok(false) => Ok(false)
    Ok(true) => {
      if active.state.phase is Response(cursor) {
        @admitted.cancel_wire_emit(cursor)
      }
      @encode.cancel_writer(active.state.writer)
      active.state.phase = Done
      active.state.chunk = ""
      release_verified_model_capture(active.state.capture) |> ignore
      active.reclaimed = true
      Ok(true)
    }
  }
}
