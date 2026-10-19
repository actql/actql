///|
// Companion preparation custody is part of the same private Store Owner.
// It reserves descriptor and response together; it is not a send witness.
priv struct PrivateEvidencePreparation {
  table : String
  wire : String
  terminal : Bytes
}

///|
fn PrivateEffectEvidenceCustody::confirm_preparation(
  self : PrivateEffectEvidenceCustody,
) -> Result[Bool, NativePublicationStoreIssue] {
  guard self.preparation is Some(preparation) else { return Ok(false) }
  match require_store_open(self.store) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let row = match self.store.database.read(preparation.table, self.holding) {
    Ok(value) => value
    Err(issue) => return Err(Database(issue))
  }
  if row.body == preparation.terminal {
    return if row.revision == 1L { Ok(true) } else { Err(StateCollision) }
  }
  if row.revision != 0L {
    return Err(StateCollision)
  }
  match
    self.crypto.open_private_evidence(
      self.key,
      self.kind,
      self.semantic_cid,
      row.body,
    ) {
    Ok(plain) if plain == @utf8.encode(preparation.wire) => Ok(false)
    Ok(_) => Err(StateCollision)
    Err(issue) => Err(PrivateEvidence(issue))
  }
}

///|
fn PrivateEffectEvidenceCustody::retire_preparation(
  self : PrivateEffectEvidenceCustody,
) -> Result[Unit, NativePublicationStoreIssue] {
  guard self.preparation is Some(preparation) else { return Ok(()) }
  match self.confirm_preparation() {
    Ok(true) => return Ok(())
    Ok(false) => ()
    Err(issue) => return Err(issue)
  }
  match
    allocation_prepare(
      self.store,
      self.step_prefix + "-before-descriptor-cleanup",
      () => {
        self.store.database
        .compare_exchange(
          preparation.table,
          self.holding,
          0L,
          preparation.terminal,
        )
        .map(_ => ())
        .map_err(issue => Database(issue))
      },
    ) {
    Ok(_) | Err(Database(@sqlite.Collision)) => ()
    Err(issue) => return Err(issue)
  }
  match self.confirm_preparation() {
    Ok(true) => Ok(())
    Ok(false) => Err(CleanupPending)
    Err(issue) => Err(issue)
  }
}

///|
struct LocalPreparationRawCustody {
  binding : LocalPreparationRawBinding
  private_custody : PrivateEffectEvidenceCustody
}

///|
fn raw_preparation_terminal(
  holding : String,
  response_limit : Int,
  bytes : Int64,
) -> Bytes {
  @utf8.encode(
    "[\"actql-native-local-preparation-raw-retired/0.1\",\"" +
    holding +
    "\",\"" +
    response_limit.to_string() +
    "\",\"" +
    bytes.to_string() +
    "\"]",
  )
}

///|
fn prepare_local_raw_custody(
  store : Store,
  binding : LocalPreparationRawBinding,
  crypto : @signature.Library,
  key : Bytes,
) -> Result[LocalPreparationRawCustody, NativePublicationStoreIssue] {
  if store.closed {
    return Err(Closed)
  }
  if store.retiring {
    return Err(CleanupPending)
  }
  let holding = match local_raw_preparation_holding(binding) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let bytes = match local_preparation_raw_reservation_bytes(binding) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // These are the existing physical limits, not an enlarged profile.
  if key.length() != 32 ||
    raw_cipher_envelope_bytes(binding.max_plaintext_bytes.to_int64()) >
    store.max_record_bytes.to_int64() ||
    raw_cipher_envelope_bytes(
      @utf8.encode(binding.descriptor_wire).length().to_int64(),
    ) >
    store.max_record_bytes.to_int64() ||
    bytes > store.capacity_bytes ||
    store.max_objects < 2L {
    return Err(InvalidConfiguration)
  }
  Ok({
    binding,
    private_custody: {
      store,
      crypto,
      key: key[:].to_owned(),
      envelope: Bytes::new(0),
      reservation_bytes: bytes,
      reservation_objects: 2L,
      preparation: Some({
        table: "credential_raw_preparation",
        wire: binding.descriptor_wire,
        terminal: raw_preparation_terminal(
          holding,
          binding.response_limit,
          bytes,
        ),
      }),
      terminal: @utf8.encode(
        "[\"actql-native-local-preparation-raw-body-retired/0.1\",\"" +
        holding +
        "\"]",
      ),
      capacity_key: "credential-raw:" + holding,
      table: "credential_raw_observation",
      holding,
      kind: "credential_raw_observation",
      semantic_cid: holding,
      wire: "",
      step_prefix: "credential-raw",
      transaction_uncertain: false,
    },
  })
}

