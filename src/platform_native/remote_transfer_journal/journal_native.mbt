///|
struct Journal {
  database : @sqlite.Database
  max_chunks : Int
  max_manifest_bytes : Int
  max_referenced_bytes : Int64
  mut closed : Bool
}

///|
fn destination_allocation_key(
  request : @transfer.RemoteTransferRequest,
  use_id : String,
  index : Int,
) -> Result[String, NativeRemoteTransferJournalIssue] {
  if index < 0 {
    return Err(Protocol(@transfer.InvalidTransfer))
  }
  let store_use = match @transfer.prepare_store_use(request, use_id) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  Ok(@transfer.store_use_cid(store_use) + "-" + index.to_string())
}

///|
fn destination_allocation_body(
  staging_name : String,
  final_name : String,
  phase : NativeRemoteDestinationAllocationPhase,
) -> Bytes {
  let (code, device, inode, size) = match phase {
    DestinationAllocationIntent => ("intent", "", "", "")
    DestinationAllocationStagingOwned(value) =>
      ("owned", value.device.to_string(), value.inode.to_string(), "")
    DestinationAllocationSealed(value) =>
      (
        "sealed",
        value.device.to_string(),
        value.inode.to_string(),
        value.size.to_string(),
      )
    DestinationAllocationReused(value) =>
      (
        "reused",
        value.device.to_string(),
        value.inode.to_string(),
        value.size.to_string(),
      )
    DestinationAllocationReclaimingOwned(value) =>
      ("reclaim-owned", value.device.to_string(), value.inode.to_string(), "")
    DestinationAllocationReclaimingSealed(value) =>
      (
        "reclaim-sealed",
        value.device.to_string(),
        value.inode.to_string(),
        value.size.to_string(),
      )
    DestinationAllocationReleased => ("released", "", "", "")
  }
  @utf8.encode(
    "1\n" +
    staging_name +
    "\n" +
    final_name +
    "\n" +
    code +
    "\n" +
    device +
    "\n" +
    inode +
    "\n" +
    size,
  )
}

