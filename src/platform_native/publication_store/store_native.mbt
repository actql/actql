///|
struct Store {
  root : @filesystem.Root
  database : @sqlite.Database
  authority_cid : String
  capacity_bytes : Int64
  max_objects : Int64
  active_writers : Map[String, Bool]
  active_readers : Map[String, Int]
  mut closed : Bool
}

///|
struct PayloadWriter {
  store : Store
  record : @payload.PublicationPayloadRecord
  physical : @filesystem.Writer
  hash : @sha.Hasher
  mut sealed_generation : @payload.PublicationPayloadGeneration?
  mut sealed_digest : String
  mut closed : Bool
}

///|
struct PayloadReader {
  store : Store
  material_generation_cid : String
  physical : @filesystem.Reader
  hash : @sha.Hasher
  expected_digest : String
  mut closed : Bool
}

///|
fn[T] protocol(
  result : Result[T, @payload.PublicationPayloadIssue],
) -> Result[T, NativePublicationStoreIssue] {
  match result {
    Ok(value) => Ok(value)
    Err(issue) => Err(Protocol(issue))
  }
}

///|
fn[T] database(
  result : Result[T, @sqlite.NativeSqliteIssue],
) -> Result[T, NativePublicationStoreIssue] {
  match result {
    Ok(value) => Ok(value)
    Err(issue) => Err(Database(issue))
  }
}

///|
fn[T] filesystem(
  result : Result[T, @filesystem.NativeFilesystemIssue],
) -> Result[T, NativePublicationStoreIssue] {
  match result {
    Ok(value) => Ok(value)
    Err(issue) => Err(Filesystem(issue))
  }
}

///|
pub fn open_store(
  library : @sqlite.Library,
  root_path : String,
  authority_cid : String,
  capacity_bytes : Int64,
  max_objects : Int64,
  max_record_bytes : Int64,
) -> Result[Store, NativePublicationStoreIssue] {
  if capacity_bytes < 0L || max_objects < 1L || max_record_bytes < 1L {
    return Err(InvalidConfiguration)
  }
  let root = match @filesystem.open_root(root_path) {
    Ok(value) => value
    Err(issue) => return Err(Filesystem(issue))
  }
  let journal_path = root_path + "/.actql-publication.sqlite3"
  let database = match library.open_database(journal_path, max_record_bytes) {
    Ok(value) => value
    Err(issue) => return Err(Database(issue))
  }
  Ok({
    root,
    database,
    authority_cid,
    capacity_bytes,
    max_objects,
    active_writers: Map([]),
    active_readers: Map([]),
    closed: false,
  })
}

///|
fn record_key(request : @payload.PublicationPayloadRequest) -> String {
  @payload.publication_payload_material_identity(request)
}

///|
fn load_record(
  store : Store,
  key : String,
) -> Result[@payload.PublicationPayloadRecord, NativePublicationStoreIssue] {
  let value = match store.database.read("publication_payload", key) {
    Ok(value) => value
    Err(issue) => return Err(Database(issue))
  }
  let durable = match
    @payload.admit_durable_publication_payload_record(value.body) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  if @payload.durable_publication_payload_record_material_identity(durable) !=
    key ||
    @payload.durable_publication_payload_record_revision(durable).to_int64() !=
    value.revision {
    return Err(StateCollision)
  }
  protocol(@payload.restore_durable_publication_payload_record(durable))
}

///|
fn persist_transition(
  store : Store,
  transition : @payload.PublicationPayloadTransition,
) -> Result[@payload.PublicationPayloadRecord, NativePublicationStoreIssue] {
  let record = match
    protocol(@payload.publication_payload_transition_durable_json(transition)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let expected = @payload.publication_payload_transition_expected_revision(
    transition,
  ).to_int64()
  let key = @payload.publication_payload_transition_material_identity(
    transition,
  )
  let bytes = @utf8.encode(record)
  let durable = match
    store.database.compare_exchange("publication_payload", key, expected, bytes) {
    Ok(revision) => revision == expected + 1L
    Err(@sqlite.Collision) =>
      match store.database.read("publication_payload", key) {
        Ok(value) => value.revision == expected + 1L && value.body == bytes
        Err(issue) => return Err(Database(issue))
      }
    Err(issue) => return Err(Database(issue))
  }
  if !durable {
    return Err(StateCollision)
  }
  protocol(@payload.commit_publication_payload_transition(transition, true))
}

///|
fn filesystem_generation(
  generation : @payload.PublicationPayloadGeneration,
) -> @filesystem.NativeFileGeneration {
  { device: generation.device, inode: generation.inode, size: generation.size, }
}

///|
fn payload_generation(
  generation : @filesystem.NativeFileGeneration,
) -> @payload.PublicationPayloadGeneration {
  { device: generation.device, inode: generation.inode, size: generation.size, }
}

///|
fn discovered_generation(
  store : Store,
  request : @payload.PublicationPayloadRequest,
) -> Result[@payload.PublicationPayloadGeneration?, NativePublicationStoreIssue] {
  let staging = match
    store.root.inspect_generation(
      @payload.publication_payload_staging_name(request),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Filesystem(issue))
  }
  let committed = match
    store.root.inspect_generation(
      @payload.publication_payload_object_name(request),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Filesystem(issue))
  }
  match (staging, committed) {
    (Some(left), Some(right)) if left != right => Err(StateCollision)
    (Some(value), _) | (_, Some(value)) => Ok(Some(payload_generation(value)))
    (None, None) => Ok(None)
  }
}

