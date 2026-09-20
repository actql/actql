///|
struct DurableRemoteTransferStoreUseRecord {
  store_use : RemoteTransferStoreUse
  state : Array[String]
  body : String
}

///|
priv suberror DurableStoreUseStop {
  DurableStoreUseStop
}

///|
fn[T] durable_store_use_decoded(
  value : Result[T, @decode.Issue],
) -> T raise DurableStoreUseStop {
  match value {
    Ok(result) => result
    Err(_) => raise DurableStoreUseStop
  }
}

///|
fn durable_store_use_text(
  object : @decode.ObjectView,
  key : String,
) -> String raise DurableStoreUseStop {
  durable_store_use_decoded(
    @decode.text(durable_store_use_decoded(@decode.required(object, key))),
  )
}

///|
fn durable_store_use_int64(
  object : @decode.ObjectView,
  key : String,
) -> Int64 raise DurableStoreUseStop {
  durable_store_use_decoded(
    @decode.safe_integer(
      durable_store_use_decoded(@decode.required(object, key)),
    ),
  )
}

///|
fn durable_store_use_int(
  object : @decode.ObjectView,
  key : String,
) -> Int raise DurableStoreUseStop {
  let value = durable_store_use_int64(object, key)
  if value < 0L || value > 2147483647L {
    raise DurableStoreUseStop
  }
  value.to_int()
}

///|
fn durable_store_use_bool(
  object : @decode.ObjectView,
  key : String,
) -> Bool raise DurableStoreUseStop {
  durable_store_use_decoded(
    @decode.boolean(durable_store_use_decoded(@decode.required(object, key))),
  )
}

///|
fn durable_store_use_limit(manifest_bytes : Int) -> Int? {
  if manifest_bytes < 0 {
    return None
  }
  let limit = manifest_bytes.to_int64() * 6L + 131072L
  if limit > 2147483647L {
    None
  } else {
    Some(limit.to_int())
  }
}