///|
/// Prepare only a bounded original slot. This neither reserves nor enters I/O;
/// the credential use Owner must still prove fresh atomic entry and current
/// authorization. The ceiling is read from this actual HTTP Owner.
pub fn Store::prepare_local_preparation_raw_observation(
  self : Store,
  grant : @credential.LocalPreparationCredentialGrant,
  original_use : @credential.LocalPreparationCredentialUse,
  client : @http.Client,
  crypto : @signature.Library,
  key : Bytes,
) -> Result[LocalPreparationRawCustody, NativePublicationStoreIssue] {
  self.with_original_read(false, false, fn() {
    self.prepare_local_preparation_raw_observation_in_scope(
      grant, original_use, client, crypto, key,
    )
  })
}

///|
fn Store::prepare_local_preparation_raw_observation_in_scope(
  self : Store,
  grant : @credential.LocalPreparationCredentialGrant,
  original_use : @credential.LocalPreparationCredentialUse,
  client : @http.Client,
  crypto : @signature.Library,
  key : Bytes,
) -> Result[LocalPreparationRawCustody, NativePublicationStoreIssue] {
  match require_store_open(self) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let limit = match client.response_limit() {
    Ok(value) => value
    Err(_) => return Err(InvalidConfiguration)
  }
  let binding = match
    local_preparation_raw_binding(
      grant,
      original_use,
      self.authority_cid,
      limit,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  prepare_local_raw_custody(self, binding, crypto, key)
}

///|
/// Prefund both retained records before physical entry. A retained/missing slot
/// does not classify the original send. Only the credential use Owner can enter.
pub fn LocalPreparationRawCustody::reserve(
  self : LocalPreparationRawCustody,
) -> Result[Unit, NativePublicationStoreIssue] {
  self.private_custody.store.with_original_read(false, false, fn() {
    self.reserve_in_scope()
  })
}

///|
fn LocalPreparationRawCustody::reserve_in_scope(
  self : LocalPreparationRawCustody,
) -> Result[Unit, NativePublicationStoreIssue] {
  let owner = self.private_custody
  if owner.store.closed {
    return Err(Closed)
  }
  if owner.store.retiring {
    return Err(CleanupPending)
  }
  if owner.transaction_uncertain {
    return Err(CleanupPending)
  }
  let db = owner.store.database
  match db.begin_immediate() {
    Ok(_) => ()
    Err(issue) => return Err(Database(issue))
  }
  let operation = () => {
    let present = match owner.confirm_preparation() {
      Ok(false) => true
      Ok(true) => return Err(RecoveryRequired)
      Err(Database(@sqlite.NotFound)) => false
      Err(issue) => return Err(issue)
    }
    // A body/tombstone cannot stand in for lost preparation. Never revive it.
    if !present {
      match db.read(owner.table, owner.holding) {
        Err(@sqlite.NotFound) => ()
        Ok(_) => return Err(StateCollision)
        Err(issue) => return Err(Database(issue))
      }
    }
    let fresh = match
      db.reserve_capacity_in_transaction(
        "publication_payload",
        owner.capacity_key,
        owner.reservation_bytes,
        owner.reservation_objects,
        owner.store.capacity_bytes,
        owner.store.max_objects,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Database(issue))
    }
    if present == fresh {
      return Err(StateCollision)
    }
    if fresh {
      // Descriptor encryption/copy happens only after this transaction owns
      // both descriptor and maximal response capacity.
      let envelope = match
        owner.crypto.seal_private_evidence(
          owner.key,
          owner.kind,
          owner.semantic_cid,
          @utf8.encode(self.binding.descriptor_wire),
        ) {
        Ok(value) => value
        Err(issue) => return Err(PrivateEvidence(issue))
      }
      match
        allocation_prepare(
          owner.store,
          "credential-raw-before-descriptor-persist",
          () => {
            db
            .insert("credential_raw_preparation", owner.holding, envelope)
            .map(_ => ())
            .map_err(issue => Database(issue))
          },
        ) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
    }
    match owner.confirm_preparation() {
      Ok(false) => Ok(())
      Ok(true) => Err(RecoveryRequired)
      Err(issue) => Err(issue)
    }
  }
  if operation() is Err(primary) {
    if db.rollback() is Err(cleanup) {
      owner.transaction_uncertain = true
      return Err(PrivateCaptureRollback(primary, cleanup))
    }
    return Err(primary)
  }
  match db.commit() {
    Ok(_) => ()
    Err(issue) => {
      if db.rollback() is Err(cleanup) {
        owner.transaction_uncertain = true
        return Err(PrivateCaptureRollback(Database(issue), cleanup))
      }
      return Err(Database(issue))
    }
  }
  observe(owner.store, "credential-raw-reserved")
  self.require_original_reservation()
}

