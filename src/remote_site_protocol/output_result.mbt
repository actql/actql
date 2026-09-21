///|
/// Canonical physical result of one retained-output operation. This record is
/// a Site observation, not publication commit authority and not permission to
/// release the source output.
struct RemoteOutputResult {
  dispatch_request_cid : String
  intent_cid : String
  payload_request_cid : String
  payload_physical_digest : String
  transfer_request_cid : String
  transfer_reply_json : String
  body : String
  result_cid : String
}

///|
fn output_result_inputs_valid(
  output : RemotePollOutput,
  payload_request : @payload.PublicationPayloadRequest,
  payload_physical_digest : String,
  transfer_record : @transfer.RemoteTransferRecord,
) -> Bool {
  let request = output.request
  let intent = output.intent
  let intent_projection = remote_output_intent_projection(intent)
  let transfer_projection = @transfer.request_projection(
    @transfer.record_request(transfer_record),
  )
  let transfer_occurrence = @transfer.request_journal_key(
    @transfer.record_request(transfer_record),
  )
  remote_output_intent_matches_dispatch(intent, request) &&
  valid_cid(payload_physical_digest) &&
  @payload.publication_payload_request_store_authority(payload_request) ==
  intent_projection.store_authority_cid &&
  @payload.publication_payload_request_attempt(payload_request) ==
  intent_projection.publication_attempt_cid &&
  @payload.publication_payload_request_result_definition(payload_request) ==
  intent_projection.result_definition_cid &&
  @payload.publication_payload_request_ordering_evidence(payload_request) ==
  intent_projection.ordering_evidence_cid &&
  @payload.publication_payload_request_max_bytes(payload_request) <=
  intent_projection.transfer_max_bytes &&
  transfer_projection.length() == 13 &&
  transfer_projection[1] == output_route_text(intent_projection.transfer_route) &&
  transfer_projection[2] == request.site_key &&
  transfer_projection[3] == request.site_generation.to_string() &&
  transfer_projection[4] == intent_projection.destination_site_key &&
  transfer_projection[5] ==
  intent_projection.destination_site_generation.to_string() &&
  transfer_projection[6] ==
  @payload.publication_payload_material_identity(payload_request) &&
  transfer_projection[8] == intent_projection.transfer_max_bytes.to_string() &&
  transfer_projection[9] ==
  intent_projection.transfer_expires_unix_ms.to_string() &&
  transfer_projection[10] == intent_projection.source_grant_cid &&
  transfer_projection[11] == intent_projection.destination_grant_cid &&
  transfer_projection[12] == intent_projection.route_capability_cid &&
  transfer_occurrence ==
  [
    intent_projection.coordinator_authority,
    intent_projection.destination_site_key,
    intent_projection.destination_site_generation.to_string(),
    intent_projection.transfer_attempt,
  ] &&
  @transfer.record_is_destination_committed(transfer_record)
}

///|
fn emit_remote_output_result(
  dispatch_request_cid : String,
  intent_cid : String,
  payload_request_cid : String,
  payload_physical_digest : String,
  transfer_request_cid : String,
  transfer_reply_json : String,
) -> Result[(String, String), DispatchIssue] {
  if !valid_cid(dispatch_request_cid) ||
    !valid_cid(intent_cid) ||
    !valid_cid(payload_request_cid) ||
    !valid_cid(payload_physical_digest) ||
    !valid_cid(transfer_request_cid) ||
    transfer_reply_json.is_empty() {
    return Err(InvalidDispatch)
  }
  let writer = @encode.writer(16384, 32, 2) catch {
    _ => return Err(InvalidDispatch)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "dispatch_request_cid")
    @encode.string_value(writer, dispatch_request_cid)
    @encode.key(writer, "intent_cid")
    @encode.string_value(writer, intent_cid)
    @encode.key(writer, "payload_physical_digest")
    @encode.string_value(writer, payload_physical_digest)
    @encode.key(writer, "payload_request_cid")
    @encode.string_value(writer, payload_request_cid)
    @encode.key(writer, "transfer_reply_json")
    @encode.string_value(writer, transfer_reply_json)
    @encode.key(writer, "transfer_request_cid")
    @encode.string_value(writer, transfer_request_cid)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-remote-output-result/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(InvalidDispatch)
  }
  let body = @encode.finish(writer) catch { _ => return Err(InvalidDispatch) }
  Ok((body, "sha256:" + @sha.hex(@utf8.encode(body))))
}

