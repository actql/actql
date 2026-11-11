///|
// Decode only the authenticated saved Preview, never the private continuation.
// This is evidence DATA under an existing Read, not an approval or resume.
fn NativeLocalSavedEffectReview::saved_effect_display_preview(
  self : NativeLocalSavedEffectReview,
  persisted : @checkpoint.PersistedCheckpoint,
  continuation : @decode.Cursor,
  definition_cid : String,
  limits : @checkpoint.WireLimits,
) -> Result[@canonical.CanonicalValue, NativeLocalAdoptionIssue] {
  let fields = match saved_effect_review_fields_from_cursor(continuation) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  guard epoch_text(fields, "review_wire") is Some(wire) &&
    epoch_text(fields, "authoring_context_cid") is Some(authoring) &&
    persisted.artifact.checkpoint.run_definition_cid() == Some(definition_cid) else {
    return Err(Journal(CustodyLost))
  }
  let cursor = match self.admit_wire_in_original_read(wire, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let usage = @decode.admission_usage(cursor)
  let bytes = @decode.cursor_span(cursor).end_byte
  if bytes > 65536 ||
    wire.length() > 65536 ||
    usage.nodes > 8192 ||
    usage.depth > 64 {
    return Err(Journal(CapacityExceeded))
  }
  match
    self.capture.prepare_effect_display_identity_construction(
      self._retained_constructor_bytes,
      bytes,
      usage.nodes,
      Int::max(1, usage.depth),
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  // Bound the selected display and fund its actual construction BEFORE
  // creating this additional UTF8/hash copy of the original Preview.
  if persisted.artifact.checkpoint.review_projection_cid !=
    "sha256:" + @sha.hex(@utf8.encode(wire)) {
    return Err(Journal(CustodyLost))
  }
  let (preview, root) = match
    @publication.admit_effect_preview_identity_cursor_with_original(
      wire,
      cursor,
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
  let retained = match effect_display_root_retained(root) {
    Some(value) => value
    None => return Err(ConfigurationLimit)
  }
  guard @execution.checked_preparation_add_product(
      self._retained_constructor_bytes,
      retained,
      1L,
    )
    is Some(retained) else {
    return Err(ConfigurationLimit)
  }
  self._retained_constructor_bytes = retained
  Ok(root)
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
) -> Result[@canonical.CanonicalValue, NativeLocalAdoptionIssue] {
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
  let continuation = match
    self.admit_wire_in_original_read(continuation, limits) {
    Ok(value) => value
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
    let root = match
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
    Ok(root)
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
) -> Result[@canonical.CanonicalValue, NativeLocalAdoptionIssue] {
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
      saved._retained_store.retained_data_current() is Ok(_) &&
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
      !current() {
      return Err(Journal(CustodyLost))
    }
    let limits : @checkpoint.WireLimits = {
      max_wire_bytes: 65536,
      max_nodes: 8192,
      max_depth: 64,
    }
    let preflight = match
      @source.start_json_source_preflight(
        wire,
        {
          max_input_bytes: limits.max_wire_bytes,
          max_nodes: limits.max_nodes,
          max_depth: limits.max_depth,
        },
        data_keys=true,
      ) {
      Ok(value) => value
      Err(_) => return Err(Journal(CustodyLost))
    }
    defer @source.cancel_json_source_preflight(preflight)
    let geometry = while true {
      match @source.advance_json_source_preflight(preflight, 4096) {
        Ok(@source.JsonSourceContinue(..)) => continue
        Ok(@source.JsonSourceReady(value, ..)) => break value
        _ => return Err(Journal(CustodyLost))
      }
    } nobreak {
      return Err(Journal(CustodyLost))
    }
    guard saved_effect_wire_construction(geometry)
      is Some((retained, peak, raw)) &&
      self.capture.original_resources is Some(resources) else {
      return Err(ConfigurationLimit)
    }
    // Add this new parser/index beside every existing Store/Model frame.
    // The pure construction recipe and one-use parser are B's SAME owners.
    guard @execution.checked_preparation_add_product(
        saved._retained_display_constructor_bytes,
        retained,
        1L,
      )
      is Some(next_retained) &&
      @execution.checked_preparation_add_product(
        saved._retained_display_constructor_bytes,
        peak,
        1L,
      )
      is Some(next_peak) else {
      return Err(ConfigurationLimit)
    }
    saved._retained_display_constructor_bytes = next_retained
    match
      resources.host.prepare_domain_original_read_construction(
        resources.read,
        next_retained,
        next_peak,
        raw,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(OriginalResources(@arena.Read(issue)))
    }
    let cursor = match saved_effect_admit_preflight(preflight, limits) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    match
      self.capture.prepare_effect_display_identity_construction(
        saved._retained_display_constructor_bytes,
        geometry.input_bytes,
        geometry.node_upper,
        Int::max(1, geometry.depth_upper),
      ) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    // The same bounded preflight and actual identity construction precede
    // this extra UTF8 copy; an overlimit display never reaches the hash.
    if !current() ||
      "sha256:" + @sha.hex(@utf8.encode(wire)) !=
      persisted.artifact.checkpoint.review_projection_cid {
      return Err(Journal(CustodyLost))
    }
    let (checked, root) = match
      @publication.admit_effect_preview_identity_cursor_with_original(
        wire,
        cursor,
        @publication.publication_contract_identity(self.definition),
        @publication.effect_preview_authoring_context_cid(identity),
        limits.max_wire_bytes,
        limits.max_nodes,
        limits.max_depth,
      ) {
      Ok(value) => value
      Err(_) => return Err(Journal(CustodyLost))
    }
    if @publication.effect_preview_semantic_identity(checked) !=
      @publication.effect_preview_semantic_identity(identity) ||
      !current() {
      return Err(Journal(CustodyLost))
    }
    let retained = match effect_display_root_retained(root) {
      Some(value) => value
      None => return Err(ConfigurationLimit)
    }
    guard @execution.checked_preparation_add_product(
        saved._retained_display_constructor_bytes,
        retained,
        1L,
      )
      is Some(retained) else {
      return Err(ConfigurationLimit)
    }
    saved._retained_display_constructor_bytes = retained
    Ok(root)
  })
}

///|
// The existing Preview Owner quotes its complete construction from actual
// geometry. Its wire inventory conservatively also covers Source scratch that
// the cursor route omits; no parser is run a second time. Quote the phase beside
// actual retained Store/cursor DATA, never beside a finished execution peak.
fn NativeLocalJournalCapture::prepare_effect_display_identity_construction(
  self : Self,
  retained_originals : Int64,
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  guard self.original_resources is Some(original) &&
    original.active_phase is Some(@arena.HostRead) &&
    !original.interrupted &&
    @publication.effect_preview_identity_construction_inventory(
      bytes, nodes, depth,
    )
    is Some(inventory) &&
    @execution.preparation_representation_cost({
      record_headers: inventory.record_headers + 8L,
      reference_slots: inventory.reference_slots + 24L,
      scalar_words: inventory.scalar_words + 16L,
      owned_utf16_units: inventory.owned_utf16_units + 196608L,
      owned_wire_bytes: inventory.owned_wire_bytes + 65536L,
    })
    is Some(cost) else {
    return Err(ConfigurationLimit)
  }
  // A conservative physical single-request ceiling is derived from these
  // SAME actual constructor counts and the pinned Native layout, never from
  // a logical deficit or free-memory number. Per-record terminators cover the
  // String/Bytes/array alternatives; Int words use an eight-byte upper bound.
  let (header, unit, terminator, _, pointer) = @bootstrap.native_managed_value_layout()
  guard header > 0L &&
    unit == 2L &&
    pointer > 0L &&
    @execution.checked_preparation_add_product(
      0L,
      inventory.record_headers + 8L,
      header + terminator,
    )
    is Some(raw) &&
    @execution.checked_preparation_add_product(
      raw,
      inventory.reference_slots + 24L,
      pointer,
    )
    is Some(raw) &&
    @execution.checked_preparation_add_product(
      raw,
      inventory.scalar_words + 16L,
      8L,
    )
    is Some(raw) &&
    @execution.checked_preparation_add_product(
      raw,
      inventory.owned_utf16_units + 196608L,
      unit,
    )
    is Some(raw) &&
    @execution.checked_preparation_add_product(
      raw,
      inventory.owned_wire_bytes + 65536L,
      1L,
    )
    is Some(raw) else {
    return Err(ConfigurationLimit)
  }
  guard @execution.checked_preparation_add_product(retained_originals, cost, 1L)
    is Some(phase) else {
    return Err(ConfigurationLimit)
  }
  original.host
  .prepare_domain_original_read_construction(original.read, phase, phase, raw)
  .map_err(issue => OriginalResources(@arena.Read(issue)))
}

///|
// Fold only the returned canonical DATA root, not the finished parser/hash/
// identity/writer workspace. Source strings are borrowed from the same retained
// preserving cursor. Canonical owner facts include actual backing capacities;
// one enum per node, FrozenArray+array per container and object-entry tuples.
fn effect_display_root_retained(root : @canonical.CanonicalValue) -> Int64? {
  guard @canonical.representation_extent(root, 8192, 64, 65536) is Ok(extent) else {
    return None
  }
  let containers = extent.arrays + extent.objects
  @execution.preparation_representation_cost({
    record_headers: extent.nodes + 2L * containers + extent.object_backing_slots,
    reference_slots: extent.nodes +
    2L * containers +
    extent.array_backing_slots +
    2L * extent.object_backing_slots,
    scalar_words: extent.nodes,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
}
