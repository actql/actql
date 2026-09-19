///|
pub(all) enum RemoteTransferStoreUseState {
  StoreUseAdmitted
  StoreUseReading
  StoreUseCompleted
  StoreUseFailed
  StoreUseUnknown
} derive(Eq, Debug)

///|
pub(all) enum RemoteTransferStoreUseCleanupState {
  StoreUseCleanupActive
  StoreUseCleanupReleased
  StoreUseCleanupUnknown
} derive(Eq, Debug)

///|
struct RemoteTransferStoreUse {
  request : RemoteTransferRequest
  use_id : String
  use_cid : String
}

///|
struct RemoteTransferStoreUseRecord {
  store_use : RemoteTransferStoreUse
  mut revision : Int
  mut state : RemoteTransferStoreUseState
  mut cleanup : RemoteTransferStoreUseCleanupState
  mut confirmed_chunks : Int
  mut confirmed_bytes : Int64
  mut reader_stopped : Bool
  mut destination_receipt_cid : String
}

///|
struct RemoteTransferStoreUseTransition {
  record : RemoteTransferStoreUseRecord
  expected : Array[String]
  next : Array[String]
  state : RemoteTransferStoreUseState
  cleanup : RemoteTransferStoreUseCleanupState
  confirmed_chunks : Int
  confirmed_bytes : Int64
  reader_stopped : Bool
  destination_receipt_cid : String
  mut consumed : Bool
}

///|
fn store_use_state_code(value : RemoteTransferStoreUseState) -> Int {
  match value {
    StoreUseAdmitted => 0
    StoreUseReading => 1
    StoreUseCompleted => 2
    StoreUseFailed => 3
    StoreUseUnknown => 4
  }
}

///|
fn store_use_cleanup_code(value : RemoteTransferStoreUseCleanupState) -> Int {
  match value {
    StoreUseCleanupActive => 0
    StoreUseCleanupReleased => 1
    StoreUseCleanupUnknown => 2
  }
}

///|
fn store_use_body(
  store_use : RemoteTransferStoreUse,
) -> Result[String, RemoteTransferIssue] {
  let writer = @encode.writer(4096, 16, 2) catch {
    _ => return Err(InvalidTransfer)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "destination_grant_cid")
    @encode.string_value(writer, store_use.request.destination_grant_cid)
    @encode.key(writer, "destination_site_generation")
    @encode.number_value(
      writer,
      store_use.request.destination_site_generation.to_double(),
    )
    @encode.key(writer, "destination_site_key")
    @encode.string_value(writer, store_use.request.destination_site_key)
    @encode.key(writer, "request_cid")
    @encode.string_value(writer, store_use.request.request_cid)
    @encode.key(writer, "use_id")
    @encode.string_value(writer, store_use.use_id)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-remote-transfer-store-use/0.1")
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(InvalidTransfer)
  }
}

///|
fn store_use_identity(
  store_use : RemoteTransferStoreUse,
) -> Result[String, RemoteTransferIssue] {
  let body = match store_use_body(store_use) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match @sha.text_hex(body) {
    Ok(value) => Ok("sha256:" + value)
    Err(_) => Err(InvalidTransfer)
  }
}

///|
fn store_use_total_bytes(request : RemoteTransferRequest) -> Int64 {
  let mut total = 0L
  for length in request_chunk_byte_lengths(request) {
    total = total + length
  }
  total
}

///|
fn store_use_prefix_bytes(
  request : RemoteTransferRequest,
  confirmed_chunks : Int,
) -> Result[Int64, RemoteTransferIssue] {
  let lengths = request_chunk_byte_lengths(request)
  if confirmed_chunks < 0 || confirmed_chunks > lengths.length() {
    return Err(InvalidTransfer)
  }
  let mut total = 0L
  for index = 0; index < confirmed_chunks; index = index + 1 {
    total = total + lengths[index]
  }
  Ok(total)
}

///|
pub fn prepare_store_use(
  request : RemoteTransferRequest,
  use_id : String,
) -> Result[RemoteTransferStoreUse, RemoteTransferIssue] {
  if request.route != TransferStore ||
    !valid_request_fields(request) ||
    use_id.is_empty() ||
    use_id.length() > 256 {
    return Err(InvalidTransfer)
  }
  let pending : RemoteTransferStoreUse = {
    request,
    use_id,
    use_cid: "pending",
  }
  let identity = match store_use_identity(pending) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({ ..pending, use_cid: identity, })
}

///|
pub fn store_use_cid(store_use : RemoteTransferStoreUse) -> String {
  store_use.use_cid
}

///|
pub fn store_use_projection(
  store_use : RemoteTransferStoreUse,
) -> Array[String] {
  [
    store_use.use_cid,
    store_use.request.request_cid,
    store_use.use_id,
    store_use.request.destination_site_key,
    store_use.request.destination_site_generation.to_string(),
    store_use.request.destination_grant_cid,
  ]
}

