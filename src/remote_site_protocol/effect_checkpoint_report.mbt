///|
/// Exact Site review observation. Receipt admission establishes canonical
/// identity only, not remote persistence, approval, execution or cleanup.
struct RemoteEffectCheckpointReport {
  dispatch : DispatchRequest
  checkpoint : @checkpoint.SealedCheckpoint
  body : String
  report_cid : String
}

///|
pub(all) enum RemoteEffectCheckpointReply {
  Accepted
  Refused(String)
} derive(Eq, Debug)

///|
fn effect_checkpoint_report(
  dispatch : DispatchRequest,
  checkpoint : @checkpoint.SealedCheckpoint,
  limits : @checkpoint.WireLimits,
) -> Result[RemoteEffectCheckpointReport, DispatchIssue] {
  if dispatch_request_json(dispatch) is Err(_) ||
    @checkpoint.admit_checkpoint_wire(checkpoint.wire, limits) != Ok(checkpoint) {
    return Err(InvalidDispatch)
  }
  guard checkpoint.checkpoint.subject
    is @checkpoint.RunUnit(run_definition_cid~, ..) &&
    run_definition_cid == dispatch.run_definition_cid &&
    checkpoint.checkpoint.phase == @checkpoint.Commit &&
    checkpoint.checkpoint.kind == @checkpoint.EffectSet &&
    checkpoint.checkpoint.requirements == [@checkpoint.EffectScopeApproved] else {
    return Err(InvalidDispatch)
  }
  let writer = @encode.writer(limits.max_wire_bytes, 16, 2) catch {
    _ => return Err(InvalidDispatch)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "checkpoint_wire")
    @encode.string_value(writer, checkpoint.wire)
    @encode.key(writer, "dispatch_request_cid")
    @encode.string_value(writer, dispatch.dispatch_request_cid)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-remote-effect-checkpoint-report/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(InvalidDispatch)
  }
  let body = @encode.finish(writer) catch { _ => return Err(InvalidDispatch) }
  Ok({
    dispatch,
    checkpoint,
    body,
    report_cid: "sha256:" + @sha.hex(@utf8.encode(body)),
  })
}

///|
/// The Native issuer confirms its original capture, Preview and paired Store
/// readback before calling this function. Private continuation bytes stay Site
/// side. No report receipt can be used as a PersistedCheckpoint proof.
pub fn prepare_remote_effect_checkpoint_report(
  dispatch : DispatchRequest,
  checkpoint : @checkpoint.PersistedCheckpoint,
  limits : @checkpoint.WireLimits,
) -> Result[RemoteEffectCheckpointReport, DispatchIssue] {
  effect_checkpoint_report(dispatch, checkpoint.artifact, limits)
}

///|
/// The receiving Host authenticates the current Site/generation and verifies
/// the original Run/unit, consumer, current authority and custody separately.
/// This parser cannot establish the sender's physical persistence.
pub fn admit_remote_effect_checkpoint_report_json(
  body : String,
  dispatch : DispatchRequest,
  limits : @checkpoint.WireLimits,
) -> Result[RemoteEffectCheckpointReport, DispatchIssue] {
  try {
    let object = evidence_object(
      evidence_root(body, limits.max_wire_bytes, 16, 2),
      ["checkpoint_wire", "dispatch_request_cid", "version"],
    )
    if evidence_text(object, "version") !=
      "actql-remote-effect-checkpoint-report/0.1" ||
      evidence_text(object, "dispatch_request_cid") !=
      dispatch_request_identity(dispatch) {
      raise EvidenceJsonStop
    }
    let checkpoint = match
      @checkpoint.admit_checkpoint_wire(
        evidence_text(object, "checkpoint_wire"),
        limits,
      ) {
      Ok(value) => value
      Err(_) => raise EvidenceJsonStop
    }
    let report = match effect_checkpoint_report(dispatch, checkpoint, limits) {
      Ok(value) => value
      Err(_) => raise EvidenceJsonStop
    }
    if report.body != body {
      raise EvidenceJsonStop
    }
    Ok(report)
  } catch {
    EvidenceJsonStop => Err(InvalidDispatch)
  }
}

///|
pub fn remote_effect_checkpoint_report_identity(
  report : RemoteEffectCheckpointReport,
) -> String {
  report.report_cid
}

///|
pub fn remote_effect_checkpoint_report_json(
  report : RemoteEffectCheckpointReport,
) -> String {
  report.body
}

///|
pub fn remote_effect_checkpoint_report_dispatch(
  report : RemoteEffectCheckpointReport,
) -> DispatchRequest {
  report.dispatch
}

///|
pub fn remote_effect_checkpoint_report_checkpoint(
  report : RemoteEffectCheckpointReport,
) -> @checkpoint.SealedCheckpoint {
  report.checkpoint
}

///|
/// Accepted means the receiving Run Owner durably committed this exact review
/// as waiting. It grants neither approval nor permission to retire custody.
pub fn remote_effect_checkpoint_reply_json(
  report : RemoteEffectCheckpointReport,
  reply : RemoteEffectCheckpointReply,
) -> Result[String, DispatchIssue] {
  let (outcome, reason) = match reply {
    Accepted => ("accepted", "")
    Refused(reason) if output_report_reply_reason_valid(reason) =>
      ("refused", reason)
    _ => return Err(InvalidDispatch)
  }
  let writer = @encode.writer(2048, 24, 2) catch {
    _ => return Err(InvalidDispatch)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "checkpoint_cid")
    @encode.string_value(writer, report.checkpoint.checkpoint_cid)
    @encode.key(writer, "dispatch_request_cid")
    @encode.string_value(writer, dispatch_request_identity(report.dispatch))
    @encode.key(writer, "outcome")
    @encode.string_value(writer, outcome)
    @encode.key(writer, "reason")
    @encode.string_value(writer, reason)
    @encode.key(writer, "report_cid")
    @encode.string_value(writer, report.report_cid)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-remote-effect-checkpoint-reply/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(InvalidDispatch)
  }
  Ok(@encode.finish(writer) catch { _ => return Err(InvalidDispatch) })
}

///|
pub fn admit_remote_effect_checkpoint_reply_json(
  body : String,
  report : RemoteEffectCheckpointReport,
) -> Result[RemoteEffectCheckpointReply, DispatchIssue] {
  try {
    let object = evidence_object(evidence_root(body, 2048, 24, 2), [
      "checkpoint_cid", "dispatch_request_cid", "outcome", "reason", "report_cid",
      "version",
    ])
    if evidence_text(object, "version") !=
      "actql-remote-effect-checkpoint-reply/0.1" ||
      evidence_text(object, "checkpoint_cid") !=
      report.checkpoint.checkpoint_cid ||
      evidence_text(object, "dispatch_request_cid") !=
      dispatch_request_identity(report.dispatch) ||
      evidence_text(object, "report_cid") != report.report_cid {
      raise EvidenceJsonStop
    }
    let reply = match
      (evidence_text(object, "outcome"), evidence_text(object, "reason")) {
      ("accepted", "") => RemoteEffectCheckpointReply::Accepted
      ("refused", reason) if output_report_reply_reason_valid(reason) =>
        Refused(reason)
      _ => raise EvidenceJsonStop
    }
    if remote_effect_checkpoint_reply_json(report, reply) != Ok(body) {
      raise EvidenceJsonStop
    }
    Ok(reply)
  } catch {
    EvidenceJsonStop => Err(InvalidDispatch)
  }
}
