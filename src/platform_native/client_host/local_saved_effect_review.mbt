///|
// A read-only alias child of the original command Read. Store remains the
// physical custody/cleanup owner. Reading a saved review must never run its
// cleanup operation, repeat its Model, or manufacture a Resident compute owner.
struct NativeLocalSavedEffectReview {
  capture : NativeLocalJournalCapture
  store : @publication_store.Store
  selected : NativeLocalCheckpointSelection
  principal : String
  connection : String
  namespace_id : String
  mut attempted : Bool
  mut retired : Bool
  mut _retained_checkpoint : @publication_store.EffectCheckpointCustody?
  mut _retained_continuation : String?
  mut _retained_original : NativeClientOriginalCheckpointMetadata?
}

///|
/// Retain this receiver before restore or a fallible Read return. It initially
/// owns no physical Store child, permission, signing operation or resume claim.
pub fn NativeLocalJournalCapture::prepare_saved_effect_review(
  self : NativeLocalJournalCapture,
  store : @publication_store.Store,
  selected : NativeLocalCheckpointSelection,
  principal : String,
  connection : String,
  namespace_id : String,
) -> Result[NativeLocalSavedEffectReview, NativeLocalAdoptionIssue] {
  match
    self.prepare_model_entry_construction(
      None,
      additional_controls=Some({
        // Receiver, returned Some/Result and the restoration callback. All
        // input identity/Store/String fields remain original borrowed values.
        record_headers: 5L,
        reference_slots: 24L,
        scalar_words: 4L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      }),
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  Ok({
    capture: self,
    store,
    selected,
    principal,
    connection,
    namespace_id,
    attempted: false,
    retired: false,
    _retained_checkpoint: None,
    _retained_continuation: None,
    _retained_original: None,
  })
}

///|
// A retained observer never turns a declined/failed restoration into another
// constructor attempt. The caller keeps the receiver across that failure.
pub fn NativeLocalSavedEffectReview::restore_in_original_read(
  self : NativeLocalSavedEffectReview,
  now : Double,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  if self.attempted || self.retired {
    return Err(Journal(CustodyLost))
  }
  self.attempted = true
  let capture = self.capture
  let (key_bytes, key_nodes, key_depth) = native_mock_model_evidence_key_codec_limits
  match
    capture.prepare_model_entry_construction(
      Some(key_bytes),
      nodes=key_nodes,
      depth=key_depth,
      additional=Some((65536, 4096, 64)),
      additional_controls=Some({
        record_headers: 8L,
        reference_slots: 24L,
        scalar_words: 8L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      }),
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  capture.with_current_adoption_material_in_original_read((
    host,
    material,
    operations,
  ) => {
    let metadata = match
      host.lookup_submitted_checkpoint_metadata_with_operations(
        capture.crypto,
        self.principal,
        self.connection,
        self.selected.reference,
        self.selected.request,
        now,
        operations=Some(operations),
        capture=Some(capture),
      ) {
      Ok(Some(value)) => value
      Err(Journal(issue)) => return Err(Journal(issue))
      _ => return Err(Journal(CustodyLost))
    }
    if metadata.checkpoint_cid != self.selected.checkpoint_cid ||
      metadata.cancellation_requested ||
      self.retired {
      return Err(Journal(CustodyLost))
    }
    let record = match
      host.journal.retained(self.selected.request, reads=Some(operations.reads)) {
      Ok(Some(value)) => value
      Ok(None) => return Err(Journal(CustodyLost))
      Err(issue) => return Err(Journal(issue))
    }
    guard record.checkpoint is Some(checkpoint) &&
      checkpoint.artifact.checkpoint_cid == metadata.checkpoint_cid &&
      checkpoint.artifact.checkpoint.checkpoint_id ==
      self.selected.checkpoint_id &&
      @publication.publication_contract_identity(record.definition) ==
      metadata.run_definition_cid else {
      return Err(Journal(CustodyLost))
    }
    let (authority, device, inode) = match self.store.custody_location() {
      Ok(value) => value
      Err(issue) => return Err(Journal(PublicationObservation(issue)))
    }
    let binding = match
      installed_publication_binding(self.namespace_id, authority, device, inode) {
      Ok(value) => value
      Err(issue) => return Err(Journal(issue))
    }
    if record.publication_binding != Some(binding) || self.retired {
      return Err(Journal(CustodyLost))
    }
    let (extent, layout) = match
      self.store.effect_checkpoint_restore_construction(checkpoint.artifact) {
      Ok(value) => value
      Err(issue) => return Err(Journal(PublicationObservation(issue)))
    }
    // Observe first; then grow this SAME Read before ciphertext/decrypt/JSON.
    // The Store rechecks the exact revision/extent, not a caller byte guess.
    match
      capture.prepare_private_store_layouts_construction(1, _ => Some(layout)) {
      Ok(_) => ()
      Err(Original(issue)) => return Err(issue)
      Err(_) => return Err(Encoding)
    }
    let key = match
      native_local_private_evidence_key(
        host,
        binding,
        operations.reads,
        "actql-native-local-effect-review-key/0.1",
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let current = () => {
      !self.retired &&
      capture.operation_scope(host, material, self.principal, self.connection)
      is Ok(scope) &&
      scope == @host.client_request_authority_scope_cid(self.selected.request) &&
      capture.operation_account(host, material, {
        principal: self.principal,
        connection: self.connection,
        resource: "run",
        operation: "read",
      })
      is Ok(@authorization.Allow(_))
    }
    if !current() {
      return Err(Journal(AuthorizationDenied))
    }
    let restored = match
      self.store.restore_confirmed_effect_checkpoint_custody(
        checkpoint.artifact,
        authority,
        capture.crypto,
        key,
        continuation_extent=Some(extent),
      ) {
      Ok(value) => value
      Err(issue) => return Err(Journal(PublicationObservation(issue)))
    }
    self._retained_checkpoint = Some(restored)
    let (_, continuation) = match restored.confirm() {
      Ok(value) => value
      Err(issue) => return Err(Journal(PublicationObservation(issue)))
    }
    self._retained_continuation = Some(continuation)
    self._retained_original = Some(metadata)
    if !current() {
      return Err(Journal(AuthorizationDenied))
    }
    // Rejoin the original Journal after Store/crypto callbacks. A changed
    // checkpoint/revision cannot leave an apparently current saved scope.
    match
      host.lookup_submitted_checkpoint_metadata_with_operations(
        capture.crypto,
        self.principal,
        self.connection,
        self.selected.reference,
        self.selected.request,
        now,
        operations=Some(operations),
        capture=Some(capture),
      ) {
      Ok(Some(actual)) if actual.checkpoint_cid == metadata.checkpoint_cid &&
        actual.run_definition_cid == metadata.run_definition_cid &&
        actual.revision == metadata.revision &&
        !actual.cancellation_requested &&
        current() => Ok(())
      Err(Journal(issue)) => Err(Journal(issue))
      _ => Err(Journal(CustodyLost))
    }
  })
}

///|
/// Retire only this command's aliases, including failed/partial restoration.
/// This is not historical evidence deletion or a physical Store cleanup ACK.
pub fn NativeLocalSavedEffectReview::retire_read_aliases(
  self : NativeLocalSavedEffectReview,
) -> Unit {
  self.retired = true
  self._retained_checkpoint = None
  self._retained_continuation = None
  self._retained_original = None
}
