///|
/// Canonical Coordinator intent for the physical handling of one retained
/// dispatch output. Output generation and manifest facts are deliberately
/// absent because the Site establishes them only after execution.
struct RemoteOutputIntent {
  dispatch_request_cid : String
  store_authority_cid : String
  publication_attempt_cid : String
  result_definition_cid : String
  ordering_evidence_cid : String
  coordinator_authority : String
  transfer_attempt : String
  transfer_route : @transfer.RemoteTransferRoute
  destination_site_key : String
  destination_site_generation : Int
  transfer_max_bytes : Int64
  transfer_expires_unix_ms : Int64
  source_grant_cid : String
  destination_grant_cid : String
  route_capability_cid : String
  transfer_origin : String
  body : String
  intent_cid : String
}

///|
/// Typed projection consumed by the application owner after intent identity
/// and canonical encoding have already been verified.
pub(all) struct RemoteOutputIntentProjection {
  store_authority_cid : String
  publication_attempt_cid : String
  result_definition_cid : String
  ordering_evidence_cid : String
  coordinator_authority : String
  transfer_attempt : String
  transfer_route : @transfer.RemoteTransferRoute
  destination_site_key : String
  destination_site_generation : Int
  transfer_max_bytes : Int64
  transfer_expires_unix_ms : Int64
  source_grant_cid : String
  destination_grant_cid : String
  route_capability_cid : String
  transfer_origin : String
}

///|
fn valid_output_intent(
  dispatch_request_cid : String,
  projection : RemoteOutputIntentProjection,
) -> Bool {
  valid_cid(dispatch_request_cid) &&
  valid_cid(projection.store_authority_cid) &&
  valid_cid(projection.publication_attempt_cid) &&
  valid_cid(projection.result_definition_cid) &&
  valid_cid(projection.ordering_evidence_cid) &&
  !projection.coordinator_authority.is_empty() &&
  !projection.transfer_attempt.is_empty() &&
  !projection.destination_site_key.is_empty() &&
  projection.destination_site_generation >= 0 &&
  projection.transfer_max_bytes > 0L &&
  projection.transfer_expires_unix_ms > 0L &&
  valid_cid(projection.source_grant_cid) &&
  valid_cid(projection.destination_grant_cid) &&
  valid_cid(projection.route_capability_cid) &&
  !projection.transfer_origin.is_empty()
}

///|
fn output_route_text(route : @transfer.RemoteTransferRoute) -> String {
  match route {
    @transfer.DirectStream => "direct"
    @transfer.TransferStore => "store"
  }
}

///|
fn emit_remote_output_intent(
  dispatch_request_cid : String,
  projection : RemoteOutputIntentProjection,
) -> Result[(String, String), DispatchIssue] {
  if !valid_output_intent(dispatch_request_cid, projection) {
    return Err(InvalidDispatch)
  }
  let writer = @encode.writer(65536, 64, 2) catch {
    _ => return Err(InvalidDispatch)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "coordinator_authority")
    @encode.string_value(writer, projection.coordinator_authority)
    @encode.key(writer, "destination_grant_cid")
    @encode.string_value(writer, projection.destination_grant_cid)
    @encode.key(writer, "destination_site_generation")
    @encode.number_value(
      writer,
      projection.destination_site_generation.to_double(),
    )
    @encode.key(writer, "destination_site_key")
    @encode.string_value(writer, projection.destination_site_key)
    @encode.key(writer, "dispatch_request_cid")
    @encode.string_value(writer, dispatch_request_cid)
    @encode.key(writer, "ordering_evidence_cid")
    @encode.string_value(writer, projection.ordering_evidence_cid)
    @encode.key(writer, "publication_attempt_cid")
    @encode.string_value(writer, projection.publication_attempt_cid)
    @encode.key(writer, "result_definition_cid")
    @encode.string_value(writer, projection.result_definition_cid)
    @encode.key(writer, "route_capability_cid")
    @encode.string_value(writer, projection.route_capability_cid)
    @encode.key(writer, "source_grant_cid")
    @encode.string_value(writer, projection.source_grant_cid)
    @encode.key(writer, "store_authority_cid")
    @encode.string_value(writer, projection.store_authority_cid)
    @encode.key(writer, "transfer_attempt")
    @encode.string_value(writer, projection.transfer_attempt)
    @encode.key(writer, "transfer_expires_unix_ms")
    @encode.string_value(
      writer,
      projection.transfer_expires_unix_ms.to_string(),
    )
    @encode.key(writer, "transfer_max_bytes")
    @encode.string_value(writer, projection.transfer_max_bytes.to_string())
    @encode.key(writer, "transfer_origin")
    @encode.string_value(writer, projection.transfer_origin)
    @encode.key(writer, "transfer_route")
    @encode.string_value(writer, output_route_text(projection.transfer_route))
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-remote-output-intent/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(InvalidDispatch)
  }
  let body = @encode.finish(writer) catch { _ => return Err(InvalidDispatch) }
  Ok((body, "sha256:" + @sha.hex(@utf8.encode(body))))
}

