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
fn delivery(
  result : Result[String, @publication.DeliverySerializationIssue],
) -> Result[String, NativePublicationStoreIssue] {
  match result {
    Ok(value) => Ok(value)
    Err(issue) => Err(Delivery(issue))
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
