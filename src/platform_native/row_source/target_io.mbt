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
/// Checked-operation DATA supplied by the existing Host.
pub(all) enum NativeRelationFileTargetMutation {
  ObserveTarget
  ObserveDeleteTarget
  ObserveOptionalTarget
  UpdateTarget(String, String, String)
  DeleteTarget(String, String)
  InsertTarget(String, String)
}

///|
fn NativeRelationFileTargetMutation::writes(self : Self) -> Bool {
  self is UpdateTarget(_, _, _) ||
  self is DeleteTarget(_, _) ||
  self is InsertTarget(_, _)
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
  mutation : NativeRelationFileTargetMutation
  ordered_key : @rows.RelationDocumentPreparedKey?
  mut before_response : ((Int) -> Bool)?
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
  mut replacement_ack : NativeRelationFileReplacementAck?
  mut predecessor : NativeRelationFileReplacementAck?
  mut observed_row : (String, String)?
  mut received : Int64
  mut submitted : Int64
  mut offset : Int
  mut replacement_attempted : Bool
}

///|
/// The actual existing Writer's acknowledged replacement, not a Journal commit,
/// permission, cleanup ACK or reconstruction from current target contents.
/// Only the original physical child constructs this immutable observation.
struct NativeRelationFileReplacementAck {
  provider : NativeRelationFilePreparedProvider
  identity : String
  expected_version : String
  operation : NativeRelationFileReplacementKind
  changes_wire : String
  replacement : Bytes
  generation : @files.NativeFileGeneration
}

///|
priv enum NativeRelationFileReplacementKind {
  TargetUpdated
  TargetDeleted
  TargetInserted
}

///|
pub fn NativeRelationFileReplacementAck::selection(
  self : Self,
) -> NativeRelationFileSelection {
  self.provider.selection
}

///|
pub fn NativeRelationFileReplacementAck::identity(self : Self) -> String {
  self.identity
}

///|
/// The physical child retains the prepared key of the exact file provider.
pub fn NativeRelationFileReplacementAck::has_ordered_key(self : Self) -> Bool {
  self.provider.has_ordered_key()
}

///|
pub fn NativeRelationFileReplacementAck::expected_version(
  self : Self,
) -> String {
  self.expected_version
}

///|
pub fn NativeRelationFileReplacementAck::is_delete(self : Self) -> Bool {
  self.operation is TargetDeleted
}

///|
pub fn NativeRelationFileReplacementAck::is_insert(self : Self) -> Bool {
  self.operation is TargetInserted
}

///|
pub fn NativeRelationFileReplacementAck::changes_wire(self : Self) -> String {
  self.changes_wire
}

///|
/// Borrow the exact submitted replacement; no copy, decode or target reread.
pub fn NativeRelationFileReplacementAck::replacement(self : Self) -> Bytes {
  self.replacement
}

///|
pub fn NativeRelationFileReplacementAck::generation(
  self : Self,
) -> @files.NativeFileGeneration {
  self.generation
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
  guard writable_fields > 0 else { return None }
  native_relation_file_target_io_capacity_original(provider, writable_fields)
}

///|
/// The locked DELETE constructs a whole-file replacement from the original
/// document and exact row, without a mapped field list.
pub fn native_relation_file_delete_target_io_capacity(
  provider : NativeRelationFilePreparedProvider,
) -> @execution.ExecutionCapacity? {
  native_relation_file_target_io_capacity_original(provider, 0)
}

