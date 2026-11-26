///|
// This is a correlation check on already signed DATA, not signature
// verification or Checkpoint authorization. The original Host owns both.
fn remote_signed_resolution_binding(
  answer : Json,
) -> (String, String, String) raise ClientStop {
  guard wire_resolve_item_shape(answer) &&
    answer is Object(fields) &&
    json_text(fields, "checkpointCid") is Some(checkpoint_cid) &&
    json_text(fields, "resolutionWire") is Some(wire) &&
    json_text(fields, "approvalEvidenceWire") is Some(evidence) else {
    stop("InvalidCheckpointAnswer")
  }
  if @source.parse_json(wire, {
      max_input_bytes: 16384,
      max_nodes: 128,
      max_depth: 8,
    })
    is Err(_) {
    stop("InvalidCheckpointAnswer")
  }
  let resolution = @json.parse(wire) catch {
    _ => stop("InvalidCheckpointAnswer")
  }
  guard resolution is Object(original) &&
    json_text(original, "checkpoint_cid") == Some(checkpoint_cid) &&
    original.get("resolution_cid") is Some(cid) &&
    wire_resolution_cid_shape(cid) &&
    cid is String(resolution_cid) &&
    json_text(original, "decision") is Some(decision) else {
    stop("InvalidCheckpointAnswer")
  }
  if !((decision == "approved" && !evidence.is_empty()) ||
    (decision == "rejected" && evidence.is_empty())) {
    stop("InvalidCheckpointAnswer")
  }
  (checkpoint_cid, resolution_cid, decision)
}

///|
fn verify_remote_resolution_reply(
  request : Bytes,
  raw_reply : Bytes,
  reply_text : String,
  response_max : Int,
) -> Unit raise ClientStop {
  let request_value = @json.parse(@utf8.decode(request)) catch {
    _ => stop("ResolutionUnknown")
  }
  guard request_value is Object(request_fields) &&
    request_fields.get("items") is Some(Array([answer])) else {
    stop("ResolutionUnknown")
  }
  let (checkpoint_cid, resolution_cid, decision) = remote_signed_resolution_binding(
    answer,
  )
  if @source.parse_json_bytes_preserving(raw_reply, {
      max_input_bytes: response_max,
      max_nodes: 128,
      max_depth: 8,
    })
    is Err(_) {
    stop("ResolutionUnknown")
  }
  let reply = @json.parse(reply_text) catch { _ => stop("ResolutionUnknown") }
  guard reply is Object(reply_fields) &&
    reply_fields.length() == 1 &&
    reply_fields.get("results") is Some(Array([result])) &&
    wire_resolve_result_shape(result) &&
    result is Object(result_fields) &&
    json_text(result_fields, "checkpointCid") == Some(checkpoint_cid) else {
    stop("ResolutionUnknown")
  }
  match json_text(result_fields, "status") {
    Some("committed") | Some("duplicate") =>
      if json_text(result_fields, "resolutionCid") != Some(resolution_cid) ||
        json_text(result_fields, "decision") != Some(decision) {
        stop("ResolutionUnknown")
      }
    _ =>
      // Typed refusals are not approvals and must carry an explicit reason.
      if json_text(result_fields, "reason") is None {
        stop("ResolutionUnknown")
      }
  }
}
