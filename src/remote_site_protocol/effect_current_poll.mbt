///|
/// Bounded routing only. The holder admits the query against its own original
/// accepted report and checks current evidence authority before Store access.
struct RemotePollEffectCurrent {
  request : DispatchRequest
  query_json : String
}

///|
fn remote_poll_effect_current_body(
  request : DispatchRequest,
  query_json : String,
) -> Result[String, DispatchIssue] {
  if query_json.length() > 65536 || @utf8.encode(query_json).length() > 65536 {
    return Err(InvalidDispatch)
  }
  let request_json = match dispatch_request_json(request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let writer = @encode.writer(131072, 16, 2) catch {
    _ => return Err(InvalidDispatch)
  }
  try {
    @encode.begin_object(writer)
    for
      (name, value) in [
        ("dispatch_request_cid", request.dispatch_request_cid),
        ("query_json", query_json),
        ("request_json", request_json),
        ("version", "actql-remote-poll-effect-current/0.1"),
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
/// The original report-bound query Owner supplies both dispatch and query.
pub fn remote_poll_effect_current_json(
  query : RemoteEffectCurrentQuery,
) -> Result[String, DispatchIssue] {
  remote_poll_effect_current_body(query.report.dispatch, query.body)
}

///|
pub fn admit_remote_poll_effect_current_json(
  body : String,
) -> Result[RemotePollEffectCurrent, DispatchIssue] {
  if body.length() > 131072 {
    return Err(InvalidDispatch)
  }
  try {
    let fields = evidence_object(evidence_root(body, 131072, 16, 2), [
      "dispatch_request_cid", "query_json", "request_json", "version",
    ])
    if evidence_text(fields, "version") !=
      "actql-remote-poll-effect-current/0.1" {
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
    let query_json = evidence_text(fields, "query_json")
    let query = evidence_object(evidence_root(query_json, 65536, 4096, 32), [
      "checkpoint_cid", "dispatch_request_cid", "effect_id", "query_id", "report_cid",
      "version",
    ])
    if evidence_text(query, "version") !=
      "actql-remote-effect-current-query/0.1" ||
      evidence_text(query, "dispatch_request_cid") !=
      request.dispatch_request_cid {
      raise EvidenceJsonStop
    }
    // Check canonical routing syntax, without adopting transported report,
    // Checkpoint, member or query identity as the receiving holder's authority.
    if effect_current_query_body(
        evidence_text(query, "checkpoint_cid"),
        request.dispatch_request_cid,
        evidence_text(query, "effect_id"),
        evidence_text(query, "query_id"),
        evidence_text(query, "report_cid"),
        { max_wire_bytes: 65536, max_nodes: 4096, max_depth: 32, },
      ) !=
      Ok(query_json) ||
      remote_poll_effect_current_body(request, query_json) != Ok(body) {
      raise EvidenceJsonStop
    }
    Ok({ request, query_json, })
  } catch {
    EvidenceJsonStop => Err(InvalidDispatch)
  }
}

///|
pub fn remote_poll_effect_current_request(
  value : RemotePollEffectCurrent,
) -> DispatchRequest {
  value.request
}

///|
pub fn remote_poll_effect_current_query_json(
  value : RemotePollEffectCurrent,
) -> String {
  value.query_json
}