///|
fn reclaim_record(
  store : Store,
  record : @payload.PublicationPayloadRecord,
) -> Result[Unit, NativePublicationStoreIssue] {
  let request = @payload.publication_payload_record_request(record)
  let key = record_key(request)
  if store.active_writers.contains(key) {
    return Err(CleanupPending)
  }
  if store.active_readers.get(key).unwrap_or(0) != 0 {
    return Err(ReaderBusy)
  }
  let state = @payload.publication_payload_record_state(record)
  if state == @payload.Reclaimed {
    match
      database(
        store.database.release_capacity(
          "publication_payload",
          key,
          @payload.publication_payload_request_max_bytes(request),
          1L,
        ),
      ) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    return Ok(())
  }
  let found = match discovered_generation(store, request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if state != @payload.Reclaiming {
    let transition = match
      protocol(
        @payload.prepare_publication_payload_reclaiming(
          record,
          discovered_generation=found,
        ),
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    match persist_transition(store, transition) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  } else {
    match (@payload.publication_payload_record_generation(record), found) {
      (Some(expected), Some(actual)) if expected != actual =>
        return Err(StateCollision)
      (None, Some(_)) => return Err(StateCollision)
      _ => ()
    }
  }
  if @payload.publication_payload_record_generation(record) is Some(generation) {
    let exact = filesystem_generation(generation)
    match
      filesystem(
        store.root.reclaim_generation(
          @payload.publication_payload_staging_name(request),
          exact,
        ),
      ) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    match
      filesystem(
        store.root.reclaim_generation(
          @payload.publication_payload_object_name(request),
          exact,
        ),
      ) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  match
    database(
      store.database.release_capacity(
        "publication_payload",
        key,
        @payload.publication_payload_request_max_bytes(request),
        1L,
      ),
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let transition = match
    protocol(@payload.prepare_publication_payload_reclaimed(record)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match persist_transition(store, transition) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  Ok(())
}

///|
fn cleanup_after_begin_failure(
  store : Store,
  record : @payload.PublicationPayloadRecord,
) -> Bool {
  reclaim_record(store, record) is Ok(_)
}

///|
pub fn Store::begin_payload(
  self : Store,
  request : @payload.PublicationPayloadRequest,
) -> Result[PayloadWriter, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  if @payload.publication_payload_request_store_authority(request) !=
    self.authority_cid {
    return Err(StateCollision)
  }
  let key = record_key(request)
  if self.active_writers.contains(key) {
    return Err(RecoveryRequired)
  }
  let record = @payload.prepare_publication_payload_record(request)
  let initial = match
    protocol(@payload.publication_payload_record_durable_json(record)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match
    self.database.insert("publication_payload", key, @utf8.encode(initial)) {
    Ok(revision) => if revision != 0L { return Err(StateCollision) }
    Err(@sqlite.Collision) => {
      let existing = match load_record(self, key) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      if @payload.publication_payload_request_identity(
          @payload.publication_payload_record_request(existing),
        ) !=
        @payload.publication_payload_request_identity(request) {
        return Err(StateCollision)
      }
      return if @payload.publication_payload_record_state(existing) ==
        @payload.Sealed {
        Err(ExistingPayload)
      } else {
        Err(RecoveryRequired)
      }
    }
    Err(issue) => return Err(Database(issue))
  }
  match
    self.database.reserve_capacity(
      "publication_payload",
      key,
      @payload.publication_payload_request_max_bytes(request),
      1L,
      self.capacity_bytes,
      self.max_objects,
    ) {
    Ok(_) => ()
    Err(issue) => {
      if !cleanup_after_begin_failure(self, record) {
        return Err(CleanupPending)
      }
      return Err(Database(issue))
    }
  }
  let reserved = match
    protocol(@payload.prepare_publication_payload_reserved(record)) {
    Ok(transition) =>
      match persist_transition(self, transition) {
        Ok(value) => value
        Err(issue) => {
          if !cleanup_after_begin_failure(self, record) {
            return Err(CleanupPending)
          }
          return Err(issue)
        }
      }
    Err(issue) => return Err(issue)
  }
  let writing = match
    protocol(@payload.prepare_publication_payload_writing(reserved)) {
    Ok(transition) =>
      match persist_transition(self, transition) {
        Ok(value) => value
        Err(issue) => {
          if !cleanup_after_begin_failure(self, record) {
            return Err(CleanupPending)
          }
          return Err(issue)
        }
      }
    Err(issue) => return Err(issue)
  }
  let physical = match
    self.root.create_writer(
      @payload.publication_payload_staging_name(request),
      @payload.publication_payload_request_max_bytes(request),
    ) {
    Ok(value) => value
    Err(issue) => {
      if !cleanup_after_begin_failure(self, writing) {
        return Err(CleanupPending)
      }
      return Err(Filesystem(issue))
    }
  }
  self.active_writers[key] = true
  Ok({
    store: self,
    record: writing,
    physical,
    hash: @sha.hasher(),
    sealed_generation: None,
    sealed_digest: "",
    closed: false,
  })
}

///|
pub fn PayloadWriter::append(
  self : PayloadWriter,
  chunk : Bytes,
) -> Result[Unit, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  match filesystem(self.physical.append(chunk)) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  @sha.update(self.hash, chunk) catch {
    _ => return Err(StateCollision)
  }
  Ok(())
}

///|
fn payload_info(
  record : @payload.PublicationPayloadRecord,
) -> Result[NativePublicationPayloadInfo, NativePublicationStoreIssue] {
  let request = @payload.publication_payload_record_request(record)
  let generation = match
    @payload.publication_payload_record_generation(record) {
    Some(value) => filesystem_generation(value)
    None => return Err(StateCollision)
  }
  Ok({
    material_generation_cid: @payload.publication_payload_material_identity(
      request,
    ),
    publication_attempt_cid: @payload.publication_payload_request_attempt(
      request,
    ),
    result_definition_cid: @payload.publication_payload_request_result_definition(
      request,
    ),
    logical_relation_cid: @payload.publication_payload_request_logical_relation(
      request,
    ),
    result_schema_cid: @payload.publication_payload_request_schema(request),
    ordering_evidence_cid: @payload.publication_payload_request_ordering_evidence(
      request,
    ),
    durable_codec_cid: @payload.publication_payload_request_codec(request),
    row_count: @payload.publication_payload_request_row_count(request),
    physical_digest: @payload.publication_payload_record_digest(record),
    object_name: @payload.publication_payload_object_name(request),
    generation,
  })
}

///|
pub fn PayloadWriter::seal(
  self : PayloadWriter,
) -> Result[NativePublicationPayloadInfo, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  if self.sealed_generation is None {
    let request = @payload.publication_payload_record_request(self.record)
    let physical = match
      filesystem(
        self.physical.seal(@payload.publication_payload_object_name(request)),
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let digest = @sha.finish_hex(self.hash) catch {
      _ => return Err(StateCollision)
    }
    self.sealed_generation = Some(payload_generation(physical))
    self.sealed_digest = "sha256:" + digest
  }
  let generation = self.sealed_generation.unwrap()
  let transition = match
    protocol(
      @payload.prepare_publication_payload_sealed(
        self.record,
        generation,
        self.sealed_digest,
      ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let record = match persist_transition(self.store, transition) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let key = record_key(@payload.publication_payload_record_request(record))
  ignore(self.store.active_writers.remove(key))
  self.closed = true
  payload_info(record)
}

///|
pub fn PayloadWriter::cancel(
  self : PayloadWriter,
) -> Result[Unit, NativePublicationStoreIssue] {
  if self.closed {
    return Ok(())
  }
  match filesystem(self.physical.cancel()) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let key = record_key(@payload.publication_payload_record_request(self.record))
  ignore(self.store.active_writers.remove(key))
  match reclaim_record(self.store, self.record) {
    Ok(_) => {
      self.closed = true
      Ok(())
    }
    Err(issue) => {
      self.store.active_writers[key] = true
      Err(issue)
    }
  }
}

///|
pub fn Store::inspect_payload(
  self : Store,
  material_generation_cid : String,
) -> Result[NativePublicationPayloadInfo, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  let record = match load_record(self, material_generation_cid) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if @payload.publication_payload_record_state(record) != @payload.Sealed {
    return Err(RecoveryRequired)
  }
  let info = match payload_info(record) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !self.root.verify_generation(info.object_name, info.generation) {
    return Err(Filesystem(@filesystem.GenerationMismatch))
  }
  Ok(info)
}

///|
pub fn Store::open_payload_reader(
  self : Store,
  material_generation_cid : String,
) -> Result[PayloadReader, NativePublicationStoreIssue] {
  let info = match self.inspect_payload(material_generation_cid) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let physical = match
    filesystem(self.root.open_reader(info.object_name, info.generation)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  self.active_readers[material_generation_cid] = self.active_readers
    .get(material_generation_cid)
    .unwrap_or(0) +
    1
  Ok({
    store: self,
    material_generation_cid,
    physical,
    hash: @sha.hasher(),
    expected_digest: info.physical_digest,
    closed: false,
  })
}

///|
pub fn PayloadReader::next(
  self : PayloadReader,
  max_bytes : Int,
) -> Result[@filesystem.NativeFileChunk, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  let chunk = match filesystem(self.physical.next(max_bytes)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  @sha.update(self.hash, chunk.bytes) catch {
    _ => return Err(StateCollision)
  }
  Ok(chunk)
}

///|
fn PayloadReader::release_pin(self : PayloadReader) -> Unit {
  let count = self.store.active_readers
    .get(self.material_generation_cid)
    .unwrap_or(0)
  if count <= 1 {
    ignore(self.store.active_readers.remove(self.material_generation_cid))
  } else {
    self.store.active_readers[self.material_generation_cid] = count - 1
  }
  self.closed = true
}

///|
pub fn PayloadReader::finish(
  self : PayloadReader,
) -> Result[Unit, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  match filesystem(self.physical.finish()) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let actual = "sha256:" +
    (@sha.finish_hex(self.hash) catch { _ => return Err(StateCollision) })
  self.release_pin()
  if actual != self.expected_digest {
    Err(DigestMismatch)
  } else {
    Ok(())
  }
}

///|
pub fn PayloadReader::close(
  self : PayloadReader,
) -> Result[Unit, NativePublicationStoreIssue] {
  if self.closed {
    return Ok(())
  }
  match filesystem(self.physical.close()) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  self.release_pin()
  Ok(())
}

///|
pub fn Store::reclaim_payload(
  self : Store,
  material_generation_cid : String,
) -> Result[Unit, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  let record = match load_record(self, material_generation_cid) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  reclaim_record(self, record)
}

///|
pub fn Store::recover(
  self : Store,
) -> Result[NativePublicationRecovery, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  if !self.active_writers.is_empty() || !self.active_readers.is_empty() {
    return Err(CleanupPending)
  }
  let mut cursor = ""
  let mut retained = 0
  let mut reclaimed = 0
  while true {
    let entry = match self.database.scan_after("publication_payload", cursor) {
      Ok(value) => value
      Err(@sqlite.NotFound) => break
      Err(issue) => return Err(Database(issue))
    }
    cursor = entry.key
    let durable = match
      @payload.admit_durable_publication_payload_record(entry.body) {
      Ok(value) => value
      Err(issue) => return Err(Protocol(issue))
    }
    if @payload.durable_publication_payload_record_material_identity(durable) !=
      entry.key ||
      @payload.durable_publication_payload_record_revision(durable).to_int64() !=
      entry.revision {
      return Err(StateCollision)
    }
    let record = match
      protocol(@payload.restore_durable_publication_payload_record(durable)) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    match @payload.publication_payload_record_state(record) {
      @payload.Sealed => {
        match self.inspect_payload(entry.key) {
          Ok(_) => ()
          Err(issue) => return Err(issue)
        }
        retained += 1
      }
      @payload.Reclaimed =>
        match
          database(
            self.database.release_capacity(
              "publication_payload",
              entry.key,
              @payload.publication_payload_request_max_bytes(
                @payload.publication_payload_record_request(record),
              ),
              1L,
            ),
          ) {
          Ok(_) => ()
          Err(issue) => return Err(issue)
        }
      _ => {
        match reclaim_record(self, record) {
          Ok(_) => ()
          Err(issue) => return Err(issue)
        }
        reclaimed += 1
      }
    }
  }
  Ok({ retained, reclaimed, })
}

///|
pub fn Store::capacity_usage(
  self : Store,
) -> Result[@sqlite.NativeCapacityUsage, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  database(self.database.capacity_usage("publication_payload"))
}

///|
pub fn Store::close(self : Store) -> Result[Bool, NativePublicationStoreIssue] {
  if self.closed {
    return Ok(false)
  }
  if !self.active_writers.is_empty() || !self.active_readers.is_empty() {
    return Err(CleanupPending)
  }
  match self.recover() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  self.database.close()
  self.closed = true
  Ok(true)
}
