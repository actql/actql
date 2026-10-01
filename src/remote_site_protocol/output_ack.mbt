///|
/// A response to an exact Output observation, not execution or release
/// authority. Issuers must commit acceptance before emitting Accepted.
pub(all) enum RemoteOutputReportReply {
  Accepted
  Refused(String)
  /// Internal durable marker: retry the original report while retaining the
  /// last checked refusal for inspection. This is never a wire ACK.
  Retry(String)
} derive(Eq, Debug)

///|
fn output_report_reply_reason_valid(reason : String) -> Bool {
  reason == "authorization_denied" ||
  reason == "scope_mismatch" ||
  reason == "report_conflict"
}

///|
pub fn remote_output_report_reply_json(
  result : RemoteOutputResult,
  reply : RemoteOutputReportReply,
) -> Result[String, DispatchIssue] {
  match remote_output_result_json(result) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
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
    @encode.key(writer, "dispatch_request_cid")
    @encode.string_value(writer, result.dispatch_request_cid)
    @encode.key(writer, "intent_cid")
    @encode.string_value(writer, result.intent_cid)
    @encode.key(writer, "outcome")
    @encode.string_value(writer, outcome)
    @encode.key(writer, "reason")
    @encode.string_value(writer, reason)
    @encode.key(writer, "report_cid")
    @encode.string_value(writer, result.result_cid)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-remote-output-report-reply/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(InvalidDispatch)
  }
  let body = @encode.finish(writer) catch { _ => return Err(InvalidDispatch) }
  Ok(body)
}

///|
/// Durable local marker used when an operator explicitly retries a checked
/// refusal. It is intentionally a separate version from the wire ACK.
pub fn remote_output_report_retry_json(
  reason : String,
) -> Result[String, DispatchIssue] {
  if !output_report_reply_reason_valid(reason) {
    return Err(InvalidDispatch)
  }
  let writer = @encode.writer(256, 8, 1) catch {
    _ => return Err(InvalidDispatch)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "previous_reason")
    @encode.string_value(writer, reason)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-site-output-report-retry/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(InvalidDispatch)
  }
  Ok(@encode.finish(writer) catch { _ => return Err(InvalidDispatch) })
}

///|
pub fn admit_remote_output_report_retry_json(
  body : String,
) -> Result[String, DispatchIssue] {
  try {
    let object = evidence_object(evidence_root(body, 256, 8, 1), [
      "previous_reason", "version",
    ])
    if evidence_text(object, "version") != "actql-site-output-report-retry/0.1" ||
      !output_report_reply_reason_valid(
        evidence_text(object, "previous_reason"),
      ) {
      raise EvidenceJsonStop
    }
    if remote_output_report_retry_json(evidence_text(object, "previous_reason")) !=
      Ok(body) {
      raise EvidenceJsonStop
    }
    Ok(evidence_text(object, "previous_reason"))
  } catch {
    EvidenceJsonStop => Err(InvalidDispatch)
  }
}

///|
/// The caller authenticates the current transport peer and Site scope.
/// All fields and canonical bytes must match the retained original report.
pub fn admit_remote_output_report_reply_json(
  body : String,
  result : RemoteOutputResult,
) -> Result[RemoteOutputReportReply, DispatchIssue] {
  try {
    let object = evidence_object(evidence_root(body, 2048, 24, 2), [
      "dispatch_request_cid", "intent_cid", "outcome", "reason", "report_cid", "version",
    ])
    if evidence_text(object, "version") !=
      "actql-remote-output-report-reply/0.1" ||
      evidence_text(object, "report_cid") != result.result_cid ||
      evidence_text(object, "dispatch_request_cid") !=
      result.dispatch_request_cid ||
      evidence_text(object, "intent_cid") != result.intent_cid {
      raise EvidenceJsonStop
    }
    let reply = match
      (evidence_text(object, "outcome"), evidence_text(object, "reason")) {
      ("accepted", "") => RemoteOutputReportReply::Accepted
      ("refused", reason) if output_report_reply_reason_valid(reason) =>
        Refused(reason)
      _ => raise EvidenceJsonStop
    }
    if remote_output_report_reply_json(result, reply) != Ok(body) {
      raise EvidenceJsonStop
    }
    Ok(reply)
  } catch {
    EvidenceJsonStop => Err(InvalidDispatch)
  }
}
