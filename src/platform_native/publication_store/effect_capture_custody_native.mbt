///|
// The same Store transaction, encryption, reservation and cleanup path serves
// separately admitted Preview and computation custody. Only the typed factories
// below supply scope/body facts; this internal owner grants no execution rights.
priv struct PrivateEffectEvidenceCustody {
  store : Store
  crypto : @signature.Library
  key : Bytes
  mut envelope : Bytes
  reservation_bytes : Int64
  reservation_objects : Int64
  preparation : PrivateEvidencePreparation?
  terminal : Bytes
  capacity_key : String
  table : String
  holding : String
  kind : String
  semantic_cid : String
  mut wire : String
  step_prefix : String
  mut transaction_uncertain : Bool
}

///|
fn prepare_private_effect_custody(
  store : Store,
  holding : String,
  kind : String,
  semantic_cid : String,
  wire : String,
  table : String,
  step_prefix : String,
  terminal : String,
  crypto : @signature.Library,
  key : Bytes,
) -> Result[PrivateEffectEvidenceCustody, NativePublicationStoreIssue] {
  if store.closed {
    return Err(Closed)
  }
  if store.retiring {
    return Err(CleanupPending)
  }
  let owned_key = key[:].to_owned()
  let envelope = match
    crypto.seal_private_evidence(
      owned_key,
      kind,
      semantic_cid,
      @utf8.encode(wire),
    ) {
    Ok(value) => value
    Err(issue) => return Err(PrivateEvidence(issue))
  }
  if envelope.length() > store.max_record_bytes {
    return Err(InvalidConfiguration)
  }
  Ok({
    store,
    crypto,
    key: owned_key,
    envelope,
    reservation_bytes: envelope.length().to_int64(),
    reservation_objects: 1L,
    preparation: None,
    terminal: @utf8.encode(terminal),
    capacity_key: step_prefix + ":" + holding,
    table,
    holding,
    kind,
    semantic_cid,
    wire,
    step_prefix,
    transaction_uncertain: false,
  })
}

///|
fn PrivateEffectEvidenceCustody::same_binding(
  self : PrivateEffectEvidenceCustody,
  other : PrivateEffectEvidenceCustody,
) -> Bool {
  physical_equal(self.store, other.store) &&
  self.key == other.key &&
  self.table == other.table &&
  self.holding == other.holding &&
  self.kind == other.kind &&
  self.semantic_cid == other.semantic_cid &&
  self.wire == other.wire
}

///|
/// Independent encrypted computation capture, issued by the evidence Owner.
struct EffectCaptureCustody {
  private_custody : PrivateEffectEvidenceCustody
  binding : @publication.EffectCaptureHoldingBinding
}

///|
pub fn Store::prepare_effect_capture_custody(
  self : Store,
  binding : @publication.EffectCaptureHoldingBinding,
  crypto : @signature.Library,
  key : Bytes,
) -> Result[EffectCaptureCustody, NativePublicationStoreIssue] {
  self.with_original_read(false, false, fn() {
    self.prepare_effect_capture_custody_in_scope(binding, crypto, key)
  })
}

///|
fn Store::prepare_effect_capture_custody_in_scope(
  self : Store,
  binding : @publication.EffectCaptureHoldingBinding,
  crypto : @signature.Library,
  key : Bytes,
) -> Result[EffectCaptureCustody, NativePublicationStoreIssue] {
  match require_store_open(self) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if self.closed {
    return Err(Closed)
  }
  if @publication.effect_capture_holding_authority(binding) !=
    self.authority_cid {
    return Err(StateCollision)
  }
  let captured = @publication.effect_capture_holding_contract(binding)
  let cid = @publication.publication_contract_identity(captured)
  let terminal = "{\"cleanup_complete\":true,\"captured_run_cid\":\"" +
    cid +
    "\",\"version\":\"actql-native-effect-capture-custody/0.1\"}"
  prepare_private_effect_custody(
    self,
    @publication.effect_capture_holding_identity(binding),
    "effect_capture",
    cid,
    @publication.publication_contract_json(captured),
    "effect_capture_custody",
    "effect-capture",
    terminal,
    crypto,
    key,
  ).map(private_custody => { private_custody, binding, })
}

