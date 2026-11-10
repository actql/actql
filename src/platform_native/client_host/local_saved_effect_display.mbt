///|
// Decode only the authenticated saved Preview, never the private continuation.
// This is evidence DATA under an existing Read, not an approval or resume.
fn NativeLocalSavedEffectReview::saved_effect_display_preview(
  self : NativeLocalSavedEffectReview,
  persisted : @checkpoint.PersistedCheckpoint,
  continuation : String,
  definition_cid : String,
  limits : @checkpoint.WireLimits,
) -> Result[String, NativeLocalAdoptionIssue] {
  let fields = match saved_effect_review_fields(continuation, limits) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  guard epoch_text(fields, "review_wire") is Some(wire) &&
    epoch_text(fields, "authoring_context_cid") is Some(authoring) &&
    persisted.artifact.checkpoint.run_definition_cid() == Some(definition_cid) &&
    persisted.artifact.checkpoint.review_projection_cid ==
    "sha256:" + @sha.hex(@utf8.encode(wire)) else {
    return Err(Journal(CustodyLost))
  }
  // The existing packet Owner quotes this exact admitted Preview wire,
  // independently of its unchanged maximum admission limits.
  match self.prepare_wire_construction_in_original_read(wire, limits) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let preview = match
    @publication.admit_effect_preview_identity(
      wire,
      definition_cid,
      authoring,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    ) {
    Ok(value) => value
    Err(_) => return Err(Journal(CustodyLost))
  }
  if @publication.effect_preview_semantic_identity(preview) !=
    persisted.artifact.checkpoint.required_artifact_cid {
    return Err(Journal(CustodyLost))
  }
  Ok(wire)
}

///|
/// Read the SAME restored Store/Checkpoint under current Run-read authority.
/// No signing material, approval reconstruction or Model replay is requested.
pub fn NativeLocalSavedEffectReview::display_preview_in_original_read(
  self : Self,
  now : Double,
  limits : @checkpoint.WireLimits,
  checkpoint_id : String,
  checkpoint_cid : String,
) -> Result[String, NativeLocalAdoptionIssue] {
  guard self.selected.checkpoint_id == checkpoint_id &&
    self.selected.checkpoint_cid == checkpoint_cid &&
    !self.retired &&
    self.attempted &&
    self.retained_persisted is Some(persisted) &&
    self._retained_continuation is Some(continuation) &&
    self._retained_original is Some(original) &&
    self.store.retained_data_current() is Ok(_) else {
    return Err(Journal(CustodyLost))
  }
  match
    self.capture.prepare_model_entry_construction(
      None,
      // The bounded display parser/canonical/escaped text has its own policy.
      // The already held continuation is quoted from ACTUAL geometry below.
      additional=Some((65536, 8192, 64)),
      additional_controls=Some({
        record_headers: 8L,
        reference_slots: 16L,
        scalar_words: 8L,
        owned_utf16_units: 196608L,
        owned_wire_bytes: 65536L,
      }),
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match self.prepare_wire_construction_in_original_read(continuation, limits) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  self.capture.with_current_adoption_material_in_original_read((
    host,
    _,
    operations,
  ) => {
    let current = () => {
      !self.retired &&
      self.store.retained_data_current() is Ok(_) &&
      host.lookup_submitted_checkpoint_metadata_with_operations(
        self.capture.crypto,
        self.principal,
        self.connection,
        self.selected.reference,
        self.selected.request,
        now,
        operations=Some(operations),
        capture=Some(self.capture),
      )
      is Ok(Some(actual)) &&
      actual.checkpoint_cid == original.checkpoint_cid &&
      actual.run_definition_cid == original.run_definition_cid &&
      actual.revision == original.revision &&
      !actual.cancellation_requested
    }
    if !current() {
      return Err(Journal(CustodyLost))
    }
    let wire = match
      self.saved_effect_display_preview(
        persisted,
        continuation,
        original.run_definition_cid,
        limits,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if !current() {
      return Err(Journal(CustodyLost))
    }
    Ok(wire)
  })
}

///|
/// Observe only this live command's already persisted waiting Preview. The
/// existing Store children remain retained by this ModelWork on every failure.
pub fn NativeClientMockModelWork::display_preview_in_original_read(
  self : Self,
  connection : String,
  checkpoint_id : String,
  checkpoint_cid : String,
) -> Result[String, NativeLocalAdoptionIssue] {
  guard !self.closing &&
    !self.closed &&
    !self.advancing &&
    self.effect_review is Some(saved) &&
    saved.waiting is Some(waiting) &&
    waiting.checkpoint is Some(original) &&
    original.artifact.checkpoint.checkpoint_id == checkpoint_id &&
    original.artifact.checkpoint_cid == checkpoint_cid &&
    saved.checkpoint is Some(checkpoint) &&
    saved.preview is Some(preview) &&
    saved.checkpoint_confirmed &&
    saved.preview_confirmed else {
    return Err(Journal(CustodyLost))
  }
  match
    self.capture.prepare_model_entry_construction(
      Some(65536),
      nodes=8192,
      depth=64,
      additional=Some((65536, 8192, 64)),
      additional_controls=Some({
        record_headers: 8L,
        reference_slots: 16L,
        scalar_words: 8L,
        owned_utf16_units: 196608L,
        owned_wire_bytes: 65536L,
      }),
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  self.capture.with_current_adoption_material_in_original_read((
    host,
    material,
    operations,
  ) => {
    let current = () => {
      !self.closing &&
      !self.closed &&
      !self.advancing &&
      self.capture.operation_scope(host, material, self.principal, connection)
      is Ok(scope) &&
      scope == @host.client_request_authority_scope_cid(self.request) &&
      self.capture.operation_account(host, material, {
        principal: self.principal,
        connection,
        resource: "run",
        operation: "read",
      })
      is Ok(@authorization.Allow(_)) &&
      host.journal.retained(self.request, reads=Some(operations.reads))
      is Ok(Some(actual)) &&
      actual.revision == waiting.revision &&
      !actual.cancellation_requested &&
      actual.checkpoint is Some(selected) &&
      selected.artifact.checkpoint_cid == checkpoint_cid
    }
    if !current() {
      return Err(Journal(AuthorizationDenied))
    }
    let (persisted, _) = match checkpoint.confirm() {
      Ok(value) => value
      Err(issue) => return Err(Journal(PublicationObservation(issue)))
    }
    let (identity, wire) = match preview.confirm() {
      Ok(value) => value
      Err(issue) => return Err(Journal(PublicationObservation(issue)))
    }
    if persisted.artifact.checkpoint_cid != checkpoint_cid ||
      @publication.effect_preview_run_identity(identity) !=
      @publication.publication_contract_identity(self.definition) ||
      @publication.effect_preview_semantic_identity(identity) !=
      persisted.artifact.checkpoint.required_artifact_cid ||
      "sha256:" + @sha.hex(@utf8.encode(wire)) !=
      persisted.artifact.checkpoint.review_projection_cid ||
      !current() {
      return Err(Journal(CustodyLost))
    }
    Ok(wire)
  })
}
