///|
priv enum NativeRelationTargetIOPhase {
  TargetPrepared
  TargetReading
  TargetProjecting
  TargetWriting
  TargetReady
  TargetFailed
  TargetClosing
  TargetClosed
}

///|
/// Physical child of the installed file implementation, not a Run, permission
/// or resource owner. The Host must fund its original constructor/decoder and
/// charge its actual byte observations on the SAME selected operation. Reads
/// require original Account authorization; updates require the original durable
/// Effect claim before the first advance. No authority is derived from DATA.
struct NativeRelationFileTargetIO {
  mut original : NativeRelationFileTargetIO?
  provider : NativeRelationFilePreparedProvider
  writable : Array[String]
  identity : String
  update : (String, String, String)?
  mut phase : NativeRelationTargetIOPhase
  mut advancing : Bool
  mut issue : NativeRelationFileIssue?
  mut root : @files.Root?
  mut rejected_root : @files.NativeRootOpenFailure?
  mut observation : @files.NativeFileObservation?
  mut reader : @files.Reader?
  mut rejected_reader : @files.NativeReaderOpenFailure?
  mut lock : @files.Lock?
  mut rejected_lock : @files.NativeLockOpenFailure?
  mut writer : @files.Writer?
  mut rejected_writer : @files.NativeWriterOpenFailure?
  mut buffer : FixedArray[Byte]?
  mut backing : @rows.RelationDocument?
  mut document : @rows.RelationTargetDocument?
  mut row : @rows.RelationTargetRow?
  mut replacement : Bytes?
  mut observed_row : (String, String)?
  mut received : Int64
  mut submitted : Int64
  mut offset : Int
  mut replacement_attempted : Bool
}

///|
/// Same file/typed-document implementation bounds, before its physical child
/// exists. Reuse Common's original parser/projection and JSON Effect envelope;
/// fixed child controls use the existing file caller census. No new budget,
/// policy ceiling, physical attempt or permission is selected here.
pub fn native_relation_file_target_io_capacity(
  provider : NativeRelationFilePreparedProvider,
  writable_fields : Int,
) -> @execution.ExecutionCapacity? {
  let limits = provider.limits
  let selection = provider.selection
  guard writable_fields > 0 &&
    writable_fields <= limits.page.max_nodes &&
    file_capture_provider_capacity(
      selection,
      limits,
      @rows.relation_document_prepared_contract(provider.prepared_contract),
      prepared_contract=Some(provider.prepared_contract),
      writable_fields~,
    )
    is Some(document) &&
    @local.installed_file_effect_constructor_capacity(
      document,
      limits.page.max_bytes,
      limits.page.max_nodes,
      limits.page.max_depth,
    )
    is Ok(construction) &&
    file_capture_metadata_capacity(
      selection,
      limits,
      prepared_provider=Some(provider),
    )
    is Some(controls) &&
    @files.native_filesystem_write_layout() is Some(writer) &&
    @encode.text_writer_construction_inventory(
      limits.page.max_bytes,
      limits.page.max_nodes,
      limits.page.max_depth,
    )
    is Some(before) &&
    @encode.hash_writer_construction_inventory(
      limits.page.max_nodes,
      limits.page.max_depth,
    )
    is Some(version) &&
    @execution.preparation_array_representation(
      1L,
      writable_fields.to_int64(),
      false,
    )
    is Some(writable) &&
    @execution.compose_preparation_representation([
      {
        record_headers: before.record_headers,
        reference_slots: before.reference_slots,
        scalar_words: before.scalar_words,
        owned_utf16_units: before.owned_utf16_units,
        owned_wire_bytes: 0L,
      },
      {
        record_headers: version.record_headers,
        reference_slots: version.reference_slots,
        scalar_words: version.scalar_words,
        owned_utf16_units: version.owned_utf16_units,
        owned_wire_bytes: version.owned_wire_bytes,
      },
      writable,
    ])
    is Some(observation) &&
    @execution.preparation_representation_cost(observation) is Some(observation) else {
    return None
  }
  // Original receive/document storage is already in `construction`. Add the
  // submitted replacement and actual Writer+lock native storage beside it.
  // The FS Owner statically proves its lock payload fits its Writer layout.
  // Target/lock UTF8 copies, the terminated lock suffix, and the original
  // <=64-unit staging name. Additional diagnostics retain C error/close-error,
  // the returned Bytes and decoded refusal text beside existing read storage.
  let names = 16L * selection.name.length().to_int64() +
    8L * 64L +
    10L * 17L +
    8L
  let native = 2L *
    (writer.writer_payload_bytes + writer.external_object_overhead_bytes) +
    names +
    16L * limits.diagnostic_ceiling.to_int64() +
    6L +
    limits.page.max_bytes.to_int64()
  guard @execution.execution_capacity(
      controls + observation + native,
      controls + observation + native,
    )
    is Some(extra) else {
    return None
  }
  @execution.add_execution_capacity(construction, extra)
}

