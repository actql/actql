///|
/// A poll response carries canonical dispatch bytes but has no execution
/// authority of its own. Site admission still checks the exact generation,
/// attempt, grant, budget, and registered runtime.
struct RemotePollDispatch {
  request : DispatchRequest
}

///|
/// Polling transports dispatch delivery and status reconciliation as distinct
/// physical operations. Only `Dispatch` may reach Site admission.
pub(all) enum RemotePollOperation {
  Dispatch(DispatchRequest)
  Query(DispatchRequest)
}

///|
fn remote_poll_request_json(
  request : DispatchRequest,
  version : String,
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
    @encode.string_value(writer, version)
    @encode.end_object(writer)
  } catch {
    _ => return Err(InvalidDispatch)
  }
  Ok(@encode.finish(writer) catch { _ => return Err(InvalidDispatch) })
}

///|
pub fn remote_poll_dispatch_json(
  request : DispatchRequest,
) -> Result[String, DispatchIssue] {
  remote_poll_request_json(request, "actql-remote-poll-dispatch/0.1")
}

///|
pub fn remote_poll_query_json(
  request : DispatchRequest,
) -> Result[String, DispatchIssue] {
  remote_poll_request_json(request, "actql-remote-poll-query/0.1")
}

///|
fn admit_remote_poll_request_json(
  body : String,
  expected_version : String,
) -> Result[DispatchRequest, DispatchIssue] {
  try {
    let object = evidence_object(evidence_root(body, 131072, 16, 2), [
      "dispatch_request_cid", "request_json", "version",
    ])
    if evidence_text(object, "version") != expected_version {
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
    Ok(request)
  } catch {
    EvidenceJsonStop => Err(InvalidDispatch)
  }
}

///|
pub fn admit_remote_poll_dispatch_json(
  body : String,
) -> Result[RemotePollDispatch, DispatchIssue] {
  match admit_remote_poll_request_json(body, "actql-remote-poll-dispatch/0.1") {
    Ok(request) => Ok({ request, })
    Err(issue) => Err(issue)
  }
}

///|
pub fn admit_remote_poll_operation_json(
  body : String,
) -> Result[RemotePollOperation, DispatchIssue] {
  match admit_remote_poll_request_json(body, "actql-remote-poll-dispatch/0.1") {
    Ok(request) => return Ok(Dispatch(request))
    Err(_) => ()
  }
  match admit_remote_poll_request_json(body, "actql-remote-poll-query/0.1") {
    Ok(request) => Ok(Query(request))
    Err(issue) => Err(issue)
  }
}

///|
pub fn remote_poll_operation_request(
  operation : RemotePollOperation,
) -> DispatchRequest {
  match operation {
    Dispatch(request) | Query(request) => request
  }
}

///|
pub fn remote_poll_operation_is_query(operation : RemotePollOperation) -> Bool {
  match operation {
    Dispatch(_) => false
    Query(_) => true
  }
}

///|
pub fn remote_poll_dispatch_request(
  dispatch : RemotePollDispatch,
) -> DispatchRequest {
  dispatch.request
}

///|
pub fn remote_poll_not_seen_json(
  request : DispatchRequest,
) -> Result[String, DispatchIssue] {
  let writer = @encode.writer(4096, 8, 1) catch {
    _ => return Err(InvalidDispatch)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "dispatch_request_cid")
    @encode.string_value(writer, request.dispatch_request_cid)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-remote-dispatch-not-seen/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(InvalidDispatch)
  }
  Ok(@encode.finish(writer) catch { _ => return Err(InvalidDispatch) })
}

///|
pub fn admit_remote_poll_not_seen_json(
  body : String,
  request : DispatchRequest,
) -> Result[Unit, DispatchIssue] {
  try {
    let object = evidence_object(evidence_root(body, 4096, 8, 1), [
      "dispatch_request_cid", "version",
    ])
    if evidence_text(object, "version") != "actql-remote-dispatch-not-seen/0.1" ||
      evidence_text(object, "dispatch_request_cid") !=
      request.dispatch_request_cid {
      raise EvidenceJsonStop
    }
    Ok(())
  } catch {
    EvidenceJsonStop => Err(InvalidDispatch)
  }
}
