///|
pub(all) enum RemoteDispatchResponseKind {
  DispatchReply
  StatusReply
} derive(Eq, Debug)

///|
/// A transport response is an authenticated observation candidate. It does
/// not become Coordinator state until the common transition is made durable.
struct RemoteDispatchResponse {
  kind : RemoteDispatchResponseKind
  dispatch_request_cid : String
  revision : Int
  execution : Int
  evidence_state : Int
  cleanup : Int
  material_available : Bool
  quarantined_capacity : Bool
  evidence : RemoteExecutionEvidence?
  subject : RemoteManagedOutputSubject?
  measurement : RemoteManagedOutputMeasurement?
}

///|
priv suberror ResponseJsonStop {
  ResponseJsonStop
}

///|
fn[T] response_decoded(
  value : Result[T, @decode.Issue],
) -> T raise ResponseJsonStop {
  match value {
    Ok(result) => result
    Err(_) => raise ResponseJsonStop
  }
}

///|
fn response_root(body : String) -> @decode.Cursor raise ResponseJsonStop {
  let bytes = @utf8.encode(body)
  if bytes.length() > 524288 {
    raise ResponseJsonStop
  }
  let node = match
    @source.parse_json_bytes(bytes, {
      max_input_bytes: 524288,
      max_nodes: 64,
      max_depth: 3,
    }) {
    Ok(value) => value
    Err(_) => raise ResponseJsonStop
  }
  response_decoded(
    @decode.admit(node, {
      max_nodes: 64,
      max_depth: 3,
      max_string_bytes: 262144,
      max_total_string_bytes: 524288,
    }),
  )
}

///|
fn response_text(
  object : @decode.ObjectView,
  name : String,
) -> String raise ResponseJsonStop {
  response_decoded(
    @decode.text(response_decoded(@decode.required(object, name))),
  )
}

///|
fn response_int_cursor(cursor : @decode.Cursor) -> Int raise ResponseJsonStop {
  let value = response_decoded(@decode.safe_integer(cursor))
  if value < 0L || value > 2147483647L {
    raise ResponseJsonStop
  }
  value.to_int()
}

///|
fn response_int(
  object : @decode.ObjectView,
  name : String,
) -> Int raise ResponseJsonStop {
  response_int_cursor(response_decoded(@decode.required(object, name)))
}

///|
fn response_state(
  object : @decode.ObjectView,
) -> (Int, Int, Int, Bool, Bool) raise ResponseJsonStop {
  let cursor = response_decoded(@decode.required(object, "state"))
  let elements = response_decoded(@decode.elements(cursor))
  if elements.length() != 5 {
    raise ResponseJsonStop
  }
  let execution = response_int_cursor(elements[0])
  let evidence = response_int_cursor(elements[1])
  let cleanup = response_int_cursor(elements[2])
  let material = response_int_cursor(elements[3])
  let quarantined = response_int_cursor(elements[4])
  if (material != 0 && material != 1) ||
    (quarantined != 0 && quarantined != 1) ||
    !valid_site_observation(
      execution,
      evidence,
      cleanup,
      material == 1,
      quarantined == 1,
    ) {
    raise ResponseJsonStop
  }
  (execution, evidence, cleanup, material == 1, quarantined == 1)
}

///|
fn response_wire_record(
  cursor : @decode.Cursor,
) -> (String, String) raise ResponseJsonStop {
  let object = response_decoded(@decode.closed_object(cursor, ["cid", "wire"]))
  (response_text(object, "cid"), response_text(object, "wire"))
}

