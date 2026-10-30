///|
/// Complete opaque carrier DATA tied to the receiver's original approved
/// delivery. This codec does not admit Completion, renew a claim, authorize
/// execution, confirm persistence, or acknowledge physical cleanup.
struct RemoteEffectCompletionReport {
  delivery : RemoteEffectResumeDelivery
  completion_wire : String
  completion_cid : String
  body : String
  report_cid : String
}

///|
pub(all) enum RemoteEffectCompletionReply {
  Accepted
  Refused(String)
} derive(Eq, Debug)

///|
/// The existing sender keeps the complete final carrier and its original
/// custody alive. The receiving Owner separately admits that complete carrier
/// and confirms its durable Run transition before issuing Accepted. Partial
/// original-input evidence cannot stand in for the complete carrier here.
pub fn prepare_remote_effect_completion_report(
  delivery : RemoteEffectResumeDelivery,
  completion_wire : String,
  limits : @checkpoint.WireLimits,
) -> Result[RemoteEffectCompletionReport, DispatchIssue] {
  if completion_wire.is_empty() ||
    limits.max_wire_bytes <= 0 ||
    limits.max_nodes <= 0 ||
    limits.max_depth <= 0 ||
    completion_wire.length() > limits.max_wire_bytes {
    return Err(InvalidDispatch)
  }
  let bytes = @utf8.encode(completion_wire)
  if bytes.length() > limits.max_wire_bytes {
    return Err(InvalidDispatch)
  }
  let completion_cid = "sha256:" + @sha.hex(bytes)
  let writer = @encode.writer(
    limits.max_wire_bytes,
    limits.max_nodes,
    limits.max_depth,
  ) catch {
    _ => return Err(InvalidDispatch)
  }
  try {
    @encode.begin_object(writer)
    for
      (name, value) in [
        ("checkpoint_cid", delivery.report.checkpoint.checkpoint_cid),
        ("checkpoint_report_cid", delivery.report.report_cid),
        ("claimant", delivery.claim.claimant),
        ("completion_cid", completion_cid),
        ("completion_wire", completion_wire),
        ("dispatch_request_cid", delivery.report.dispatch.dispatch_request_cid),
        ("generation", delivery.claim.generation.to_string()),
        ("resolution_cid", delivery.resolution.resolution_cid),
        ("resume_intent_id", delivery.resolution.resume_intent_id.unwrap()),
        ("verified_resolution_cid", delivery.resolution.verified_resolution_cid),
        ("version", "actql-remote-effect-completion-report/0.1"),
      ] {
      @encode.key(writer, name)
      @encode.string_value(writer, value)
    }
    @encode.end_object(writer)
  } catch {
    _ => return Err(InvalidDispatch)
  }
  let body = @encode.finish(writer) catch { _ => return Err(InvalidDispatch) }
  Ok({
    delivery,
    completion_wire,
    completion_cid,
    body,
    report_cid: "sha256:" + @sha.hex(@utf8.encode(body)),
  })
}

///|
/// The receiving Owner supplies its SAME approved delivery and bounds. No
/// transported delivery or claim replaces it. Inner bytes remain unchanged;
/// their one complete semantic admission belongs to the existing receiver.
pub fn admit_remote_effect_completion_report_json(
  body : String,
  delivery : RemoteEffectResumeDelivery,
  limits : @checkpoint.WireLimits,
) -> Result[RemoteEffectCompletionReport, DispatchIssue] {
  if limits.max_wire_bytes <= 0 ||
    limits.max_nodes <= 0 ||
    limits.max_depth <= 0 ||
    body.length() > limits.max_wire_bytes {
    return Err(InvalidDispatch)
  }
  try {
    let object = evidence_object(
      evidence_root(
        body,
        limits.max_wire_bytes,
        limits.max_nodes,
        limits.max_depth,
      ),
      [
        "checkpoint_cid", "checkpoint_report_cid", "claimant", "completion_cid",
        "completion_wire", "dispatch_request_cid", "generation", "resolution_cid",
        "resume_intent_id", "verified_resolution_cid", "version",
      ],
    )
    let report = match
      prepare_remote_effect_completion_report(
        delivery,
        evidence_text(object, "completion_wire"),
        limits,
      ) {
      Ok(value) => value
      Err(_) => raise EvidenceJsonStop
    }
    // Closed canonical equality binds all original delivery fields and the
    // digest of the exact inner bytes, including whitespace and Unicode.
    if report.body != body {
      raise EvidenceJsonStop
    }
    Ok(report)
  } catch {
    EvidenceJsonStop => Err(InvalidDispatch)
  }
}