///|
pub fn open_store_use(
  store_use : RemoteTransferStoreUse,
) -> RemoteTransferStoreUseRecord {
  {
    store_use,
    revision: 0,
    state: StoreUseAdmitted,
    cleanup: StoreUseCleanupActive,
    confirmed_chunks: 0,
    confirmed_bytes: 0L,
    reader_stopped: false,
    destination_receipt_cid: "",
  }
}

///|
fn store_use_state_projection(
  record : RemoteTransferStoreUseRecord,
) -> Array[String] {
  [
    record.revision.to_string(),
    store_use_state_code(record.state).to_string(),
    store_use_cleanup_code(record.cleanup).to_string(),
    record.confirmed_chunks.to_string(),
    record.confirmed_bytes.to_string(),
    if record.reader_stopped {
      "1"
    } else {
      "0"
    },
    record.destination_receipt_cid,
  ]
}

///|
fn prepare_store_use_transition(
  record : RemoteTransferStoreUseRecord,
  state : RemoteTransferStoreUseState,
  cleanup : RemoteTransferStoreUseCleanupState,
  confirmed_chunks : Int,
  confirmed_bytes : Int64,
  reader_stopped : Bool,
  destination_receipt_cid : String,
) -> RemoteTransferStoreUseTransition {
  {
    record,
    expected: store_use_state_projection(record),
    next: [
      (record.revision + 1).to_string(),
      store_use_state_code(state).to_string(),
      store_use_cleanup_code(cleanup).to_string(),
      confirmed_chunks.to_string(),
      confirmed_bytes.to_string(),
      if reader_stopped {
        "1"
      } else {
        "0"
      },
      destination_receipt_cid,
    ],
    state,
    cleanup,
    confirmed_chunks,
    confirmed_bytes,
    reader_stopped,
    destination_receipt_cid,
    consumed: false,
  }
}

///|
pub fn prepare_store_use_start(
  record : RemoteTransferStoreUseRecord,
) -> Result[RemoteTransferStoreUseTransition, RemoteTransferIssue] {
  if record.state != StoreUseAdmitted || record.cleanup != StoreUseCleanupActive {
    return Err(InvalidTransfer)
  }
  Ok(
    prepare_store_use_transition(
      record,
      StoreUseReading,
      record.cleanup,
      0,
      0L,
      false,
      "",
    ),
  )
}

///|
pub fn prepare_store_use_progress(
  record : RemoteTransferStoreUseRecord,
  confirmed_chunks : Int,
  confirmed_bytes : Int64,
) -> Result[RemoteTransferStoreUseTransition, RemoteTransferIssue] {
  let expected_bytes = match
    store_use_prefix_bytes(record.store_use.request, confirmed_chunks) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if record.state != StoreUseReading ||
    record.cleanup != StoreUseCleanupActive ||
    confirmed_chunks != record.confirmed_chunks + 1 ||
    confirmed_bytes != expected_bytes {
    return Err(InvalidTransfer)
  }
  Ok(
    prepare_store_use_transition(
      record,
      record.state,
      record.cleanup,
      confirmed_chunks,
      confirmed_bytes,
      false,
      "",
    ),
  )
}

///|
pub fn prepare_store_use_complete(
  record : RemoteTransferStoreUseRecord,
  receipt : RemoteTransferDestinationReceipt,
) -> Result[RemoteTransferStoreUseTransition, RemoteTransferIssue] {
  if record.state != StoreUseReading ||
    record.cleanup != StoreUseCleanupActive ||
    record.confirmed_chunks !=
    request_chunk_byte_lengths(record.store_use.request).length() ||
    record.confirmed_bytes != store_use_total_bytes(record.store_use.request) ||
    receipt.request_cid != record.store_use.request.request_cid ||
    receipt.destination_site_key !=
    record.store_use.request.destination_site_key ||
    receipt.destination_site_generation !=
    record.store_use.request.destination_site_generation ||
    receipt.destination_grant_cid !=
    record.store_use.request.destination_grant_cid ||
    destination_receipt_json(receipt) is Err(_) {
    return Err(InvalidTransfer)
  }
  Ok(
    prepare_store_use_transition(
      record,
      StoreUseCompleted,
      record.cleanup,
      record.confirmed_chunks,
      record.confirmed_bytes,
      true,
      receipt.receipt_cid,
    ),
  )
}

///|
pub fn prepare_store_use_failure(
  record : RemoteTransferStoreUseRecord,
  reader_stopped : Bool,
) -> Result[RemoteTransferStoreUseTransition, RemoteTransferIssue] {
  if record.state == StoreUseCompleted ||
    record.cleanup == StoreUseCleanupReleased {
    return Err(InvalidTransfer)
  }
  Ok(
    prepare_store_use_transition(
      record,
      StoreUseFailed,
      record.cleanup,
      record.confirmed_chunks,
      record.confirmed_bytes,
      record.reader_stopped || reader_stopped,
      "",
    ),
  )
}

