///|
priv suberror RemoteTransferWireStop {
  RemoteTransferWireStop
}

///|
fn[T] transfer_wire_decoded(
  value : Result[T, @decode.Issue],
) -> T raise RemoteTransferWireStop {
  match value {
    Ok(result) => result
    Err(_) => raise RemoteTransferWireStop
  }
}

///|
fn transfer_wire_root(
  body : String,
  max_input_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> @decode.Cursor raise RemoteTransferWireStop {
  let bytes = @utf8.encode(body)
  let node = match
    @source.parse_json_bytes(bytes, { max_input_bytes, max_nodes, max_depth, }) {
    Ok(value) => value
    Err(_) => raise RemoteTransferWireStop
  }
  transfer_wire_decoded(
    @decode.admit(node, {
      max_nodes,
      max_depth,
      max_string_bytes: max_input_bytes,
      max_total_string_bytes: max_input_bytes,
    }),
  )
}

///|
fn transfer_wire_text(
  object : @decode.ObjectView,
  name : String,
) -> String raise RemoteTransferWireStop {
  transfer_wire_decoded(
    @decode.text(transfer_wire_decoded(@decode.required(object, name))),
  )
}

///|
fn transfer_wire_limit(max_manifest_bytes : Int) -> Int? {
  if max_manifest_bytes < 0 {
    return None
  }
  let limit = max_manifest_bytes.to_int64() * 6L + 32768L
  if limit > 2147483647L {
    None
  } else {
    Some(limit.to_int())
  }
}

///|
pub fn transfer_admission_envelope_json(
  request : RemoteTransferRequest,
) -> Result[String, RemoteTransferIssue] {
  let request_body = match request_json(request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let manifest_body = match request_manifest_json(request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let max_output_bytes = match transfer_wire_limit(manifest_body.length()) {
    Some(value) => value
    None => return Err(InvalidTransfer)
  }
  let writer = @encode.writer(max_output_bytes, 4, 2) catch {
    _ => return Err(InvalidTransfer)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "manifest")
    @encode.string_value(writer, manifest_body)
    @encode.key(writer, "request")
    @encode.string_value(writer, request_body)
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(InvalidTransfer)
  }
}

///|
pub fn admit_transfer_admission_envelope_json(
  body : String,
  claimed_request_cid : String,
  claimed_manifest_cid : String,
  max_chunks : Int,
  max_manifest_bytes : Int,
  max_referenced_bytes : Int64,
) -> Result[RemoteTransferRequest, RemoteTransferIssue] {
  let max_input_bytes = match transfer_wire_limit(max_manifest_bytes) {
    Some(value) => value
    None => return Err(InvalidTransfer)
  }
  try {
    let object = transfer_wire_decoded(
      @decode.closed_object(transfer_wire_root(body, max_input_bytes, 4, 2), [
        "manifest", "request",
      ]),
    )
    let request = match
      admit_request_json(
        transfer_wire_text(object, "request"),
        transfer_wire_text(object, "manifest"),
        claimed_request_cid,
        claimed_manifest_cid,
        max_chunks,
        max_manifest_bytes,
        max_referenced_bytes,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if transfer_admission_envelope_json(request) == Ok(body) {
      Ok(request)
    } else {
      Err(InvalidTransfer)
    }
  } catch {
    RemoteTransferWireStop => Err(InvalidTransfer)
  }
}

///|
pub fn remote_transfer_reply_json(
  record : RemoteTransferRecord,
) -> Result[String, RemoteTransferIssue] {
  let state = record_projection(record)
  if restore_record(record.request, state.copy()) is Err(_) {
    return Err(InvalidTransfer)
  }
  let writer = @encode.writer(4096, 16, 3) catch {
    _ => return Err(InvalidTransfer)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "requestCid")
    @encode.string_value(writer, request_cid(record.request))
    @encode.key(writer, "state")
    @encode.begin_array(writer)
    for value in state {
      @encode.number_value(writer, value.to_double())
    }
    @encode.end_array(writer)
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(InvalidTransfer)
  }
}

///|
pub fn admit_remote_transfer_reply_json(
  body : String,
  request : RemoteTransferRequest,
) -> Result[RemoteTransferRecord, RemoteTransferIssue] {
  try {
    let object = transfer_wire_decoded(
      @decode.closed_object(transfer_wire_root(body, 4096, 16, 3), [
        "requestCid", "state",
      ]),
    )
    if transfer_wire_text(object, "requestCid") != request_cid(request) {
      return Err(TransferIdentityMismatch)
    }
    let elements = transfer_wire_decoded(
      @decode.elements(transfer_wire_decoded(@decode.required(object, "state"))),
    )
    if elements.length() != 9 {
      return Err(InvalidTransfer)
    }
    let state : Array[Int] = []
    for element in elements {
      let value = transfer_wire_decoded(@decode.safe_integer(element))
      if value < 0L || value > 2147483647L {
        raise RemoteTransferWireStop
      }
      state.push(value.to_int())
    }
    let record = match restore_record(request, state) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if remote_transfer_reply_json(record) == Ok(body) {
      Ok(record)
    } else {
      Err(InvalidTransfer)
    }
  } catch {
    RemoteTransferWireStop => Err(InvalidTransfer)
  }
}
