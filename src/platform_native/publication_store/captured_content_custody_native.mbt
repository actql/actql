///|
// Physical child custody of the EXISTING Store. Common keeps the original
// Run/keyed request/ContentRef. No separate Root, Ledger or permission exists.
struct CapturedContentCustody {
  store : Store
  original : @publication.CapturedContentReference
  holding : String
  key : String
  staging : String
  name : String
  wire : String
  digest : String
  bytes : Int64
  intent : Bytes
  retired_record : Bytes
  mut registered : Bool
  mut attempted : Bool
  mut intent_owned : Bool
  mut reservation_attempted : Bool
  mut committed : Bool
  mut verified : Bool
  mut closed : Bool
  mut generation : @filesystem.NativeFileGeneration?
  mut writer : @filesystem.Writer?
  mut failed_writer : @filesystem.NativeWriterOpenFailure?
  mut reader : @filesystem.Reader?
  mut failed_reader : @filesystem.NativeReaderOpenFailure?
}

///|
fn captured_content_record(
  holding : String,
  wire : String,
  state : String,
  generation : @filesystem.NativeFileGeneration?,
  max_bytes : Int,
) -> Result[Bytes, NativePublicationStoreIssue] {
  let fields = [
    "actql-native-captured-content-custody/0.1", holding, wire, state,
  ]
  if generation is Some(original) {
    fields.push(original.device.to_string())
    fields.push(original.inode.to_string())
    fields.push(original.size.to_string())
  }
  effect_catalog_strings(fields, max_bytes).map(value => @utf8.encode(value))
}

///|
fn captured_content_generation(
  body : Bytes,
  holding : String,
  wire : String,
  max_bytes : Int,
) -> Result[@filesystem.NativeFileGeneration, NativePublicationStoreIssue] {
  if body.length() > max_bytes {
    return Err(StateCollision)
  }
  try {
    let source = match
      @source.parse_json_bytes_preserving(body, {
        max_input_bytes: max_bytes,
        max_nodes: 8,
        max_depth: 2,
      }) {
      Ok(value) => value
      Err(_) => return Err(StateCollision)
    }
    let cursor = match
      @decode.admit(source, {
        max_nodes: 8,
        max_depth: 2,
        max_string_bytes: max_bytes,
        max_total_string_bytes: max_bytes,
      }) {
      Ok(value) => value
      Err(_) => return Err(StateCollision)
    }
    guard @decode.array_length(cursor) == Some(7) else {
      return Err(StateCollision)
    }
    let field = index => {
      @decode.element_at(cursor, index).bind(child => {
        @decode.text(child).to_option()
      })
    }
    guard field(0) == Some("actql-native-captured-content-custody/0.1") &&
      field(1) == Some(holding) &&
      field(2) == Some(wire) &&
      field(3) == Some("sealed") &&
      field(4) is Some(device) &&
      field(5) is Some(inode) &&
      field(6) is Some(size) else {
      return Err(StateCollision)
    }
    let generation : @filesystem.NativeFileGeneration = {
      device: @string.parse_uint64(device),
      inode: @string.parse_uint64(inode),
      size: @string.parse_int64(size),
    }
    // Exact canonical original record, not a permissive second wire format.
    guard captured_content_record(
        holding,
        wire,
        "sealed",
        Some(generation),
        max_bytes,
      )
      is Ok(original) &&
      original == body else {
      return Err(StateCollision)
    }
    Ok(generation)
  } catch {
    _ => Err(StateCollision)
  }
}

