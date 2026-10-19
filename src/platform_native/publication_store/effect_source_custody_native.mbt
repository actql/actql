///|
/// Cleanup custody in the existing Store, independent from completed capture
/// or approval. The payload lifecycle, physical pins and capacity remain owned
/// by PublicationPayload; this record associates that responsibility with the
/// original Run before the first payload allocation.
struct EffectSourceCustody {
  store : Store
  key : String
  request : @payload.PublicationPayloadRequest
  intent : Bytes
  terminal : Bytes
  physical_digest : String
  physical_bytes : Int64
}

///|
fn valid_effect_custody_digest(value : String) -> Bool {
  if value.length() != 71 || !value.has_prefix("sha256:") {
    return false
  }
  for index = 7; index < 71; index = index + 1 {
    let ch = value[index]
    if !((ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f')) {
      return false
    }
  }
  true
}

///|
fn effect_custody_body(
  store : Store,
  run : @publication.PublicationContract,
  source : @publication.CapturedEffectSourceArtifact,
  request : @payload.PublicationPayloadRequest,
  digest : String,
  bytes : Int64,
  complete : Bool,
) -> Result[Bytes, NativePublicationStoreIssue] {
  let request_wire = match @payload.publication_payload_request_json(request) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  let wire = match
    @publication.native_effect_source_custody_record_json(
      run,
      source,
      request_wire,
      store.authority_cid,
      digest,
      bytes,
      complete,
      store.max_record_bytes,
    ) {
    Ok(value) => value
    Err(_) => return Err(StateCollision)
  }
  Ok(@utf8.encode(wire))
}

///|
fn prepare_effect_custody(
  store : Store,
  run : @publication.PublicationContract,
  source : @publication.CapturedEffectSourceArtifact,
  request : @payload.PublicationPayloadRequest,
  digest : String,
  bytes : Int64,
) -> Result[EffectSourceCustody, NativePublicationStoreIssue] {
  if store.closed {
    return Err(Closed)
  }
  if store.retiring {
    return Err(CleanupPending)
  }
  guard @publication.captured_effect_source_payload_facts(source, run)
    is Some((logical, schema, rows, _)) else {
    return Err(StateCollision)
  }
  if @publication.captured_effect_source_store_authority_cid(source) !=
    store.authority_cid ||
    @payload.publication_payload_request_store_authority(request) !=
    store.authority_cid ||
    @payload.publication_payload_request_logical_relation(request) != logical ||
    @payload.publication_payload_request_schema(request) != schema ||
    @payload.publication_payload_request_row_count(request) != rows ||
    bytes < 0L ||
    bytes > @payload.publication_payload_request_max_bytes(request) ||
    !valid_effect_custody_digest(digest) {
    return Err(StateCollision)
  }
  let intent = match
    effect_custody_body(store, run, source, request, digest, bytes, false) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let terminal = match
    effect_custody_body(store, run, source, request, digest, bytes, true) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({
    store,
    key: record_key(request),
    request,
    intent,
    terminal,
    physical_digest: digest,
    physical_bytes: bytes,
  })
}

///|
fn EffectSourceCustody::record(
  self : EffectSourceCustody,
) -> Result[(@sqlite.NativeJournalValue, Bool), NativePublicationStoreIssue] {
  if self.store.closed {
    return Err(Closed)
  }
  if self.store.retiring {
    return Err(CleanupPending)
  }
  let value = match
    self.store.database.read("effect_source_custody", self.key) {
    Ok(value) => value
    Err(issue) => return Err(Database(issue))
  }
  if value.body == self.intent {
    Ok((value, false))
  } else if value.body == self.terminal {
    Ok((value, true))
  } else {
    Err(StateCollision)
  }
}

///|
/// Prepare exact cleanup responsibility without Store writes or allocations.
/// The caller must retain this owner through failed/uncertain persistence, and
/// reserve payload capacity with its existing execution Ledger before copying.
pub fn Store::prepare_effect_source_custody(
  self : Store,
  run : @publication.PublicationContract,
  source : @publication.CapturedEffectSourceArtifact,
  request : @payload.PublicationPayloadRequest,
  physical_digest : String,
  physical_bytes : Int64,
) -> Result[EffectSourceCustody, NativePublicationStoreIssue] {
  self.with_original_read(false, false, fn() {
    self.prepare_effect_source_custody_in_scope(
      run, source, request, physical_digest, physical_bytes,
    )
  })
}

///|
fn Store::prepare_effect_source_custody_in_scope(
  self : Store,
  run : @publication.PublicationContract,
  source : @publication.CapturedEffectSourceArtifact,
  request : @payload.PublicationPayloadRequest,
  physical_digest : String,
  physical_bytes : Int64,
) -> Result[EffectSourceCustody, NativePublicationStoreIssue] {
  match require_store_open(self) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  prepare_effect_custody(
    self, run, source, request, physical_digest, physical_bytes,
  )
}

///|
/// Retain this exact prepared responsibility. The caller keeps the same owner
/// on a failed or uncertain write and can retry it without another allocation.
pub fn EffectSourceCustody::retain(
  self : EffectSourceCustody,
) -> Result[Unit, NativePublicationStoreIssue] {
  self.store.with_original_read(false, false, fn() { self.retain_in_scope() })
}

///|
fn EffectSourceCustody::retain_in_scope(
  self : EffectSourceCustody,
) -> Result[Unit, NativePublicationStoreIssue] {
  if self.store.closed {
    return Err(Closed)
  }
  if self.store.retiring {
    return Err(CleanupPending)
  }
  observe(self.store, "effect-custody-before-intent")
  if self.store.closed {
    return Err(Closed)
  }
  if self.store.retiring {
    return Err(CleanupPending)
  }
  match
    allocation_prepare(self.store, "effect-custody-intent", () => {
      match
        self.store.database.insert(
          "effect_source_custody",
          self.key,
          self.intent,
        ) {
        Ok(_) | Err(@sqlite.Collision) => Ok(())
        Err(issue) => Err(Database(issue))
      }
    }) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  observe(self.store, "effect-custody-intent-saved")
  match self.record() {
    Ok((_, false)) => Ok(())
    Ok((_, true)) => Err(RecoveryRequired)
    Err(issue) => Err(issue)
  }
}

///|
/// Reopen the original responsibility by exact identity. This does not create
/// missing custody or authorize Source refetch, Compute or Effect execution.
pub fn Store::restore_effect_source_custody(
  self : Store,
  run : @publication.PublicationContract,
  source : @publication.CapturedEffectSourceArtifact,
  request : @payload.PublicationPayloadRequest,
  physical_digest : String,
  physical_bytes : Int64,
) -> Result[EffectSourceCustody, NativePublicationStoreIssue] {
  self.with_original_read(false, false, fn() {
    self.restore_effect_source_custody_in_scope(
      run, source, request, physical_digest, physical_bytes,
    )
  })
}

///|
fn Store::restore_effect_source_custody_in_scope(
  self : Store,
  run : @publication.PublicationContract,
  source : @publication.CapturedEffectSourceArtifact,
  request : @payload.PublicationPayloadRequest,
  physical_digest : String,
  physical_bytes : Int64,
) -> Result[EffectSourceCustody, NativePublicationStoreIssue] {
  match require_store_open(self) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let custody = match
    prepare_effect_custody(
      self, run, source, request, physical_digest, physical_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match custody.record() {
    Ok(_) => Ok(custody)
    Err(issue) => Err(issue)
  }
}

///|
pub fn EffectSourceCustody::begin_payload(
  self : EffectSourceCustody,
) -> Result[PayloadWriter, NativePublicationStoreIssue] {
  self.store.with_original_read(false, false, fn() {
    self.begin_payload_in_scope()
  })
}

///|
fn EffectSourceCustody::begin_payload_in_scope(
  self : EffectSourceCustody,
) -> Result[PayloadWriter, NativePublicationStoreIssue] {
  match self.record() {
    Ok((_, false)) => self.store.begin_payload_in_scope(self.request)
    Ok((_, true)) => Err(RecoveryRequired)
    Err(issue) => Err(issue)
  }
}

///|
/// Verify the sealed bytes and exact allocation generation in the existing
/// payload Owner. A sealed payload alone is not completed Effect capture.
pub fn EffectSourceCustody::confirm_payload(
  self : EffectSourceCustody,
) -> Result[NativePublicationPayloadInfo, NativePublicationStoreIssue] {
  self.store.with_original_read(false, false, fn() {
    self.confirm_payload_in_scope()
  })
}

///|
fn EffectSourceCustody::confirm_payload_in_scope(
  self : EffectSourceCustody,
) -> Result[NativePublicationPayloadInfo, NativePublicationStoreIssue] {
  match self.record() {
    Ok((_, false)) => ()
    Ok((_, true)) => return Err(RecoveryRequired)
    Err(issue) => return Err(issue)
  }
  let info = match self.store.reconcile_payload_in_scope(self.request) {
    Ok(Some(value)) => value
    Ok(None) => return Err(RecoveryRequired)
    Err(issue) => return Err(issue)
  }
  if info.physical_digest != self.physical_digest ||
    info.generation.size != self.physical_bytes {
    return Err(DigestMismatch)
  }
  Ok(info)
}

///|
pub fn EffectSourceCustody::open_reader(
  self : EffectSourceCustody,
) -> Result[PayloadReader, NativePublicationStoreIssue] {
  self.store.with_original_read(false, false, fn() {
    self.open_reader_in_scope()
  })
}

///|
fn EffectSourceCustody::open_reader_in_scope(
  self : EffectSourceCustody,
) -> Result[PayloadReader, NativePublicationStoreIssue] {
  match self.confirm_payload_in_scope() {
    Ok(_) => self.store.open_payload_reader_in_scope(self.key)
    Err(issue) => Err(issue)
  }
}

///|
pub fn EffectSourceCustody::cleanup_complete(
  self : EffectSourceCustody,
) -> Result[Bool, NativePublicationStoreIssue] {
  self.store.with_original_read(true, false, fn() {
    self.cleanup_complete_in_scope()
  })
}

///|
fn EffectSourceCustody::cleanup_complete_in_scope(
  self : EffectSourceCustody,
) -> Result[Bool, NativePublicationStoreIssue] {
  self.record().map(value => value.1)
}

///|
/// Retry the same payload cleanup, then persist completion. A reader/writer,
/// physical reclaim failure or failed terminal write keeps custody pending.
/// The existing payload Owner alone decides when its capacity may be returned.
pub fn EffectSourceCustody::retry_cleanup(
  self : EffectSourceCustody,
) -> Result[Bool, NativePublicationStoreIssue] {
  self.store.with_original_read(true, false, fn() {
    self.retry_cleanup_in_scope()
  })
}

///|
fn EffectSourceCustody::retry_cleanup_in_scope(
  self : EffectSourceCustody,
) -> Result[Bool, NativePublicationStoreIssue] {
  let record = match self.record() {
    Ok((_, true)) => return Ok(false)
    Ok((value, false)) => value
    Err(issue) => return Err(issue)
  }
  match self.store.acquire_payload_cleanup_in_scope(self.request) {
    Ok(cleanup) =>
      match cleanup.retry() {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
    Err(Database(@sqlite.NotFound)) =>
      // The payload Owner persists its intent before reservation/allocation and
      // never deletes that record. Absence plus no allocation means the saved
      // custody intent never acquired physical resources.
      match
        self.store.database.read("publication_payload_allocation", self.key) {
        Err(@sqlite.NotFound) => ()
        Ok(_) => return Err(RecoveryRequired)
        Err(issue) => return Err(Database(issue))
      }
    Err(issue) => return Err(issue)
  }
  observe(self.store, "effect-custody-before-terminal")
  if self.store.closed {
    return Err(Closed)
  }
  if self.store.retiring {
    return Err(CleanupPending)
  }
  match
    allocation_prepare(self.store, "effect-custody-terminal", () => {
      match
        self.store.database.compare_exchange(
          "effect_source_custody",
          self.key,
          record.revision,
          self.terminal,
        ) {
        Ok(_) => Ok(())
        Err(@sqlite.Collision) =>
          match self.record() {
            Ok((_, true)) => Ok(())
            Ok((_, false)) => Err(StateCollision)
            Err(issue) => Err(issue)
          }
        Err(issue) => Err(Database(issue))
      }
    }) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match self.record() {
    Ok((_, true)) => Ok(true)
    Ok((_, false)) => Err(RecoveryRequired)
    Err(issue) => Err(issue)
  }
}
