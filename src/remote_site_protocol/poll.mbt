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
  /// Typed run materials for a Site that did not install this Run. The
  /// protocol bounds and carries the bytes; the Site admits their meaning by
  /// rebuilding the Run and matching `run_definition_cid`. They carry no
  /// execution authority of their own.
  materials : String?
}

///|
/// Upper bound of the run materials carried in one dispatch envelope.
pub const REMOTE_RUN_MATERIALS_MAX_BYTES : Int = 262144

///|
struct RemotePollOutput {
  request : DispatchRequest
  intent : RemoteOutputIntent
}

///|
/// Polling transports dispatch, output handling, status reconciliation, and
/// release as distinct physical operations. Output handling cannot recreate
/// or replace the completed dispatch.
pub(all) enum RemotePollOperation {
  Dispatch(RemotePollDispatch)
  Plan(RemotePollOutput)
  RetainedPlan(RemotePollRetainedInput)
  Output(RemotePollOutput)
  Query(DispatchRequest)
  Cancel(DispatchRequest)
  Release(DispatchRequest)
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
    @encode.string_value(writer, "actql-remote-poll-dispatch/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(InvalidDispatch)
  }
  Ok(@encode.finish(writer) catch { _ => return Err(InvalidDispatch) })
}

///|
/// A dispatch envelope that also carries the typed run materials. The binding
/// keeps its Connector-owned meaning; the materials are a separate body.
pub fn remote_poll_dispatch_materials_json(
  request : DispatchRequest,
  binding : RemoteInputBinding,
  materials : String,
) -> Result[String, DispatchIssue] {
  if request.input_binding_cid != binding.cid {
    return Err(DispatchIdentityMismatch)
  }
  let size = @utf8.encode(materials).length()
  if size == 0 || size > REMOTE_RUN_MATERIALS_MAX_BYTES {
    return Err(InvalidDispatch)
  }
  let request_json = match dispatch_request_json(request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let writer = @encode.writer(
    1179648 + REMOTE_RUN_MATERIALS_MAX_BYTES + 1024,
    16,
    2,
  ) catch {
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
    @encode.key(writer, "run_materials_json")
    @encode.string_value(writer, materials)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-remote-poll-dispatch-materials/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(InvalidDispatch)
  }
  Ok(@encode.finish(writer) catch { _ => return Err(InvalidDispatch) })
}

///|
pub fn remote_poll_output_json(
  request : DispatchRequest,
  intent : RemoteOutputIntent,
) -> Result[String, DispatchIssue] {
  remote_poll_output_operation_json(
    request, intent, "actql-remote-poll-output/0.1",
  )
}

///|
/// Ask the Site to derive the immutable physical output requests without
/// executing publication or Transfer effects.
pub fn remote_poll_output_plan_json(
  request : DispatchRequest,
  intent : RemoteOutputIntent,
) -> Result[String, DispatchIssue] {
  remote_poll_output_operation_json(
    request, intent, "actql-remote-poll-output-plan/0.1",
  )
}

///|
fn remote_poll_output_operation_json(
  request : DispatchRequest,
  intent : RemoteOutputIntent,
  version : String,
) -> Result[String, DispatchIssue] {
  if !remote_output_intent_matches_dispatch(intent, request) {
    return Err(DispatchIdentityMismatch)
  }
  let request_json = match dispatch_request_json(request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let intent_json = match remote_output_intent_json(intent) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let writer = @encode.writer(524288, 16, 2) catch {
    _ => return Err(InvalidDispatch)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "dispatch_request_cid")
    @encode.string_value(writer, dispatch_request_identity(request))
    @encode.key(writer, "intent_cid")
    @encode.string_value(writer, remote_output_intent_identity(intent))
    @encode.key(writer, "intent_json")
    @encode.string_value(writer, intent_json)
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
pub fn remote_poll_query_json(
  request : DispatchRequest,
) -> Result[String, DispatchIssue] {
  remote_poll_request_json(request, "actql-remote-poll-query/0.1")
}

///|
/// Request release of the exact retained dispatch output. This operation has
/// no authority to execute or recreate the dispatch; an exact retry only
/// reconciles the existing Site owner and durable cleanup state.
pub fn remote_poll_release_json(
  request : DispatchRequest,
) -> Result[String, DispatchIssue] {
  remote_poll_request_json(request, "actql-remote-poll-release/0.1")
}

///|
/// Request cancellation of the exact original dispatch, including its scope,
/// attempt, Site generation and registered runtime. This carries no Run
/// materials and cannot authorize execution. The Site must persist the
/// cancellation through its journal before returning cancellation evidence.
pub fn remote_poll_cancel_json(
  request : DispatchRequest,
) -> Result[String, DispatchIssue] {
  remote_poll_request_json(request, "actql-remote-poll-cancel/0.1")
}

///|
pub fn admit_remote_poll_cancel_json(
  body : String,
) -> Result[DispatchRequest, DispatchIssue] {
  admit_remote_poll_request_json(body, "actql-remote-poll-cancel/0.1")
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
  match admit_remote_poll_dispatch_fields(body, false) {
    Ok(value) => Ok(value)
    Err(_) => admit_remote_poll_dispatch_fields(body, true)
  }
}

///|
fn admit_remote_poll_dispatch_fields(
  body : String,
  with_materials : Bool,
) -> Result[RemotePollDispatch, DispatchIssue] {
  try {
    let object = if with_materials {
      evidence_object(
        evidence_root(
          body,
          1179648 + REMOTE_RUN_MATERIALS_MAX_BYTES + 1024,
          16,
          2,
        ),
        [
          "dispatch_request_cid", "input_binding_cid", "input_binding_json", "request_json",
          "run_materials_json", "version",
        ],
      )
    } else {
      evidence_object(evidence_root(body, 1179648, 16, 2), [
        "dispatch_request_cid", "input_binding_cid", "input_binding_json", "request_json",
        "version",
      ])
    }
    let expected = if with_materials {
      "actql-remote-poll-dispatch-materials/0.1"
    } else {
      "actql-remote-poll-dispatch/0.1"
    }
    if evidence_text(object, "version") != expected {
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
    let materials = if with_materials {
      let text = evidence_text(object, "run_materials_json")
      let size = @utf8.encode(text).length()
      if size == 0 || size > REMOTE_RUN_MATERIALS_MAX_BYTES {
        raise EvidenceJsonStop
      }
      Some(text)
    } else {
      None
    }
    Ok({ request, binding, materials, })
  } catch {
    EvidenceJsonStop => Err(InvalidDispatch)
  }
}

///|
pub fn admit_remote_poll_output_json(
  body : String,
) -> Result[RemotePollOutput, DispatchIssue] {
  admit_remote_poll_output_operation_json(body, "actql-remote-poll-output/0.1")
}

///|
pub fn admit_remote_poll_output_plan_json(
  body : String,
) -> Result[RemotePollOutput, DispatchIssue] {
  admit_remote_poll_output_operation_json(
    body, "actql-remote-poll-output-plan/0.1",
  )
}

///|
fn admit_remote_poll_output_operation_json(
  body : String,
  expected_version : String,
) -> Result[RemotePollOutput, DispatchIssue] {
  try {
    let object = evidence_object(evidence_root(body, 524288, 16, 2), [
      "dispatch_request_cid", "intent_cid", "intent_json", "request_json", "version",
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
    let intent = match
      admit_remote_output_intent_json(
        evidence_text(object, "intent_json"),
        evidence_text(object, "intent_cid"),
        request,
      ) {
      Ok(value) => value
      Err(_) => raise EvidenceJsonStop
    }
    Ok({ request, intent, })
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
  match admit_remote_poll_retained_input_plan_json(body) {
    Ok(input) => return Ok(RetainedPlan(input))
    Err(_) => ()
  }
  match admit_remote_poll_output_plan_json(body) {
    Ok(output) => return Ok(Plan(output))
    Err(_) => ()
  }
  match admit_remote_poll_output_json(body) {
    Ok(output) => return Ok(Output(output))
    Err(_) => ()
  }
  match admit_remote_poll_cancel_json(body) {
    Ok(request) => return Ok(Cancel(request))
    Err(_) => ()
  }
  match admit_remote_poll_request_json(body, "actql-remote-poll-query/0.1") {
    Ok(request) => Ok(Query(request))
    Err(_) =>
      match
        admit_remote_poll_request_json(body, "actql-remote-poll-release/0.1") {
        Ok(request) => Ok(Release(request))
        Err(issue) => Err(issue)
      }
  }
}

///|
pub fn remote_poll_operation_request(
  operation : RemotePollOperation,
) -> DispatchRequest {
  match operation {
    Dispatch(dispatch) => dispatch.request
    Plan(output) | Output(output) => output.request
    RetainedPlan(input) => input.request
    Query(request) | Cancel(request) | Release(request) => request
  }
}

///|
pub fn remote_poll_operation_is_query(operation : RemotePollOperation) -> Bool {
  match operation {
    Dispatch(_) | RetainedPlan(_) | Plan(_) | Output(_) => false
    Query(_) => true
    Release(_) | Cancel(_) => false
  }
}

///|
pub fn remote_poll_operation_is_release(
  operation : RemotePollOperation,
) -> Bool {
  match operation {
    Release(_) => true
    Dispatch(_)
    | RetainedPlan(_)
    | Plan(_)
    | Output(_)
    | Query(_)
    | Cancel(_) => false
  }
}

///|
pub fn remote_poll_operation_is_output(operation : RemotePollOperation) -> Bool {
  match operation {
    Output(_) => true
    Dispatch(_)
    | RetainedPlan(_)
    | Plan(_)
    | Query(_)
    | Release(_)
    | Cancel(_) => false
  }
}

///|
pub fn remote_poll_operation_is_output_plan(
  operation : RemotePollOperation,
) -> Bool {
  match operation {
    Plan(_) => true
    Dispatch(_)
    | RetainedPlan(_)
    | Output(_)
    | Query(_)
    | Release(_)
    | Cancel(_) => false
  }
}

///|
pub fn remote_poll_dispatch_request(
  dispatch : RemotePollDispatch,
) -> DispatchRequest {
  dispatch.request
}

///|
pub fn remote_poll_dispatch_run_materials(
  dispatch : RemotePollDispatch,
) -> String? {
  dispatch.materials
}

///|
pub fn remote_poll_dispatch_input_binding(
  dispatch : RemotePollDispatch,
) -> RemoteInputBinding {
  dispatch.binding
}

///|
pub fn remote_poll_output_request(output : RemotePollOutput) -> DispatchRequest {
  output.request
}

///|
pub fn remote_poll_output_intent(
  output : RemotePollOutput,
) -> RemoteOutputIntent {
  output.intent
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

///|
pub fn remote_poll_operation_is_cancel(operation : RemotePollOperation) -> Bool {
  match operation {
    Cancel(_) => true
    Dispatch(_)
    | RetainedPlan(_)
    | Plan(_)
    | Output(_)
    | Query(_)
    | Release(_) => false
  }
}

///|
pub fn remote_poll_operation_is_retained_input_plan(
  operation : RemotePollOperation,
) -> Bool {
  operation is RetainedPlan(_)
}