///|
fn LocalPreparationRawCustody::require_original_reservation(
  self : LocalPreparationRawCustody,
) -> Result[Unit, NativePublicationStoreIssue] {
  let owner = self.private_custody
  if owner.store.closed {
    return Err(Closed)
  }
  if owner.store.retiring {
    return Err(CleanupPending)
  }
  if owner.transaction_uncertain {
    return Err(CleanupPending)
  }
  match owner.confirm_preparation() {
    Ok(false) => ()
    Ok(true) => return Err(RecoveryRequired)
    Err(issue) => return Err(issue)
  }
  let db = owner.store.database
  match db.begin_immediate() {
    Ok(_) => ()
    Err(issue) => return Err(Database(issue))
  }
  let result = match
    db.reserve_capacity_in_transaction(
      "publication_payload",
      owner.capacity_key,
      owner.reservation_bytes,
      owner.reservation_objects,
      owner.store.capacity_bytes,
      owner.store.max_objects,
    ) {
    Ok(false) => Ok(())
    Ok(true) => Err(StateCollision)
    Err(issue) => Err(Database(issue))
  }
  // This is a read/verification transaction. Roll back even the accidental
  // fresh reservation; missing original capacity is never reconstructed.
  if db.rollback() is Err(cleanup) {
    owner.transaction_uncertain = true
    return Err(
      PrivateCaptureRollback(
        match result {
          Err(primary) => primary
          Ok(_) => StateCollision
        },
        cleanup,
      ),
    )
  }
  result
}

///|
/// Retain every physical status/body before ACK or outcome. A failed save keeps
/// this same custody and the original use; it grants no request retry.
pub fn LocalPreparationRawCustody::persist(
  self : LocalPreparationRawCustody,
  status : Int,
  body : Bytes,
) -> Result[Unit, NativePublicationStoreIssue] {
  self.private_custody.store.with_original_read(false, false, fn() {
    self.persist_in_scope(status, body)
  })
}

