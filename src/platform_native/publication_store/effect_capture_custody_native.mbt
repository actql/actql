///|
/// One encrypted private capture in the existing Store/SQLite capacity scope.
/// Public Result payloads and Source holdings retain independent responsibility.
/// No waiting Run, approval or Effect outcome is inferred from this record.
struct EffectCaptureCustody {
  store : Store
  binding : @publication.EffectCaptureHoldingBinding
  crypto : @signature.Library
  key : Bytes
  envelope : Bytes
  terminal : Bytes
  capacity_key : String
  mut transaction_uncertain : Bool
}

///|
pub fn Store::prepare_effect_capture_custody(
  self : Store,
  binding : @publication.EffectCaptureHoldingBinding,
  crypto : @signature.Library,
  key : Bytes,
) -> Result[EffectCaptureCustody, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  if @publication.effect_capture_holding_authority(binding) !=
    self.authority_cid {
    return Err(StateCollision)
  }
  let captured = @publication.effect_capture_holding_contract(binding)
  let owned_key = key[:].to_owned()
  let envelope = match
    crypto.seal_private_evidence(
      owned_key,
      "effect_capture",
      @publication.publication_contract_identity(captured),
      @utf8.encode(@publication.publication_contract_json(captured)),
    ) {
    Ok(value) => value
    Err(issue) => return Err(PrivateEvidence(issue))
  }
  if envelope.length() > self.max_record_bytes {
    return Err(InvalidConfiguration)
  }
  let terminal = @utf8.encode(
    "{\"cleanup_complete\":true,\"captured_run_cid\":\"" +
    @publication.publication_contract_identity(captured) +
    "\",\"version\":\"actql-native-effect-capture-custody/0.1\"}",
  )
  Ok({
    store: self,
    binding,
    crypto,
    key: owned_key,
    envelope,
    terminal,
    capacity_key: "effect-capture:" +
    @publication.effect_capture_holding_identity(binding),
    transaction_uncertain: false,
  })
}

///|
fn EffectCaptureCustody::read(
  self : EffectCaptureCustody,
) -> Result[(@sqlite.NativeJournalValue, Bool), NativePublicationStoreIssue] {
  if self.store.closed {
    return Err(Closed)
  }
  if self.transaction_uncertain {
    return Err(CleanupPending)
  }
  let row = match
    self.store.database.read(
      "effect_capture_custody",
      @publication.effect_capture_holding_identity(self.binding),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Database(issue))
  }
  if row.body == self.terminal {
    if row.revision != 1L {
      return Err(StateCollision)
    }
    return Ok((row, true))
  }
  if row.revision != 0L || row.body.length() != self.envelope.length() {
    return Err(StateCollision)
  }
  let capture = @publication.effect_capture_holding_contract(self.binding)
  let plain = match
    self.crypto.open_private_evidence(
      self.key,
      "effect_capture",
      @publication.publication_contract_identity(capture),
      row.body,
    ) {
    Ok(value) => value
    Err(issue) => return Err(PrivateEvidence(issue))
  }
  if plain != @utf8.encode(@publication.publication_contract_json(capture)) {
    return Err(StateCollision)
  }
  Ok((row, false))
}

