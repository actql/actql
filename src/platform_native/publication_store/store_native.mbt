///|
struct Store {
  root : @filesystem.Root
  database : @sqlite.Database
  authority_cid : String
  capacity_bytes : Int64
  max_objects : Int64
  max_record_bytes : Int
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
struct PayloadDelivery {
  reader : PayloadReader
  frames : @publication.DurableResultRowFrames
  serializer : @publication.ResultDeliverySerializer
  input_chunk_bytes : Int
  expected_rows : Int64
  max_delivery_bytes : Int64
  hash : @sha.Hasher
  mut queued_rows : Array[String]
  mut queued_index : Int
  mut pending : Bytes
  mut pending_offset : Int
  mut source_eof : Bool
  mut input_finished : Bool
  mut serializer_finished : Bool
  mut terminal : Bool
  mut produced_bytes : Int64
  mut emitted_bytes : Int64
  mut emitted_rows : Int64
  mut delivery_digest : String?
  mut closed : Bool
}

///|
struct ConfirmedPayloadDelivery {
  source : PayloadDelivery
  progress : @publication.DeliverySinkProgress
  mut closed : Bool
}

///|
struct ResultDelivery {
  store : Store
  source : ConfirmedPayloadDelivery
  index : @publication.PublicationContract
  manifest : @publication.PublicationContract
  grant : @publication.PublicationContract
  retention : @publication.PublicationContract
  result_name : String
  attempt : @publication.PublicationContract
  streaming : @publication.PublicationContract
  mut record_revision : Int64
  max_wire_bytes : Int
  max_nodes : Int
  max_depth : Int
  mut source_summary : NativePublicationDeliverySummary?
  mut failure_confirmed : Int64?
  mut terminal_observed_at : String
  mut succeeded : NativeResultDeliverySuccess?
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
  if capacity_bytes < 0L ||
    max_objects < 1L ||
    max_record_bytes < 1L ||
    max_record_bytes > 2147483647L {
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
    max_record_bytes: max_record_bytes.to_int(),
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
fn delivery(
  result : Result[String, @publication.DeliverySerializationIssue],
) -> Result[String, NativePublicationStoreIssue] {
  match result {
    Ok(value) => Ok(value)
    Err(issue) => Err(Delivery(issue))
  }
}

///|
fn[T] sink_progress(
  result : Result[T, @publication.DeliverySinkProgressIssue],
) -> Result[T, NativePublicationStoreIssue] {
  match result {
    Ok(value) => Ok(value)
    Err(issue) => Err(SinkProgress(issue))
  }
}

///|
fn[T] delivery_issuance(
  result : Result[T, @publication.DeliveryIssuanceIssue],
) -> Result[T, NativePublicationStoreIssue] {
  match result {
    Ok(value) => Ok(value)
    Err(issue) => Err(DeliveryIssuance(issue))
  }
}

///|
fn put_publication_contract(
  store : Store,
  contract : @publication.PublicationContract,
) -> Result[Unit, NativePublicationStoreIssue] {
  let identity = @publication.publication_contract_identity(contract)
  let body = @utf8.encode(@publication.publication_contract_json(contract))
  match store.database.insert("publication_contract", identity, body) {
    Ok(_) => Ok(())
    Err(@sqlite.Collision) => {
      let existing = match
        store.database.read("publication_contract", identity) {
        Ok(value) => value
        Err(issue) => return Err(Database(issue))
      }
      if existing.body == body {
        Ok(())
      } else {
        Err(StateCollision)
      }
    }
    Err(issue) => Err(Database(issue))
  }
}

///|
fn load_publication_contract(
  store : Store,
  name : String,
  identity : String,
) -> Result[@publication.PublicationContract, NativePublicationStoreIssue] {
  let stored = match store.database.read("publication_contract", identity) {
    Ok(value) => value
    Err(issue) => return Err(Database(issue))
  }
  let wire = @utf8.decode(stored.body) catch { _ => return Err(StateCollision) }
  let contract = match
    @publication.admit_publication_contract(
      name,
      wire,
      store.max_record_bytes,
      store.max_record_bytes,
      64,
    ) {
    Ok(value) => value
    Err(_) => return Err(StateCollision)
  }
  if @publication.publication_contract_identity(contract) != identity {
    return Err(StateCollision)
  }
  Ok(contract)
}

///|
/// Load and re-admit one exact publication contract from durable storage.
/// Callers must separately establish authority for the requested identity.
pub fn Store::read_publication_contract(
  self : Store,
  name : String,
  identity : String,
) -> Result[@publication.PublicationContract, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  load_publication_contract(self, name, identity)
}

///|
fn put_result_schema(
  store : Store,
  result_schema_cid : String,
  result_schema_wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, NativePublicationStoreIssue] {
  match
    delivery_issuance(
      @publication.validate_result_schema_wire(
        result_schema_cid, result_schema_wire, max_wire_bytes, max_nodes, max_depth,
      ),
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let body = @utf8.encode(result_schema_wire)
  match store.database.insert("result_schema", result_schema_cid, body) {
    Ok(_) => Ok(())
    Err(@sqlite.Collision) => {
      let existing = match
        store.database.read("result_schema", result_schema_cid) {
        Ok(value) => value
        Err(issue) => return Err(Database(issue))
      }
      if existing.body == body {
        Ok(())
      } else {
        Err(StateCollision)
      }
    }
    Err(issue) => Err(Database(issue))
  }
}

///|
/// Load and revalidate the canonical schema retained for a committed Result.
pub fn Store::read_result_schema(
  self : Store,
  result_schema_cid : String,
) -> Result[String, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  let stored = match self.database.read("result_schema", result_schema_cid) {
    Ok(value) => value
    Err(issue) => return Err(Database(issue))
  }
  let wire = @utf8.decode(stored.body) catch { _ => return Err(StateCollision) }
  match
    delivery_issuance(
      @publication.validate_result_schema_wire(
        result_schema_cid,
        wire,
        self.max_record_bytes,
        self.max_record_bytes,
        64,
      ),
    ) {
    Ok(_) => Ok(wire)
    Err(_) => Err(StateCollision)
  }
}

///|
fn publication_commit(
  result : Result[Unit, @publication.PublicationCommitIssue],
) -> Result[Unit, NativePublicationStoreIssue] {
  match result {
    Ok(_) => Ok(())
    Err(issue) => Err(PublicationCommit(issue))
  }
}

///|
fn publication_commit_key(
  result : Result[String, @publication.PublicationCommitIssuanceIssue],
) -> Result[String, NativePublicationStoreIssue] {
  match result {
    Ok(value) => Ok(value)
    Err(issue) => Err(PublicationCommitIssuance(issue))
  }
}

///|
/// Make one fully validated Run-bound publication visible. Semantic contracts
/// are durable before the single scoped index row is installed. An exact
/// retry returns the existing commit; a different publication for the same
/// scoped Run is a conflict.
pub fn Store::commit_publication(
  self : Store,
  run_definition : @publication.PublicationContract,
  invocation : @publication.PublicationContract,
  definitions : Array[@publication.PublicationContract],
  artifacts : Array[@publication.PublicationContract],
  derivations : Array[@publication.PublicationContract],
  orderings : Array[@publication.PublicationContract],
  retentions : Array[@publication.PublicationContract],
  bindings : Array[@publication.PublicationContract],
  binding_schema_wires : Array[String],
  manifest : @publication.PublicationContract,
  receipt : @publication.PublicationContract,
  captured_run : @publication.PublicationContract,
  request : @publication.PublicationContract,
  attempt : @publication.PublicationContract,
  index : @publication.PublicationContract,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[NativePublicationCommit, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  if bindings.length() != binding_schema_wires.length() {
    return Err(InvalidConfiguration)
  }
  match
    publication_commit(
      @publication.validate_effect_free_publication_commit_with_result_evidence(
        run_definition, invocation, definitions, artifacts, derivations, orderings,
        retentions, bindings, manifest, receipt, captured_run, request, attempt,
        index, max_wire_bytes, max_nodes, max_depth,
      ),
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  for index, binding in bindings {
    let projected = match
      delivery_issuance(
        @publication.project_durable_result_binding_read(binding),
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let info = match self.inspect_payload(projected.material_generation_cid) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if !info.physical_digest.has_prefix("sha256:") {
      return Err(DigestMismatch)
    }
    let facts : @publication.DeliveryPayloadFacts = {
      store_authority_cid: self.authority_cid,
      material_generation_cid: info.material_generation_cid,
      logical_result_cid: info.logical_relation_cid,
      result_schema_cid: info.result_schema_cid,
      ordering_evidence_cid: info.ordering_evidence_cid,
      codec_contract_cid: info.durable_codec_cid,
      result_fields: projected.result_fields,
      result_schema_wire: binding_schema_wires[index],
      row_count: info.row_count,
      byte_count: info.generation.size,
      physical_sha256: info.physical_digest[7:].to_owned(),
    }
    match
      delivery_issuance(
        @publication.validate_durable_result_binding_facts(
          binding, facts, max_wire_bytes, max_nodes, max_depth,
        ),
      ) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  let key = match
    publication_commit_key(
      @publication.publication_index_storage_key(
        index, max_wire_bytes, max_nodes, max_depth,
      ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let contracts : Array[@publication.PublicationContract] = [
    run_definition, invocation, manifest, receipt, captured_run, request, attempt,
  ]
  for
    values in [
      definitions, artifacts, derivations, orderings, retentions, bindings,
    ] {
    for contract in values {
      contracts.push(contract)
    }
  }
  contracts.push(index)
  for contract in contracts {
    match put_publication_contract(self, contract) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  for binding_index, binding in bindings {
    let projected = match
      delivery_issuance(
        @publication.project_durable_result_binding_read(binding),
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    match
      put_result_schema(
        self,
        projected.result_schema_cid,
        binding_schema_wires[binding_index],
        max_wire_bytes,
        max_nodes,
        max_depth,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  let identity = @publication.publication_contract_identity(index)
  let body = @utf8.encode(identity)
  match self.database.insert("public_index", key, body) {
    Ok(_) =>
      Ok({
        public_index_entry_cid: identity,
        committed: true,
        idempotent: false,
      })
    Err(@sqlite.Collision) => {
      let existing = match self.database.read("public_index", key) {
        Ok(value) => value
        Err(issue) => return Err(Database(issue))
      }
      if existing.body != body {
        return Err(PublicationCommitConflict)
      }
      Ok({
        public_index_entry_cid: identity,
        committed: false,
        idempotent: true,
      })
    }
    Err(issue) => Err(Database(issue))
  }
}

///|
/// Resolve one durably committed index after the caller has separately
/// authorized the scoped lookup. SQLite FULL durability makes a returned row
/// the confirmed commit boundary rather than a process-local observation.
pub fn Store::inspect_committed_publication(
  self : Store,
  tenant_id : String,
  authority_scope_cid : String,
  run_definition_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@publication.PublicationContract?, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  let key = match
    publication_commit_key(
      @publication.publication_index_scope_storage_key(
        tenant_id, authority_scope_cid, run_definition_cid, max_wire_bytes, max_nodes,
        max_depth,
      ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let stored = match self.database.read("public_index", key) {
    Ok(value) => value
    Err(@sqlite.NotFound) => return Ok(None)
    Err(issue) => return Err(Database(issue))
  }
  let identity = @utf8.decode(stored.body) catch {
    _ => return Err(StateCollision)
  }
  let index = match
    load_publication_contract(self, "public_index_entry", identity) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let actual_key = match
    publication_commit_key(
      @publication.publication_index_storage_key(
        index, max_wire_bytes, max_nodes, max_depth,
      ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if actual_key != key {
    return Err(StateCollision)
  }
  Ok(Some(index))
}

///|
fn require_committed_publication(
  store : Store,
  index : @publication.PublicationContract,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, NativePublicationStoreIssue] {
  let key = match
    publication_commit_key(
      @publication.publication_index_storage_key(
        index, max_wire_bytes, max_nodes, max_depth,
      ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let installed = match store.database.read("public_index", key) {
    Ok(value) => value
    Err(@sqlite.NotFound) => return Err(DeliveryAttemptUnresolved)
    Err(issue) => return Err(Database(issue))
  }
  let expected = @utf8.encode(@publication.publication_contract_identity(index))
  if installed.body != expected {
    return Err(PublicationCommitConflict)
  }
  Ok(())
}

///|
fn delivery_attempt_key(attempt_id : String) -> String {
  @sha.hex(@sha.digest(@utf8.encode(attempt_id)))
}

///|
fn claim_result_read_grant_use(
  store : Store,
  grant : @publication.PublicationContract,
  attempt : @publication.PublicationContract,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Bool, NativePublicationStoreIssue] {
  let scope = "result_read_grant_usage"
  let key = @publication.publication_contract_identity(grant)
  for _ in 0..<32 {
    let existing = match store.database.read(scope, key) {
      Ok(value) => Some(value)
      Err(@sqlite.NotFound) => None
      Err(@sqlite.Busy) => continue
      Err(issue) => return Err(Database(issue))
    }
    let existing_wire = match existing {
      Some(value) =>
        Some(@utf8.decode(value.body) catch { _ => return Err(StateCollision) })
      None => None
    }
    let claim = match
      @publication.prepare_delivery_grant_usage_claim(
        grant, existing_wire, attempt, max_wire_bytes, max_nodes, max_depth,
      ) {
      Ok(value) => value
      Err(issue) => return Err(DeliveryGrantUsage(issue))
    }
    if !@publication.delivery_grant_usage_claim_is_new(claim) {
      return Ok(false)
    }
    let body = @utf8.encode(@publication.delivery_grant_usage_claim_wire(claim))
    let committed = match existing {
      Some(value) =>
        store.database.compare_exchange(scope, key, value.revision, body)
      None => store.database.insert(scope, key, body)
    }
    match committed {
      Ok(_) => return Ok(true)
      Err(@sqlite.Collision) | Err(@sqlite.Busy) => continue
      Err(issue) => return Err(Database(issue))
    }
  }
  Err(Database(@sqlite.Busy))
}

///|
fn claim_delivery_attempt(
  store : Store,
  attempt_id : String,
  attempt : @publication.PublicationContract,
) -> Result[Unit, NativePublicationStoreIssue] {
  let identity = @publication.publication_contract_identity(attempt)
  match
    store.database.insert(
      "delivery_attempt",
      delivery_attempt_key(attempt_id),
      @utf8.encode(identity),
    ) {
    Ok(_) => Ok(())
    Err(@sqlite.Collision) => {
      let existing = match
        store.database.read(
          "delivery_attempt",
          delivery_attempt_key(attempt_id),
        ) {
        Ok(value) => value
        Err(issue) => return Err(Database(issue))
      }
      if existing.body == @utf8.encode(identity) {
        Err(ExistingDeliveryAttempt)
      } else {
        Err(StateCollision)
      }
    }
    Err(issue) => Err(Database(issue))
  }
}

///|
fn append_initial_delivery_record(
  store : Store,
  attempt : @publication.PublicationContract,
  record : @publication.PublicationContract,
) -> Result[Int64, NativePublicationStoreIssue] {
  match put_publication_contract(store, record) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let key = @publication.publication_contract_identity(attempt)
  let body = @utf8.encode(@publication.publication_contract_json(record))
  match store.database.insert("delivery_record_head", key, body) {
    Ok(revision) => Ok(revision)
    Err(@sqlite.Collision) => Err(DeliveryAttemptUnresolved)
    Err(issue) => Err(Database(issue))
  }
}

///|
fn append_next_delivery_record(
  store : Store,
  attempt : @publication.PublicationContract,
  expected_revision : Int64,
  record : @publication.PublicationContract,
) -> Result[Int64, NativePublicationStoreIssue] {
  match put_publication_contract(store, record) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let key = @publication.publication_contract_identity(attempt)
  let body = @utf8.encode(@publication.publication_contract_json(record))
  match
    store.database.compare_exchange(
      "delivery_record_head", key, expected_revision, body,
    ) {
    Ok(revision) => Ok(revision)
    Err(@sqlite.Collision) => {
      let existing = match store.database.read("delivery_record_head", key) {
        Ok(value) => value
        Err(issue) => return Err(Database(issue))
      }
      if existing.body == body {
        Ok(existing.revision)
      } else {
        Err(StateCollision)
      }
    }
    Err(issue) => Err(Database(issue))
  }
}

///|
fn queue_delivery_output(
  stream : PayloadDelivery,
  output : String,
) -> Result[Unit, NativePublicationStoreIssue] {
  let bytes = @utf8.encode(output)
  let size = bytes.length().to_int64()
  if size > stream.max_delivery_bytes - stream.produced_bytes {
    return Err(DeliveryLimit)
  }
  stream.produced_bytes += size
  stream.pending = bytes
  stream.pending_offset = 0
  Ok(())
}

///|
pub fn Store::open_payload_delivery(
  self : Store,
  material_generation_cid : String,
  format : String,
  schema_wire : String,
  fields : Array[String],
  input_chunk_bytes : Int,
  max_row_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_delivery_bytes : Int64,
) -> Result[PayloadDelivery, NativePublicationStoreIssue] {
  if input_chunk_bytes < 1 ||
    input_chunk_bytes > 16777216 ||
    max_row_bytes < 1 ||
    max_row_bytes > 16777216 ||
    max_delivery_bytes < 0L {
    return Err(InvalidConfiguration)
  }
  let info = match self.inspect_payload(material_generation_cid) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if info.generation.size < 0L ||
    info.generation.size > 2147483647L ||
    info.row_count < 0L ||
    info.row_count > 2147483647L {
    return Err(InvalidConfiguration)
  }
  let serializer = match
    @publication.prepare_result_delivery_serializer(
      format, schema_wire, fields, max_row_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Delivery(issue))
  }
  let frames = match
    @publication.prepare_durable_result_row_frames(
      info.generation.size.to_int(),
      info.row_count.to_int(),
      max_row_bytes,
      max_depth,
      input_chunk_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(RowFrame(issue))
  }
  let prefix = match delivery(@publication.begin_result_delivery(serializer)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let prefix_bytes = @utf8.encode(prefix)
  if prefix_bytes.length().to_int64() > max_delivery_bytes {
    return Err(DeliveryLimit)
  }
  let reader = match self.open_payload_reader(material_generation_cid) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({
    reader,
    frames,
    serializer,
    input_chunk_bytes,
    expected_rows: info.row_count,
    max_delivery_bytes,
    hash: @sha.hasher(),
    queued_rows: [],
    queued_index: 0,
    pending: prefix_bytes,
    pending_offset: 0,
    source_eof: false,
    input_finished: false,
    serializer_finished: false,
    terminal: false,
    produced_bytes: prefix_bytes.length().to_int64(),
    emitted_bytes: 0L,
    emitted_rows: 0L,
    delivery_digest: None,
    closed: false,
  })
}

///|
/// Open a delivery that keeps Store reads separate from sink confirmation.
/// `next` exposes at most one bounded chunk. The caller must confirm that
/// exact chunk before requesting another one, and must explicitly confirm the
/// sink's successful end even when the representation is empty.
pub fn Store::open_confirmed_payload_delivery(
  self : Store,
  material_generation_cid : String,
  format : String,
  schema_wire : String,
  fields : Array[String],
  input_chunk_bytes : Int,
  max_row_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_delivery_bytes : Int64,
) -> Result[ConfirmedPayloadDelivery, NativePublicationStoreIssue] {
  let source = match
    self.open_payload_delivery(
      material_generation_cid, format, schema_wire, fields, input_chunk_bytes, max_row_bytes,
      max_nodes, max_depth, max_delivery_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let progress = match
    sink_progress(
      @publication.prepare_delivery_sink_progress(max_delivery_bytes),
    ) {
    Ok(value) => value
    Err(issue) => {
      ignore(source.close())
      return Err(issue)
    }
  }
  Ok({ source, progress, closed: false, })
}

///|
fn fill_delivery_pending(
  stream : PayloadDelivery,
) -> Result[Unit, NativePublicationStoreIssue] {
  while stream.pending_offset == stream.pending.length() && !stream.terminal {
    stream.pending = b""
    stream.pending_offset = 0
    if stream.queued_index < stream.queued_rows.length() {
      let row = stream.queued_rows[stream.queued_index]
      stream.queued_index += 1
      let output = match
        delivery(@publication.next_result_delivery_row(stream.serializer, row)) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      stream.emitted_rows += 1L
      match queue_delivery_output(stream, output) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      continue
    }
    stream.queued_rows = []
    stream.queued_index = 0
    if stream.source_eof {
      if !stream.input_finished {
        let summary = match
          @publication.finish_durable_result_row_frames(stream.frames) {
          Ok(value) => value
          Err(issue) => return Err(RowFrame(issue))
        }
        match stream.reader.finish() {
          Ok(_) => ()
          Err(issue) => return Err(issue)
        }
        if summary.rows.to_int64() != stream.expected_rows ||
          stream.emitted_rows != stream.expected_rows {
          return Err(DeliveryIncomplete)
        }
        stream.input_finished = true
      }
      if !stream.serializer_finished {
        let suffix = match
          delivery(@publication.finish_result_delivery(stream.serializer)) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        stream.serializer_finished = true
        match queue_delivery_output(stream, suffix) {
          Ok(_) => ()
          Err(issue) => return Err(issue)
        }
        if stream.pending.length() == 0 {
          stream.terminal = true
        }
        continue
      }
      stream.terminal = true
      continue
    }
    let physical = match stream.reader.next(stream.input_chunk_bytes) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let rows = match
      @publication.feed_durable_result_row_frames(stream.frames, physical.bytes) {
      Ok(value) => value
      Err(issue) => return Err(RowFrame(issue))
    }
    stream.queued_rows = rows
    stream.source_eof = physical.eof
  }
  Ok(())
}

///|
pub fn PayloadDelivery::next(
  self : PayloadDelivery,
  max_bytes : Int,
) -> Result[NativePublicationDeliveryChunk, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  if max_bytes < 1 || max_bytes > 16777216 {
    return Err(InvalidConfiguration)
  }
  match fill_delivery_pending(self) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if self.pending_offset == self.pending.length() {
    return Ok({ bytes: b"", eof: self.terminal, })
  }
  let end = Int::min(self.pending.length(), self.pending_offset + max_bytes)
  let bytes = self.pending[self.pending_offset:end].to_owned()
  self.pending_offset = end
  self.emitted_bytes += bytes.length().to_int64()
  @sha.update(self.hash, bytes) catch {
    _ => return Err(StateCollision)
  }
  if self.serializer_finished && self.pending_offset == self.pending.length() {
    self.terminal = true
  }
  Ok({ bytes, eof: self.terminal, })
}

///|
pub fn PayloadDelivery::finish(
  self : PayloadDelivery,
) -> Result[NativePublicationDeliverySummary, NativePublicationStoreIssue] {
  if self.closed ||
    !self.terminal ||
    self.pending_offset != self.pending.length() ||
    self.emitted_bytes != self.produced_bytes {
    return Err(DeliveryIncomplete)
  }
  let digest = match self.delivery_digest {
    Some(value) => value
    None => {
      let value = "sha256:" +
        (@sha.finish_hex(self.hash) catch { _ => return Err(StateCollision) })
      self.delivery_digest = Some(value)
      value
    }
  }
  self.closed = true
  Ok({
    bytes: self.emitted_bytes,
    rows: self.emitted_rows,
    delivery_digest: digest,
  })
}

///|
pub fn PayloadDelivery::close(
  self : PayloadDelivery,
) -> Result[Unit, NativePublicationStoreIssue] {
  if self.closed {
    return Ok(())
  }
  if !self.input_finished {
    match self.reader.close() {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    @publication.cancel_durable_result_row_frames(self.frames)
  }
  self.closed = true
  Ok(())
}

///|
pub fn ConfirmedPayloadDelivery::next(
  self : ConfirmedPayloadDelivery,
  max_bytes : Int,
) -> Result[NativePublicationDeliveryChunk, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  match sink_progress(self.progress.prepare_next()) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let chunk = match self.source.next(max_bytes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match sink_progress(self.progress.offer(chunk.bytes, chunk.eof)) {
    Ok(_) => Ok(chunk)
    Err(issue) => Err(issue)
  }
}

///|
pub fn ConfirmedPayloadDelivery::confirm_chunk(
  self : ConfirmedPayloadDelivery,
) -> Result[Int64, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  sink_progress(self.progress.confirm_chunk())
}

///|
pub fn ConfirmedPayloadDelivery::fail_chunk(
  self : ConfirmedPayloadDelivery,
  confirmed_prefix_bytes : Int,
) -> Result[Int64, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  let confirmed = match
    sink_progress(self.progress.fail_chunk(confirmed_prefix_bytes)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match self.source.close() {
    Ok(_) => {
      self.closed = true
      Ok(confirmed)
    }
    Err(issue) => Err(issue)
  }
}

///|
pub fn ConfirmedPayloadDelivery::fail(
  self : ConfirmedPayloadDelivery,
) -> Result[Int64, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  let confirmed = match sink_progress(self.progress.fail()) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match self.source.close() {
    Ok(_) => {
      self.closed = true
      Ok(confirmed)
    }
    Err(issue) => Err(issue)
  }
}

///|
pub fn ConfirmedPayloadDelivery::confirm_sink_finished(
  self : ConfirmedPayloadDelivery,
) -> Result[NativePublicationDeliverySummary, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  let source = match self.source.finish() {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let confirmed = match sink_progress(self.progress.confirm_finished()) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if source.bytes != confirmed.confirmed_bytes ||
    source.delivery_digest != confirmed.delivered_sha256 {
    return Err(StateCollision)
  }
  self.closed = true
  Ok(source)
}

///|
pub fn ConfirmedPayloadDelivery::close(
  self : ConfirmedPayloadDelivery,
) -> Result[Unit, NativePublicationStoreIssue] {
  if self.closed {
    return Ok(())
  }
  match self.source.close() {
    Ok(_) => {
      self.closed = true
      Ok(())
    }
    Err(issue) => Err(issue)
  }
}

///|
/// Begin one formally admitted Result delivery. The immutable attempt and its
/// initial streaming record are durable before any payload byte is exposed.
pub fn Store::begin_result_delivery(
  self : Store,
  index : @publication.PublicationContract,
  manifest : @publication.PublicationContract,
  grant : @publication.PublicationContract,
  retention : @publication.PublicationContract,
  binding : @publication.PublicationContract,
  material_generation_cid : String,
  result_name : String,
  format : String,
  attempt_id : String,
  requested_at : String,
  schema_wire : String,
  fields : Array[String],
  input_chunk_bytes : Int,
  max_row_bytes : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_delivery_bytes : Int64,
) -> Result[ResultDelivery, NativePublicationStoreIssue] {
  if self.closed || max_delivery_bytes < 0L || max_delivery_bytes > 2147483647L {
    return Err(InvalidConfiguration)
  }
  match
    require_committed_publication(
      self, index, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if !@publication.result_read_grant_valid_at(grant, requested_at) ||
    !@publication.result_read_grant_allows_bytes(
      grant,
      max_delivery_bytes.to_int(),
    ) {
    return Err(DeliveryLimit)
  }
  let availability = match
    delivery_issuance(
      @publication.result_read_availability(
        manifest, result_name, retention, requested_at,
      ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if availability != "available" {
    return Err(DeliveryLimit)
  }
  let attempt = match
    delivery_issuance(
      @publication.issue_delivery_attempt(
        index, manifest, grant, result_name, format, attempt_id, requested_at, max_wire_bytes,
        max_nodes, max_depth,
      ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let info = match self.inspect_payload(material_generation_cid) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !info.physical_digest.has_prefix("sha256:") {
    return Err(DigestMismatch)
  }
  let facts : @publication.DeliveryPayloadFacts = {
    store_authority_cid: self.authority_cid,
    material_generation_cid,
    logical_result_cid: info.logical_relation_cid,
    result_schema_cid: info.result_schema_cid,
    ordering_evidence_cid: info.ordering_evidence_cid,
    codec_contract_cid: info.durable_codec_cid,
    result_fields: fields.copy(),
    result_schema_wire: schema_wire,
    row_count: info.row_count,
    byte_count: info.generation.size,
    physical_sha256: info.physical_digest[7:].to_owned(),
  }
  match
    delivery_issuance(
      @publication.validate_delivery_payload_binding(
        index, manifest, attempt, binding, facts, max_wire_bytes, max_nodes, max_depth,
      ),
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  for contract in [index, manifest, grant, retention, binding, attempt] {
    match put_publication_contract(self, contract) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  match
    claim_result_read_grant_use(
      self, grant, attempt, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match claim_delivery_attempt(self, attempt_id, attempt) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let streaming = match
    delivery_issuance(
      @publication.issue_delivery_record(
        attempt,
        None,
        "streaming",
        0,
        "exact",
        None,
        None,
        None,
        None,
        requested_at,
        [],
        max_wire_bytes,
        max_nodes,
        max_depth,
      ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let record_revision = match
    append_initial_delivery_record(self, attempt, streaming) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let source = match
    self.open_confirmed_payload_delivery(
      material_generation_cid, format, schema_wire, fields, input_chunk_bytes, max_row_bytes,
      max_nodes, max_depth, max_delivery_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({
    store: self,
    source,
    index,
    manifest,
    grant,
    retention,
    result_name,
    attempt,
    streaming,
    record_revision,
    max_wire_bytes,
    max_nodes,
    max_depth,
    source_summary: None,
    failure_confirmed: None,
    terminal_observed_at: "",
    succeeded: None,
    closed: false,
  })
}

///|
pub fn ResultDelivery::attempt_cid(self : ResultDelivery) -> String {
  @publication.publication_contract_identity(self.attempt)
}

///|
pub fn ResultDelivery::next(
  self : ResultDelivery,
  max_bytes : Int,
  observed_at : String,
) -> Result[NativePublicationDeliveryChunk, NativePublicationStoreIssue] {
  if self.closed || self.succeeded is Some(_) {
    return Err(Closed)
  }
  if !@publication.result_read_grant_valid_at(self.grant, observed_at) {
    return Err(DeliveryLimit)
  }
  let availability = match
    delivery_issuance(
      @publication.result_read_availability(
        self.manifest,
        self.result_name,
        self.retention,
        observed_at,
      ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if availability != "available" {
    return Err(DeliveryLimit)
  }
  self.source.next(max_bytes)
}

///|
pub fn ResultDelivery::confirm_chunk(
  self : ResultDelivery,
) -> Result[Int64, NativePublicationStoreIssue] {
  if self.closed || self.succeeded is Some(_) {
    return Err(Closed)
  }
  self.source.confirm_chunk()
}

///|
pub fn ResultDelivery::confirm_sink_finished(
  self : ResultDelivery,
  observed_at : String,
) -> Result[NativeResultDeliverySuccess, NativePublicationStoreIssue] {
  match self.succeeded {
    Some(value) => return Ok(value)
    None => ()
  }
  if self.closed {
    return Err(Closed)
  }
  if !@publication.result_read_grant_valid_at(self.grant, observed_at) {
    return Err(DeliveryLimit)
  }
  let availability = match
    delivery_issuance(
      @publication.result_read_availability(
        self.manifest,
        self.result_name,
        self.retention,
        observed_at,
      ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if availability != "available" {
    return Err(DeliveryLimit)
  }
  let summary = match self.source_summary {
    Some(value) => value
    None => {
      let value = match self.source.confirm_sink_finished() {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      self.source_summary = Some(value)
      value
    }
  }
  if !@publication.result_read_grant_allows_bytes(
      self.grant,
      summary.bytes.to_int(),
    ) {
    return Err(DeliveryLimit)
  }
  if self.terminal_observed_at.is_empty() {
    self.terminal_observed_at = observed_at
  }
  if !summary.delivery_digest.has_prefix("sha256:") {
    return Err(DigestMismatch)
  }
  let delivered_sha256 = summary.delivery_digest[7:].to_owned()
  let receipt = match
    delivery_issuance(
      @publication.issue_result_delivery_receipt(
        self.index,
        self.manifest,
        self.grant,
        self.attempt,
        summary.bytes.to_int(),
        delivered_sha256,
        self.max_wire_bytes,
        self.max_nodes,
        self.max_depth,
      ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match put_publication_contract(self.store, receipt) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let succeeded = match
    delivery_issuance(
      @publication.issue_delivery_record(
        self.attempt,
        Some(self.streaming),
        "succeeded",
        summary.bytes.to_int(),
        "exact",
        None,
        Some(delivered_sha256),
        Some(receipt),
        None,
        self.terminal_observed_at,
        [],
        self.max_wire_bytes,
        self.max_nodes,
        self.max_depth,
      ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  self.record_revision = match
    append_next_delivery_record(
      self.store,
      self.attempt,
      self.record_revision,
      succeeded,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match
    delivery_issuance(
      @publication.validate_delivery_success_evidence(
        self.attempt,
        receipt,
        succeeded,
      ),
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let result : NativeResultDeliverySuccess = {
    delivery_attempt_cid: @publication.publication_contract_identity(
      self.attempt,
    ),
    delivery_record_cid: @publication.publication_contract_identity(succeeded),
    result_delivery_receipt_cid: @publication.publication_contract_identity(
      receipt,
    ),
    confirmed_bytes: summary.bytes,
    delivered_sha256,
  }
  self.succeeded = Some(result)
  self.closed = true
  Ok(result)
}

///|
/// Terminate a failed or cancelled attempt after reporting the sink-confirmed
/// prefix of the one outstanding chunk, if any. The payload reader is stopped
/// before the terminal record is committed, while a durability failure keeps
/// this session retryable without reading or sending more payload.
pub fn ResultDelivery::terminate(
  self : ResultDelivery,
  confirmed_prefix_bytes : Int?,
  cancellation_observed : Bool,
  exposure : String,
  possible_unconfirmed_max_bytes : Int?,
  failure_cid : String?,
  observed_at : String,
) -> Result[NativeResultDeliveryFailure, NativePublicationStoreIssue] {
  if self.succeeded is Some(_) || self.closed {
    return Err(Closed)
  }
  let confirmed = match self.failure_confirmed {
    Some(value) => value
    None => {
      let value = match confirmed_prefix_bytes {
        Some(prefix) =>
          match self.source.fail_chunk(prefix) {
            Ok(value) => value
            Err(issue) => return Err(issue)
          }
        None =>
          match self.source.fail() {
            Ok(value) => value
            Err(issue) => return Err(issue)
          }
      }
      self.failure_confirmed = Some(value)
      value
    }
  }
  if confirmed > 2147483647L {
    return Err(InvalidConfiguration)
  }
  if self.terminal_observed_at.is_empty() {
    self.terminal_observed_at = observed_at
  }
  let action = @publication.prepare_delivery_failure_terminal(
    cancellation_observed,
  )
  let state = @publication.delivery_failure_terminal_state(action)
  let terminal = match
    delivery_issuance(
      @publication.issue_delivery_record(
        self.attempt,
        Some(self.streaming),
        state,
        confirmed.to_int(),
        exposure,
        possible_unconfirmed_max_bytes,
        None,
        None,
        failure_cid,
        self.terminal_observed_at,
        [],
        self.max_wire_bytes,
        self.max_nodes,
        self.max_depth,
      ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  self.record_revision = match
    append_next_delivery_record(
      self.store,
      self.attempt,
      self.record_revision,
      terminal,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  self.closed = true
  Ok({
    delivery_attempt_cid: @publication.publication_contract_identity(
      self.attempt,
    ),
    delivery_record_cid: @publication.publication_contract_identity(terminal),
    confirmed_bytes: confirmed,
    state,
  })
}

///|
pub fn ResultDelivery::close(
  self : ResultDelivery,
) -> Result[Unit, NativePublicationStoreIssue] {
  if self.closed {
    return Ok(())
  }
  match self.source.close() {
    Ok(_) => {
      self.closed = true
      Ok(())
    }
    Err(issue) => Err(issue)
  }
}

///|
/// Reconcile the latest durable terminal or unresolved fact for one delivery
/// occurrence after a process restart. This does not authorize a new delivery
/// or imply that its source material remains available.
pub fn Store::inspect_result_delivery(
  self : Store,
  attempt_id : String,
) -> Result[NativeResultDeliveryStatus, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  let mapped = match
    self.database.read("delivery_attempt", delivery_attempt_key(attempt_id)) {
    Ok(value) => value
    Err(issue) => return Err(Database(issue))
  }
  let attempt_cid = @utf8.decode(mapped.body) catch {
    _ => return Err(StateCollision)
  }
  let attempt = match
    load_publication_contract(self, "delivery_attempt", attempt_cid) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let head = match self.database.read("delivery_record_head", attempt_cid) {
    Ok(value) => value
    Err(issue) => return Err(Database(issue))
  }
  let record_wire = @utf8.decode(head.body) catch {
    _ => return Err(StateCollision)
  }
  let record = match
    @publication.admit_publication_contract(
      "delivery_record",
      record_wire,
      self.max_record_bytes,
      self.max_record_bytes,
      64,
    ) {
    Ok(value) => value
    Err(_) => return Err(StateCollision)
  }
  let projection = match
    delivery_issuance(@publication.project_delivery_record(record)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if projection.delivery_attempt_cid != attempt_cid {
    return Err(StateCollision)
  }
  match projection.result_delivery_receipt_cid {
    Some(receipt_cid) => {
      let receipt = match
        load_publication_contract(self, "result_delivery_receipt", receipt_cid) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      match
        delivery_issuance(
          @publication.validate_delivery_success_evidence(
            attempt, receipt, record,
          ),
        ) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
    }
    None => ()
  }
  Ok({
    delivery_attempt_cid: attempt_cid,
    delivery_record_cid: @publication.publication_contract_identity(record),
    state: projection.state,
    confirmed_bytes: projection.confirmed_byte_count,
    delivered_sha256: projection.delivered_sha256,
    result_delivery_receipt_cid: projection.result_delivery_receipt_cid,
  })
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