///|
fn LocalPreparationRawCustody::persist_in_scope(
  self : LocalPreparationRawCustody,
  status : Int,
  body : Bytes,
) -> Result[Unit, NativePublicationStoreIssue] {
  match self.require_original_reservation() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let wire = match local_preparation_raw_record(self.binding, status, body) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let owner = self.private_custody
  if !owner.wire.is_empty() && owner.wire != wire {
    return Err(StateCollision)
  }
  // A repeated save reconciles the existing original ciphertext first.
  match owner.store.database.read(owner.table, owner.holding) {
    Ok(row) => {
      if row.body == owner.terminal {
        return Err(RecoveryRequired)
      }
      let plain = match
        owner.crypto.open_private_evidence(
          owner.key,
          owner.kind,
          owner.semantic_cid,
          row.body,
        ) {
        Ok(value) => value
        Err(issue) => return Err(PrivateEvidence(issue))
      }
      if row.revision != 0L || plain != @utf8.encode(wire) {
        return Err(StateCollision)
      }
      owner.wire = wire
      owner.envelope = row.body
    }
    Err(@sqlite.NotFound) => {
      let envelope = match
        owner.crypto.seal_private_evidence(
          owner.key,
          owner.kind,
          owner.semantic_cid,
          @utf8.encode(wire),
        ) {
        Ok(value) => value
        Err(issue) => return Err(PrivateEvidence(issue))
      }
      owner.wire = wire
      owner.envelope = envelope
    }
    Err(issue) => return Err(Database(issue))
  }
  owner.persist()
}

///|
pub fn LocalPreparationRawCustody::confirm(
  self : LocalPreparationRawCustody,
) -> Result[NativeLocalPreparationRawObservation, NativePublicationStoreIssue] {
  self.private_custody.store.with_original_read(false, false, fn() {
    self.confirm_in_scope()
  })
}

///|
fn LocalPreparationRawCustody::confirm_in_scope(
  self : LocalPreparationRawCustody,
) -> Result[NativeLocalPreparationRawObservation, NativePublicationStoreIssue] {
  match self.require_original_reservation() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match self.private_custody.read() {
    Ok((_, false)) =>
      restore_local_preparation_raw_record(
        self.private_custody.wire,
        self.binding,
      )
    Ok((_, true)) => Err(RecoveryRequired)
    Err(issue) => Err(issue)
  }
}

///|
pub fn LocalPreparationRawCustody::reserved_bytes(
  self : LocalPreparationRawCustody,
) -> Int64 {
  self.private_custody.reservation_bytes
}

///|
pub fn LocalPreparationRawCustody::retry_cleanup(
  self : LocalPreparationRawCustody,
) -> Result[Bool, NativePublicationStoreIssue] {
  self.private_custody.store.with_original_read(true, false, fn() {
    self.retry_cleanup_in_scope()
  })
}

///|
fn LocalPreparationRawCustody::retry_cleanup_in_scope(
  self : LocalPreparationRawCustody,
) -> Result[Bool, NativePublicationStoreIssue] {
  self.private_custody.retry_cleanup()
}

///|
/// Restore an original slot from authenticated saved descriptor and opaque
/// original grant/use. There is no HTTP Client, new ordinal or reserve here.
pub fn Store::restore_local_preparation_raw_observation(
  self : Store,
  grant : @credential.LocalPreparationCredentialGrant,
  original_use : @credential.LocalPreparationCredentialUse,
  crypto : @signature.Library,
  key : Bytes,
) -> Result[LocalPreparationRawCustody, NativePublicationStoreIssue] {
  self.with_original_read(false, false, fn() {
    self.restore_local_preparation_raw_observation_in_scope(
      grant, original_use, crypto, key,
    )
  })
}