///|
/// Reserve and persist atomically; confirm the encrypted bytes only after the
/// commit. Lost acknowledgements keep this owner and reconcile the same slot.
/// Existing ciphertext is reused rather than replaced by a fresh nonce.
pub fn EffectCaptureCustody::persist(
  self : EffectCaptureCustody,
) -> Result[Unit, NativePublicationStoreIssue] {
  if self.store.closed {
    return Err(Closed)
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
        self.envelope.length().to_int64(),
        1L,
        self.store.capacity_bytes,
        self.store.max_objects,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(Database(issue))
    }
    match
      allocation_prepare(self.store, "effect-capture-before-persist", () => {
        match
          db.insert(
            "effect_capture_custody",
            @publication.effect_capture_holding_identity(self.binding),
            self.envelope,
          ) {
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
  observe(self.store, "effect-capture-persisted")
  self.confirm().map(_ => ())
}

///|
/// Read/decrypt only the existing exact capture. It cannot fill missing input,
/// create a new Run or authorize a resume. A terminal capture is unavailable.
pub fn EffectCaptureCustody::confirm(
  self : EffectCaptureCustody,
) -> Result[@publication.PublicationContract, NativePublicationStoreIssue] {
  match self.read() {
    Ok((_, false)) =>
      Ok(@publication.effect_capture_holding_contract(self.binding))
    Ok((_, true)) => Err(RecoveryRequired)
    Err(issue) => Err(issue)
  }
}

///|
/// Reopen an exact physical capture after Store reconstruction. Nothing is
/// allocated or re-encrypted in the durable Store by this operation.
pub fn Store::restore_effect_capture_custody(
  self : Store,
  binding : @publication.EffectCaptureHoldingBinding,
  crypto : @signature.Library,
  key : Bytes,
) -> Result[EffectCaptureCustody, NativePublicationStoreIssue] {
  let custody = match
    self.prepare_effect_capture_custody(binding, crypto, key) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match custody.read() {
    Ok(_) => Ok(custody)
    Err(issue) => Err(issue)
  }
}

///|
/// Erase the active encrypted body and confirm the terminal record before
/// returning its exact Store reservation. Failure retains cleanup responsibility.
/// The tombstone prevents a later persist from reviving this original capture.
pub fn EffectCaptureCustody::retry_cleanup(
  self : EffectCaptureCustody,
) -> Result[Bool, NativePublicationStoreIssue] {
  let (row, complete) = match self.read() {
    Ok(value) => value
    Err(Database(@sqlite.NotFound)) =>
      // No asynchronous writer exists in this synchronous Store operation.
      // An uncertain transaction is rejected by read() before this branch.
      return self.store.database
        .release_capacity(
          "publication_payload",
          self.capacity_key,
          self.envelope.length().to_int64(),
          1L,
        )
        .map_err(issue => Database(issue))
    Err(issue) => return Err(issue)
  }
  if !complete {
    match
      allocation_prepare(self.store, "effect-capture-before-cleanup", () => {
        self.store.database
        .compare_exchange(
          "effect_capture_custody",
          @publication.effect_capture_holding_identity(self.binding),
          row.revision,
          self.terminal,
        )
        .map(_ => ())
        .map_err(issue => Database(issue))
      }) {
      Ok(_) | Err(Database(@sqlite.Collision)) => ()
      Err(issue) => return Err(issue)
    }
  }
  observe(self.store, "effect-capture-terminal-saved")
  match self.read() {
    Ok((_, true)) => ()
    Ok((_, false)) => return Err(CleanupPending)
    Err(issue) => return Err(issue)
  }
  match
    allocation_prepare(self.store, "effect-capture-before-capacity-release", () => {
      self.store.database
      .release_capacity(
        "publication_payload",
        self.capacity_key,
        self.envelope.length().to_int64(),
        1L,
      )
      .map_err(issue => Database(issue))
    }) {
    Ok(released) => Ok(released)
    Err(issue) => Err(issue)
  }
}

///|
pub fn EffectCaptureCustody::reserved_bytes(
  self : EffectCaptureCustody,
) -> Int64 {
  self.envelope.length().to_int64()
}

///|
pub fn EffectCaptureCustody::same_binding(
  self : EffectCaptureCustody,
  other : EffectCaptureCustody,
) -> Bool {
  physical_equal(self.store, other.store) &&
  self.key == other.key &&
  @publication.effect_capture_holding_identity(self.binding) ==
  @publication.effect_capture_holding_identity(other.binding) &&
  @publication.publication_contract_identity(
    @publication.effect_capture_holding_contract(self.binding),
  ) ==
  @publication.publication_contract_identity(
    @publication.effect_capture_holding_contract(other.binding),
  )
}