///|
pub fn prepare_remote_output_intent(
  request : DispatchRequest,
  projection : RemoteOutputIntentProjection,
) -> Result[RemoteOutputIntent, DispatchIssue] {
  let dispatch_request_cid = dispatch_request_identity(request)
  match emit_remote_output_intent(dispatch_request_cid, projection) {
    Ok((body, intent_cid)) =>
      Ok({
        dispatch_request_cid,
        store_authority_cid: projection.store_authority_cid,
        publication_attempt_cid: projection.publication_attempt_cid,
        result_definition_cid: projection.result_definition_cid,
        ordering_evidence_cid: projection.ordering_evidence_cid,
        coordinator_authority: projection.coordinator_authority,
        transfer_attempt: projection.transfer_attempt,
        transfer_route: projection.transfer_route,
        destination_site_key: projection.destination_site_key,
        destination_site_generation: projection.destination_site_generation,
        transfer_max_bytes: projection.transfer_max_bytes,
        transfer_expires_unix_ms: projection.transfer_expires_unix_ms,
        source_grant_cid: projection.source_grant_cid,
        destination_grant_cid: projection.destination_grant_cid,
        route_capability_cid: projection.route_capability_cid,
        transfer_origin: projection.transfer_origin,
        body,
        intent_cid,
      })
    Err(issue) => Err(issue)
  }
}

///|
pub fn remote_output_intent_identity(intent : RemoteOutputIntent) -> String {
  intent.intent_cid
}

///|
pub fn remote_output_intent_json(
  intent : RemoteOutputIntent,
) -> Result[String, DispatchIssue] {
  let projection = remote_output_intent_projection(intent)
  match emit_remote_output_intent(intent.dispatch_request_cid, projection) {
    Ok((body, identity)) if body == intent.body && identity == intent.intent_cid =>
      Ok(body)
    _ => Err(InvalidDispatch)
  }
}

///|
/// Re-admit one canonical output operation intent for the exact dispatch.
/// Physical output facts are deliberately unavailable to this request.
pub fn admit_remote_output_intent_json(
  body : String,
  claimed_cid : String,
  request : DispatchRequest,
) -> Result[RemoteOutputIntent, DispatchIssue] {
  try {
    let object = evidence_object(evidence_root(body, 65536, 64, 2), [
      "coordinator_authority", "destination_grant_cid", "destination_site_generation",
      "destination_site_key", "dispatch_request_cid", "ordering_evidence_cid", "publication_attempt_cid",
      "result_definition_cid", "route_capability_cid", "source_grant_cid", "store_authority_cid",
      "transfer_attempt", "transfer_expires_unix_ms", "transfer_max_bytes", "transfer_origin",
      "transfer_route", "version",
    ])
    if evidence_text(object, "version") != "actql-remote-output-intent/0.1" ||
      evidence_text(object, "dispatch_request_cid") !=
      dispatch_request_identity(request) {
      raise EvidenceJsonStop
    }
    let route = match evidence_text(object, "transfer_route") {
      "direct" => @transfer.DirectStream
      "store" => @transfer.TransferStore
      _ => raise EvidenceJsonStop
    }
    let projection : RemoteOutputIntentProjection = {
      store_authority_cid: evidence_text(object, "store_authority_cid"),
      publication_attempt_cid: evidence_text(object, "publication_attempt_cid"),
      result_definition_cid: evidence_text(object, "result_definition_cid"),
      ordering_evidence_cid: evidence_text(object, "ordering_evidence_cid"),
      coordinator_authority: evidence_text(object, "coordinator_authority"),
      transfer_attempt: evidence_text(object, "transfer_attempt"),
      transfer_route: route,
      destination_site_key: evidence_text(object, "destination_site_key"),
      destination_site_generation: evidence_int(
        object, "destination_site_generation",
      ),
      transfer_max_bytes: evidence_text_int64(object, "transfer_max_bytes"),
      transfer_expires_unix_ms: evidence_text_int64(
        object, "transfer_expires_unix_ms",
      ),
      source_grant_cid: evidence_text(object, "source_grant_cid"),
      destination_grant_cid: evidence_text(object, "destination_grant_cid"),
      route_capability_cid: evidence_text(object, "route_capability_cid"),
      transfer_origin: evidence_text(object, "transfer_origin"),
    }
    let admitted = match prepare_remote_output_intent(request, projection) {
      Ok(value) => value
      Err(_) => raise EvidenceJsonStop
    }
    if admitted.body != body || admitted.intent_cid != claimed_cid {
      raise EvidenceJsonStop
    }
    Ok(admitted)
  } catch {
    EvidenceJsonStop => Err(InvalidDispatch)
  }
}

///|
pub fn remote_output_intent_matches_dispatch(
  intent : RemoteOutputIntent,
  request : DispatchRequest,
) -> Bool {
  intent.dispatch_request_cid == dispatch_request_identity(request)
}

///|
pub fn remote_output_intent_projection(
  intent : RemoteOutputIntent,
) -> RemoteOutputIntentProjection {
  {
    store_authority_cid: intent.store_authority_cid,
    publication_attempt_cid: intent.publication_attempt_cid,
    result_definition_cid: intent.result_definition_cid,
    ordering_evidence_cid: intent.ordering_evidence_cid,
    coordinator_authority: intent.coordinator_authority,
    transfer_attempt: intent.transfer_attempt,
    transfer_route: intent.transfer_route,
    destination_site_key: intent.destination_site_key,
    destination_site_generation: intent.destination_site_generation,
    transfer_max_bytes: intent.transfer_max_bytes,
    transfer_expires_unix_ms: intent.transfer_expires_unix_ms,
    source_grant_cid: intent.source_grant_cid,
    destination_grant_cid: intent.destination_grant_cid,
    route_capability_cid: intent.route_capability_cid,
    transfer_origin: intent.transfer_origin,
  }
}
