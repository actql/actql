///|
/// A poll response carries canonical dispatch bytes but has no execution
/// authority of its own. Site admission still checks the exact generation,
/// attempt, grant, budget, and registered runtime.
struct RemoteInputBinding {
  body : String
  cid : String
}

///|
/// One bounded canonical Connector input binding. The remote protocol owns
/// only its bytes and identity; the selected registered Connector owns the
/// binding schema and meaning.
pub fn prepare_remote_input_binding(
  body : String,
  max_bytes : Int,
) -> Result[RemoteInputBinding, DispatchIssue] {
  let bytes = @utf8.encode(body)
  if max_bytes < 0 || bytes.length() > max_bytes {
    return Err(InvalidDispatch)
  }
  Ok({ body, cid: "sha256:" + @sha.hex(bytes), })
}

///|
pub fn remote_input_binding_cid(binding : RemoteInputBinding) -> String {
  binding.cid
}

///|
pub fn remote_input_binding_body(binding : RemoteInputBinding) -> String {
  binding.body
}

///|
pub fn remote_input_binding_matches_dispatch(
  binding : RemoteInputBinding,
  request : DispatchRequest,
) -> Bool {
  binding.cid == request.input_binding_cid
}

///|
struct RemotePollDispatch {
  request : DispatchRequest
  binding : RemoteInputBinding
}

///|
/// Polling transports dispatch delivery and status reconciliation as distinct
/// physical operations. Only `Dispatch` may reach Site admission.
pub(all) enum RemotePollOperation {
  Dispatch(RemotePollDispatch)
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
  binding : RemoteInputBinding,
) -> Result[String, DispatchIssue] {
  if request.input_binding_cid != binding.cid {
    return Err(DispatchIdentityMismatch)
  }
  let request_json = match dispatch_request_json(request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let writer = @encode.writer(1179648, 16, 2) catch {
    _ => return Err(InvalidDispatch)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "dispatch_request_cid")
    @encode.string_value(writer, request.dispatch_request_cid)
    @encode.key(writer, "input_binding_cid")
    @encode.string_value(writer, binding.cid)
    @encode.key(writer, "input_binding_json")
    @encode.string_value(writer, binding.body)
    @encode.key(writer, "request_json")
    @encode.string_value(writer, request_json)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-remote-poll-dispatch/0.2")
    @encode.end_object(writer)
  } catch {
    _ => return Err(InvalidDispatch)
  }
  Ok(@encode.finish(writer) catch { _ => return Err(InvalidDispatch) })
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
  try {
    let object = evidence_object(evidence_root(body, 1179648, 16, 2), [
      "dispatch_request_cid", "input_binding_cid", "input_binding_json", "request_json",
      "version",
    ])
    if evidence_text(object, "version") != "actql-remote-poll-dispatch/0.2" {
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
    let binding = match
      prepare_remote_input_binding(
        evidence_text(object, "input_binding_json"),
        1048576,
      ) {
      Ok(value) => value
      Err(_) => raise EvidenceJsonStop
    }
    if binding.cid != evidence_text(object, "input_binding_cid") ||
      binding.cid != request.input_binding_cid {
      raise EvidenceJsonStop
    }
    Ok({ request, binding, })
  } catch {
    EvidenceJsonStop => Err(InvalidDispatch)
  }
}

///|
pub fn admit_remote_poll_operation_json(
  body : String,
) -> Result[RemotePollOperation, DispatchIssue] {
  match admit_remote_poll_dispatch_json(body) {
    Ok(dispatch) => return Ok(Dispatch(dispatch))
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
    Dispatch(dispatch) => dispatch.request
    Query(request) => request
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
pub fn remote_poll_dispatch_input_binding(
  dispatch : RemotePollDispatch,
) -> RemoteInputBinding {
  dispatch.binding
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