///|
pub fn prepare_store_use_unknown(
  record : RemoteTransferStoreUseRecord,
) -> Result[RemoteTransferStoreUseTransition, RemoteTransferIssue] {
  if record.state == StoreUseCompleted ||
    record.cleanup == StoreUseCleanupReleased {
    return Err(InvalidTransfer)
  }
  Ok(
    prepare_store_use_transition(
      record,
      StoreUseUnknown,
      StoreUseCleanupUnknown,
      record.confirmed_chunks,
      record.confirmed_bytes,
      record.reader_stopped,
      "",
    ),
  )
}

///|
pub fn prepare_store_use_cleanup(
  record : RemoteTransferStoreUseRecord,
) -> Result[RemoteTransferStoreUseTransition, RemoteTransferIssue] {
  if !record.reader_stopped ||
    (record.state != StoreUseCompleted && record.state != StoreUseFailed) ||
    record.cleanup == StoreUseCleanupReleased {
    return Err(InvalidTransfer)
  }
  Ok(
    prepare_store_use_transition(
      record,
      record.state,
      StoreUseCleanupReleased,
      record.confirmed_chunks,
      record.confirmed_bytes,
      true,
      record.destination_receipt_cid,
    ),
  )
}

///|
pub fn store_use_transition_projection(
  transition : RemoteTransferStoreUseTransition,
) -> (Array[String], Array[String]) {
  (transition.expected.copy(), transition.next.copy())
}

///|
pub fn store_use_transition_journal_key(
  transition : RemoteTransferStoreUseTransition,
) -> Array[String] {
  let store_use = transition.record.store_use
  [
    store_use.use_cid,
    store_use.request.request_cid,
    store_use.request.destination_site_key,
    store_use.request.destination_site_generation.to_string(),
    store_use.use_id,
  ]
}

///|
pub fn commit_store_use_transition(
  transition : RemoteTransferStoreUseTransition,
  durable : Bool,
) -> Result[RemoteTransferStoreUseRecord, RemoteTransferIssue] {
  if transition.consumed ||
    !durable ||
    transition.expected != store_use_state_projection(transition.record) {
    return Err(InvalidTransfer)
  }
  transition.record.revision = transition.record.revision + 1
  transition.record.state = transition.state
  transition.record.cleanup = transition.cleanup
  transition.record.confirmed_chunks = transition.confirmed_chunks
  transition.record.confirmed_bytes = transition.confirmed_bytes
  transition.record.reader_stopped = transition.reader_stopped
  transition.record.destination_receipt_cid = transition.destination_receipt_cid
  transition.consumed = true
  Ok(transition.record)
}

///|
pub fn store_use_record_projection(
  record : RemoteTransferStoreUseRecord,
) -> Array[String] {
  store_use_state_projection(record)
}

///|
pub fn restore_store_use_record(
  store_use : RemoteTransferStoreUse,
  revision : Int,
  state_code : Int,
  cleanup_code : Int,
  confirmed_chunks : Int,
  confirmed_bytes : Int64,
  reader_stopped : Bool,
  destination_receipt_cid : String,
) -> Result[RemoteTransferStoreUseRecord, RemoteTransferIssue] {
  let state = match state_code {
    0 => StoreUseAdmitted
    1 => StoreUseReading
    2 => StoreUseCompleted
    3 => StoreUseFailed
    4 => StoreUseUnknown
    _ => return Err(InvalidTransfer)
  }
  let cleanup = match cleanup_code {
    0 => StoreUseCleanupActive
    1 => StoreUseCleanupReleased
    2 => StoreUseCleanupUnknown
    _ => return Err(InvalidTransfer)
  }
  let total = store_use_total_bytes(store_use.request)
  let chunk_count = request_chunk_byte_lengths(store_use.request).length()
  let prefix = match
    store_use_prefix_bytes(store_use.request, confirmed_chunks) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if revision < 0 ||
    confirmed_chunks < 0 ||
    confirmed_chunks > chunk_count ||
    confirmed_bytes < 0L ||
    confirmed_bytes > total ||
    confirmed_bytes != prefix ||
    (
      state == StoreUseAdmitted &&
      (
        revision != 0 ||
        confirmed_chunks != 0 ||
        confirmed_bytes != 0L ||
        reader_stopped ||
        cleanup != StoreUseCleanupActive
      )
    ) ||
    (
      state == StoreUseReading &&
      (reader_stopped || cleanup != StoreUseCleanupActive)
    ) ||
    (
      state == StoreUseCompleted &&
      (
        confirmed_chunks != chunk_count ||
        confirmed_bytes != total ||
        !reader_stopped ||
        cleanup == StoreUseCleanupUnknown ||
        !valid_transfer_cid(destination_receipt_cid)
      )
    ) ||
    (state != StoreUseCompleted && !destination_receipt_cid.is_empty()) ||
    (state == StoreUseUnknown && cleanup != StoreUseCleanupUnknown) ||
    (
      cleanup == StoreUseCleanupReleased &&
      (
        !reader_stopped ||
        (state != StoreUseCompleted && state != StoreUseFailed)
      )
    ) {
    return Err(InvalidTransfer)
  }
  Ok({
    store_use,
    revision,
    state,
    cleanup,
    confirmed_chunks,
    confirmed_bytes,
    reader_stopped,
    destination_receipt_cid,
  })
}