///|
pub fn prepare_remote_output_result(
  output : RemotePollOutput,
  payload_request : @payload.PublicationPayloadRequest,
  payload_physical_digest : String,
  transfer_record : @transfer.RemoteTransferRecord,
) -> Result[RemoteOutputResult, DispatchIssue] {
  if !output_result_inputs_valid(
      output, payload_request, payload_physical_digest, transfer_record,
    ) {
    return Err(InvalidDispatch)
  }
  let transfer_reply_json = match
    @transfer.remote_transfer_reply_json(transfer_record) {
    Ok(value) => value
    Err(_) => return Err(InvalidDispatch)
  }
  let dispatch_request_cid = dispatch_request_identity(output.request)
  let intent_cid = remote_output_intent_identity(output.intent)
  let payload_request_cid = @payload.publication_payload_request_identity(
    payload_request,
  )
  let transfer_request_cid = @transfer.record_request_identity(transfer_record)
  match
    emit_remote_output_result(
      dispatch_request_cid, intent_cid, payload_request_cid, payload_physical_digest,
      transfer_request_cid, transfer_reply_json,
    ) {
    Ok((body, result_cid)) =>
      Ok({
        dispatch_request_cid,
        intent_cid,
        payload_request_cid,
        payload_physical_digest,
        transfer_request_cid,
        transfer_reply_json,
        body,
        result_cid,
      })
    Err(issue) => Err(issue)
  }
}

///|
pub fn remote_output_result_identity(result : RemoteOutputResult) -> String {
  result.result_cid
}

///|
pub fn remote_output_result_json(
  result : RemoteOutputResult,
) -> Result[String, DispatchIssue] {
  match
    emit_remote_output_result(
      result.dispatch_request_cid,
      result.intent_cid,
      result.payload_request_cid,
      result.payload_physical_digest,
      result.transfer_request_cid,
      result.transfer_reply_json,
    ) {
    Ok((body, identity)) if body == result.body && identity == result.result_cid =>
      Ok(body)
    _ => Err(InvalidDispatch)
  }
}

///|
/// Re-admit one Site result against the exact Coordinator intent and the
/// physical requests derived from the accepted output observation.
pub fn admit_remote_output_result_json(
  body : String,
  output : RemotePollOutput,
  payload_request : @payload.PublicationPayloadRequest,
  transfer_request : @transfer.RemoteTransferRequest,
) -> Result[RemoteOutputResult, DispatchIssue] {
  try {
    let object = evidence_object(evidence_root(body, 16384, 32, 2), [
      "dispatch_request_cid", "intent_cid", "payload_physical_digest", "payload_request_cid",
      "transfer_reply_json", "transfer_request_cid", "version",
    ])
    if evidence_text(object, "version") != "actql-remote-output-result/0.1" ||
      evidence_text(object, "dispatch_request_cid") !=
      dispatch_request_identity(output.request) ||
      evidence_text(object, "intent_cid") !=
      remote_output_intent_identity(output.intent) ||
      evidence_text(object, "payload_request_cid") !=
      @payload.publication_payload_request_identity(payload_request) ||
      evidence_text(object, "transfer_request_cid") !=
      @transfer.request_cid(transfer_request) {
      raise EvidenceJsonStop
    }
    let transfer_record = match
      @transfer.admit_remote_transfer_reply_json(
        evidence_text(object, "transfer_reply_json"),
        transfer_request,
      ) {
      Ok(value) => value
      Err(_) => raise EvidenceJsonStop
    }
    let admitted = match
      prepare_remote_output_result(
        output,
        payload_request,
        evidence_text(object, "payload_physical_digest"),
        transfer_record,
      ) {
      Ok(value) => value
      Err(_) => raise EvidenceJsonStop
    }
    if admitted.body != body {
      raise EvidenceJsonStop
    }
    Ok(admitted)
  } catch {
    EvidenceJsonStop => Err(InvalidDispatch)
  }
}

///|
pub fn remote_output_result_payload_digest(
  result : RemoteOutputResult,
) -> String {
  result.payload_physical_digest
}

///|
pub fn remote_output_result_transfer_record(
  result : RemoteOutputResult,
  request : @transfer.RemoteTransferRequest,
) -> Result[@transfer.RemoteTransferRecord, DispatchIssue] {
  match
    @transfer.admit_remote_transfer_reply_json(
      result.transfer_reply_json,
      request,
    ) {
    Ok(record) if @transfer.record_is_destination_committed(record) =>
      Ok(record)
    _ => Err(InvalidDispatch)
  }
}

///|
pub fn remote_output_result_projection(
  result : RemoteOutputResult,
  request : @transfer.RemoteTransferRequest,
) -> Result[Array[String], DispatchIssue] {
  let record = match remote_output_result_transfer_record(result, request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok([
    result.result_cid,
    result.payload_request_cid,
    result.payload_physical_digest,
    result.transfer_request_cid,
    @transfer.record_revision(record).to_string(),
  ])
}
