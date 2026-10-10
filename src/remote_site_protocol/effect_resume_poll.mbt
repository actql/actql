///|
/// Routing bytes for an approved original holder. This is not an admitted
/// Resolution, a current claim or permission to execute an Effect.
struct RemotePollEffectResume {
  request : DispatchRequest
  delivery_json : String
}

///|
fn remote_poll_effect_resume_body(
  request : DispatchRequest,
  delivery_json : String,
) -> Result[String, DispatchIssue] {
  if @utf8.encode(delivery_json).length() > 262144 {
    return Err(InvalidDispatch)
  }
  let request_json = match dispatch_request_json(request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let writer = @encode.writer(1048576, 16, 2) catch {
    _ => return Err(InvalidDispatch)
  }
  try {
    @encode.begin_object(writer)
    for
      (name, value) in [
        ("delivery_json", delivery_json),
        ("dispatch_request_cid", request.dispatch_request_cid),
        ("request_json", request_json),
        ("version", "actql-remote-poll-effect-resume/0.1"),
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
/// Issue only from the common report-bound approved delivery. The request
/// comes from that same Owner; a caller cannot supply another dispatch.
pub fn remote_poll_effect_resume_json(
  delivery : RemoteEffectResumeDelivery,
) -> Result[String, DispatchIssue] {
  remote_poll_effect_resume_body(delivery.report.dispatch, delivery.body)
}

///|
/// Admit routing only. The retained holder must separately admit these exact
/// delivery bytes against its durable accepted report and current fence.
pub fn admit_remote_poll_effect_resume_json(
  body : String,
) -> Result[RemotePollEffectResume, DispatchIssue] {
  try {
    let fields = evidence_object(evidence_root(body, 1048576, 16, 2), [
      "delivery_json", "dispatch_request_cid", "request_json", "version",
    ])
    if evidence_text(fields, "version") != "actql-remote-poll-effect-resume/0.1" {
      raise EvidenceJsonStop
    }
    let request = match
      admit_dispatch_request_json(
        evidence_text(fields, "request_json"),
        evidence_text(fields, "dispatch_request_cid"),
      ) {
      Ok(value) => value
      Err(_) => raise EvidenceJsonStop
    }
    let delivery_json = evidence_text(fields, "delivery_json")
    let delivery = evidence_object(
      evidence_root(delivery_json, 262144, 32, 2),
      [
        "checkpoint_cid", "claimant", "dispatch_request_cid", "generation", "report_cid",
        "resolution_cid", "resolution_wire", "resume_intent_id", "version",
      ],
    )
    if evidence_text(delivery, "version") !=
      "actql-remote-effect-resume-delivery/0.1" ||
      evidence_text(delivery, "dispatch_request_cid") !=
      request.dispatch_request_cid {
      raise EvidenceJsonStop
    }
    // Validate closed bounded routing syntax without trusting its signature,
    // approval, report identity or claim as current receiving authority.
    for
      name in [
        "checkpoint_cid", "claimant", "generation", "report_cid", "resolution_cid",
        "resolution_wire", "resume_intent_id",
      ] {
      ignore(evidence_text(delivery, name))
    }
    if remote_poll_effect_resume_body(request, delivery_json) != Ok(body) {
      raise EvidenceJsonStop
    }
    Ok({ request, delivery_json, })
  } catch {
    EvidenceJsonStop => Err(InvalidDispatch)
  }
}

///|
pub fn remote_poll_effect_resume_request(
  value : RemotePollEffectResume,
) -> DispatchRequest {
  value.request
}

///|
pub fn remote_poll_effect_resume_delivery_json(
  value : RemotePollEffectResume,
) -> String {
  value.delivery_json
}