///|
fn parse_destination_allocation(
  key : String,
  value : @sqlite.NativeJournalValue,
) -> Result[NativeRemoteDestinationAllocation, NativeRemoteTransferJournalIssue] {
  let body = @utf8.decode(value.body) catch { _ => return Err(StateCollision) }
  let fields = body.split("\n").to_array()
  if fields.length() != 7 ||
    fields[0] != "1" ||
    fields[1].is_empty() ||
    fields[2].is_empty() {
    return Err(StateCollision)
  }
  let ownership = fn() -> Result[
    @filesystem.NativeFileOwnership,
    NativeRemoteTransferJournalIssue,
  ] {
    guard destination_allocation_u64(fields[4].to_owned()) is Some(device) else {
      return Err(StateCollision)
    }
    guard destination_allocation_u64(fields[5].to_owned()) is Some(inode) else {
      return Err(StateCollision)
    }
    Ok({ device, inode, })
  }
  let generation = fn() -> Result[
    @filesystem.NativeFileGeneration,
    NativeRemoteTransferJournalIssue,
  ] {
    let owned = match ownership() {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    guard destination_allocation_i64(fields[6].to_owned()) is Some(size) else {
      return Err(StateCollision)
    }
    if size < 0L {
      return Err(StateCollision)
    }
    Ok({ device: owned.device, inode: owned.inode, size, })
  }
  let phase = match fields[3] {
    "intent" => DestinationAllocationIntent
    "owned" =>
      match ownership() {
        Ok(value) => DestinationAllocationStagingOwned(value)
        Err(issue) => return Err(issue)
      }
    "sealed" =>
      match generation() {
        Ok(value) => DestinationAllocationSealed(value)
        Err(issue) => return Err(issue)
      }
    "reused" =>
      match generation() {
        Ok(value) => DestinationAllocationReused(value)
        Err(issue) => return Err(issue)
      }
    "reclaim-owned" =>
      match ownership() {
        Ok(value) => DestinationAllocationReclaimingOwned(value)
        Err(issue) => return Err(issue)
      }
    "reclaim-sealed" =>
      match generation() {
        Ok(value) => DestinationAllocationReclaimingSealed(value)
        Err(issue) => return Err(issue)
      }
    "released" => DestinationAllocationReleased
    _ => return Err(StateCollision)
  }
  Ok({
    key,
    staging_name: fields[1].to_owned(),
    final_name: fields[2].to_owned(),
    revision: value.revision,
    phase,
  })
}

///|
fn Journal::replace_destination_allocation(
  self : Journal,
  current : NativeRemoteDestinationAllocation,
  phase : NativeRemoteDestinationAllocationPhase,
) -> Result[NativeRemoteDestinationAllocation, NativeRemoteTransferJournalIssue] {
  let body = destination_allocation_body(
    current.staging_name,
    current.final_name,
    phase,
  )
  match
    self.database.compare_exchange(
      "remote_transfer_destination_allocation",
      current.key,
      current.revision,
      body,
    ) {
    Ok(revision) if revision == current.revision + 1L =>
      Ok({ ..current, revision, phase, })
    Ok(_) | Err(@sqlite.Collision) => Err(StateCollision)
    Err(issue) => Err(Physical(issue))
  }
}

///|
fn receipt_storage_body(
  receipt : @transfer.RemoteTransferDestinationReceipt,
) -> Result[Bytes, NativeRemoteTransferJournalIssue] {
  let body = match @transfer.destination_receipt_json(receipt) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  journal_bytes(@transfer.destination_receipt_cid(receipt) + "\n" + body) |> Ok
}

///|
fn admit_stored_receipt(
  bytes : Bytes,
  request : @transfer.RemoteTransferRequest,
) -> Result[
  @transfer.RemoteTransferDestinationReceipt,
  NativeRemoteTransferJournalIssue,
] {
  let mut separator = -1
  for index, byte in bytes {
    if byte == (10 : Byte) && separator < 0 {
      separator = index
    }
  }
  if separator <= 0 || separator + 1 >= bytes.length() {
    return Err(StateCollision)
  }
  let cid_bytes : Array[Byte] = []
  let body_bytes : Array[Byte] = []
  for index, byte in bytes {
    if index < separator {
      cid_bytes.push(byte)
    } else if index > separator {
      body_bytes.push(byte)
    }
  }
  let cid = @utf8.decode(Bytes::from_array(cid_bytes)) catch {
    _ => return Err(StateCollision)
  }
  let body = @utf8.decode(Bytes::from_array(body_bytes)) catch {
    _ => return Err(StateCollision)
  }
  match @transfer.admit_destination_receipt_json(body, request, cid) {
    Ok(value) => Ok(value)
    Err(issue) => Err(Protocol(issue))
  }
}

///|
pub fn open_journal(
  library : @sqlite.Library,
  path : String,
  max_record_bytes : Int64,
  max_chunks : Int,
  max_manifest_bytes : Int,
  max_referenced_bytes : Int64,
) -> Result[Journal, NativeRemoteTransferJournalIssue] {
  if max_record_bytes < 0L ||
    max_chunks < 0 ||
    max_manifest_bytes < 0 ||
    max_referenced_bytes < 0L {
    return Err(Protocol(@transfer.InvalidTransfer))
  }
  match library.open_database(path, max_record_bytes) {
    Ok(database) =>
      Ok({
        database,
        max_chunks,
        max_manifest_bytes,
        max_referenced_bytes,
        closed: false,
      })
    Err(issue) => Err(Physical(issue))
  }
}

///|
fn Journal::restore_value(
  self : Journal,
  value : @sqlite.NativeJournalValue,
) -> Result[@transfer.RemoteTransferRecord, NativeRemoteTransferJournalIssue] {
  let durable = match
    @transfer.admit_durable_remote_transfer_record(
      value.body,
      self.max_chunks,
      self.max_manifest_bytes,
      self.max_referenced_bytes,
    ) {
    Ok(record) => record
    Err(issue) => return Err(Protocol(issue))
  }
  if value.revision !=
    @transfer.durable_remote_transfer_record_revision(durable).to_int64() {
    return Err(StateCollision)
  }
  match @transfer.restore_durable_remote_transfer_record(durable) {
    Ok(record) => Ok(record)
    Err(issue) => Err(Protocol(issue))
  }
}

///|
fn Journal::existing(
  self : Journal,
  request : @transfer.RemoteTransferRequest,
  value : @sqlite.NativeJournalValue,
) -> Result[@transfer.RemoteTransferRecord, NativeRemoteTransferJournalIssue] {
  let record = match self.restore_value(value) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if @transfer.record_request_identity(record) == @transfer.request_cid(request) {
    Ok(record)
  } else {
    Err(StateCollision)
  }
}

///|
fn Journal::restore_store_use_value(
  self : Journal,
  value : @sqlite.NativeJournalValue,
) -> Result[
  @transfer.RemoteTransferStoreUseRecord,
  NativeRemoteTransferJournalIssue,
] {
  let durable = match
    @transfer.admit_durable_remote_transfer_store_use_record(
      value.body,
      self.max_chunks,
      self.max_manifest_bytes,
      self.max_referenced_bytes,
    ) {
    Ok(record) => record
    Err(issue) => return Err(Protocol(issue))
  }
  if value.revision !=
    @transfer.durable_remote_transfer_store_use_revision(durable).to_int64() {
    return Err(StateCollision)
  }
  match @transfer.restore_durable_remote_transfer_store_use_record(durable) {
    Ok(record) => Ok(record)
    Err(issue) => Err(Protocol(issue))
  }
}

///|
pub fn Journal::accept(
  self : Journal,
  request : @transfer.RemoteTransferRequest,
) -> Result[
  (NativeRemoteTransferAdmission, @transfer.RemoteTransferRecord),
  NativeRemoteTransferJournalIssue,
] {
  if self.closed {
    return Err(Closed)
  }
  let key = match @transfer.request_journal_identity(request) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  match self.database.read("remote_transfer", key) {
    Ok(value) =>
      match self.existing(request, value) {
        Ok(record) => Ok((ExistingTransfer, record))
        Err(issue) => Err(issue)
      }
    Err(@sqlite.NotFound) => {
      let record = @transfer.open_record(request)
      let body = match @transfer.remote_transfer_record_durable_json(record) {
        Ok(value) => journal_bytes(value)
        Err(issue) => return Err(Protocol(issue))
      }
      match self.database.begin_immediate() {
        Ok(_) => ()
        Err(issue) => return Err(Physical(issue))
      }
      match self.database.read("remote_transfer", key) {
        Ok(value) => {
          ignore(self.database.rollback())
          return match self.existing(request, value) {
            Ok(existing) => Ok((ExistingTransfer, existing))
            Err(issue) => Err(issue)
          }
        }
        Err(@sqlite.NotFound) => ()
        Err(issue) => {
          ignore(self.database.rollback())
          return Err(Physical(issue))
        }
      }
      match self.database.insert("remote_transfer", key, body) {
        Ok(0L) => ()
        Ok(_) | Err(@sqlite.Collision) => {
          ignore(self.database.rollback())
          return Err(StateCollision)
        }
        Err(issue) => {
          ignore(self.database.rollback())
          return Err(Physical(issue))
        }
      }
      match self.database.commit() {
        Ok(_) => Ok((NewTransfer, record))
        Err(issue) => {
          ignore(self.database.rollback())
          Err(Physical(issue))
        }
      }
    }
    Err(issue) => Err(Physical(issue))
  }
}

///|
pub fn Journal::require(
  self : Journal,
  request : @transfer.RemoteTransferRequest,
) -> Result[@transfer.RemoteTransferRecord, NativeRemoteTransferJournalIssue] {
  if self.closed {
    return Err(Closed)
  }
  let key = match @transfer.request_journal_identity(request) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  match self.database.read("remote_transfer", key) {
    Ok(value) => self.existing(request, value)
    Err(issue) => Err(Physical(issue))
  }
}

///|
pub fn Journal::accept_store_use(
  self : Journal,
  request : @transfer.RemoteTransferRequest,
  use_id : String,
) -> Result[
  (NativeRemoteTransferAdmission, @transfer.RemoteTransferStoreUseRecord),
  NativeRemoteTransferJournalIssue,
] {
  if self.closed {
    return Err(Closed)
  }
  let store_use = match @transfer.prepare_store_use(request, use_id) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  let key = @transfer.store_use_cid(store_use)
  match self.database.read("remote_transfer_store_use", key) {
    Ok(value) =>
      match self.restore_store_use_value(value) {
        Ok(record) => Ok((ExistingTransfer, record))
        Err(issue) => Err(issue)
      }
    Err(@sqlite.NotFound) => {
      let record = @transfer.open_store_use(store_use)
      let body = match
        @transfer.remote_transfer_store_use_record_durable_json(record) {
        Ok(value) => journal_bytes(value)
        Err(issue) => return Err(Protocol(issue))
      }
      match self.database.begin_immediate() {
        Ok(_) => ()
        Err(issue) => return Err(Physical(issue))
      }
      match self.database.read("remote_transfer_store_use", key) {
        Ok(value) => {
          ignore(self.database.rollback())
          return match self.restore_store_use_value(value) {
            Ok(existing) => Ok((ExistingTransfer, existing))
            Err(issue) => Err(issue)
          }
        }
        Err(@sqlite.NotFound) => ()
        Err(issue) => {
          ignore(self.database.rollback())
          return Err(Physical(issue))
        }
      }
      match self.database.insert("remote_transfer_store_use", key, body) {
        Ok(0L) => ()
        Ok(_) | Err(@sqlite.Collision) => {
          ignore(self.database.rollback())
          return Err(StateCollision)
        }
        Err(issue) => {
          ignore(self.database.rollback())
          return Err(Physical(issue))
        }
      }
      match self.database.commit() {
        Ok(_) => Ok((NewTransfer, record))
        Err(issue) => {
          ignore(self.database.rollback())
          Err(Physical(issue))
        }
      }
    }
    Err(issue) => Err(Physical(issue))
  }
}

///|
pub fn Journal::require_store_use(
  self : Journal,
  store_use : @transfer.RemoteTransferStoreUse,
) -> Result[
  @transfer.RemoteTransferStoreUseRecord,
  NativeRemoteTransferJournalIssue,
] {
  if self.closed {
    return Err(Closed)
  }
  match
    self.database.read(
      "remote_transfer_store_use",
      @transfer.store_use_cid(store_use),
    ) {
    Ok(value) => self.restore_store_use_value(value)
    Err(issue) => Err(Physical(issue))
  }
}

///|
pub fn Journal::reserve_destination_holding(
  self : Journal,
  request : @transfer.RemoteTransferRequest,
  max_bytes : Int64,
  max_objects : Int64,
) -> Result[Bool, NativeRemoteTransferJournalIssue] {
  if self.closed {
    return Err(Closed)
  }
  let mut bytes = 0L
  let lengths = @transfer.request_chunk_byte_lengths(request)
  for length in lengths {
    if length < 0L || bytes > 9223372036854775807L - length {
      return Err(Protocol(@transfer.InvalidTransfer))
    }
    bytes = bytes + length
  }
  match
    self.database.reserve_capacity(
      "remote_transfer_destination",
      @transfer.request_cid(request),
      bytes,
      lengths.length().to_int64(),
      max_bytes,
      max_objects,
    ) {
    Ok(value) => Ok(value)
    Err(issue) => Err(Physical(issue))
  }
}

///|
pub fn Journal::release_destination_holding(
  self : Journal,
  request : @transfer.RemoteTransferRequest,
) -> Result[Bool, NativeRemoteTransferJournalIssue] {
  if self.closed {
    return Err(Closed)
  }
  let mut bytes = 0L
  let lengths = @transfer.request_chunk_byte_lengths(request)
  for length in lengths {
    if length < 0L || bytes > 9223372036854775807L - length {
      return Err(Protocol(@transfer.InvalidTransfer))
    }
    bytes = bytes + length
  }
  match
    self.database.release_capacity(
      "remote_transfer_destination",
      @transfer.request_cid(request),
      bytes,
      lengths.length().to_int64(),
    ) {
    Ok(value) => Ok(value)
    Err(issue) => Err(Physical(issue))
  }
}

///|
pub fn Journal::destination_capacity_usage(
  self : Journal,
) -> Result[@sqlite.NativeCapacityUsage, NativeRemoteTransferJournalIssue] {
  if self.closed {
    return Err(Closed)
  }
  match self.database.capacity_usage("remote_transfer_destination") {
    Ok(value) => Ok(value)
    Err(issue) => Err(Physical(issue))
  }
}

///|
pub fn Journal::prepare_destination_allocation(
  self : Journal,
  request : @transfer.RemoteTransferRequest,
  use_id : String,
  index : Int,
  staging_name : String,
  final_name : String,
) -> Result[NativeRemoteDestinationAllocation, NativeRemoteTransferJournalIssue] {
  if self.closed || staging_name.is_empty() || final_name.is_empty() {
    return if self.closed { Err(Closed) } else { Err(StateCollision) }
  }
  let key = match destination_allocation_key(request, use_id, index) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match self.database.read("remote_transfer_destination_allocation", key) {
    Ok(value) => {
      let existing = match parse_destination_allocation(key, value) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      if existing.staging_name == staging_name &&
        existing.final_name == final_name {
        Ok(existing)
      } else {
        Err(StateCollision)
      }
    }
    Err(@sqlite.NotFound) => {
      let body = destination_allocation_body(
        staging_name,
        final_name,
        DestinationAllocationIntent,
      )
      match
        self.database.insert(
          "remote_transfer_destination_allocation", key, body,
        ) {
        Ok(revision) =>
          Ok({
            key,
            staging_name,
            final_name,
            revision,
            phase: DestinationAllocationIntent,
          })
        Err(@sqlite.Collision) => Err(StateCollision)
        Err(issue) => Err(Physical(issue))
      }
    }
    Err(issue) => Err(Physical(issue))
  }
}

///|
pub fn Journal::record_destination_allocation_owned(
  self : Journal,
  current : NativeRemoteDestinationAllocation,
  ownership : @filesystem.NativeFileOwnership,
) -> Result[NativeRemoteDestinationAllocation, NativeRemoteTransferJournalIssue] {
  if current.phase != DestinationAllocationIntent {
    return Err(StateCollision)
  }
  self.replace_destination_allocation(
    current,
    DestinationAllocationStagingOwned(ownership),
  )
}

///|
pub fn Journal::record_destination_allocation_sealed(
  self : Journal,
  current : NativeRemoteDestinationAllocation,
  generation : @filesystem.NativeFileGeneration,
) -> Result[NativeRemoteDestinationAllocation, NativeRemoteTransferJournalIssue] {
  guard current.phase is DestinationAllocationStagingOwned(ownership) else {
    return Err(StateCollision)
  }
  if generation.device != ownership.device ||
    generation.inode != ownership.inode {
    return Err(StateCollision)
  }
  self.replace_destination_allocation(
    current,
    DestinationAllocationSealed(generation),
  )
}

///|
pub fn Journal::record_destination_allocation_reused(
  self : Journal,
  current : NativeRemoteDestinationAllocation,
  generation : @filesystem.NativeFileGeneration,
) -> Result[NativeRemoteDestinationAllocation, NativeRemoteTransferJournalIssue] {
  if current.phase != DestinationAllocationIntent {
    return Err(StateCollision)
  }
  self.replace_destination_allocation(
    current,
    DestinationAllocationReused(generation),
  )
}

///|
pub fn Journal::begin_destination_allocation_reclaim(
  self : Journal,
  current : NativeRemoteDestinationAllocation,
) -> Result[NativeRemoteDestinationAllocation, NativeRemoteTransferJournalIssue] {
  match current.phase {
    DestinationAllocationStagingOwned(value) =>
      self.replace_destination_allocation(
        current,
        DestinationAllocationReclaimingOwned(value),
      )
    DestinationAllocationSealed(value) =>
      self.replace_destination_allocation(
        current,
        DestinationAllocationReclaimingSealed(value),
      )
    DestinationAllocationReclaimingOwned(_)
    | DestinationAllocationReclaimingSealed(_)
    | DestinationAllocationReleased => Ok(current)
    DestinationAllocationReused(_) =>
      self.replace_destination_allocation(
        current,
        DestinationAllocationReleased,
      )
    DestinationAllocationIntent => Err(RecoveryRequired)
  }
}

///|
pub fn Journal::release_destination_allocation_intent(
  self : Journal,
  current : NativeRemoteDestinationAllocation,
) -> Result[NativeRemoteDestinationAllocation, NativeRemoteTransferJournalIssue] {
  if current.phase != DestinationAllocationIntent {
    return Err(StateCollision)
  }
  self.replace_destination_allocation(current, DestinationAllocationReleased)
}

///|
pub fn Journal::finish_destination_allocation_reclaim(
  self : Journal,
  current : NativeRemoteDestinationAllocation,
) -> Result[NativeRemoteDestinationAllocation, NativeRemoteTransferJournalIssue] {
  match current.phase {
    DestinationAllocationReclaimingOwned(_)
    | DestinationAllocationReclaimingSealed(_) =>
      self.replace_destination_allocation(
        current,
        DestinationAllocationReleased,
      )
    DestinationAllocationReleased => Ok(current)
    _ => Err(StateCollision)
  }
}

///|
pub fn Journal::commit_destination_receipt(
  self : Journal,
  receipt : @transfer.RemoteTransferDestinationReceipt,
  request : @transfer.RemoteTransferRequest,
) -> Result[
  @transfer.RemoteTransferDestinationReceipt,
  NativeRemoteTransferJournalIssue,
] {
  if self.closed {
    return Err(Closed)
  }
  let key = match @transfer.request_journal_identity(request) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  let body = match receipt_storage_body(receipt) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match self.database.begin_immediate() {
    Ok(_) => ()
    Err(issue) => return Err(Physical(issue))
  }
  match self.database.read("remote_transfer_destination_receipt", key) {
    Ok(value) => {
      ignore(self.database.rollback())
      if value.revision != 0L || value.body != body {
        return Err(StateCollision)
      }
      admit_stored_receipt(value.body, request)
    }
    Err(@sqlite.NotFound) => {
      match
        self.database.insert("remote_transfer_destination_receipt", key, body) {
        Ok(0L) => ()
        Ok(_) | Err(@sqlite.Collision) => {
          ignore(self.database.rollback())
          return Err(StateCollision)
        }
        Err(issue) => {
          ignore(self.database.rollback())
          return Err(Physical(issue))
        }
      }
      match self.database.commit() {
        Ok(_) => admit_stored_receipt(body, request)
        Err(issue) => {
          ignore(self.database.rollback())
          Err(Physical(issue))
        }
      }
    }
    Err(issue) => {
      ignore(self.database.rollback())
      Err(Physical(issue))
    }
  }
}

///|
pub fn Journal::inspect_destination_receipt(
  self : Journal,
  request : @transfer.RemoteTransferRequest,
) -> Result[
  @transfer.RemoteTransferDestinationReceipt?,
  NativeRemoteTransferJournalIssue,
] {
  if self.closed {
    return Err(Closed)
  }
  let key = match @transfer.request_journal_identity(request) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  match self.database.read("remote_transfer_destination_receipt", key) {
    Ok(value) =>
      if value.revision == 0L {
        match admit_stored_receipt(value.body, request) {
          Ok(receipt) => Ok(Some(receipt))
          Err(issue) => Err(issue)
        }
      } else {
        Err(StateCollision)
      }
    Err(@sqlite.NotFound) => Ok(None)
    Err(issue) => Err(Physical(issue))
  }
}

///|
pub fn Journal::commit_transition(
  self : Journal,
  transition : @transfer.RemoteTransferTransition,
) -> Result[Unit, NativeRemoteTransferJournalIssue] {
  if self.closed {
    return Err(Closed)
  }
  let key = match
    @transfer.remote_transfer_transition_journal_identity(transition) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  let expected = @transfer.remote_transfer_transition_expected_revision(
    transition,
  )
  let body = match
    @transfer.remote_transfer_transition_durable_json(transition) {
    Ok(value) => journal_bytes(value)
    Err(issue) => return Err(Protocol(issue))
  }
  match self.database.begin_immediate() {
    Ok(_) => ()
    Err(issue) => return Err(Physical(issue))
  }
  let durable = match
    self.database.compare_exchange(
      "remote_transfer",
      key,
      expected.to_int64(),
      body,
    ) {
    Ok(revision) => revision == expected.to_int64() + 1L
    Err(@sqlite.Collision) =>
      match self.database.read("remote_transfer", key) {
        Ok(value) =>
          value.revision == expected.to_int64() + 1L && value.body == body
        Err(issue) => {
          ignore(self.database.rollback())
          return Err(Physical(issue))
        }
      }
    Err(issue) => {
      ignore(self.database.rollback())
      return Err(Physical(issue))
    }
  }
  if !durable {
    ignore(self.database.rollback())
    return Err(StateCollision)
  }
  match self.database.commit() {
    Ok(_) => ()
    Err(issue) => {
      ignore(self.database.rollback())
      return Err(Physical(issue))
    }
  }
  match @transfer.commit_transition(transition, true) {
    Ok(_) => Ok(())
    Err(issue) => Err(Protocol(issue))
  }
}

///|
pub fn Journal::commit_store_use_transition(
  self : Journal,
  transition : @transfer.RemoteTransferStoreUseTransition,
) -> Result[Unit, NativeRemoteTransferJournalIssue] {
  if self.closed {
    return Err(Closed)
  }
  let key = @transfer.remote_transfer_store_use_transition_journal_identity(
    transition,
  )
  let expected = @transfer.remote_transfer_store_use_transition_expected_revision(
    transition,
  )
  if expected < 0 {
    return Err(Protocol(@transfer.InvalidTransfer))
  }
  let body = match
    @transfer.remote_transfer_store_use_transition_durable_json(transition) {
    Ok(value) => journal_bytes(value)
    Err(issue) => return Err(Protocol(issue))
  }
  match self.database.begin_immediate() {
    Ok(_) => ()
    Err(issue) => return Err(Physical(issue))
  }
  let durable = match
    self.database.compare_exchange(
      "remote_transfer_store_use",
      key,
      expected.to_int64(),
      body,
    ) {
    Ok(revision) => revision == expected.to_int64() + 1L
    Err(@sqlite.Collision) =>
      match self.database.read("remote_transfer_store_use", key) {
        Ok(value) =>
          value.revision == expected.to_int64() + 1L && value.body == body
        Err(issue) => {
          ignore(self.database.rollback())
          return Err(Physical(issue))
        }
      }
    Err(issue) => {
      ignore(self.database.rollback())
      return Err(Physical(issue))
    }
  }
  if !durable {
    ignore(self.database.rollback())
    return Err(StateCollision)
  }
  match self.database.commit() {
    Ok(_) => ()
    Err(issue) => {
      ignore(self.database.rollback())
      return Err(Physical(issue))
    }
  }
  match @transfer.commit_store_use_transition(transition, true) {
    Ok(_) => Ok(())
    Err(issue) => Err(Protocol(issue))
  }
}

///|
pub fn Journal::recover_after(
  self : Journal,
  after_key : String,
) -> Result[RecoveredRemoteTransfer?, NativeRemoteTransferJournalIssue] {
  if self.closed {
    return Err(Closed)
  }
  match self.database.scan_after("remote_transfer", after_key) {
    Ok(entry) => {
      let record = match
        self.restore_value({ revision: entry.revision, body: entry.body, }) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      Ok(Some({ key: entry.key, record, }))
    }
    Err(@sqlite.NotFound) => Ok(None)
    Err(issue) => Err(Physical(issue))
  }
}

///|
pub fn Journal::close(self : Journal) -> Bool {
  if self.closed {
    return true
  }
  self.database.close()
  self.closed = true
  true
}
