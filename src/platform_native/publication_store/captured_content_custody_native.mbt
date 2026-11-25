///|
// Physical child custody of the EXISTING Store. Common keeps the original
// Run/keyed request/ContentRef. No separate Root, Ledger or permission exists.
struct CapturedContentCustody {
  store : Store
  original : CapturedPayloadOriginal
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
// Closed metadata purposes share the same Store file/capacity/cleanup owner.
// A raw lookup payload cannot supply ContentRef custody.
priv enum CapturedPayloadOriginal {
  Content(@publication.CapturedContentReference)
  Generated(@publication.GeneratedContentReference)
  SavedGenerated(@publication.StoredGeneratedContentReference)
  LookupRaw(@publication.PublicationContract)
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
  guard captured_content_record_bound(wire, max_bytes) is Some(bound) else {
    return Err(StateCollision)
  }
  // A longer body cannot be the canonical original checked below. Refuse it
  // before constructing its preserving parser/index, including failed/cold
  // readback. The original database read and Store limit remain unchanged.
  if body.length() > bound {
    return Err(StateCollision)
  }
  try {
    let source = match
      @source.parse_json_bytes_preserving(body, {
        max_input_bytes: bound,
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
        max_string_bytes: bound,
        max_total_string_bytes: bound,
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
  self.prepare_captured_payload_custody(
    Content(original),
    holding,
    wire,
    digest,
    count.to_int64(),
  )
}

///|
/// Keep the completed encoder's candidate and the admitted Run's holding on
/// the existing Content Store owner. The caller funds construction and keeps
/// the original current and publication policy checks through issuance.
pub fn Store::prepare_generated_content_custody(
  self : Store,
  original : @publication.GeneratedContentReference,
  holding : String,
) -> Result[CapturedContentCustody, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  if self.retiring {
    return Err(CleanupPending)
  }
  let (authority, _, digest, count) = @publication.generated_content_reference_storage(
    original,
  )
  guard authority == self.authority_cid &&
    count >= 0 &&
    valid_effect_custody_digest(holding) else {
    return Err(StateCollision)
  }
  self.prepare_captured_payload_custody(
    Generated(original),
    holding,
    @publication.generated_content_reference_wire(original),
    digest,
    count.to_int64(),
  )
}

///|
/// Prepare only a read of the exact stored generated holding. Its canonical
/// reference was readmitted by Common from the original Run, with no encoder.
pub fn Store::prepare_saved_generated_content_custody(
  self : Store,
  original : @publication.StoredGeneratedContentReference,
  holding : String,
) -> Result[CapturedContentCustody, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  if self.retiring {
    return Err(CleanupPending)
  }
  let (_, authority, _, digest, count) = @publication.stored_generated_content_reference_storage(
    original,
  )
  guard authority == self.authority_cid &&
    count >= 0 &&
    valid_effect_custody_digest(holding) else {
    return Err(StateCollision)
  }
  self.prepare_captured_payload_custody(
    SavedGenerated(original),
    holding,
    @publication.stored_generated_content_reference_wire(original),
    digest,
    count.to_int64(),
  )
}

///|
/// The authenticated Source caller supplies its original raw metadata and
/// private holding. Only persist/confirm on this SAME owner establish byte
/// custody; a kind, CID or Store quota is not Source permission or memory.
pub fn Store::prepare_lookup_raw_custody(
  self : Store,
  original : @publication.PublicationContract,
  holding : String,
) -> Result[CapturedContentCustody, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  if self.retiring {
    return Err(CleanupPending)
  }
  guard valid_effect_custody_digest(holding) &&
    @publication.lookup_raw_response_content(original) is Some((digest, count)) else {
    return Err(StateCollision)
  }
  self.prepare_captured_payload_custody(
    LookupRaw(original),
    holding,
    @publication.publication_contract_json(original),
    digest,
    count,
  )
}

///|
fn Store::prepare_captured_payload_custody(
  self : Store,
  original : CapturedPayloadOriginal,
  holding : String,
  wire : String,
  digest : String,
  count : Int64,
) -> Result[CapturedContentCustody, NativePublicationStoreIssue] {
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
    bytes: count,
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
/// Synchronous, fixed Native backing for one encoder already funded by its
/// original Run. It consumes only the bytes returned by that encoder.
struct NativeGeneratedContentOutput {
  encoder : @publication.ContentByteEncoder
  backing : FixedArray[Byte]
  mut written : Int
}

///|
pub fn start_native_generated_content_output(
  encoder : @publication.ContentByteEncoder,
) -> Result[NativeGeneratedContentOutput, NativePublicationStoreIssue] {
  let (_, capacity) = @publication.content_byte_generation_limits(encoder)
  Ok({ encoder, backing: FixedArray::make(capacity, 0), written: 0, })
}

///|
/// The caller accounts for returned work before interpreting a failure. No
/// provisional strings or mutable array aliases leave this bounded port.
pub fn NativeGeneratedContentOutput::advance(
  self : Self,
  quantum : Int,
) -> (Result[Bool, @publication.ContentSerializationIssue], Int) {
  let (ready, piece, work) = match
    @publication.advance_content_bytes(self.encoder, quantum) {
    @publication.ContentBytesContinue(piece, work~) => (false, piece, work)
    @publication.ContentBytesReady(piece, work~) => (true, piece, work)
    @publication.ContentBytesFailed(issue, work~) => return (Err(issue), work)
  }
  if piece.length() == 0 {
    return (Ok(ready), work)
  }
  let chunk = @utf8.encode(piece)
  if chunk.length() > self.backing.length() - self.written {
    @publication.cancel_content_byte_encoder(self.encoder)
    return (Err(@publication.ContentByteLimit), work)
  }
  self.backing.blit_from_bytes(self.written, chunk, 0, chunk.length())
  self.written += chunk.length()
  (Ok(ready), work)
}

///|
/// Captured Source and lookup bytes use the original whole-body entry point.
pub fn CapturedContentCustody::persist(
  self : Self,
  bytes : Bytes,
) -> Result[Unit, NativePublicationStoreIssue] {
  guard self.original is Content(_) || self.original is LookupRaw(_) else {
    return Err(RecoveryRequired)
  }
  self.persist_extent(bytes, bytes.length())
}

///|
pub fn CapturedContentCustody::matches_generated_selection(
  self : Self,
  store : Store,
  candidate : @publication.GeneratedContentReference,
  holding : String,
) -> Bool {
  self.original is Generated(selected) &&
  physical_equal(selected, candidate) &&
  physical_equal(self.store, store) &&
  self.holding == holding &&
  !self.closed
}

///|
/// Consume a checked generated byte extent from the same nominal encoder as
/// the candidate. Only this synchronous Store call borrows the backing.
pub fn CapturedContentCustody::persist_generated_output(
  self : Self,
  output : NativeGeneratedContentOutput,
) -> Result[Unit, NativePublicationStoreIssue] {
  guard self.original is Generated(candidate) &&
    @publication.generated_content_reference_completion_for(
      candidate,
      output.encoder,
    )
    is Some(_) else {
    return Err(StateCollision)
  }
  self.persist_extent(
    output.backing.unsafe_reinterpret_as_bytes(),
    output.written,
  )
}

///|
fn CapturedContentCustody::persist_extent(
  self : Self,
  bytes : Bytes,
  count : Int,
) -> Result[Unit, NativePublicationStoreIssue] {
  guard count.to_int64() == self.bytes &&
    @sha.hex_prefix(bytes, count) is Some(digest) &&
    "sha256:" + digest == self.digest else {
    return Err(DigestMismatch)
  }
  match self.register() {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  self.store.with_original_read(false, false, fn() {
    self.persist_in_scope(bytes, count)
  })
}

///|
fn CapturedContentCustody::persist_in_scope(
  self : Self,
  bytes : Bytes,
  count : Int,
) -> Result[Unit, NativePublicationStoreIssue] {
  match
    self.store.database.insert("captured_content", self.holding, self.intent) {
    Ok(0L) => self.intent_owned = true
    Ok(_) => return Err(StateCollision)
    Err(@sqlite.Collision) => {
      // A fresh Source capture can have the same ContentRef as an earlier
      // capture in this Run. Require the exact sealed record and quota before
      // opening its bytes in confirm. Never write or reserve them a second
      // time, or reuse an unresolved record or raw-response attempt.
      guard self.original is Content(_) else { return Err(RecoveryRequired) }
      return match self.confirm_record_in_scope() {
        Err(StateCollision) => Err(RecoveryRequired)
        result => result
      }
    }
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
  match filesystem(writer.append(bytes, length=count)) {
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
fn CapturedContentCustody::confirmed_bytes_current(self : Self) -> Bool {
  self.verified &&
  self.committed &&
  !self.store.closed &&
  !self.store.retiring &&
  self.reader is None &&
  self.failed_reader is None
}

///|
/// Callback-free custody correspondence. The Source still checks its original
/// current/Account/Run before issuance.
pub fn CapturedContentCustody::matches_confirmed(
  self : Self,
  original : @publication.CapturedContentReference,
) -> Bool {
  self.original is Content(retained) &&
  physical_equal(retained, original) &&
  self.confirmed_bytes_current()
}

///|
/// A physical receipt belongs to the exact generated candidate it verified.
/// Current scope and policy still belong to the original Content issuer.
pub fn CapturedContentCustody::matches_generated_confirmed(
  self : Self,
  original : @publication.GeneratedContentReference,
) -> Bool {
  self.original is Generated(retained) &&
  physical_equal(retained, original) &&
  self.confirmed_bytes_current()
}

///|
/// Reverification of saved bytes supplies only this stored candidate's
/// physical observation. The original issuer still checks live read access.
pub fn CapturedContentCustody::matches_saved_generated_confirmed(
  self : Self,
  original : @publication.StoredGeneratedContentReference,
) -> Bool {
  self.original is SavedGenerated(retained) &&
  physical_equal(retained, original) &&
  self.confirmed_bytes_current()
}

///|
/// Pure original-purpose correspondence after actual byte verification.
/// This cannot authorize another Source call or create a ContentRef.
pub fn CapturedContentCustody::matches_lookup_raw_confirmed(
  self : Self,
  original : @publication.PublicationContract,
) -> Bool {
  self.original is LookupRaw(retained) &&
  physical_equal(retained, original) &&
  self.confirmed_bytes_current()
}

///|
/// Keep committed bytes for their original durable holding. Partial bytes are
/// removed only by their acquired Writer; absence or a filename is never ACK.
pub fn CapturedContentCustody::retry_cleanup(
  self : Self,
) -> Result[Bool, NativePublicationStoreIssue] {
  self.retire_generated_or_close(discard=false)
}

///|
/// The command calls this only after proving its publication was never
/// entered. A sealed private holding then has no public Result borrower.
pub fn CapturedContentCustody::abandon_unpublished_generated(
  self : Self,
) -> Result[Bool, NativePublicationStoreIssue] {
  guard self.original is Generated(_) else { return Err(StateCollision) }
  self.retire_generated_or_close(discard=true)
}

///|
fn CapturedContentCustody::retire_generated_or_close(
  self : Self,
  discard~ : Bool,
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
    if discard && self.committed {
      match self.reclaim_generated_in_scope() {
        Ok(_) => ()
        Err(issue) => return Err(issue)
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
/// Record the exact sealed generation before removing its file. Unknown
/// replies must observe the same row and inode before proceeding; a replaced
/// name is never removed. The original owner retains pending cleanup.
fn CapturedContentCustody::reclaim_generated_in_scope(
  self : Self,
) -> Result[Unit, NativePublicationStoreIssue] {
  guard self.original is Generated(_) &&
    self.intent_owned &&
    self.generation is Some(generation) else {
    return Err(StateCollision)
  }
  self.verified = false
  let row = match
    database(self.store.database.read("captured_content", self.holding)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if row.revision == 3L && row.body == self.retired_record {
    return Ok(())
  }
  if row.revision == 1L {
    guard captured_content_record(
        self.holding,
        self.wire,
        "sealed",
        Some(generation),
        self.store.max_record_bytes,
      )
      is Ok(expected) &&
      expected == row.body else {
      return Err(StateCollision)
    }
  } else if row.revision != 2L {
    return Err(StateCollision)
  }
  // Compare against one canonical state at a time. Do not retain both
  // encoded records across the SQLite mutation.
  guard captured_content_record(
      self.holding,
      self.wire,
      "retiring",
      Some(generation),
      self.store.max_record_bytes,
    )
    is Ok(retiring) else {
    return Err(StateCollision)
  }
  if row.revision == 1L {
    match
      database(
        self.store.database.compare_exchange(
          "captured_content",
          self.holding,
          1L,
          retiring,
        ),
      ) {
      Ok(2L) => ()
      Ok(_) => return Err(StateCollision)
      Err(issue) => return Err(issue)
    }
  } else if row.body != retiring {
    return Err(StateCollision)
  }
  match filesystem(self.store.root.reclaim_generation(self.name, generation)) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match
    database(
      self.store.database.release_capacity(
        "publication_payload",
        self.key,
        self.bytes,
        1L,
      ),
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match
    database(
      self.store.database.compare_exchange(
        "captured_content",
        self.holding,
        2L,
        self.retired_record,
      ),
    ) {
    Ok(3L) => Ok(())
    Ok(_) => Err(StateCollision)
    Err(issue) => Err(issue)
  }
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
    if state == "pending" || state == "retiring" {
      return Err(CleanupPending)
    }
    if state == "retired" &&
      (row.revision == 1L || row.revision == 3L) &&
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