///|
/// Retain this child before advancing it. `update` contains the SAME expected
/// row version, checked changes wire and unique staging basename. It supplies
/// no approval or permission. The prepared provider retains the original full
/// relation contract and physical selection; no second schema is admitted.
pub fn prepare_native_relation_file_target_io(
  provider : NativeRelationFilePreparedProvider,
  writable : Array[String],
  identity : String,
  update? : (String, String, String)? = None,
) -> Result[NativeRelationFileTargetIO, NativeRelationFileIssue] {
  if !file_capture_text(identity, provider.limits.page.max_bytes) ||
    writable.is_empty() ||
    writable.length() > provider.limits.page.max_nodes {
    return Err(InvalidInput)
  }
  if update is Some((version, changes, staging)) &&
    (
      !file_capture_text(version, provider.limits.page.max_bytes) ||
      !file_capture_text(changes, provider.limits.page.max_bytes) ||
      !file_capture_text(staging, 64) ||
      staging.contains("/") ||
      staging == "." ||
      staging == ".." ||
      staging == provider.selection.name
    ) {
    return Err(InvalidInput)
  }
  let child : NativeRelationFileTargetIO = {
    original: None,
    provider,
    writable: writable.copy(),
    identity,
    update,
    phase: TargetPrepared,
    advancing: false,
    issue: None,
    root: None,
    rejected_root: None,
    observation: None,
    reader: None,
    rejected_reader: None,
    lock: None,
    rejected_lock: None,
    writer: None,
    rejected_writer: None,
    buffer: None,
    backing: None,
    document: None,
    row: None,
    replacement: None,
    observed_row: None,
    received: 0L,
    submitted: 0L,
    offset: 0,
    replacement_attempted: false,
  }
  child.original = Some(child)
  Ok(child)
}

///|
fn NativeRelationFileTargetIO::same(self : Self) -> Bool {
  self.original is Some(original) && physical_equal(original, self)
}

///|
fn NativeRelationFileTargetIO::open(self : Self) -> Unit raise FileCaptureStop {
  let selection = self.provider.selection
  let root = match
    @files.open_root_in_current_read_context_with_custody(
      selection.directory,
      self.provider.limits.diagnostic_ceiling,
    ) {
    Ok(value) => value
    Err(failure) => {
      self.rejected_root = Some(failure)
      raise FileCaptureStop(Filesystem(failure.issue()))
    }
  }
  self.root = Some(root)
  if self.update is Some(_) {
    match root.acquire_lock_with_custody(selection.name + ".actql-write.lock") {
      Ok(value) => self.lock = Some(value)
      Err(failure) => {
        self.rejected_lock = Some(failure)
        raise FileCaptureStop(Filesystem(failure.issue()))
      }
    }
  }
  let observed = file_require(
    root.observe_file(selection.name).map_err(issue => Filesystem(issue)),
  )
  self.observation = Some(observed)
  let generation = file_require(
    observed.generation().map_err(issue => Filesystem(issue)),
  )
  if generation.size < 0L ||
    generation.size > self.provider.limits.page.max_bytes.to_int64() {
    raise FileCaptureStop(FileLimit)
  }
  match observed.open_reader_with_custody() {
    Ok(value) => self.reader = Some(value)
    Err(failure) => {
      self.rejected_reader = Some(failure)
      raise FileCaptureStop(Filesystem(failure.issue()))
    }
  }
  self.buffer = Some(FixedArray::make(generation.size.to_int(), 0))
  self.phase = TargetReading
}