///|
fn response_evidence(
  object : @decode.ObjectView,
  request : DispatchRequest,
) -> (
  RemoteExecutionEvidence?,
  RemoteManagedOutputSubject?,
  RemoteManagedOutputMeasurement?,
) raise ResponseJsonStop {
  let evidence_cursor = match @decode.lookup(object, "evidence") {
    Some(value) => value
    None => raise ResponseJsonStop
  }
  let subject_cursor = match @decode.lookup(object, "subject") {
    Some(value) => value
    None => raise ResponseJsonStop
  }
  let measurement_cursor = match @decode.lookup(object, "measurement") {
    Some(value) => value
    None => raise ResponseJsonStop
  }
  if @decode.is_null(evidence_cursor) &&
    @decode.is_null(subject_cursor) &&
    @decode.is_null(measurement_cursor) {
    return (None, None, None)
  }
  if @decode.is_null(evidence_cursor) ||
    @decode.is_null(subject_cursor) ||
    @decode.is_null(measurement_cursor) {
    raise ResponseJsonStop
  }
  let evidence_wire = response_wire_record(evidence_cursor)
  let subject_wire = response_wire_record(subject_cursor)
  let measurement_wire = response_wire_record(measurement_cursor)
  let evidence = match
    admit_remote_execution_evidence_json(
      evidence_wire.1,
      evidence_wire.0,
      request,
    ) {
    Ok(value) => value
    Err(_) => raise ResponseJsonStop
  }
  let subject = match
    admit_remote_managed_output_subject_json(
      subject_wire.1,
      subject_wire.0,
      request,
    ) {
    Ok(value) => value
    Err(_) => raise ResponseJsonStop
  }
  let measurement = match
    admit_remote_managed_output_measurement_json(
      measurement_wire.1,
      measurement_wire.0,
    ) {
    Ok(value) => value
    Err(_) => raise ResponseJsonStop
  }
  if !remote_managed_output_subject_matches_evidence(subject, evidence, request) ||
    !remote_managed_output_subject_matches_measurement(subject, measurement) {
    raise ResponseJsonStop
  }
  (Some(evidence), Some(subject), Some(measurement))
}

///|
/// Re-admit an exact remote response. TLS authentication protects the live
/// channel but does not replace this dispatch, state, or evidence admission.
pub fn admit_remote_dispatch_response_json(
  body : String,
  request : DispatchRequest,
  expected : RemoteDispatchResponseKind,
) -> Result[RemoteDispatchResponse, DispatchIssue] {
  try {
    let root = response_root(body)
    let common = ["dispatch_request_cid", "revision", "state", "version"]
    let names = match expected {
      DispatchReply => common
      StatusReply => common + ["evidence", "measurement", "subject"]
    }
    let object = response_decoded(@decode.closed_object(root, names))
    let expected_version = match expected {
      DispatchReply => "actql-remote-dispatch-response/0.1"
      StatusReply => "actql-remote-dispatch-status/0.1"
    }
    if response_text(object, "version") != expected_version ||
      response_text(object, "dispatch_request_cid") !=
      request.dispatch_request_cid {
      raise ResponseJsonStop
    }
    if expected == DispatchReply &&
      (
        @decode.lookup(object, "evidence") is Some(_) ||
        @decode.lookup(object, "subject") is Some(_) ||
        @decode.lookup(object, "measurement") is Some(_)
      ) {
      raise ResponseJsonStop
    }
    let (execution, evidence_state, cleanup, material, quarantined) = response_state(
      object,
    )
    let (evidence, subject, measurement) = match expected {
      DispatchReply => (None, None, None)
      StatusReply => response_evidence(object, request)
    }
    Ok({
      kind: expected,
      dispatch_request_cid: request.dispatch_request_cid,
      revision: response_int(object, "revision"),
      execution,
      evidence_state,
      cleanup,
      material_available: material,
      quarantined_capacity: quarantined,
      evidence,
      subject,
      measurement,
    })
  } catch {
    ResponseJsonStop => Err(InvalidDispatch)
  }
}

///|
/// Convert an admitted transport observation into the existing Coordinator
/// transition. Durability is still required before this transition commits.
pub fn prepare_coordinator_response_observation(
  record : CoordinatorDispatchIntentRecord,
  response : RemoteDispatchResponse,
) -> Result[CoordinatorDispatchTransition, DispatchIssue] {
  if record.request.dispatch_request_cid != response.dispatch_request_cid {
    return Err(DispatchIdentityMismatch)
  }
  prepare_coordinator_observation(
    record,
    response.revision,
    response.execution,
    response.evidence_state,
    response.cleanup,
    response.material_available,
    response.quarantined_capacity,
    response.evidence,
    response.subject,
    response.measurement,
  )
}

///|
pub fn remote_dispatch_response_kind(
  response : RemoteDispatchResponse,
) -> RemoteDispatchResponseKind {
  response.kind
}

///|
pub fn remote_dispatch_response_revision(
  response : RemoteDispatchResponse,
) -> Int {
  response.revision
}