///|
fn native_relation_file_target_io_capacity_original(
  provider : NativeRelationFilePreparedProvider,
  writable_fields : Int,
) -> @execution.ExecutionCapacity? {
  let limits = provider.limits
  let selection = provider.selection
  guard writable_fields <= limits.page.max_nodes &&
    file_capture_provider_capacity(
      selection,
      limits,
      @rows.relation_document_prepared_contract(provider.prepared_contract),
      prepared_contract=Some(provider.prepared_contract),
      writable_fields~,
      ordered_projection=provider.has_ordered_key(),
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
    native_relation_target_observation_capacity(provider, writable_fields)
    is Some(observation) &&
    // Original returned generation (one header/three words), immutable ACK
    // (one header/six borrowed references), and retained Some (one header/one
    // reference). A chained update also retains one original predecessor Some
    // (one header/reference/word); its ACK/body remain borrowed and backed by
    // the original caller, never copied or treated as new permission here.
    // Both child fields are in the shared metadata census. Also hold the
    // original typed update variant (one header/three references/one word)
    // and the ACK's operation flag (one scalar word).
    @execution.preparation_representation_cost({
      record_headers: 5L,
      reference_slots: 11L,
      scalar_words: 6L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(acknowledgment) else {
    return None
  }
  // Original receive/document storage is already in `construction`. Add the
  // submitted replacement and actual Writer+lock native storage beside it.
  // The FS Owner statically proves its lock payload fits its Writer layout.
  // At replacement the four concurrent name extents are the MoonBit target
  // UTF8, C target copy, retained exclusive-lock C name and temporary lock
  // comparison C name. Each is <=4 bytes per source UTF16 unit; the two lock
  // copies also retain the fixed suffix. The existing two staging-name extents
  // and terminators remain alongside them. This is live overlap, not spare
  // funding or a new allowance. Additional diagnostics retain C error/close-error,
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
      controls + observation + native + acknowledgment,
      controls + observation + native + acknowledgment,
    )
    is Some(extra) else {
    return None
  }
  let capacity = @execution.add_execution_capacity(construction, extra)
  if provider.ordered_key is Some(key) {
    guard capacity is Some(capacity) &&
      ordered_target_key_capacity(key, limits.page.max_bytes)
      is Some((tuple, _)) else {
      return None
    }
    @execution.add_execution_capacity(capacity, tuple)
  } else {
    capacity
  }
}

///|
/// Retain this child before advancing it. `update` contains the SAME expected
/// row version, checked changes wire and unique staging basename. It supplies
/// no approval or permission. An optional predecessor is the SAME provider
/// owner's actual earlier replacement ACK; retain its original backing until
/// this child returns. Generation and complete bytes must match before another
/// row can be projected or written. This does not reconstruct a lost ACK.
/// The prepared provider retains the original full
/// relation contract and physical selection; no second schema is admitted.
pub fn prepare_native_relation_file_target_io(
  provider : NativeRelationFilePreparedProvider,
  writable : Array[String],
  identity : String,
  update? : (String, String, String)? = None,
  predecessor? : NativeRelationFileReplacementAck? = None,
  before_response? : ((Int) -> Bool)? = None,
) -> Result[NativeRelationFileTargetIO, NativeRelationFileIssue] {
  prepare_native_relation_file_target_io_original(
    provider,
    writable,
    identity,
    update
    .map(value => UpdateTarget(value.0, value.1, value.2))
    .unwrap_or(ObserveTarget),
    predecessor~,
    before_response~,
  )
}

///|
/// Observe the exact DELETE row and its version before Preview. This child
/// has no field intent and cannot prepare or perform a replacement.
pub fn prepare_native_relation_file_delete_target_observation(
  provider : NativeRelationFilePreparedProvider,
  identity : String,
  before_response : (Int) -> Bool,
) -> Result[NativeRelationFileTargetIO, NativeRelationFileIssue] {
  prepare_native_relation_file_target_io_original(
    provider,
    [],
    identity,
    ObserveDeleteTarget,
    before_response=Some(before_response),
  )
}

///|
/// Same physical child for a checked update whose response backing is staged.
/// The callback runs before any lock/Reader/body and supplies no permission.
/// After it returns the owner locks and reobserves the original file, then
/// performs the unchanged typed expected-version and replacement checks.
/// The Saved Effect caller can pass its latest ACK for this same selected file
/// from the same application. That ACK binds only the observed file generation
/// and complete bytes, even if the prior row used another collection provider.
pub fn prepare_native_relation_file_target_update_io(
  provider : NativeRelationFilePreparedProvider,
  writable : Array[String],
  identity : String,
  update : (String, String, String),
  before_response : (Int) -> Bool,
  predecessor? : NativeRelationFileReplacementAck? = None,
) -> Result[NativeRelationFileTargetIO, NativeRelationFileIssue] {
  prepare_native_relation_file_target_io_original(
    provider,
    writable,
    identity,
    UpdateTarget(update.0, update.1, update.2),
    predecessor~,
    before_response=Some(before_response),
    staged_update=true,
  )
}

///|
/// Stage the original row deletion on the same locked replacement child.
/// The selected file and expected version still belong to the caller's claim.
pub fn prepare_native_relation_file_target_delete_io(
  provider : NativeRelationFilePreparedProvider,
  identity : String,
  expected_version : String,
  staging : String,
  before_response : (Int) -> Bool,
  predecessor? : NativeRelationFileReplacementAck? = None,
) -> Result[NativeRelationFileTargetIO, NativeRelationFileIssue] {
  prepare_native_relation_file_target_io_original(
    provider,
    [],
    identity,
    DeleteTarget(expected_version, staging),
    predecessor~,
    before_response=Some(before_response),
    staged_update=true,
  )
}

///|
/// Enter the existing locked file child with an already selected physical
/// Text key and the original mapped values. The Host still owns the original
/// claim and must admit the full insertion peak in before_response.
pub fn prepare_native_relation_file_target_insert_io(
  provider : NativeRelationFilePreparedProvider,
  identity : String,
  mapped_wire : String,
  staging : String,
  before_response : (Int) -> Bool,
  predecessor? : NativeRelationFileReplacementAck? = None,
) -> Result[NativeRelationFileTargetIO, NativeRelationFileIssue] {
  prepare_native_relation_file_target_io_original(
    provider,
    [],
    identity,
    InsertTarget(mapped_wire, staging),
    predecessor~,
    before_response=Some(before_response),
    staged_update=true,
  )
}

///|
fn native_relation_file_target_staging_name(
  provider : NativeRelationFilePreparedProvider,
  staging : String,
) -> Bool {
  file_capture_text(staging, 64) &&
  !staging.contains("/") &&
  staging != "." &&
  staging != ".." &&
  staging != provider.selection.name
}

///|
fn native_relation_file_target_write_names(
  provider : NativeRelationFilePreparedProvider,
  version : String,
  staging : String,
) -> Bool {
  file_capture_text(version, provider.limits.page.max_bytes) &&
  native_relation_file_target_staging_name(provider, staging)
}

///|
fn prepare_native_relation_file_target_io_original(
  provider : NativeRelationFilePreparedProvider,
  writable : Array[String],
  identity : String,
  mutation : NativeRelationFileTargetMutation,
  predecessor? : NativeRelationFileReplacementAck? = None,
  before_response? : ((Int) -> Bool)? = None,
  staged_update? : Bool = false,
  ordered_key? : @rows.RelationDocumentPreparedKey? = None,
) -> Result[NativeRelationFileTargetIO, NativeRelationFileIssue] {
  let matching_key = match (provider.ordered_key, ordered_key) {
    (None, None) => true
    (Some(expected), Some(selected)) => physical_equal(expected, selected)
    _ => false
  }
  guard matching_key else { return Err(ForeignOriginal) }
  let fieldless = mutation is ObserveDeleteTarget ||
    mutation is DeleteTarget(_, _) ||
    mutation is InsertTarget(_, _)
  if !file_capture_text(identity, provider.limits.page.max_bytes) ||
    writable.is_empty() != fieldless ||
    writable.length() > provider.limits.page.max_nodes ||
    (mutation is ObserveOptionalTarget && ordered_key is None) {
    return Err(InvalidInput)
  }
  match mutation {
    ObserveTarget | ObserveDeleteTarget | ObserveOptionalTarget => ()
    UpdateTarget(version, changes, staging) =>
      if !file_capture_text(changes, provider.limits.page.max_bytes) ||
        !native_relation_file_target_write_names(provider, version, staging) {
        return Err(InvalidInput)
      }
    DeleteTarget(version, staging) =>
      if !native_relation_file_target_write_names(provider, version, staging) {
        return Err(InvalidInput)
      }
    InsertTarget(mapped_wire, staging) =>
      if !file_capture_text(mapped_wire, provider.limits.page.max_bytes) ||
        !native_relation_file_target_staging_name(provider, staging) {
        return Err(InvalidInput)
      }
  }
  if predecessor is Some(prior) {
    let same_file = prior.provider.selection.directory ==
      provider.selection.directory &&
      prior.provider.selection.name == provider.selection.name
    if !mutation.writes() ||
      !(physical_equal(prior.provider, provider) || (staged_update && same_file)) {
      return Err(ForeignOriginal)
    }
  }
  // Private constructor selection only, never authority or funding evidence.
  // Keep the general entrance's original validation order and refusal.
  if !staged_update && mutation.writes() && before_response is Some(_) {
    return Err(InvalidInput)
  }
  let child : NativeRelationFileTargetIO = {
    original: None,
    provider,
    writable: writable.copy(),
    identity,
    mutation,
    ordered_key,
    before_response,
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
    replacement_ack: None,
    predecessor,
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
  if self.mutation.writes() && self.before_response is None {
    match
      root.acquire_exclusive_lock_with_custody(
        selection.name + ".actql-write.lock",
      ) {
      Ok(value) => self.lock = Some(value)
      Err(failure) => {
        self.rejected_lock = Some(failure)
        raise FileCaptureStop(Filesystem(failure.issue()))
      }
    }
  }
  let mut observed = file_require(
    root.observe_file(selection.name).map_err(issue => Filesystem(issue)),
  )
  self.observation = Some(observed)
  let generation = file_require(
    observed.generation().map_err(issue => Filesystem(issue)),
  )
  // Compare the actual open observation with the original Writer ACK before
  // creating a Reader. Equal path/content alone cannot replace its generation.
  if self.predecessor is Some(prior) &&
    (
      generation.device != prior.generation.device ||
      generation.inode != prior.generation.inode ||
      generation.size != prior.generation.size
    ) {
    raise FileCaptureStop(ForeignOriginal)
  }
  if generation.size < 0L ||
    generation.size > self.provider.limits.page.max_bytes.to_int64() {
    raise FileCaptureStop(FileLimit)
  }
  if self.before_response is Some(prepare) {
    if !prepare(generation.size.to_int()) {
      raise FileCaptureStop(Capacity)
    }
    // A quota callback may call out. No Reader/buffer is created from a
    // retired/replaced child, even after it returns true.
    if !self.same() ||
      !(self.phase is TargetPrepared) ||
      !(self.root is Some(actual) && physical_equal(actual, root)) ||
      !(self.observation is Some(actual) && physical_equal(actual, observed)) {
      raise FileCaptureStop(Unavailable)
    }
    self.before_response = None
    if self.mutation.writes() {
      // No external callback runs with this lock held. A fresh observation
      // after acquiring it must match the size/generation used for backing.
      match
        root.acquire_exclusive_lock_with_custody(
          selection.name + ".actql-write.lock",
        ) {
        Ok(value) => self.lock = Some(value)
        Err(failure) => {
          self.rejected_lock = Some(failure)
          raise FileCaptureStop(Filesystem(failure.issue()))
        }
      }
      let current = file_require(
        root.observe_file(selection.name).map_err(issue => Filesystem(issue)),
      )
      let actual = file_require(
        current.generation().map_err(issue => Filesystem(issue)),
      )
      if actual.device != generation.device ||
        actual.inode != generation.inode ||
        actual.size != generation.size ||
        !self.same() ||
        !(self.root is Some(original) && physical_equal(original, root)) {
        raise FileCaptureStop(ForeignOriginal)
      }
      observed = current
      self.observation = Some(current)
    }
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
  // Device/inode/size do not detect a stable in-place external edit. Reuse
  // these already received bytes, without another read or digest allocation.
  if self.predecessor is Some(prior) && bytes != prior.replacement {
    raise FileCaptureStop(ForeignOriginal)
  }
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
  if self.mutation is InsertTarget(mapped_wire, _) {
    let replacement = match self.ordered_key {
      Some(key) =>
        @rows.prepare_relation_target_insert_with_key(
          backing,
          key,
          selected.items_path,
          selected.key_path,
          self.identity,
          mapped_wire,
        )
      None =>
        @rows.prepare_relation_target_insert(
          backing,
          provider.prepared_contract,
          selected.items_path,
          selected.key_path,
          self.identity,
          mapped_wire,
        )
    }
    self.replacement = Some(
      file_require(replacement.map_err(issue => Document(issue))),
    )
    self.phase = TargetWriting
    return
  }
  let row = match self.ordered_key {
    Some(key) => {
      let original = file_require(
        @rows.project_relation_target_document_with_key(
          backing,
          provider.declaration,
          selected.resource,
          selected.items_path,
          selected.key_path,
          self.writable,
          key,
        ).map_err(issue => Document(issue)),
      )
      self.document = Some(@rows.relation_ordered_target_document(original))
      let tuple = file_require(
        @rows.admit_relation_target_key_wire(original, self.identity).map_err(issue => {
          Document(issue)
        }),
      )
      match
        file_require(
          @rows.find_relation_target_with_key(
            original,
            provider.declaration,
            tuple,
          ).map_err(issue => Document(issue)),
        ) {
        Some(row) => row
        None if self.mutation is ObserveOptionalTarget => {
          self.phase = TargetReady
          return
        }
        None => raise FileCaptureStop(Document(InvalidPage))
      }
    }
    None => {
      let document = file_require(
        @rows.project_relation_target_document(
          backing,
          provider.declaration,
          selected.resource,
          selected.items_path,
          selected.key_path,
          selected.primary_identity,
          self.writable,
          prepared_contract=Some(provider.prepared_contract),
        ).map_err(issue => Document(issue)),
      )
      self.document = Some(document)
      file_require(
        @rows.observe_relation_target(
          document,
          provider.declaration,
          self.identity,
        ).map_err(issue => Document(issue)),
      )
    }
  }
  let document = self.document.unwrap()
  self.row = Some(row)
  guard @rows.relation_target_before(row) is Some(before) &&
    @rows.relation_target_version(row) is Some(version) else {
    raise FileCaptureStop(ForeignOriginal)
  }
  self.observed_row = Some((before, version))
  match self.mutation {
    ObserveTarget | ObserveDeleteTarget | ObserveOptionalTarget =>
      self.phase = TargetReady
    UpdateTarget(expected, changes, _) => {
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
    DeleteTarget(expected, _) => {
      let output = file_require(
        @rows.prepare_relation_target_delete(
          document,
          row,
          expected,
          provider.limits.max_work,
        ).map_err(issue => Document(issue)),
      )
      self.replacement = Some(output)
      self.phase = TargetWriting
    }
    InsertTarget(_, _) => raise FileCaptureStop(Unavailable)
  }
}

///|
fn NativeRelationFileTargetIO::write(self : Self) -> Unit raise FileCaptureStop {
  if self.replacement_attempted {
    raise FileCaptureStop(Unavailable)
  }
  let (expected_version, changes_wire, staging, operation) = match
    self.mutation {
    UpdateTarget(version, changes, staging) =>
      (version, changes, staging, TargetUpdated)
    DeleteTarget(version, staging) => (version, "", staging, TargetDeleted)
    InsertTarget(mapped_wire, staging) =>
      ("", mapped_wire, staging, TargetInserted)
    ObserveTarget | ObserveDeleteTarget | ObserveOptionalTarget =>
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
  let generation = file_require(
    writer
    .replace_observed_file(self.observation.unwrap(), self.lock.unwrap())
    .map_err(issue => Filesystem(issue)),
  )
  // The FS Owner returns only after staging and directory synchronization and
  // generation confirmation. A post-rename failure never reaches this branch.
  self.replacement_ack = Some({
    provider: self.provider,
    identity: self.identity,
    expected_version,
    operation,
    changes_wire,
    replacement: output,
    generation,
  })
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
/// Original complete absence for UPSERT Preview. Unfinished, invalid or
/// retired observations return false.
pub fn NativeRelationFileTargetIO::target_absent(self : Self) -> Bool {
  self.same() &&
  self.phase is TargetReady &&
  self.issue is None &&
  self.mutation is ObserveOptionalTarget &&
  self.observed_row is None &&
  self.root is Some(root) &&
  root.require_current_original_read() is Ok(_)
}

///|
/// Preserve the same immutable physical ACK before retiring this child. The
/// receiving Host must retain/back it before close; it cannot infer success
/// from replacement_attempted, submitted bytes, current contents or cleanup.
pub fn NativeRelationFileTargetIO::replacement_acknowledgment(
  self : Self,
) -> NativeRelationFileReplacementAck? {
  if self.same() && self.phase is TargetReady && self.issue is None {
    self.replacement_ack
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
    (self.mutation is ObserveTarget || self.mutation is ObserveOptionalTarget) &&
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
    self.before_response = None
    self.replacement = None
    self.replacement_ack = None
    self.predecessor = None
    self.observed_row = None
    self.original = None
    self.phase = TargetClosed
    Ok(true)
  } catch {
    FileCaptureStop(issue) => Err(issue)
  }
}

///|
/// A read of this SAME prepared provider. Actual file size is original
/// filesystem observation DATA, not a changed page/contract guard or a grant.
/// None keeps its original maximum; zero backs pre-response controls only.
pub fn native_relation_file_target_read_io_capacity(
  provider : NativeRelationFilePreparedProvider,
  writable_fields : Int,
  response_bytes? : Int? = None,
  ordered_wire_utf16? : Int? = None,
) -> @execution.ExecutionCapacity? {
  guard writable_fields > 0 else { return None }
  native_relation_file_target_read_io_capacity_original(
    provider, writable_fields, response_bytes, ordered_wire_utf16,
  )
}

///|
/// Quote the same original guard-row observation with zero field intents.
pub fn native_relation_file_delete_target_read_io_capacity(
  provider : NativeRelationFilePreparedProvider,
  response_bytes? : Int? = None,
  ordered_wire_utf16? : Int? = None,
) -> @execution.ExecutionCapacity? {
  native_relation_file_target_read_io_capacity_original(
    provider, 0, response_bytes, ordered_wire_utf16,
  )
}

///|
fn native_relation_file_target_read_io_capacity_original(
  provider : NativeRelationFilePreparedProvider,
  writable_fields : Int,
  response_bytes : Int?,
  ordered_wire_utf16 : Int?,
) -> @execution.ExecutionCapacity? {
  let limits = provider.limits
  let project_ordered = provider.has_ordered_key() &&
    (response_bytes != Some(0) || ordered_wire_utf16 is Some(_))
  let contract = @rows.relation_document_prepared_contract(
    provider.prepared_contract,
  )
  let observation_page = if provider.has_ordered_key() &&
    response_bytes is Some(bytes) {
    {
      ..limits.page,
      max_bytes: native_ordered_target_before_wire_bound(
        contract,
        limits.page.max_bytes,
        bytes,
      ),
    }
  } else {
    limits.page
  }
  guard writable_fields <= limits.page.max_nodes &&
    file_capture_provider_capacity(
      provider.selection,
      limits,
      contract,
      prepared_contract=Some(provider.prepared_contract),
      response_bytes~,
      writable_fields~,
      ordered_projection=project_ordered,
      // The staged Target opens its Reader and allocates both file-sized
      // representations only after the original size callback admits them.
      // Chunk, Root/Reader and diagnostics retain the same fixed quote.
      measured_transport_bytes=response_bytes,
      measured_projection=if project_ordered {
        response_bytes.bind(bytes => {
          native_ordered_target_measured_projection(
            contract,
            limits.page,
            bytes,
          )
        })
      } else {
        None
      },
    )
    is Some(document) &&
    native_relation_file_target_read_fixed_capacity(provider, contract)
    is Some(fixed) &&
    native_relation_target_observation_capacity(
      provider,
      writable_fields,
      page=Some(observation_page),
    )
    is Some(observation) &&
    @execution.checked_preparation_add_product(fixed, observation, 1L)
    is Some(extra) &&
    @execution.execution_capacity(extra, extra) is Some(extra) else {
    return None
  }
  let ordinary = @execution.add_execution_capacity(document, extra)
  if project_ordered && provider.ordered_key is Some(key) {
    guard ordinary is Some(ordinary) &&
      @rows.relation_target_key_wire_workspace_inventory(
        key,
        ordered_wire_utf16.unwrap_or(limits.page.max_bytes),
      )
      is Some(units) &&
      @execution.preparation_representation_cost(units) is Some(bytes) &&
      @execution.execution_capacity(bytes, bytes) is Some(tuple) else {
      return None
    }
    @execution.add_execution_capacity(ordinary, tuple)
  } else {
    ordinary
  }
}

///|
fn native_relation_file_target_read_fixed_capacity(
  provider : NativeRelationFilePreparedProvider,
  contract : @contract.Contract,
) -> Int64? {
  let limits = provider.limits
  guard file_capture_metadata_capacity(
      provider.selection,
      limits,
      prepared_provider=Some(provider),
      response_quote_nodes=file_capture_text_contract_nodes(contract),
    )
    is Some(controls) &&
    native_relation_file_caller_preparation_inventory(
      provider.selection,
      limits,
      prepared_provider=Some(provider),
    )
    is Some(caller) &&
    @execution.compose_preparation_representation([
      caller,
      native_relation_file_caller_preparation_evaluation_inventory(
        provider.selection,
      ),
      { // Retained callback H1/R4, optional/callback products H3/R3/S3.
        record_headers: 4L,
        reference_slots: 7L,
        scalar_words: 3L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
    ])
    is Some(frontier) &&
    @execution.preparation_representation_cost(frontier) is Some(frontier) &&
    @execution.checked_preparation_add_product(controls, frontier, 1L)
    is Some(total) else {
    return None
  }
  Some(total)
}

///|
// The staged read starts with only the child, its Root/Observation, and the
// bounded selector check. The original size callback funds the Reader and all
// document, typed projection, and observation writer storage before they run.
pub fn native_ordered_target_capture_initial_capacity(
  provider : NativeRelationFilePreparedProvider,
  writable_fields : Int,
) -> @execution.ExecutionCapacity? {
  let limits = provider.limits
  let contract = @rows.relation_document_prepared_contract(
    provider.prepared_contract,
  )
  guard writable_fields >= 0 &&
    writable_fields <= limits.page.max_nodes &&
    native_ordered_target_selector_limits(provider) is Some(selector) &&
    @source.json_construction_extent(
      selector.max_input_bytes,
      selector.max_nodes,
      selector.max_depth,
      normalize_keys=true,
    )
    is Some(units) &&
    @execution.preparation_representation_cost({
      record_headers: units.record_headers,
      reference_slots: units.reference_slots,
      scalar_words: units.scalar_words,
      owned_utf16_units: units.owned_utf16_units,
      owned_wire_bytes: 0L,
    })
    is Some(selector_bytes) &&
    @files.native_filesystem_read_layout() is Some(layout) &&
    file_capture_transport_capacity(
      provider.selection,
      limits,
      layout,
      measured_transport_bytes=Some(0),
    )
    is Some(transport) &&
    native_relation_file_target_read_fixed_capacity(provider, contract)
    is Some(controls) &&
    @execution.preparation_array_representation(
      1L,
      writable_fields.to_int64(),
      false,
    )
    is Some(writable) &&
    @execution.preparation_representation_cost(writable) is Some(writable) &&
    @execution.checked_preparation_add_product(controls, transport, 1L)
    is Some(fixed) &&
    @execution.checked_preparation_add_product(fixed, writable, 1L)
    is Some(fixed) &&
    @execution.checked_preparation_add_product(fixed, selector_bytes, 1L)
    is Some(total) else {
    return None
  }
  @execution.execution_capacity(total, total)
}

///|
fn native_ordered_target_selector_limits(
  provider : NativeRelationFilePreparedProvider,
) -> @source.ParseLimits? {
  let page = provider.limits.page
  let contract = @rows.relation_document_prepared_contract(
    provider.prepared_contract,
  )
  guard provider.ordered_key is Some(_) &&
    contract.shape is @contract.Object(fields) &&
    page.max_depth >= 2 else {
    return None
  }
  let width = @contract.field_count(fields)
  let nodes = if width >= page.max_nodes { page.max_nodes } else { width + 1 }
  Some({ max_input_bytes: page.max_bytes, max_nodes: nodes, max_depth: 2, })
}

///|
/// Check the shape of the already captured selector before any physical Root
/// is opened. Canonical typed selection remains on the original document.
pub fn native_ordered_target_capture_selector_valid(
  provider : NativeRelationFilePreparedProvider,
  selector : String,
) -> Bool {
  guard native_ordered_target_selector_limits(provider) is Some(limits) else {
    return false
  }
  @source.parse_json(selector, limits) is Ok({ value: @source.Array(_), .. })
}

///|
// Raw spans and decoded Text are bounded by the observed bytes. A Signed64
// cell can expand when emitted in decimal and quoted (up to 22 bytes), so
// allow that many per original input byte, independently of NFC expansion.
// A flat closed projection introduces no nested nodes. Keep enough quote
// nodes for the declared field frontier even on an empty/malformed body.
fn native_ordered_target_measured_projection(
  contract : @contract.Contract,
  limits : @rows.RowPageLimits,
  response_bytes : Int,
) -> @rows.RowPageLimits? {
  guard !contract.nullable &&
    contract.shape is @contract.Object(fields) &&
    response_bytes >= 0 &&
    response_bytes <= limits.max_bytes else {
    return None
  }
  let width = @contract.field_count(fields)
  let mut signed64 = false
  for index in 0..<width {
    let field = @contract.field_at(fields, index).unwrap().contract
    if field.nullable {
      return None
    }
    match field.shape {
      @contract.Text(_) => ()
      @contract.Signed64 => signed64 = true
      _ => return None
    }
  }
  guard signed64 &&
    @canonical.nfc_lf_retained_output_units(response_bytes.to_int64())
    is Some(normalized) &&
    @execution.checked_preparation_add_product(
      response_bytes.to_int64(),
      normalized,
      6L,
    )
    is Some(text) &&
    @execution.checked_preparation_add_product(
      text,
      response_bytes.to_int64(),
      22L,
    )
    is Some(total) else {
    return None
  }
  Some({
    ..limits,
    max_bytes: Int64::min(limits.max_bytes.to_int64(), Int64::max(1L, total)).to_int(),
    max_nodes: Int::min(
      limits.max_nodes,
      Int::max(width, Int::max(1, response_bytes)),
    ),
  })
}

///|
// The ready Target emits one checked row. For flat Text/Int64, the original
// file size bounds all decoded text before normalization. Int64 is emitted as
// a quoted exact decimal, independently of the physical token spelling.
// This bounds the Before text buffer only; the document and write check keep
// their own inventories, and the actual writer retains all policy limits.
fn native_ordered_target_before_wire_bound(
  contract : @contract.Contract,
  max_bytes : Int,
  response_bytes : Int,
) -> Int {
  guard !contract.nullable &&
    contract.shape is @contract.Object(fields) &&
    @canonical.nfc_lf_retained_output_units(response_bytes.to_int64())
    is Some(normalized) else {
    return max_bytes
  }
  let width = @contract.field_count(fields)
  // Braces; two key quotes, colon and at most one comma per field; keys
  // may need six output bytes per UTF16 unit (bounded by their UTF8 bytes).
  // Field count is Int, so at most 26 bytes per field cannot overflow Int64.
  let mut bytes = 2L
  for index in 0..<width {
    let value = @contract.field_at(fields, index).unwrap().contract
    if value.nullable {
      return max_bytes
    }
    bytes += match value.shape {
      @contract.Text(_) => 6L
      @contract.Signed64 => 26L
      _ => return max_bytes
    }
  }
  guard @execution.checked_preparation_add_product(
      bytes,
      @contract.field_name_bytes(fields).to_int64(),
      6L,
    )
    is Some(with_keys) &&
    @execution.checked_preparation_add_product(with_keys, normalized, 6L)
    is Some(total) else {
    return max_bytes
  }
  Int64::min(max_bytes.to_int64(), total).to_int()
}

///|
fn native_relation_target_observation_capacity(
  provider : NativeRelationFilePreparedProvider,
  writable_fields : Int,
  page? : @rows.RowPageLimits? = None,
) -> Int64? {
  let limits = {
    ..provider.limits,
    page: page.unwrap_or(provider.limits.page),
  }
  guard @encode.text_writer_construction_inventory(
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
  @execution.checked_preparation_add_product(
    observation,
    @execution.preparation_representation_cost({
      record_headers: 0L,
      reference_slots: 1L,
      scalar_words: 0L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    }).unwrap(),
    1L,
  )
}