///|
pub fn remote_effect_completion_report_identity(
  report : RemoteEffectCompletionReport,
) -> String {
  report.report_cid
}

///|
pub fn remote_effect_completion_report_json(
  report : RemoteEffectCompletionReport,
) -> String {
  report.body
}

///|
pub fn remote_effect_completion_report_delivery(
  report : RemoteEffectCompletionReport,
) -> RemoteEffectResumeDelivery {
  report.delivery
}

///|
pub fn remote_effect_completion_report_completion_wire(
  report : RemoteEffectCompletionReport,
) -> String {
  report.completion_wire
}

///|
pub fn remote_effect_completion_report_completion_identity(
  report : RemoteEffectCompletionReport,
) -> String {
  report.completion_cid
}

///|
/// Accepted acknowledges only the original receiver's durable confirmation of
/// this exact report. Unknown persistence emits no ACK; reconciliation keeps
/// this report and never repeats the Effect or acknowledges payload cleanup.
pub fn remote_effect_completion_reply_json(
  report : RemoteEffectCompletionReport,
  reply : RemoteEffectCompletionReply,
  limits : @checkpoint.WireLimits,
) -> Result[String, DispatchIssue] {
  let (outcome, reason) = match reply {
    Accepted => ("accepted", "")
    Refused(reason) if output_report_reply_reason_valid(reason) =>
      ("refused", reason)
    _ => return Err(InvalidDispatch)
  }
  let writer = @encode.writer(
    limits.max_wire_bytes,
    limits.max_nodes,
    limits.max_depth,
  ) catch {
    _ => return Err(InvalidDispatch)
  }
  let delivery = report.delivery
  try {
    @encode.begin_object(writer)
    for
      (name, value) in [
        ("checkpoint_cid", delivery.report.checkpoint.checkpoint_cid),
        ("claimant", delivery.claim.claimant),
        ("completion_cid", report.completion_cid),
        ("dispatch_request_cid", delivery.report.dispatch.dispatch_request_cid),
        ("generation", delivery.claim.generation.to_string()),
        ("outcome", outcome),
        ("reason", reason),
        ("report_cid", report.report_cid),
        ("resume_intent_id", delivery.resolution.resume_intent_id.unwrap()),
        ("version", "actql-remote-effect-completion-reply/0.1"),
      ] {
      @encode.key(writer, name)
      @encode.string_value(writer, value)
    }
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(InvalidDispatch)
  }
}

///|
pub fn admit_remote_effect_completion_reply_json(
  body : String,
  report : RemoteEffectCompletionReport,
  limits : @checkpoint.WireLimits,
) -> Result[RemoteEffectCompletionReply, DispatchIssue] {
  if limits.max_wire_bytes <= 0 ||
    limits.max_nodes <= 0 ||
    limits.max_depth <= 0 ||
    body.length() > limits.max_wire_bytes {
    return Err(InvalidDispatch)
  }
  try {
    let object = evidence_object(
      evidence_root(
        body,
        limits.max_wire_bytes,
        limits.max_nodes,
        limits.max_depth,
      ),
      [
        "checkpoint_cid", "claimant", "completion_cid", "dispatch_request_cid", "generation",
        "outcome", "reason", "report_cid", "resume_intent_id", "version",
      ],
    )
    let reply = match
      (evidence_text(object, "outcome"), evidence_text(object, "reason")) {
      ("accepted", "") => RemoteEffectCompletionReply::Accepted
      ("refused", reason) if output_report_reply_reason_valid(reason) =>
        Refused(reason)
      _ => raise EvidenceJsonStop
    }
    if remote_effect_completion_reply_json(report, reply, limits) != Ok(body) {
      raise EvidenceJsonStop
    }
    Ok(reply)
  } catch {
    EvidenceJsonStop => Err(InvalidDispatch)
  }
}