///|
fn NativeRelationFileTargetIO::read(self : Self) -> Unit raise FileCaptureStop {
  let reader = self.reader.unwrap()
  let chunk = file_require(
    reader
    .next(self.provider.limits.chunk_bytes)
    .map_err(issue => Filesystem(issue)),
  )
  // Preserve bytes actually received even if the subsequent check/close fails.
  // Projection is a separate advance, so the caller accounts this observation
  // before any parser/target constructor runs. Failure never refunds the prefix.
  self.received += chunk.bytes.length().to_int64()
  let buffer = self.buffer.unwrap()
  if chunk.bytes.length() > buffer.length() - self.offset ||
    (chunk.bytes.is_empty() && !chunk.eof) {
    raise FileCaptureStop(FileLimit)
  }
  buffer.blit_from_bytes(self.offset, chunk.bytes, 0, chunk.bytes.length())
  self.offset += chunk.bytes.length()
  if chunk.eof {
    if self.offset != buffer.length() {
      raise FileCaptureStop(FileLimit)
    }
    file_require(
      self.observation
      .unwrap()
      .check_reader(reader)
      .map_err(issue => Filesystem(issue)),
    )
    file_require(reader.finish().map_err(issue => Filesystem(issue)))
    file_require(reader.close().map_err(issue => Filesystem(issue)))
    self.reader = None
    self.phase = TargetProjecting
  }
}

///|
fn NativeRelationFileTargetIO::project(
  self : Self,
) -> Unit raise FileCaptureStop {
  let provider = self.provider
  let selected = provider.selection
  let bytes = Bytes::from_array(self.buffer.unwrap())
  let backing = file_require(
    @rows.admit_relation_document(
      bytes,
      provider.limits.page,
      provider.limits.max_work,
    ).map_err(issue => Document(issue)),
  )
  // Retain the raw original BEFORE the fallible typed projection. Both marks
  // stay with this same child until its actual consumer and cleanup return.
  self.backing = Some(backing)
  let projected = @rows.project_relation_target_document(
    backing,
    provider.declaration,
    selected.resource,
    selected.items_path,
    selected.key_path,
    selected.primary_identity,
    self.writable,
    prepared_contract=Some(provider.prepared_contract),
  )
  let document = match projected {
    Ok(value) => value
    Err(issue) => raise FileCaptureStop(Document(issue))
  }
  self.document = Some(document)
  let row = file_require(
    @rows.observe_relation_target(document, provider.declaration, self.identity).map_err(issue => {
        Document(issue)
      },
    ),
  )
  self.row = Some(row)
  guard @rows.relation_target_before(row) is Some(before) &&
    @rows.relation_target_version(row) is Some(version) else {
    raise FileCaptureStop(ForeignOriginal)
  }
  self.observed_row = Some((before, version))
  match self.update {
    None => self.phase = TargetReady
    Some((expected, changes, _)) => {
      let output = file_require(
        @rows.prepare_relation_target_update(
          document,
          row,
          expected,
          changes,
          provider.limits.max_work,
        ).map_err(issue => Document(issue)),
      )
      self.replacement = Some(output)
      self.phase = TargetWriting
    }
  }
}

///|
fn NativeRelationFileTargetIO::write(self : Self) -> Unit raise FileCaptureStop {
  guard self.update is Some((_, _, staging)) && !self.replacement_attempted else {
    raise FileCaptureStop(Unavailable)
  }
  let root = self.root.unwrap()
  let output = self.replacement.unwrap()
  let writer = match
    root.create_writer_with_custody(staging, output.length().to_int64()) {
    Ok(value) => value
    Err(failure) => {
      self.rejected_writer = Some(failure)
      raise FileCaptureStop(Filesystem(failure.issue()))
    }
  }
  self.writer = Some(writer)
  // The original Writer receives this entire payload once. A later append or
  // rename error cannot authorize another writer, a retry or a transfer refund.
  self.submitted = output.length().to_int64()
  self.replacement_attempted = true
  file_require(writer.append(output).map_err(issue => Filesystem(issue)))
  file_require(
    writer
    .replace_observed_file(self.observation.unwrap(), self.lock.unwrap())
    .map_err(issue => Filesystem(issue)),
  )
  |> ignore
  self.phase = TargetReady
}

///|
/// One bounded transport or typed projection step on the SAME entered Native
/// read. The Host accounts received/submitted deltas on both success and error.
/// It must reserve the selected constructor overlap before calling this entry.
pub fn NativeRelationFileTargetIO::advance(
  self : Self,
) -> Result[Bool, NativeRelationFileIssue] {
  if !self.same() ||
    self.advancing ||
    self.phase is TargetClosing ||
    self.phase is TargetClosed {
    return Err(Unavailable)
  }
  if self.issue is Some(issue) {
    return Err(issue)
  }
  self.advancing = true
  defer {
    self.advancing = false
  }
  try {
    if self.root is Some(root) {
      file_require(
        root.require_current_original_read().map_err(issue => Filesystem(issue)),
      )
    }
    match self.phase {
      TargetPrepared => self.open()
      TargetReading => self.read()
      TargetProjecting => self.project()
      TargetWriting => self.write()
      TargetReady => ()
      _ => raise FileCaptureStop(Unavailable)
    }
    Ok(self.phase is TargetReady)
  } catch {
    FileCaptureStop(issue) => {
      self.issue = Some(issue)
      self.phase = TargetFailed
      Err(issue)
    }
  }
}

