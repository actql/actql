///|
/// Admitted durable body for one common Remote Transfer record.
struct DurableRemoteTransferRecord {
  request : RemoteTransferRequest
  state : Array[Int]
  body : String
}

///|
priv suberror DurableRemoteTransferStop {
  DurableRemoteTransferStop
}

///|
fn[T] durable_transfer_decoded(
  value : Result[T, @decode.Issue],
) -> T raise DurableRemoteTransferStop {
  match value {
    Ok(result) => result
    Err(_) => raise DurableRemoteTransferStop
  }
}

///|
fn durable_transfer_text(
  object : @decode.ObjectView,
  key : String,
) -> String raise DurableRemoteTransferStop {
  durable_transfer_decoded(
    @decode.text(durable_transfer_decoded(@decode.required(object, key))),
  )
}

///|
fn durable_transfer_int(
  object : @decode.ObjectView,
  key : String,
) -> Int raise DurableRemoteTransferStop {
  let value = durable_transfer_decoded(
    @decode.safe_integer(
      durable_transfer_decoded(@decode.required(object, key)),
    ),
  )
  if value < 0L || value > 2147483647L {
    raise DurableRemoteTransferStop
  }
  value.to_int()
}

///|
fn durable_transfer_bool(
  object : @decode.ObjectView,
  key : String,
) -> Bool raise DurableRemoteTransferStop {
  durable_transfer_decoded(
    @decode.boolean(durable_transfer_decoded(@decode.required(object, key))),
  )
}

///|
fn durable_transfer_record_limit(
  manifest_bytes : Int,
) -> Result[Int, RemoteTransferIssue] {
  if manifest_bytes < 0 {
    return Err(InvalidTransfer)
  }
  let limit = manifest_bytes.to_int64() * 6L + 131072L
  if limit > 2147483647L {
    return Err(InvalidTransfer)
  }
  Ok(limit.to_int())
}