///|
/// Pure preparation only. Retain the returned child and its constructor
/// backing in the SAME Source owner BEFORE persist/restore can acquire I/O.
/// Store quota is disk/object custody, never funding for these live controls.
pub fn Store::prepare_captured_content_custody(
  self : Store,
  original : @publication.CapturedContentReference,
  holding : String,
) -> Result[CapturedContentCustody, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  if self.retiring {
    return Err(CleanupPending)
  }
  let (authority, _, digest, count) = @publication.captured_content_reference_storage(
    original,
  )
  guard authority == self.authority_cid &&
    count >= 0 &&
    valid_effect_custody_digest(holding) else {
    return Err(StateCollision)
  }
  let wire = @publication.captured_content_reference_wire(original)
  let intent = match
    captured_content_record(
      holding,
      wire,
      "pending",
      None,
      self.max_record_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let retired_record = match
    captured_content_record(
      holding,
      wire,
      "retired",
      None,
      self.max_record_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // The Common-issued holding CID is used only as an exclusive private name.
  // It grants no reference/read authority. Root validates the actual leaf.
  let suffix = holding.replace(old="sha256:", new="")
  Ok({
    store: self,
    original,
    holding,
    key: "captured-content:" + holding,
    staging: "captured-pending-" + suffix,
    name: "captured-content-" + suffix,
    wire,
    digest,
    bytes: count.to_int64(),
    intent,
    retired_record,
    registered: false,
    attempted: false,
    intent_owned: false,
    reservation_attempted: false,
    committed: false,
    verified: false,
    closed: false,
    generation: None,
    writer: None,
    failed_writer: None,
    reader: None,
    failed_reader: None,
  })
}

///|
fn CapturedContentCustody::register(
  self : Self,
) -> Result[Unit, NativePublicationStoreIssue] {
  if self.closed || self.attempted || self.store.closed || self.store.retiring {
    return Err(RecoveryRequired)
  }
  if self.store.active_writers.contains(self.key) {
    return Err(RecoveryRequired)
  }
  self.store.active_writers[self.key] = true
  self.registered = true
  self.attempted = true
  Ok(())
}

///|
/// One physical write for the already selected candidate. A later call cannot
/// regenerate or resend it; failed/uncertain writes keep this exact custody.
pub fn CapturedContentCustody::persist(
  self : Self,
  bytes : Bytes,
) -> Result[Unit, NativePublicationStoreIssue] {
  if bytes.length().to_int64() != self.bytes ||
    "sha256:" + @sha.hex(bytes) != self.digest {
    return Err(DigestMismatch)
  }
  match self.register() {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  self.store.with_original_read(false, false, fn() {
    self.persist_in_scope(bytes)
  })
}

///|
fn CapturedContentCustody::persist_in_scope(
  self : Self,
  bytes : Bytes,
) -> Result[Unit, NativePublicationStoreIssue] {
  match
    self.store.database.insert("captured_content", self.holding, self.intent) {
    Ok(0L) => self.intent_owned = true
    Ok(_) => return Err(StateCollision)
    Err(@sqlite.Collision) => return Err(RecoveryRequired)
    Err(issue) => return Err(Database(issue))
  }
  self.reservation_attempted = true
  (match
    database(
      self.store.database.reserve_capacity(
        "publication_payload",
        self.key,
        self.bytes,
        1L,
        self.store.capacity_bytes,
        self.store.max_objects,
      ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  })
  |> ignore
  match self.store.root.create_writer_with_custody(self.staging, self.bytes) {
    Ok(writer) => self.writer = Some(writer)
    Err(failure) => {
      self.failed_writer = Some(failure)
      return Err(Filesystem(failure.issue()))
    }
  }
  let writer = self.writer.unwrap()
  match filesystem(writer.append(bytes)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let generation = match filesystem(writer.seal(self.name)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  self.generation = Some(generation)
  if generation.size != self.bytes {
    return Err(DigestMismatch)
  }
  let terminal = match
    captured_content_record(
      self.holding,
      self.wire,
      "sealed",
      Some(generation),
      self.store.max_record_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // The successful original CAS establishes this terminal once. Only an
  // ambiguous failure or saved restore needs the checked record readback.
  let committed = allocation_prepare(self.store, "captured-content-terminal", fn() {
    database(
      self.store.database.compare_exchange(
        "captured_content",
        self.holding,
        0L,
        terminal,
      ),
    )
  })
  match committed {
    Ok(1L) => self.committed = true
    Ok(_) => return Err(StateCollision)
    Err(issue) => return Err(issue)
  }
  match
    allocation_prepare(self.store, "captured-content-terminal-return", fn() {
      Ok(())
    }) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match filesystem(writer.close_retaining_files()) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  self.writer = None
  Ok(())
}

///|
fn CapturedContentCustody::confirm_record_in_scope(
  self : Self,
) -> Result[Unit, NativePublicationStoreIssue] {
  let stored = match
    database(self.store.database.read("captured_content", self.holding)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if stored.revision != 1L {
    return Err(RecoveryRequired)
  }
  let generation = match
    captured_content_generation(
      stored.body,
      self.holding,
      self.wire,
      self.store.max_record_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if generation.size != self.bytes {
    return Err(StateCollision)
  }
  if self.generation is Some(original) && original != generation {
    return Err(StateCollision)
  }
  let quota = match
    self.store.database.read_capacity("publication_payload", self.key) {
    Ok(value) => value
    Err(issue) => return Err(Database(issue))
  }
  if quota.reserved_bytes != self.bytes || quota.reserved_objects != 1L {
    return Err(RecoveryRequired)
  }
  self.generation = Some(generation)
  self.committed = true
  Ok(())
}

///|
/// Restore only this same Common-admitted saved candidate/holding. No provider
/// access, request, expiry renewal, writer or second physical holding exists.
pub fn CapturedContentCustody::restore(
  self : Self,
) -> Result[Unit, NativePublicationStoreIssue] {
  match self.register() {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  self.store.with_original_read(false, false, fn() {
    self.confirm_record_in_scope()
  })
}

///|
/// Verify the actual retained object before ReferenceIssuer can use it. The
/// caller backs the selected bounded read window before entering this method.
pub fn CapturedContentCustody::confirm(
  self : Self,
  chunk_bytes : Int,
) -> Result[Unit, NativePublicationStoreIssue] {
  if self.closed ||
    !self.committed ||
    self.verified ||
    chunk_bytes <= 0 ||
    self.reader is Some(_) ||
    self.failed_reader is Some(_) {
    return Err(RecoveryRequired)
  }
  self.store.with_original_read(false, false, fn() {
    let generation = self.generation.unwrap()
    match self.store.root.open_reader_with_custody(self.name, generation) {
      Ok(reader) => self.reader = Some(reader)
      Err(failure) => {
        self.failed_reader = Some(failure)
        return Err(Filesystem(failure.issue()))
      }
    }
    let reader = self.reader.unwrap()
    let hash = @sha.hasher()
    let mut received = 0L
    while true {
      let chunk = match filesystem(reader.next(chunk_bytes)) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      received += chunk.bytes.length().to_int64()
      if received > self.bytes {
        return Err(DigestMismatch)
      }
      @sha.update(hash, chunk.bytes) catch {
        _ => return Err(DigestMismatch)
      }
      if chunk.eof {
        break
      }
    }
    match filesystem(reader.finish()) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let digest = try "sha256:" + @sha.finish_hex(hash) catch {
      _ => return Err(DigestMismatch)
    }
    if received != self.bytes || digest != self.digest {
      return Err(DigestMismatch)
    }
    match filesystem(reader.close()) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    self.reader = None
    self.verified = true
    Ok(())
  })
}

///|
/// Callback-free custody correspondence. The Source still checks its original
/// current/Account/Run before issuance; this is no authorization or ACK.
pub fn CapturedContentCustody::matches_confirmed(
  self : Self,
  original : @publication.CapturedContentReference,
) -> Bool {
  physical_equal(self.original, original) &&
  self.verified &&
  self.committed &&
  !self.store.closed &&
  !self.store.retiring &&
  self.reader is None &&
  self.failed_reader is None
}

///|
/// Keep committed bytes for their original durable holding. Partial bytes are
/// removed only by their acquired Writer; absence or a filename is never ACK.
pub fn CapturedContentCustody::retry_cleanup(
  self : Self,
) -> Result[Bool, NativePublicationStoreIssue] {
  if self.closed {
    return Ok(true)
  }
  self.store.with_original_read(true, false, fn() {
    if self.failed_reader is Some(failure) {
      match filesystem(failure.retry_cleanup()) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      self.failed_reader = None
    }
    if self.reader is Some(reader) {
      match filesystem(reader.close()) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      self.reader = None
    }
    if self.intent_owned && !self.committed {
      let row = match
        database(self.store.database.read("captured_content", self.holding)) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      if row.revision == 1L && row.body != self.retired_record {
        // A CAS may have committed despite its returned error. Read the exact
        // terminal before deciding whether this original Writer may cancel.
        match self.confirm_record_in_scope() {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
      } else if row.revision != 0L && row.body != self.retired_record {
        return Err(StateCollision)
      }
    }
    if self.failed_writer is Some(failure) {
      match filesystem(failure.retry_cleanup()) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      self.failed_writer = None
    }
    if self.writer is Some(writer) {
      if self.committed {
        match filesystem(writer.close_retaining_files()) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
      } else {
        match filesystem(writer.cancel()) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
      }
      self.writer = None
    }
    if self.intent_owned && !self.committed {
      if self.reservation_attempted {
        // This exact original reservation is idempotent after release. No
        // runtime work, attempt or Source byte consumption is refunded.
        (match
          database(
            self.store.database.release_capacity(
              "publication_payload",
              self.key,
              self.bytes,
              1L,
            ),
          ) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        })
        |> ignore
      }
      match
        self.store.database.compare_exchange(
          "captured_content",
          self.holding,
          0L,
          self.retired_record,
        ) {
        Ok(1L) => ()
        Err(@sqlite.Collision) => {
          let row = match
            database(self.store.database.read("captured_content", self.holding)) {
            Ok(value) => value
            Err(issue) => return Err(issue)
          }
          if row.body != self.retired_record || row.revision != 1L {
            return Err(StateCollision)
          }
        }
        Ok(_) => return Err(StateCollision)
        Err(issue) => return Err(Database(issue))
      }
    }
    if self.registered {
      self.store.active_writers.remove(self.key) |> ignore
      self.registered = false
    }
    self.closed = true
    Ok(true)
  })
}

///|
// Existing Store retirement may keep verified durable bytes, but must never
// silently discharge an unresolved captured-content allocation after restart.
// Only its retained original Writer can cancel a partial file. This scan
// creates neither a cleanup capability nor a new read of Source data.
fn recover_captured_content_records(
  store : Store,
) -> Result[Int, NativePublicationStoreIssue] {
  let mut cursor = ""
  let mut retained = 0
  while true {
    let row = match store.database.scan_after("captured_content", cursor) {
      Ok(value) => value
      Err(@sqlite.NotFound) => break
      Err(issue) => return Err(Database(issue))
    }
    cursor = row.key
    let source = match
      @source.parse_json_bytes_preserving(row.body, {
        max_input_bytes: store.max_record_bytes,
        max_nodes: 8,
        max_depth: 2,
      }) {
      Ok(value) => value
      Err(_) => return Err(StateCollision)
    }
    let data = match
      @decode.admit(source, {
        max_nodes: 8,
        max_depth: 2,
        max_string_bytes: store.max_record_bytes,
        max_total_string_bytes: store.max_record_bytes,
      }) {
      Ok(value) => value
      Err(_) => return Err(StateCollision)
    }
    let field = index => {
      @decode.element_at(data, index).bind(child => {
        @decode.text(child).to_option()
      })
    }
    guard field(0) == Some("actql-native-captured-content-custody/0.1") &&
      field(1) == Some(row.key) &&
      field(2) is Some(wire) &&
      field(3) is Some(state) else {
      return Err(StateCollision)
    }
    if state == "pending" {
      return Err(CleanupPending)
    }
    if state == "retired" &&
      row.revision == 1L &&
      @decode.array_length(data) == Some(4) {
      match
        captured_content_record(
          row.key,
          wire,
          state,
          None,
          store.max_record_bytes,
        ) {
        Ok(original) if original == row.body => continue
        _ => return Err(StateCollision)
      }
    }
    if state != "sealed" || row.revision != 1L {
      return Err(StateCollision)
    }
    match
      captured_content_generation(
        row.body,
        row.key,
        wire,
        store.max_record_bytes,
      ) {
      Ok(_) => retained += 1
      Err(issue) => return Err(issue)
    }
  }
  Ok(retained)
}