///|
pub fn EffectCaptureCustody::persist(
  self : EffectCaptureCustody,
) -> Result[Unit, NativePublicationStoreIssue] {
  self.private_custody.store.with_original_read(false, false, fn() {
    self.persist_in_scope()
  })
}

///|
fn EffectCaptureCustody::persist_in_scope(
  self : EffectCaptureCustody,
) -> Result[Unit, NativePublicationStoreIssue] {
  self.private_custody.persist()
}

///|
/// Read only this original computation; terminal capture cannot be resumed.
pub fn EffectCaptureCustody::confirm(
  self : EffectCaptureCustody,
) -> Result[@publication.PublicationContract, NativePublicationStoreIssue] {
  self.private_custody.store.with_original_read(false, false, fn() {
    self.confirm_in_scope()
  })
}

///|
fn EffectCaptureCustody::confirm_in_scope(
  self : EffectCaptureCustody,
) -> Result[@publication.PublicationContract, NativePublicationStoreIssue] {
  match self.private_custody.read() {
    Ok((_, false)) =>
      Ok(@publication.effect_capture_holding_contract(self.binding))
    Ok((_, true)) => Err(RecoveryRequired)
    Err(issue) => Err(issue)
  }
}

///|
pub fn Store::restore_effect_capture_custody(
  self : Store,
  binding : @publication.EffectCaptureHoldingBinding,
  crypto : @signature.Library,
  key : Bytes,
) -> Result[EffectCaptureCustody, NativePublicationStoreIssue] {
  self.with_original_read(false, false, fn() {
    self.restore_effect_capture_custody_in_scope(binding, crypto, key)
  })
}

///|
fn Store::restore_effect_capture_custody_in_scope(
  self : Store,
  binding : @publication.EffectCaptureHoldingBinding,
  crypto : @signature.Library,
  key : Bytes,
) -> Result[EffectCaptureCustody, NativePublicationStoreIssue] {
  match require_store_open(self) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let custody = match
    self.prepare_effect_capture_custody_in_scope(binding, crypto, key) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  custody.private_custody.read().map(_ => custody)
}

///|
pub fn EffectCaptureCustody::retry_cleanup(
  self : EffectCaptureCustody,
) -> Result[Bool, NativePublicationStoreIssue] {
  self.private_custody.store.with_original_read(true, false, fn() {
    self.retry_cleanup_in_scope()
  })
}

///|
fn EffectCaptureCustody::retry_cleanup_in_scope(
  self : EffectCaptureCustody,
) -> Result[Bool, NativePublicationStoreIssue] {
  self.private_custody.retry_cleanup()
}

///|
pub fn EffectCaptureCustody::reserved_bytes(
  self : EffectCaptureCustody,
) -> Int64 {
  self.private_custody.reserved_bytes()
}

///|
pub fn EffectCaptureCustody::same_binding(
  self : EffectCaptureCustody,
  other : EffectCaptureCustody,
) -> Bool {
  self.private_custody.same_binding(other.private_custody)
}

///|
/// Original target Preview custody remains independent of computation, Source
/// payload and public Result holdings. It supplies evidence, not approval.
struct EffectPreviewCustody {
  private_custody : PrivateEffectEvidenceCustody
  identity : @publication.EffectPreviewIdentity
}