///|
fn Store::restore_local_preparation_raw_observation_in_scope(
  self : Store,
  grant : @credential.LocalPreparationCredentialGrant,
  original_use : @credential.LocalPreparationCredentialUse,
  crypto : @signature.Library,
  key : Bytes,
) -> Result[LocalPreparationRawCustody, NativePublicationStoreIssue] {
  if self.closed {
    return Err(Closed)
  }
  if self.retiring {
    return Err(CleanupPending)
  }
  let scope = match
    local_preparation_raw_binding(grant, original_use, self.authority_cid, 0L) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let holding = match local_raw_preparation_holding(scope) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let descriptor = match
    self.database.read("credential_raw_preparation", holding) {
    Ok(value) => value
    Err(issue) => return Err(Database(issue))
  }
  let terminal = @utf8.decode(descriptor.body) catch { _ => "" }
  let retired = terminal.has_prefix(
    "[\"actql-native-local-preparation-raw-retired/0.1\",",
  )
  let wire = if retired {
    terminal
  } else {
    if descriptor.revision != 0L {
      return Err(StateCollision)
    }
    let plain = match
      crypto.open_private_evidence(
        key,
        "credential_raw_observation",
        holding,
        descriptor.body,
      ) {
      Ok(value) => value
      Err(issue) => return Err(PrivateEvidence(issue))
    }
    @utf8.decode(plain) catch {
      _ => return Err(StateCollision)
    }
  }
  let fields = match
    local_raw_closed_strings(
      wire,
      self.max_record_bytes,
      if retired {
        4
      } else {
        7
      },
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let original_limit = @string.parse_int64(fields[if retired { 2 } else { 6 }]) catch {
    _ => return Err(StateCollision)
  }
  let binding = match
    local_preparation_raw_binding(
      grant,
      original_use,
      self.authority_cid,
      original_limit,
    ) {
    Ok(value) => value
    Err(_) => return Err(StateCollision)
  }
  let custody = match prepare_local_raw_custody(self, binding, crypto, key) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let owner = custody.private_custody
  if retired {
    if descriptor.revision != 1L ||
      descriptor.body !=
      raw_preparation_terminal(
        holding,
        binding.response_limit,
        owner.reservation_bytes,
      ) {
      return Err(StateCollision)
    }
    let row = match self.database.read(owner.table, owner.holding) {
      Ok(value) => value
      Err(issue) => return Err(Database(issue))
    }
    if row.body != owner.terminal || (row.revision != 0L && row.revision != 1L) {
      return Err(StateCollision)
    }
    return Ok(custody)
  }
  if wire != binding.descriptor_wire {
    return Err(StateCollision)
  }
  match custody.require_original_reservation() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match self.database.read(owner.table, owner.holding) {
    Err(@sqlite.NotFound) => ()
    Err(issue) => return Err(Database(issue))
    Ok(row) if row.body == owner.terminal => ()
    Ok(row) => {
      if row.revision != 0L {
        return Err(StateCollision)
      }
      let plain = match
        crypto.open_private_evidence(
          key,
          owner.kind,
          owner.semantic_cid,
          row.body,
        ) {
        Ok(value) => value
        Err(issue) => return Err(PrivateEvidence(issue))
      }
      let body_wire = @utf8.decode(plain) catch {
        _ => return Err(StateCollision)
      }
      match restore_local_preparation_raw_record(body_wire, binding) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      owner.wire = body_wire
      owner.envelope = row.body
    }
  }
  Ok(custody)
}

///|
// The physical Store key belongs to the Native custody using it.
fn local_raw_preparation_holding(
  binding : LocalPreparationRawBinding,
) -> Result[String, NativePublicationStoreIssue] {
  raw_observation_strings(binding.fields, 1048576).map(wire => {
    "sha256:" + @sha.hex(@utf8.encode(wire))
  })
}

///|
fn local_raw_closed_strings(
  wire : String,
  max_bytes : Int,
  count : Int,
) -> Result[Array[String], NativePublicationStoreIssue] {
  let source = match
    @source.parse_json_bytes_preserving(@utf8.encode(wire), {
      max_input_bytes: max_bytes,
      max_nodes: 16,
      max_depth: 2,
    }) {
    Ok(value) => value
    Err(_) => return Err(StateCollision)
  }
  let cursor = match
    @decode.admit(source, {
      max_nodes: 16,
      max_depth: 2,
      max_string_bytes: max_bytes,
      max_total_string_bytes: max_bytes,
    }) {
    Ok(value) => value
    Err(_) => return Err(StateCollision)
  }
  let elements = match @decode.elements(cursor) {
    Ok(value) if value.length() == count => value
    _ => return Err(StateCollision)
  }
  let fields : Array[String] = []
  for element in elements {
    match @decode.text(element) {
      Ok(value) => fields.push(value)
      Err(_) => return Err(StateCollision)
    }
  }
  match raw_observation_strings(fields, max_bytes) {
    Ok(original) if original == wire => Ok(fields)
    _ => Err(StateCollision)
  }
}
