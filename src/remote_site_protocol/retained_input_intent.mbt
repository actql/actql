///|
/// An internal producer handoff names a checked consumer edge, never a public
/// Result or publication attempt. The Host issuer verifies the checked edge;
/// protocol admission alone grants no Transfer, borrow or execution authority.
pub(all) struct RemoteRetainedInputIntentProjection {
  consumer_input_port : String
  consumer_logical_cid : String
  consumer_task_key : String
  destination_grant_cid : String
  producer_evidence_cid : String
  producer_logical_cid : String
  producer_output_port : String
  producer_schema_cid : String
  producer_subject_cid : String
  route_capability_cid : String
  source_grant_cid : String
  transfer_attempt : String
  transfer_expires_unix_ms : Int64
  transfer_max_bytes : Int64
}

///|
pub struct RemoteRetainedInputIntent {
  request : DispatchRequest
  projection : RemoteRetainedInputIntentProjection
  body : String
  cid : String
}

///|
pub struct RemotePollRetainedInput {
  request : DispatchRequest
  intent : RemoteRetainedInputIntent
}

///|
pub fn prepare_remote_retained_input_intent(
  request : DispatchRequest,
  projection : RemoteRetainedInputIntentProjection,
) -> Result[RemoteRetainedInputIntent, DispatchIssue] {
  let scope = dispatch_request_task_scope(request)
  if projection.consumer_task_key.is_empty() ||
    projection.consumer_task_key == scope.1 ||
    projection.consumer_input_port.is_empty() ||
    projection.producer_output_port.is_empty() ||
    projection.transfer_attempt.is_empty() ||
    projection.transfer_expires_unix_ms <= 0L ||
    projection.transfer_max_bytes < 0L ||
    !valid_cid(projection.consumer_logical_cid) ||
    !valid_cid(projection.destination_grant_cid) ||
    !valid_cid(projection.producer_evidence_cid) ||
    !valid_cid(projection.producer_logical_cid) ||
    !valid_cid(projection.producer_schema_cid) ||
    !valid_cid(projection.producer_subject_cid) ||
    !valid_cid(projection.route_capability_cid) ||
    !valid_cid(projection.source_grant_cid) ||
    !valid_cid(scope.0) {
    return Err(InvalidDispatch)
  }
  let writer = @encode.writer(65536, 64, 2) catch {
    _ => return Err(InvalidDispatch)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "consumer_input_port")
    @encode.string_value(writer, projection.consumer_input_port)
    @encode.key(writer, "consumer_logical_cid")
    @encode.string_value(writer, projection.consumer_logical_cid)
    @encode.key(writer, "consumer_task_key")
    @encode.string_value(writer, projection.consumer_task_key)
    @encode.key(writer, "destination_grant_cid")
    @encode.string_value(writer, projection.destination_grant_cid)
    @encode.key(writer, "dispatch_request_cid")
    @encode.string_value(writer, dispatch_request_identity(request))
    @encode.key(writer, "producer_evidence_cid")
    @encode.string_value(writer, projection.producer_evidence_cid)
    @encode.key(writer, "producer_logical_cid")
    @encode.string_value(writer, projection.producer_logical_cid)
    @encode.key(writer, "producer_output_port")
    @encode.string_value(writer, projection.producer_output_port)
    @encode.key(writer, "producer_schema_cid")
    @encode.string_value(writer, projection.producer_schema_cid)
    @encode.key(writer, "producer_subject_cid")
    @encode.string_value(writer, projection.producer_subject_cid)
    @encode.key(writer, "route_capability_cid")
    @encode.string_value(writer, projection.route_capability_cid)
    @encode.key(writer, "source_grant_cid")
    @encode.string_value(writer, projection.source_grant_cid)
    @encode.key(writer, "transfer_attempt")
    @encode.string_value(writer, projection.transfer_attempt)
    @encode.key(writer, "transfer_expires_unix_ms")
    @encode.string_value(
      writer,
      projection.transfer_expires_unix_ms.to_string(),
    )
    @encode.key(writer, "transfer_max_bytes")
    @encode.string_value(writer, projection.transfer_max_bytes.to_string())
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-remote-retained-input-intent/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(InvalidDispatch)
  }
  let body = @encode.finish(writer) catch { _ => return Err(InvalidDispatch) }
  Ok({
    request,
    projection,
    body,
    cid: "sha256:" + @sha.hex(@utf8.encode(body)),
  })
}