///|
/// Admit the exact wire against the original opaque Preview and its authoring
/// scope before encryption or allocation. Semantic equality cannot replace a
/// different Run/authoring occurrence or overwrite different saved bytes.
pub fn Store::prepare_effect_preview_custody(
  self : Store,
  identity : @publication.EffectPreviewIdentity,
  wire : String,
  authoring_cid : String,
  store_authority : String,
  crypto : @signature.Library,
  key : Bytes,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[EffectPreviewCustody, NativePublicationStoreIssue] {
  self.with_original_read(false, false, fn() {
    self.prepare_effect_preview_custody_in_scope(
      identity, wire, authoring_cid, store_authority, crypto, key, max_bytes, max_nodes,
      max_depth,
    )
  })
}

///|
fn Store::prepare_effect_preview_custody_in_scope(
  self : Store,
  identity : @publication.EffectPreviewIdentity,
  wire : String,
  authoring_cid : String,
  store_authority : String,
  crypto : @signature.Library,
  key : Bytes,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[EffectPreviewCustody, NativePublicationStoreIssue] {
  match require_store_open(self) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if self.closed {
    return Err(Closed)
  }
  if store_authority != self.authority_cid {
    return Err(StateCollision)
  }
  let holding = match
    @publication.effect_preview_private_holding_cid(
      identity,
      self.authority_cid,
    ) {
    Some(value) => value
    None => return Err(InvalidConfiguration)
  }
  let admitted = match
    @publication.admit_effect_preview_identity(
      wire,
      @publication.effect_preview_run_identity(identity),
      authoring_cid,
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(PreviewAdmission(issue))
  }
  let cid = @publication.effect_preview_semantic_identity(identity)
  if @publication.effect_preview_semantic_identity(admitted) != cid ||
    @publication.effect_preview_private_holding_cid(
      admitted,
      self.authority_cid,
    ) !=
    Some(holding) {
    return Err(StateCollision)
  }
  let terminal = "{\"cleanup_complete\":true,\"effect_preview_cid\":\"" +
    cid +
    "\",\"version\":\"actql-native-effect-preview-custody/0.1\"}"
  prepare_private_effect_custody(
    self, holding, "effect_preview", cid, wire, "effect_preview_custody", "effect-preview",
    terminal, crypto, key,
  ).map(private_custody => { private_custody, identity, })
}

///|
pub fn Store::restore_effect_preview_custody(
  self : Store,
  identity : @publication.EffectPreviewIdentity,
  wire : String,
  authoring_cid : String,
  store_authority : String,
  crypto : @signature.Library,
  key : Bytes,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[EffectPreviewCustody, NativePublicationStoreIssue] {
  self.with_original_read(false, false, fn() {
    self.restore_effect_preview_custody_in_scope(
      identity, wire, authoring_cid, store_authority, crypto, key, max_bytes, max_nodes,
      max_depth,
    )
  })
}

///|
fn Store::restore_effect_preview_custody_in_scope(
  self : Store,
  identity : @publication.EffectPreviewIdentity,
  wire : String,
  authoring_cid : String,
  store_authority : String,
  crypto : @signature.Library,
  key : Bytes,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[EffectPreviewCustody, NativePublicationStoreIssue] {
  match require_store_open(self) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let custody = match
    self.prepare_effect_preview_custody_in_scope(
      identity, wire, authoring_cid, store_authority, crypto, key, max_bytes, max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  custody.private_custody.read().map(_ => custody)
}

///|
pub fn EffectPreviewCustody::persist(
  self : EffectPreviewCustody,
) -> Result[Unit, NativePublicationStoreIssue] {
  self.private_custody.store.with_original_read(false, false, fn() {
    self.persist_in_scope()
  })
}

///|
fn EffectPreviewCustody::persist_in_scope(
  self : EffectPreviewCustody,
) -> Result[Unit, NativePublicationStoreIssue] {
  self.private_custody.persist()
}

///|
/// Return the exact original target evidence only after authenticated readback.
/// This does not infer a waiting commit or current approval/send authority.
pub fn EffectPreviewCustody::confirm(
  self : EffectPreviewCustody,
) -> Result[
  (@publication.EffectPreviewIdentity, String),
  NativePublicationStoreIssue,
] {
  self.private_custody.store.with_original_read(false, false, fn() {
    self.confirm_in_scope()
  })
}

///|
fn EffectPreviewCustody::confirm_in_scope(
  self : EffectPreviewCustody,
) -> Result[
  (@publication.EffectPreviewIdentity, String),
  NativePublicationStoreIssue,
] {
  match self.private_custody.read() {
    Ok((_, false)) => Ok((self.identity, self.private_custody.wire))
    Ok((_, true)) => Err(RecoveryRequired)
    Err(issue) => Err(issue)
  }
}

///|
pub fn EffectPreviewCustody::retry_cleanup(
  self : EffectPreviewCustody,
) -> Result[Bool, NativePublicationStoreIssue] {
  self.private_custody.store.with_original_read(true, false, fn() {
    self.retry_cleanup_in_scope()
  })
}

///|
fn EffectPreviewCustody::retry_cleanup_in_scope(
  self : EffectPreviewCustody,
) -> Result[Bool, NativePublicationStoreIssue] {
  self.private_custody.retry_cleanup()
}

///|
pub fn EffectPreviewCustody::reserved_bytes(
  self : EffectPreviewCustody,
) -> Int64 {
  self.private_custody.reserved_bytes()
}

///|
pub fn EffectPreviewCustody::same_binding(
  self : EffectPreviewCustody,
  other : EffectPreviewCustody,
) -> Bool {
  self.private_custody.same_binding(other.private_custody)
}

///|
fn PrivateEffectEvidenceCustody::read(
  self : PrivateEffectEvidenceCustody,
) -> Result[(@sqlite.NativeJournalValue, Bool), NativePublicationStoreIssue] {
  if self.store.closed {
    return Err(Closed)
  }
  if self.store.retiring {
    return Err(CleanupPending)
  }
  if self.transaction_uncertain {
    return Err(CleanupPending)
  }
  let row = match
    self.store.database.read_with_body_limit(
      self.table,
      self.holding,
      self.reservation_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Database(issue))
  }
  if row.body == self.terminal {
    if row.revision != 0L && row.revision != 1L {
      return Err(StateCollision)
    }
    return Ok((row, true))
  }
  if row.revision != 0L ||
    (
      self.preparation is None &&
      row.body.length().to_int64() != self.reservation_bytes
    ) ||
    (
      self.preparation is Some(_) &&
      row.body.length().to_int64() > self.reservation_bytes
    ) {
    return Err(StateCollision)
  }
  let plain = match
    self.crypto.open_private_evidence(
      self.key,
      self.kind,
      self.semantic_cid,
      row.body,
    ) {
    Ok(value) => value
    Err(issue) => return Err(PrivateEvidence(issue))
  }
  if plain != @utf8.encode(self.wire) {
    return Err(StateCollision)
  }
  Ok((row, false))
}

///|
/// Reserve and persist atomically; confirm the encrypted bytes only after the
/// commit. Lost acknowledgements keep this owner and reconcile the same slot.
/// Existing ciphertext is reused rather than replaced by a fresh nonce.
fn PrivateEffectEvidenceCustody::persist(
  self : PrivateEffectEvidenceCustody,
) -> Result[Unit, NativePublicationStoreIssue] {
  if self.store.closed {
    return Err(Closed)
  }
  if self.store.retiring {
    return Err(CleanupPending)
  }
  if self.transaction_uncertain {
    return Err(CleanupPending)
  }
  let db = self.store.database
  match db.begin_immediate() {
    Ok(_) => ()
    Err(issue) => return Err(Database(issue))
  }
  let operation = () => {
    match self.confirm_preparation() {
      Ok(false) => ()
      Ok(true) => return Err(RecoveryRequired)
      Err(issue) => return Err(issue)
    }
    match self.read() {
      Ok((_, true)) => return Err(RecoveryRequired)
      Ok((_, false)) => ()
      Err(Database(@sqlite.NotFound)) => ()
      Err(issue) => return Err(issue)
    }
    match
      db.reserve_capacity_in_transaction(
        "publication_payload",
        self.capacity_key,
        self.reservation_bytes,
        self.reservation_objects,
        self.store.capacity_bytes,
        self.store.max_objects,
      ) {
      Ok(true) if self.preparation is Some(_) => return Err(StateCollision)
      Ok(_) => ()
      Err(issue) => return Err(Database(issue))
    }
    match
      allocation_prepare(self.store, self.step_prefix + "-before-persist", () => {
        match db.insert(self.table, self.holding, self.envelope) {
          Ok(_) | Err(@sqlite.Collision) => Ok(())
          Err(issue) => Err(Database(issue))
        }
      }) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    // A concurrent writer can have persisted the same admitted capture using
    // a different nonce. Authenticate its original bytes, not nonce equality.
    match self.read() {
      Ok((_, false)) => Ok(())
      Ok((_, true)) => Err(RecoveryRequired)
      Err(issue) => Err(issue)
    }
  }
  if operation() is Err(primary) {
    if db.rollback() is Err(cleanup) {
      self.transaction_uncertain = true
      return Err(PrivateCaptureRollback(primary, cleanup))
    }
    return Err(primary)
  }
  match db.commit() {
    Ok(_) => ()
    Err(issue) => {
      // End a transaction which may still be open. Do not replace uncertain
      // persistence with success; retain this exact owner for reconciliation.
      if db.rollback() is Err(cleanup) {
        self.transaction_uncertain = true
        return Err(PrivateCaptureRollback(Database(issue), cleanup))
      }
      return Err(Database(issue))
    }
  }
  observe(self.store, self.step_prefix + "-persisted")
  allocation_prepare(self.store, self.step_prefix + "-after-persist-readback", () => {
    match self.read() {
      Ok((_, false)) => Ok(())
      Ok((_, true)) => Err(RecoveryRequired)
      Err(issue) => Err(issue)
    }
  })
}

///|
/// Erase the active encrypted body and confirm the terminal record before
/// returning its exact Store reservation. Failure retains cleanup responsibility.
/// The tombstone prevents a later persist from reviving this original capture.
fn PrivateEffectEvidenceCustody::retry_cleanup(
  self : PrivateEffectEvidenceCustody,
) -> Result[Bool, NativePublicationStoreIssue] {
  let (row, complete) = match self.read() {
    Ok(value) => value
    Err(Database(@sqlite.NotFound)) => {
      // Fence an already prepared handle even when no capture was persisted.
      // INSERT and a competing persist serialize on the same durable slot.
      // If persistence won, read and retire that exact encrypted record below.
      match
        allocation_prepare(self.store, self.step_prefix + "-before-cleanup", () => {
          insert_owned_cleanup_record(
            self.store,
            self.table,
            self.holding,
            self.terminal,
          )
          .map(_ => ())
          .map_err(issue => Database(issue))
        }) {
        Ok(_) | Err(Database(@sqlite.Collision)) => ()
        Err(issue) => return Err(issue)
      }
      match self.read() {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
    }
    Err(issue) => return Err(issue)
  }
  if !complete {
    match
      allocation_prepare(self.store, self.step_prefix + "-before-cleanup", () => {
        self.store.database
        .compare_exchange(self.table, self.holding, row.revision, self.terminal)
        .map(_ => ())
        .map_err(issue => Database(issue))
      }) {
      Ok(_) | Err(Database(@sqlite.Collision)) => ()
      Err(issue) => return Err(issue)
    }
  }
  observe(self.store, self.step_prefix + "-terminal-saved")
  match self.read() {
    Ok((_, true)) => ()
    Ok((_, false)) => return Err(CleanupPending)
    Err(issue) => return Err(issue)
  }
  match self.retire_preparation() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match
    allocation_prepare(
      self.store,
      self.step_prefix + "-before-capacity-release",
      () => {
        self.store.database
        .release_capacity(
          "publication_payload",
          self.capacity_key,
          self.reservation_bytes,
          self.reservation_objects,
        )
        .map_err(issue => Database(issue))
      },
    ) {
    Ok(released) => Ok(released)
    Err(issue) => Err(issue)
  }
}

///|
fn PrivateEffectEvidenceCustody::reserved_bytes(
  self : PrivateEffectEvidenceCustody,
) -> Int64 {
  self.reservation_bytes
}

///|
/// Separate encrypted continuation and Checkpoint holdings. Both use the
/// existing Store transaction/reservation/retirement mechanism. Their common
/// Checkpoint identity is the scoped physical key, not a second lifecycle.
struct EffectCheckpointCustody {
  continuation : PrivateEffectEvidenceCustody
  checkpoint : PrivateEffectEvidenceCustody
  sealed_checkpoint : @checkpoint.SealedCheckpoint
}

///|
pub fn Store::prepare_effect_checkpoint_custody(
  self : Store,
  checkpoint : @checkpoint.SealedCheckpoint,
  continuation_wire : String,
  store_authority : String,
  crypto : @signature.Library,
  key : Bytes,
) -> Result[EffectCheckpointCustody, NativePublicationStoreIssue] {
  self.with_original_read(false, false, fn() {
    self.prepare_effect_checkpoint_custody_in_scope(
      checkpoint, continuation_wire, store_authority, crypto, key,
    )
  })
}

///|
fn Store::prepare_effect_checkpoint_custody_in_scope(
  self : Store,
  checkpoint : @checkpoint.SealedCheckpoint,
  continuation_wire : String,
  store_authority : String,
  crypto : @signature.Library,
  key : Bytes,
) -> Result[EffectCheckpointCustody, NativePublicationStoreIssue] {
  match require_store_open(self) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if self.closed {
    return Err(Closed)
  }
  if store_authority != self.authority_cid {
    return Err(StateCollision)
  }
  if "sha256:" + @sha.hex(@utf8.encode(continuation_wire)) !=
    checkpoint.checkpoint.continuation_state_cid {
    return Err(DigestMismatch)
  }
  guard checkpoint.checkpoint.subject is @checkpoint.RunUnit(..) &&
    checkpoint.checkpoint.kind == @checkpoint.EffectSet else {
    return Err(InvalidConfiguration)
  }
  let holding = checkpoint.checkpoint_cid
  let terminal = "{\"checkpoint_cid\":\"" +
    holding +
    "\",\"cleanup_complete\":true}"
  let continuation = match
    prepare_private_effect_custody(
      self,
      holding,
      "continuation_record",
      checkpoint.checkpoint.continuation_state_cid,
      continuation_wire,
      "effect_continuation_custody",
      "effect-continuation",
      terminal,
      crypto,
      key,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let physical_checkpoint = match
    prepare_private_effect_custody(
      self,
      holding,
      "checkpoint",
      holding,
      checkpoint.wire,
      "effect_checkpoint_custody",
      "effect-checkpoint",
      terminal,
      crypto,
      key,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({
    continuation,
    checkpoint: physical_checkpoint,
    sealed_checkpoint: checkpoint,
  })
}

///|
pub fn EffectCheckpointCustody::persist(
  self : EffectCheckpointCustody,
) -> Result[Unit, NativePublicationStoreIssue] {
  self.checkpoint.store.with_original_read(false, false, fn() {
    self.persist_in_scope()
  })
}

///|
fn EffectCheckpointCustody::persist_in_scope(
  self : EffectCheckpointCustody,
) -> Result[Unit, NativePublicationStoreIssue] {
  // Partial persistence is intentionally observable. The caller keeps both
  // handles/reservations until the exact pair is confirmed or retired.
  match self.continuation.persist() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  self.checkpoint.persist()
}

///|
pub fn EffectCheckpointCustody::confirm(
  self : EffectCheckpointCustody,
) -> Result[
  (@checkpoint.PersistedCheckpoint, String),
  NativePublicationStoreIssue,
] {
  self.checkpoint.store.with_original_read(false, false, fn() {
    self.confirm_in_scope()
  })
}

///|
fn EffectCheckpointCustody::confirm_in_scope(
  self : EffectCheckpointCustody,
) -> Result[
  (@checkpoint.PersistedCheckpoint, String),
  NativePublicationStoreIssue,
] {
  match self.continuation.read() {
    Ok((_, false)) => ()
    Ok((_, true)) => return Err(RecoveryRequired)
    Err(issue) => return Err(issue)
  }
  match self.checkpoint.read() {
    Ok((_, false)) => ()
    Ok((_, true)) => return Err(RecoveryRequired)
    Err(issue) => return Err(issue)
  }
  @checkpoint.confirm_checkpoint_persisted(
    self.sealed_checkpoint,
    self.checkpoint.wire,
  )
  .map(value => (value, self.continuation.wire))
  .map_err(issue => CheckpointEvidence(issue))
}

///|
/// Rebind physical handles for the exact original pair. Missing records are
/// allowed only as unfinished persistence, never as confirmation or a resume
/// permit. A terminal record remains terminal and can only finish cleanup.
pub fn Store::restore_effect_checkpoint_custody(
  self : Store,
  checkpoint : @checkpoint.SealedCheckpoint,
  continuation_wire : String,
  store_authority : String,
  crypto : @signature.Library,
  key : Bytes,
) -> Result[EffectCheckpointCustody, NativePublicationStoreIssue] {
  self.with_original_read(false, false, fn() {
    self.restore_effect_checkpoint_custody_in_scope(
      checkpoint, continuation_wire, store_authority, crypto, key,
    )
  })
}

///|
fn Store::restore_effect_checkpoint_custody_in_scope(
  self : Store,
  checkpoint : @checkpoint.SealedCheckpoint,
  continuation_wire : String,
  store_authority : String,
  crypto : @signature.Library,
  key : Bytes,
) -> Result[EffectCheckpointCustody, NativePublicationStoreIssue] {
  match require_store_open(self) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let custody = match
    self.prepare_effect_checkpoint_custody_in_scope(
      checkpoint, continuation_wire, store_authority, crypto, key,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  for physical in [custody.continuation, custody.checkpoint] {
    match physical.read() {
      Ok(_) | Err(Database(@sqlite.NotFound)) => ()
      Err(issue) => return Err(issue)
    }
  }
  Ok(custody)
}

///|
/// Read the original persisted continuation without candidate body bytes.
/// The caller selects the sealed Checkpoint from trusted original custody;
/// Store authority, AEAD role/CID, digest and final paired readback remain
/// mandatory. Unlike an unfinished-persist continuation, missing/retired
/// records cannot produce a confirmed handle. This grants no disclosure or
/// resume permission and makes no Store write or capacity reservation.
pub fn Store::effect_checkpoint_restore_construction(
  self : Store,
  checkpoint : @checkpoint.SealedCheckpoint,
) -> Result[
  (@sqlite.NativeJournalHeader, PrivateEvidenceCustodyConstruction),
  NativePublicationStoreIssue,
] {
  self.with_original_read(false, false, fn() {
    match require_store_open(self) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    guard checkpoint.checkpoint.subject is @checkpoint.RunUnit(..) &&
      checkpoint.checkpoint.kind == @checkpoint.EffectSet else {
      return Err(InvalidConfiguration)
    }
    // Scalar SQLite metadata only, before ciphertext, plaintext or JSON is
    // constructed. The coupled read below rechecks this exact revision/extent.
    let header = match
      self.database.observe_body_extent(
        "effect_continuation_custody",
        checkpoint.checkpoint_cid,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Database(issue))
    }
    if header.revision != 0L ||
      header.body_bytes <= 0L ||
      header.body_bytes > self.max_record_bytes.to_int64() {
      return Err(RecoveryRequired)
    }
    // A canonical encrypted envelope is larger than its plaintext. Until
    // authentication proves that envelope, charge its observed extent as an
    // upper bound, including malformed-envelope parsing and refusal.
    guard private_evidence_custody_construction(header.body_bytes.to_int())
      is Some(continuation) &&
      private_evidence_custody_wire_construction(checkpoint.wire)
      is Some(checkpoint_layout) else {
      return Err(InvalidConfiguration)
    }
    let a = continuation.retained
    let b = checkpoint_layout.retained
    let e = continuation.workspace
    let f = checkpoint_layout.workspace
    Ok(
      (
        header,
        {
          retained: {
            record_headers: a.record_headers + b.record_headers + 2L,
            reference_slots: a.reference_slots + b.reference_slots + 2L,
            scalar_words: a.scalar_words + b.scalar_words,
            // The newly decrypted continuation survives beside both restored
            // custody handles. The Checkpoint wire remains its original borrow.
            owned_utf16_units: a.owned_utf16_units +
            b.owned_utf16_units +
            header.body_bytes,
            owned_wire_bytes: a.owned_wire_bytes + b.owned_wire_bytes,
          },
          // Both conservative workspaces cover the pair's sequential confirm and
          // the first decrypted continuation while its wrappers are constructed.
          workspace: {
            record_headers: e.record_headers + f.record_headers,
            reference_slots: e.reference_slots + f.reference_slots,
            scalar_words: e.scalar_words + f.scalar_words,
            owned_utf16_units: e.owned_utf16_units + f.owned_utf16_units,
            owned_wire_bytes: e.owned_wire_bytes + f.owned_wire_bytes,
          },
          envelope_bytes: Int::max(
            continuation.envelope_bytes,
            checkpoint_layout.envelope_bytes,
          ),
        },
      ),
    )
  })
}

///|
/// Observe construction first when restoring under a funded caller. An exact
/// extent is a bounded-read precondition, never custody, capacity or authority.
pub fn Store::restore_confirmed_effect_checkpoint_custody(
  self : Store,
  checkpoint : @checkpoint.SealedCheckpoint,
  store_authority : String,
  crypto : @signature.Library,
  key : Bytes,
  continuation_extent? : @sqlite.NativeJournalHeader? = None,
) -> Result[EffectCheckpointCustody, NativePublicationStoreIssue] {
  self.with_original_read(false, false, fn() {
    self.restore_confirmed_effect_checkpoint_custody_in_scope(
      checkpoint,
      store_authority,
      crypto,
      key,
      continuation_extent~,
    )
  })
}

///|
fn Store::restore_confirmed_effect_checkpoint_custody_in_scope(
  self : Store,
  checkpoint : @checkpoint.SealedCheckpoint,
  store_authority : String,
  crypto : @signature.Library,
  key : Bytes,
  continuation_extent? : @sqlite.NativeJournalHeader? = None,
) -> Result[EffectCheckpointCustody, NativePublicationStoreIssue] {
  match require_store_open(self) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if self.closed {
    return Err(Closed)
  }
  if store_authority != self.authority_cid {
    return Err(StateCollision)
  }
  guard checkpoint.checkpoint.subject is @checkpoint.RunUnit(..) &&
    checkpoint.checkpoint.kind == @checkpoint.EffectSet else {
    return Err(InvalidConfiguration)
  }
  let holding = checkpoint.checkpoint_cid
  let observed = match continuation_extent {
    Some(header) =>
      self.database.read_exact_body_extent(
        "effect_continuation_custody", holding, header,
      )
    None =>
      self.database.read_with_body_limit(
        "effect_continuation_custody",
        holding,
        self.max_record_bytes.to_int64(),
      )
  }
  let row = match observed {
    Ok(value) => value
    Err(issue) => return Err(Database(issue))
  }
  let terminal = "{\"checkpoint_cid\":\"" +
    holding +
    "\",\"cleanup_complete\":true}"
  if row.body == @utf8.encode(terminal) {
    if row.revision != 0L && row.revision != 1L {
      return Err(StateCollision)
    }
    return Err(RecoveryRequired)
  }
  if row.revision != 0L {
    return Err(StateCollision)
  }
  let plain = match
    crypto.open_private_evidence(
      key,
      "continuation_record",
      checkpoint.checkpoint.continuation_state_cid,
      row.body,
    ) {
    Ok(value) => value
    Err(issue) => return Err(PrivateEvidence(issue))
  }
  let original_wire = match
    original_effect_checkpoint_continuation(
      checkpoint,
      plain,
      self.max_record_bytes.to_int64(),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let custody = match
    self.restore_effect_checkpoint_custody_in_scope(
      checkpoint, original_wire, store_authority, crypto, key,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // Recheck both original records after decryption/preparation. Partial writes
  // and concurrent retirement stay unconfirmed; no replacement persist runs.
  custody.confirm_in_scope().map(_ => custody)
}

///|
pub fn EffectCheckpointCustody::retry_cleanup(
  self : EffectCheckpointCustody,
) -> Result[Bool, NativePublicationStoreIssue] {
  self.checkpoint.store.with_original_read(true, false, fn() {
    self.retry_cleanup_in_scope()
  })
}

///|
fn EffectCheckpointCustody::retry_cleanup_in_scope(
  self : EffectCheckpointCustody,
) -> Result[Bool, NativePublicationStoreIssue] {
  let checkpoint = match self.checkpoint.retry_cleanup() {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  self.continuation.retry_cleanup().map(value => value || checkpoint)
}

///|
pub fn EffectCheckpointCustody::reserved_bytes(
  self : EffectCheckpointCustody,
) -> Int64 {
  self.checkpoint.reserved_bytes() + self.continuation.reserved_bytes()
}

///|
pub fn EffectCheckpointCustody::same_binding(
  self : EffectCheckpointCustody,
  other : EffectCheckpointCustody,
) -> Bool {
  self.checkpoint.same_binding(other.checkpoint) &&
  self.continuation.same_binding(other.continuation)
}