///|
fn emit_durable_remote_transfer_record(
  request : RemoteTransferRequest,
  state : Array[Int],
) -> Result[String, RemoteTransferIssue] {
  if state.length() != 9 || restore_record(request, state.copy()) is Err(_) {
    return Err(InvalidTransfer)
  }
  let request_body = match request_json(request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let manifest_body = match request_manifest_json(request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let max_output_bytes = match
    durable_transfer_record_limit(manifest_body.length()) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let writer = @encode.writer(max_output_bytes, 32, 2) catch {
    _ => return Err(InvalidTransfer)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "attempt_state")
    @encode.number_value(writer, state[1].to_double())
    @encode.key(writer, "cleanup_state")
    @encode.number_value(writer, state[4].to_double())
    @encode.key(writer, "destination_material_available")
    @encode.bool_value(writer, state[8] == 1)
    @encode.key(writer, "destination_temporary_reclaimed")
    @encode.bool_value(writer, state[6] == 1)
    @encode.key(writer, "integrity_state")
    @encode.number_value(writer, state[3].to_double())
    @encode.key(writer, "object_state")
    @encode.number_value(writer, state[2].to_double())
    @encode.key(writer, "object_use_released")
    @encode.bool_value(writer, state[7] == 1)
    @encode.key(writer, "physical_manifest_cid")
    @encode.string_value(writer, request.physical_manifest_cid)
    @encode.key(writer, "physical_manifest_json")
    @encode.string_value(writer, manifest_body)
    @encode.key(writer, "request_cid")
    @encode.string_value(writer, request.request_cid)
    @encode.key(writer, "request_json")
    @encode.string_value(writer, request_body)
    @encode.key(writer, "revision")
    @encode.number_value(writer, state[0].to_double())
    @encode.key(writer, "source_access_stopped")
    @encode.bool_value(writer, state[5] == 1)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-remote-transfer-record/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(InvalidTransfer)
  }
  Ok(@encode.finish(writer) catch { _ => return Err(InvalidTransfer) })
}

///|
pub fn remote_transfer_record_durable_json(
  record : RemoteTransferRecord,
) -> Result[String, RemoteTransferIssue] {
  emit_durable_remote_transfer_record(
    record.request,
    record_state_projection(record),
  )
}

///|
pub fn remote_transfer_transition_durable_json(
  transition : RemoteTransferTransition,
) -> Result[String, RemoteTransferIssue] {
  if transition.consumed || !transition_matches_record(transition) {
    return Err(InvalidTransfer)
  }
  emit_durable_remote_transfer_record(
    transition.record.request,
    transition.next.copy(),
  )
}

///|
pub fn remote_transfer_transition_expected_revision(
  transition : RemoteTransferTransition,
) -> Int {
  transition.expected[0]
}

///|
pub fn remote_transfer_transition_request_identity(
  transition : RemoteTransferTransition,
) -> String {
  transition.record.request.request_cid
}

///|
pub fn remote_transfer_transition_journal_identity(
  transition : RemoteTransferTransition,
) -> Result[String, RemoteTransferIssue] {
  request_journal_identity(transition.record.request)
}

///|
pub fn admit_durable_remote_transfer_record(
  bytes : Bytes,
  max_chunks : Int,
  max_manifest_bytes : Int,
  max_referenced_bytes : Int64,
) -> Result[DurableRemoteTransferRecord, RemoteTransferIssue] {
  let max_input_bytes = match
    durable_transfer_record_limit(max_manifest_bytes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  try {
    let node = match
      @source.parse_json_bytes(bytes, {
        max_input_bytes,
        max_nodes: 32,
        max_depth: 2,
      }) {
      Ok(value) => value
      Err(_) => raise DurableRemoteTransferStop
    }
    let cursor = durable_transfer_decoded(
      @decode.admit(node, {
        max_nodes: 32,
        max_depth: 2,
        max_string_bytes: max_input_bytes,
        max_total_string_bytes: max_input_bytes,
      }),
    )
    let object = durable_transfer_decoded(
      @decode.closed_object(cursor, [
        "attempt_state", "cleanup_state", "destination_material_available", "destination_temporary_reclaimed",
        "integrity_state", "object_state", "object_use_released", "physical_manifest_cid",
        "physical_manifest_json", "request_cid", "request_json", "revision", "source_access_stopped",
        "version",
      ]),
    )
    if durable_transfer_text(object, "version") !=
      "actql-remote-transfer-record/0.1" {
      raise DurableRemoteTransferStop
    }
    let request = match
      admit_request_json(
        durable_transfer_text(object, "request_json"),
        durable_transfer_text(object, "physical_manifest_json"),
        durable_transfer_text(object, "request_cid"),
        durable_transfer_text(object, "physical_manifest_cid"),
        max_chunks,
        max_manifest_bytes,
        max_referenced_bytes,
      ) {
      Ok(value) => value
      Err(_) => raise DurableRemoteTransferStop
    }
    let state = [
      durable_transfer_int(object, "revision"),
      durable_transfer_int(object, "attempt_state"),
      durable_transfer_int(object, "object_state"),
      durable_transfer_int(object, "integrity_state"),
      durable_transfer_int(object, "cleanup_state"),
      if durable_transfer_bool(object, "source_access_stopped") {
        1
      } else {
        0
      },
      if durable_transfer_bool(object, "destination_temporary_reclaimed") {
        1
      } else {
        0
      },
      if durable_transfer_bool(object, "object_use_released") {
        1
      } else {
        0
      },
      if durable_transfer_bool(object, "destination_material_available") {
        1
      } else {
        0
      },
    ]
    if restore_record(request, state.copy()) is Err(_) {
      raise DurableRemoteTransferStop
    }
    let body = @utf8.decode(bytes) catch {
      _ => raise DurableRemoteTransferStop
    }
    let canonical = match emit_durable_remote_transfer_record(request, state) {
      Ok(value) => value
      Err(_) => raise DurableRemoteTransferStop
    }
    if body != canonical {
      raise DurableRemoteTransferStop
    }
    Ok({ request, state, body, })
  } catch {
    DurableRemoteTransferStop => Err(InvalidTransfer)
  }
}

///|
pub fn restore_durable_remote_transfer_record(
  durable : DurableRemoteTransferRecord,
) -> Result[RemoteTransferRecord, RemoteTransferIssue] {
  let record = match restore_record(durable.request, durable.state.copy()) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if remote_transfer_record_durable_json(record) == Ok(durable.body) {
    Ok(record)
  } else {
    Err(InvalidTransfer)
  }
}

///|
pub fn durable_remote_transfer_record_revision(
  durable : DurableRemoteTransferRecord,
) -> Int {
  durable.state[0]
}

///|
pub fn durable_remote_transfer_record_request_identity(
  durable : DurableRemoteTransferRecord,
) -> String {
  durable.request.request_cid
}

///|
pub fn durable_remote_transfer_record_journal_identity(
  durable : DurableRemoteTransferRecord,
) -> Result[String, RemoteTransferIssue] {
  request_journal_identity(durable.request)
}

///|
pub fn durable_remote_transfer_record_json(
  durable : DurableRemoteTransferRecord,
) -> String {
  durable.body
}