///|
/// Actual transport observations only, including failed prefixes. These are
/// neither a Resource debit/ACK nor successful business evidence.
pub fn NativeRelationFileTargetIO::byte_counts(self : Self) -> (Int64, Int64) {
  (self.received, self.submitted)
}

///|
/// Original full-row before/version DATA; availability grants no write. No raw
/// parser cursor or physical file handle leaves this child.
pub fn NativeRelationFileTargetIO::snapshot(self : Self) -> (String, String)? {
  if self.same() &&
    self.phase is TargetReady &&
    self.issue is None &&
    self.root is Some(root) &&
    root.require_current_original_read() is Ok(_) {
    self.observed_row
  } else {
    None
  }
}

///|
/// Validate the proposed changes against this SAME observed full document and
/// original row before Preview. This constructs no Writer and performs no
/// replacement; the original update path independently checks the version.
pub fn NativeRelationFileTargetIO::check_update(
  self : Self,
  changes : String,
) -> Result[Unit, NativeRelationFileIssue] {
  guard self.same() &&
    self.phase is TargetReady &&
    self.update is None &&
    self.issue is None &&
    self.root is Some(root) &&
    self.document is Some(document) &&
    self.row is Some(row) &&
    self.observed_row is Some((_, version)) else {
    return Err(Unavailable)
  }
  match root.require_current_original_read() {
    Err(issue) => return Err(Filesystem(issue))
    Ok(_) => ()
  }
  @rows.prepare_relation_target_update(
    document,
    row,
    version,
    changes,
    self.provider.limits.max_work,
  )
  .map(_ => ())
  .map_err(issue => Document(issue))
}

///|
fn NativeRelationFileTargetIO::retire_transport(
  self : Self,
) -> Unit raise FileCaptureStop {
  if self.rejected_writer is Some(failure) {
    file_require(failure.retry_cleanup().map_err(issue => Filesystem(issue)))
    self.rejected_writer = None
  }
  if self.writer is Some(writer) {
    file_require(writer.cancel().map_err(issue => Filesystem(issue)))
    self.writer = None
  }
  if self.rejected_reader is Some(failure) {
    file_require(failure.retry_cleanup().map_err(issue => Filesystem(issue)))
    self.rejected_reader = None
  }
  if self.reader is Some(reader) {
    file_require(reader.close().map_err(issue => Filesystem(issue)))
    self.reader = None
  }
  if self.rejected_lock is Some(failure) {
    file_require(failure.retry_cleanup().map_err(issue => Filesystem(issue)))
    self.rejected_lock = None
  }
  if self.lock is Some(lock) {
    file_require(lock.close_checked().map_err(issue => Filesystem(issue)))
    self.lock = None
  }
  self.observation = None
  if self.rejected_root is Some(failure) {
    file_require(failure.retry_cleanup().map_err(issue => Filesystem(issue)))
    self.rejected_root = None
  }
  if self.root is Some(root) {
    file_require(root.close().map_err(issue => Filesystem(issue)))
    self.root = None
  }
  ()
}

///|
/// Retire the same partial physical children, never replay a read/write. The
/// installing caller separately retires escaped DATA and its original token.
pub fn NativeRelationFileTargetIO::close(
  self : Self,
) -> Result[Bool, NativeRelationFileIssue] {
  if self.phase is TargetClosed && self.original is None {
    return Ok(true)
  }
  if !self.same() || self.advancing {
    return Err(Unavailable)
  }
  self.phase = TargetClosing
  try {
    self.retire_transport()
    if self.row is Some(row) {
      if !@rows.discard_relation_target_row_original(row) {
        return Ok(false)
      }
      self.row = None
    }
    if self.document is Some(document) {
      if !@rows.discard_relation_target_document_original(document) {
        return Ok(false)
      }
      self.document = None
    }
    if self.backing is Some(backing) {
      if !@rows.discard_relation_document_original(backing) {
        return Ok(false)
      }
      self.backing = None
    }
    self.buffer = None
    self.replacement = None
    self.observed_row = None
    self.original = None
    self.phase = TargetClosed
    Ok(true)
  } catch {
    FileCaptureStop(issue) => Err(issue)
  }
}
