///|
/// Connector-owned meaning for one standard Remote dispatch input backed by
/// an exact committed Store-route Transfer destination.
struct NativeRemoteStandardTransferInput {
  binding : @remote.RemoteInputBinding
  request : @transfer.RemoteTransferRequest
  destination_use_id : String
  destination_receipt_cid : String
}

///|
pub(all) enum NativeRemoteStandardTransferInputIssue {
  InvalidInput
  Limit
  Transfer(@transfer.RemoteTransferIssue)
}

///|
fn standard_transfer_input_body(
  request : @transfer.RemoteTransferRequest,
  destination_use_id : String,
  destination_receipt_cid : String,
) -> Result[String, NativeRemoteStandardTransferInputIssue] {
  if destination_use_id.is_empty() || destination_receipt_cid.is_empty() {
    return Err(InvalidInput)
  }
  let request_json = match @transfer.request_json(request) {
    Ok(value) => value
    Err(issue) => return Err(Transfer(issue))
  }
  let manifest_json = match @transfer.request_manifest_json(request) {
    Ok(value) => value
    Err(issue) => return Err(Transfer(issue))
  }
  let projection = @transfer.request_projection(request)
  let writer = @encode.writer(131072, 16, 2) catch { _ => return Err(Limit) }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "destination_receipt_cid")
    @encode.string_value(writer, destination_receipt_cid)
    @encode.key(writer, "destination_use_id")
    @encode.string_value(writer, destination_use_id)
    @encode.key(writer, "manifest_cid")
    @encode.string_value(writer, projection[7])
    @encode.key(writer, "manifest_json")
    @encode.string_value(writer, manifest_json)
    @encode.key(writer, "request_cid")
    @encode.string_value(writer, @transfer.request_cid(request))
    @encode.key(writer, "request_json")
    @encode.string_value(writer, request_json)
    @encode.key(writer, "version")
    @encode.string_value(
      writer, "actql-native-remote-standard-transfer-input/0.1",
    )
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(Limit)
  }
}

///|
pub fn prepare_native_remote_standard_transfer_input(
  request : @transfer.RemoteTransferRequest,
  destination_use_id : String,
  destination_receipt_cid : String,
  max_binding_bytes : Int,
) -> Result[
  NativeRemoteStandardTransferInput,
  NativeRemoteStandardTransferInputIssue,
] {
  let body = match
    standard_transfer_input_body(
      request, destination_use_id, destination_receipt_cid,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let binding = match
    @remote.prepare_remote_input_binding(body, max_binding_bytes) {
    Ok(value) => value
    Err(_) => return Err(Limit)
  }
  Ok({ binding, request, destination_use_id, destination_receipt_cid, })
}

///|
fn standard_transfer_input_text(
  object : @decode.ObjectView,
  key : String,
) -> String? {
  guard @decode.required(object, key) is Ok(cursor) else { return None }
  guard @decode.text(cursor) is Ok(value) else { return None }
  Some(value)
}

///|
pub fn admit_native_remote_standard_transfer_input(
  binding : @remote.RemoteInputBinding,
  max_binding_bytes : Int,
  max_chunks : Int,
  max_manifest_bytes : Int,
  max_referenced_bytes : Int64,
) -> Result[
  NativeRemoteStandardTransferInput,
  NativeRemoteStandardTransferInputIssue,
] {
  let body = @remote.remote_input_binding_body(binding)
  let bytes = @utf8.encode(body)
  if max_binding_bytes < 0 || bytes.length() > max_binding_bytes {
    return Err(Limit)
  }
  let node = match
    @source.parse_json_bytes(bytes, {
      max_input_bytes: max_binding_bytes,
      max_nodes: 16,
      max_depth: 2,
    }) {
    Ok(value) => value
    Err(_) => return Err(InvalidInput)
  }
  let cursor = match
    @decode.admit(node, {
      max_nodes: 16,
      max_depth: 2,
      max_string_bytes: max_binding_bytes,
      max_total_string_bytes: max_binding_bytes,
    }) {
    Ok(value) => value
    Err(_) => return Err(InvalidInput)
  }
  let object = match
    @decode.closed_object(cursor, [
      "destination_receipt_cid", "destination_use_id", "manifest_cid", "manifest_json",
      "request_cid", "request_json", "version",
    ]) {
    Ok(value) => value
    Err(_) => return Err(InvalidInput)
  }
  guard standard_transfer_input_text(object, "version") is Some(version) &&
    version == "actql-native-remote-standard-transfer-input/0.1" &&
    standard_transfer_input_text(object, "request_cid") is Some(request_cid) &&
    standard_transfer_input_text(object, "manifest_cid") is Some(manifest_cid) &&
    standard_transfer_input_text(object, "request_json") is Some(request_json) &&
    standard_transfer_input_text(object, "manifest_json") is Some(manifest_json) &&
    standard_transfer_input_text(object, "destination_use_id")
    is Some(destination_use_id) &&
    standard_transfer_input_text(object, "destination_receipt_cid")
    is Some(destination_receipt_cid) else {
    return Err(InvalidInput)
  }
  let request = match
    @transfer.admit_request_json(
      request_json, manifest_json, request_cid, manifest_cid, max_chunks, max_manifest_bytes,
      max_referenced_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Transfer(issue))
  }
  let admitted = match
    prepare_native_remote_standard_transfer_input(
      request, destination_use_id, destination_receipt_cid, max_binding_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if @remote.remote_input_binding_cid(admitted.binding) !=
    @remote.remote_input_binding_cid(binding) ||
    @remote.remote_input_binding_body(admitted.binding) != body {
    return Err(InvalidInput)
  }
  Ok(admitted)
}

///|
pub fn native_remote_standard_transfer_binding(
  input : NativeRemoteStandardTransferInput,
) -> @remote.RemoteInputBinding {
  input.binding
}

///|
pub fn native_remote_standard_transfer_request(
  input : NativeRemoteStandardTransferInput,
) -> @transfer.RemoteTransferRequest {
  input.request
}

///|
pub fn native_remote_standard_transfer_destination_use_id(
  input : NativeRemoteStandardTransferInput,
) -> String {
  input.destination_use_id
}

///|
pub fn native_remote_standard_transfer_destination_receipt_cid(
  input : NativeRemoteStandardTransferInput,
) -> String {
  input.destination_receipt_cid
}