///|
pub fn admit_remote_retained_input_intent_json(
  body : String,
  cid : String,
  request : DispatchRequest,
) -> Result[RemoteRetainedInputIntent, DispatchIssue] {
  try {
    let fields = evidence_object(evidence_root(body, 65536, 64, 2), [
      "consumer_input_port", "consumer_logical_cid", "consumer_task_key", "destination_grant_cid",
      "dispatch_request_cid", "producer_evidence_cid", "producer_logical_cid", "producer_output_port",
      "producer_schema_cid", "producer_subject_cid", "route_capability_cid", "source_grant_cid",
      "transfer_attempt", "transfer_expires_unix_ms", "transfer_max_bytes", "version",
    ])
    if evidence_text(fields, "version") !=
      "actql-remote-retained-input-intent/0.1" ||
      evidence_text(fields, "dispatch_request_cid") !=
      dispatch_request_identity(request) {
      raise EvidenceJsonStop
    }
    let projection : RemoteRetainedInputIntentProjection = {
      consumer_input_port: evidence_text(fields, "consumer_input_port"),
      consumer_logical_cid: evidence_text(fields, "consumer_logical_cid"),
      consumer_task_key: evidence_text(fields, "consumer_task_key"),
      destination_grant_cid: evidence_text(fields, "destination_grant_cid"),
      producer_evidence_cid: evidence_text(fields, "producer_evidence_cid"),
      producer_logical_cid: evidence_text(fields, "producer_logical_cid"),
      producer_output_port: evidence_text(fields, "producer_output_port"),
      producer_schema_cid: evidence_text(fields, "producer_schema_cid"),
      producer_subject_cid: evidence_text(fields, "producer_subject_cid"),
      route_capability_cid: evidence_text(fields, "route_capability_cid"),
      source_grant_cid: evidence_text(fields, "source_grant_cid"),
      transfer_attempt: evidence_text(fields, "transfer_attempt"),
      transfer_expires_unix_ms: evidence_text_int64(
        fields, "transfer_expires_unix_ms",
      ),
      transfer_max_bytes: evidence_text_int64(fields, "transfer_max_bytes"),
    }
    let intent = match
      prepare_remote_retained_input_intent(request, projection) {
      Ok(value) => value
      Err(_) => raise EvidenceJsonStop
    }
    if intent.body != body || intent.cid != cid {
      raise EvidenceJsonStop
    }
    Ok(intent)
  } catch {
    EvidenceJsonStop => Err(InvalidDispatch)
  }
}

///|
pub fn remote_retained_input_intent_json(
  intent : RemoteRetainedInputIntent,
) -> String {
  intent.body
}

///|
pub fn remote_retained_input_intent_identity(
  intent : RemoteRetainedInputIntent,
) -> String {
  intent.cid
}

///|
pub fn remote_retained_input_intent_projection(
  intent : RemoteRetainedInputIntent,
) -> RemoteRetainedInputIntentProjection {
  intent.projection
}

///|
pub fn remote_retained_input_intent_request(
  intent : RemoteRetainedInputIntent,
) -> DispatchRequest {
  intent.request
}

///|
pub fn remote_poll_retained_input_plan_json(
  intent : RemoteRetainedInputIntent,
) -> Result[String, DispatchIssue] {
  let request = match dispatch_request_json(intent.request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let writer = @encode.writer(524288, 16, 2) catch {
    _ => return Err(InvalidDispatch)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "dispatch_request_cid")
    @encode.string_value(writer, dispatch_request_identity(intent.request))
    @encode.key(writer, "intent_cid")
    @encode.string_value(writer, intent.cid)
    @encode.key(writer, "intent_json")
    @encode.string_value(writer, intent.body)
    @encode.key(writer, "request_json")
    @encode.string_value(writer, request)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-remote-poll-retained-input-plan/0.1")
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(InvalidDispatch)
  }
}

///|
pub fn admit_remote_poll_retained_input_plan_json(
  body : String,
) -> Result[RemotePollRetainedInput, DispatchIssue] {
  try {
    let fields = evidence_object(evidence_root(body, 524288, 16, 2), [
      "dispatch_request_cid", "intent_cid", "intent_json", "request_json", "version",
    ])
    if evidence_text(fields, "version") !=
      "actql-remote-poll-retained-input-plan/0.1" {
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
    let intent = match
      admit_remote_retained_input_intent_json(
        evidence_text(fields, "intent_json"),
        evidence_text(fields, "intent_cid"),
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
pub fn remote_poll_retained_input_intent(
  poll : RemotePollRetainedInput,
) -> RemoteRetainedInputIntent {
  poll.intent
}