///|
fn emit_durable_store_use_record(
  store_use : RemoteTransferStoreUse,
  state : Array[String],
) -> Result[String, RemoteTransferIssue] {
  if state.length() != 7 {
    return Err(InvalidTransfer)
  }
  let revision : Int = @string.from_str(state[0]) catch {
    _ => return Err(InvalidTransfer)
  }
  let attempt_state : Int = @string.from_str(state[1]) catch {
    _ => return Err(InvalidTransfer)
  }
  let cleanup_state : Int = @string.from_str(state[2]) catch {
    _ => return Err(InvalidTransfer)
  }
  let confirmed_chunks : Int = @string.from_str(state[3]) catch {
    _ => return Err(InvalidTransfer)
  }
  let confirmed_bytes : Int64 = @string.from_str(state[4]) catch {
    _ => return Err(InvalidTransfer)
  }
  let reader_stopped = match state[5] {
    "0" => false
    "1" => true
    _ => return Err(InvalidTransfer)
  }
  if restore_store_use_record(
      store_use,
      revision,
      attempt_state,
      cleanup_state,
      confirmed_chunks,
      confirmed_bytes,
      reader_stopped,
      state[6],
    )
    is Err(_) {
    return Err(InvalidTransfer)
  }
  let request = store_use.request
  let request_body = match request_json(request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let manifest_body = match request_manifest_json(request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard durable_store_use_limit(manifest_body.length()) is Some(limit) else {
    return Err(InvalidTransfer)
  }
  let writer = @encode.writer(limit, 40, 2) catch {
    _ => return Err(InvalidTransfer)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "attempt_state")
    @encode.number_value(writer, attempt_state.to_double())
    @encode.key(writer, "cleanup_state")
    @encode.number_value(writer, cleanup_state.to_double())
    @encode.key(writer, "confirmed_bytes")
    @encode.number_value(writer, confirmed_bytes.to_double())
    @encode.key(writer, "confirmed_chunks")
    @encode.number_value(writer, confirmed_chunks.to_double())
    @encode.key(writer, "destination_receipt_cid")
    @encode.string_value(writer, state[6])
    @encode.key(writer, "physical_manifest_cid")
    @encode.string_value(writer, request.physical_manifest_cid)
    @encode.key(writer, "physical_manifest_json")
    @encode.string_value(writer, manifest_body)
    @encode.key(writer, "reader_stopped")
    @encode.bool_value(writer, reader_stopped)
    @encode.key(writer, "request_cid")
    @encode.string_value(writer, request.request_cid)
    @encode.key(writer, "request_json")
    @encode.string_value(writer, request_body)
    @encode.key(writer, "revision")
    @encode.number_value(writer, revision.to_double())
    @encode.key(writer, "use_cid")
    @encode.string_value(writer, store_use.use_cid)
    @encode.key(writer, "use_id")
    @encode.string_value(writer, store_use.use_id)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-remote-transfer-store-use-record/0.1")
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(InvalidTransfer)
  }
}

///|
pub fn remote_transfer_store_use_record_durable_json(
  record : RemoteTransferStoreUseRecord,
) -> Result[String, RemoteTransferIssue] {
  emit_durable_store_use_record(
    record.store_use,
    store_use_state_projection(record),
  )
}

///|
pub fn remote_transfer_store_use_transition_durable_json(
  transition : RemoteTransferStoreUseTransition,
) -> Result[String, RemoteTransferIssue] {
  if transition.consumed ||
    transition.expected != store_use_state_projection(transition.record) {
    return Err(InvalidTransfer)
  }
  emit_durable_store_use_record(
    transition.record.store_use,
    transition.next.copy(),
  )
}

///|
pub fn remote_transfer_store_use_transition_expected_revision(
  transition : RemoteTransferStoreUseTransition,
) -> Int {
  @string.from_str(transition.expected[0]) catch {
    _ => -1
  }
}

///|
pub fn remote_transfer_store_use_transition_journal_identity(
  transition : RemoteTransferStoreUseTransition,
) -> String {
  transition.record.store_use.use_cid
}

///|
pub fn admit_durable_remote_transfer_store_use_record(
  bytes : Bytes,
  max_chunks : Int,
  max_manifest_bytes : Int,
  max_referenced_bytes : Int64,
) -> Result[DurableRemoteTransferStoreUseRecord, RemoteTransferIssue] {
  guard durable_store_use_limit(max_manifest_bytes) is Some(limit) else {
    return Err(InvalidTransfer)
  }
  try {
    let node = match
      @source.parse_json_bytes(bytes, {
        max_input_bytes: limit,
        max_nodes: 40,
        max_depth: 2,
      }) {
      Ok(value) => value
      Err(_) => raise DurableStoreUseStop
    }
    let cursor = durable_store_use_decoded(
      @decode.admit(node, {
        max_nodes: 40,
        max_depth: 2,
        max_string_bytes: limit,
        max_total_string_bytes: limit,
      }),
    )
    let object = durable_store_use_decoded(
      @decode.closed_object(cursor, [
        "attempt_state", "cleanup_state", "confirmed_bytes", "confirmed_chunks",
        "destination_receipt_cid", "physical_manifest_cid", "physical_manifest_json",
        "reader_stopped", "request_cid", "request_json", "revision", "use_cid", "use_id",
        "version",
      ]),
    )
    if durable_store_use_text(object, "version") !=
      "actql-remote-transfer-store-use-record/0.1" {
      raise DurableStoreUseStop
    }
    let request = match
      admit_request_json(
        durable_store_use_text(object, "request_json"),
        durable_store_use_text(object, "physical_manifest_json"),
        durable_store_use_text(object, "request_cid"),
        durable_store_use_text(object, "physical_manifest_cid"),
        max_chunks,
        max_manifest_bytes,
        max_referenced_bytes,
      ) {
      Ok(value) => value
      Err(_) => raise DurableStoreUseStop
    }
    let use_id = durable_store_use_text(object, "use_id")
    let store_use = match prepare_store_use(request, use_id) {
      Ok(value) => value
      Err(_) => raise DurableStoreUseStop
    }
    if store_use.use_cid != durable_store_use_text(object, "use_cid") {
      raise DurableStoreUseStop
    }
    let state = [
      durable_store_use_int(object, "revision").to_string(),
      durable_store_use_int(object, "attempt_state").to_string(),
      durable_store_use_int(object, "cleanup_state").to_string(),
      durable_store_use_int(object, "confirmed_chunks").to_string(),
      durable_store_use_int64(object, "confirmed_bytes").to_string(),
      if durable_store_use_bool(object, "reader_stopped") {
        "1"
      } else {
        "0"
      },
      durable_store_use_text(object, "destination_receipt_cid"),
    ]
    let body = @utf8.decode(bytes) catch { _ => raise DurableStoreUseStop }
    if emit_durable_store_use_record(store_use, state.copy()) != Ok(body) {
      raise DurableStoreUseStop
    }
    Ok({ store_use, state, body, })
  } catch {
    DurableStoreUseStop => Err(InvalidTransfer)
  }
}

///|
pub fn restore_durable_remote_transfer_store_use_record(
  durable : DurableRemoteTransferStoreUseRecord,
) -> Result[RemoteTransferStoreUseRecord, RemoteTransferIssue] {
  let revision : Int = @string.from_str(durable.state[0]) catch {
    _ => return Err(InvalidTransfer)
  }
  let attempt_state : Int = @string.from_str(durable.state[1]) catch {
    _ => return Err(InvalidTransfer)
  }
  let cleanup_state : Int = @string.from_str(durable.state[2]) catch {
    _ => return Err(InvalidTransfer)
  }
  let confirmed_chunks : Int = @string.from_str(durable.state[3]) catch {
    _ => return Err(InvalidTransfer)
  }
  let confirmed_bytes : Int64 = @string.from_str(durable.state[4]) catch {
    _ => return Err(InvalidTransfer)
  }
  let record = match
    restore_store_use_record(
      durable.store_use,
      revision,
      attempt_state,
      cleanup_state,
      confirmed_chunks,
      confirmed_bytes,
      durable.state[5] == "1",
      durable.state[6],
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if remote_transfer_store_use_record_durable_json(record) == Ok(durable.body) {
    Ok(record)
  } else {
    Err(InvalidTransfer)
  }
}

///|
pub fn durable_remote_transfer_store_use_revision(
  durable : DurableRemoteTransferStoreUseRecord,
) -> Int {
  @string.from_str(durable.state[0]) catch {
    _ => -1
  }
}

///|
pub fn durable_remote_transfer_store_use_identity(
  durable : DurableRemoteTransferStoreUseRecord,
) -> String {
  durable.store_use.use_cid
}

///|
pub fn durable_remote_transfer_store_use_json(
  durable : DurableRemoteTransferStoreUseRecord,
) -> String {
  durable.body
}
