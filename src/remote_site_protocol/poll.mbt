///|
/// A poll response carries canonical dispatch bytes but has no execution
/// authority of its own. Site admission still checks the exact generation,
/// attempt, grant, budget, and registered runtime.
struct RemotePollDispatch {
  request : DispatchRequest
}

///|
pub fn remote_poll_dispatch_json(
  request : DispatchRequest,
) -> Result[String, DispatchIssue] {
  let request_json = match dispatch_request_json(request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let writer = @encode.writer(131072, 16, 2) catch {
    _ => return Err(InvalidDispatch)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "dispatch_request_cid")
    @encode.string_value(writer, request.dispatch_request_cid)
    @encode.key(writer, "request_json")
    @encode.string_value(writer, request_json)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-remote-poll-dispatch/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(InvalidDispatch)
  }
  Ok(@encode.finish(writer) catch { _ => return Err(InvalidDispatch) })
}

///|
pub fn admit_remote_poll_dispatch_json(
  body : String,
) -> Result[RemotePollDispatch, DispatchIssue] {
  try {
    let object = evidence_object(evidence_root(body, 131072, 16, 2), [
      "dispatch_request_cid", "request_json", "version",
    ])
    if evidence_text(object, "version") != "actql-remote-poll-dispatch/0.1" {
      raise EvidenceJsonStop
    }
    let request = match
      admit_dispatch_request_json(
        evidence_text(object, "request_json"),
        evidence_text(object, "dispatch_request_cid"),
      ) {
      Ok(value) => value
      Err(_) => raise EvidenceJsonStop
    }
    Ok({ request, })
  } catch {
    EvidenceJsonStop => Err(InvalidDispatch)
  }
}

///|
pub fn remote_poll_dispatch_request(
  dispatch : RemotePollDispatch,
) -> DispatchRequest {
  dispatch.request
}
