///|
// Caller custody on the existing review, not a Request, execution or cleanup
// owner. Partial candidate/material failures remain until that review retires.
priv struct NativeLocalSavedEffectRestoration {
  packet : NativeClientRetainedEffectMaterials
  mut capacity : @execution.ExecutionCapacity
  fields : @decode.ObjectView
  capture_wire : String?
  schema_cursors : Array[@decode.Cursor]
  mut attempted : Bool
  mut completed : Bool
  mut candidate : Result[
    NativeLocalSavedEffectApprovalOriginal,
    NativeLocalAdoptionIssue,
  ]?
  mut materials : @host.ClientEffectRunMaterials?
  mut material_issue : @host.ClientEffectRunMaterialsIssue?
}

///|
// Fixed call-expanded constructor controls: two staged parser/report scopes,
// original packet/candidate/Result views and entered measurement/grow frames.
// The policy continuation adds eight callback/optional/Result frames with
// at most 24 borrowed references and 12 scalar words; variable subject DATA
// uses the original shared Request inventory before its constructors.
// Outer review DATA uses its SAME admitted JSON geometry; only the actual
// computation material uses the complete conservative compiler recovery recipe.
let native_saved_restoration_control_bytes : Int64 = @execution.preparation_representation_cost({
    record_headers: 136L,
    reference_slots: 537L,
    scalar_words: 268L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  },
).unwrap()

///|
/// Retain the exact current-authorized packet before the original Read is
/// suspended. This does not parse/check/compile a Program, sign or claim work.
/// The complete conservative original recovery envelope is preserved; policy
/// ceilings are not substituted for these actual retained wire lengths.
pub fn NativeLocalSavedEffectReview::prepare_approval_restoration_in_original_read(
  self : NativeLocalSavedEffectReview,
  now : Double,
  wire_limits : @checkpoint.WireLimits,
) -> Result[@execution.ExecutionCapacity, NativeLocalAdoptionIssue] {
  guard !self.retired &&
    !self.approval_attempted &&
    self._retained_restoration is None &&
    self.capture.opening is JournalAcquired(host) &&
    self.capture.read_callback_active &&
    self.capture.read_facts_valid &&
    self._retained_continuation is Some(wire) &&
    self._retained_original is Some(_) &&
    self.retained_persisted is Some(_) &&
    self.store.retained_data_current() is Ok(_) else {
    return Err(Journal(CustodyLost))
  }
  self.approval_attempted = true
  let packet = match
    host.lookup_submitted_effect_material_original(
      self.capture.crypto,
      self.principal,
      self.connection,
      self.selected.reference,
      self.selected.request,
      now,
    ) {
    Ok(value) => value
    Err(Journal(issue)) => return Err(Journal(issue))
    Err(_) => return Err(Journal(CustodyLost))
  }
  // The existing original-Read constructor admits this outer JSON exactly
  // once. Its text fields are computation/contract wires, not compiled IR.
  let cursor = match self.admit_wire_in_original_read(wire, wire_limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let fields = match saved_effect_review_fields_from_cursor(cursor) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  let geometry = @decode.observe_subtree_construction_geometry(cursor)
  guard saved_effect_restoration_capacity(
      packet.materials_wire,
      wire,
      geometry,
      wire_limits.max_depth,
    )
    is Some(capacity) else {
    return Err(ConfigurationLimit)
  }
  let (capture_wire, capacity) = match epoch_text(fields, "captured_run_cid") {
    None => (None, capacity)
    Some(cid) => {
      let captured = match
        self.read_saved_effect_capture(fields, packet, cid, now) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      let geometry = match
        saved_effect_capture_geometry(captured, wire_limits) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      guard @local.installed_effect_contract_response_construction_capacity(
          geometry.input_bytes,
          geometry.node_upper,
          geometry.depth_upper,
        )
        is Some(construction) &&
        @execution.add_execution_capacity(capacity, construction)
        is Some(combined) else {
        return Err(ConfigurationLimit)
      }
      (Some(captured), combined)
    }
  }
  let restoration : NativeLocalSavedEffectRestoration = {
    packet,
    capacity,
    fields,
    capture_wire,
    schema_cursors: [],
    attempted: false,
    completed: false,
    candidate: None,
    materials: None,
    material_issue: None,
  }
  self._retained_restoration = Some(restoration)
  if @decode.lookup(fields, "result_derivation_wires") is Some(_) {
    guard @decode.lookup(fields, "result_schema_wires") is Some(array) &&
      @decode.array_length(array) is Some(count) &&
      self.capture.original_resources is Some(resources) else {
      return Err(Journal(CustodyLost))
    }
    // Two append backings (Read cursors and later constructor schema bodies),
    // including their old/new overlap. Count occurrences, never text units.
    let controls = @execution.preparation_representation_cost({
      record_headers: 8L,
      reference_slots: 16L + 6L * count.to_int64(),
      scalar_words: 8L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    }).unwrap()
    guard @execution.checked_preparation_add_product(
        self._retained_constructor_bytes,
        controls,
        1L,
      )
      is Some(retained) else {
      return Err(ConfigurationLimit)
    }
    self._retained_constructor_bytes = retained
    let (_, _, _, array_header, pointer) = @bootstrap.native_managed_value_layout()
    match
      resources.host.prepare_domain_original_read_construction(
        resources.read,
        retained,
        retained,
        Int64::max(
          controls,
          array_header + (2L * count.to_int64() + 1L) * pointer,
        ),
      ) {
      Ok(_) => ()
      Err(issue) => return Err(OriginalResources(@arena.Read(issue)))
    }
    for index in 0..<count {
      guard @decode.element_at(array, index) is Some(element) &&
        @decode.text(element) is Ok(schema_wire) else {
        return Err(Journal(CustodyLost))
      }
      // Move the existing schema intake before publication. Its one measured
      // parser/index stays with this Read, including any partial refusal.
      let schema = match
        self.admit_wire_in_original_read(schema_wire, wire_limits) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      restoration.schema_cursors.push(schema)
      let usage = @decode.admission_usage(schema)
      let bytes = @decode.cursor_span(schema).end_byte
      guard @local.installed_json_effect_response_construction_capacity(
          @execution.execution_capacity(0L, 0L).unwrap(),
          bytes,
          usage.nodes,
          usage.depth,
        )
        is Some(construction) &&
        @execution.add_execution_capacity(restoration.capacity, construction)
        is Some(combined) else {
        return Err(ConfigurationLimit)
      }
      // Body + dependency node + empty references + usage tuple/Some retain
      // five controls, eight references and four scalar fields per occurrence.
      // Their backing is additional to the canonical tree/wire inventory.
      let carriers = @execution.preparation_representation_cost({
        record_headers: 5L,
        reference_slots: 8L,
        scalar_words: 4L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      }).unwrap()
      guard @execution.add_execution_capacity(
          combined,
          @execution.execution_capacity(carriers, carriers).unwrap(),
        )
        is Some(combined) else {
        return Err(ConfigurationLimit)
      }
      // The same original constructor entry receives this complete peak
      // BEFORE canonical/schema identity admission, not a second parser.
      restoration.capacity = combined
    }
  }
  Ok(restoration.capacity)
}

///|
// The fixed probe owns the Store and original-Journal callback frames, one
// holding/revision/extent and the scalar Capture preflight. Store location
// encoding and original key derivation use their existing codec recipes.
fn saved_effect_capture_probe_construction() -> (Int64, Int64, Int64)? {
  let controls = @source.json_source_preflight_control_extent()
  let fixed = @execution.preparation_representation_cost({
    record_headers: controls.record_headers + 32L,
    reference_slots: controls.reference_slots + 96L,
    scalar_words: controls.scalar_words + 40L,
    owned_utf16_units: 71L,
    owned_wire_bytes: 32L,
  }).unwrap()
  let (key_bytes, key_nodes, key_depth) = native_mock_model_evidence_key_codec_limits
  guard journal_row_construction_working(key_bytes, key_nodes, key_depth)
    is Some((key_retained, key_peak, key_raw)) &&
    journal_row_construction_working(4096, 8, 2)
    is Some((binding_retained, binding_peak, binding_raw)) else {
    return None
  }
  Some(
    (
      fixed + key_retained + binding_retained,
      fixed + key_peak + binding_peak,
      Int64::max(fixed, Int64::max(key_raw, binding_raw)),
    ),
  )
}

///|
fn prepare_saved_effect_capture_probe(
  original : NativeLocalJournalOriginalResources,
  previous : Int64,
) -> Result[Int64, NativeLocalAdoptionIssue] {
  guard original.active_phase is Some(@arena.HostRead) && !original.interrupted else {
    return Err(OriginalResourceScopePending)
  }
  guard saved_effect_capture_probe_construction() is Some((r, e, raw)) &&
    @execution.checked_preparation_add_product(previous, r, 1L)
    is Some(retained) &&
    @execution.checked_preparation_add_product(previous, e, 1L)
    is Some(execution) else {
    return Err(ConfigurationLimit)
  }
  original.host
  .prepare_domain_original_read_construction(
    original.read,
    retained,
    execution,
    raw,
  )
  .map(_ => retained)
  .map_err(issue => OriginalResources(@arena.Read(issue)))
}

///|
fn NativeLocalSavedEffectReview::read_saved_effect_capture(
  self : NativeLocalSavedEffectReview,
  fields : @decode.ObjectView,
  packet : NativeClientRetainedEffectMaterials,
  cid : String,
  now : Double,
) -> Result[String, NativeLocalAdoptionIssue] {
  let request = self.selected.request
  guard self._retained_store_location is Some(location) &&
    self._retained_original is Some(original) &&
    self.retained_persisted is Some(persisted) &&
    @host.client_request_identity_relation(packet.request, request) ==
    @host.SameRequest &&
    original.run_definition_cid ==
    @publication.publication_contract_identity(packet.definition) &&
    original.checkpoint_cid == persisted.artifact.checkpoint_cid &&
    persisted.artifact.checkpoint.subject
    is @checkpoint.RunUnit(run_definition_cid~, ..) &&
    run_definition_cid == original.run_definition_cid &&
    epoch_text(fields, "request_scope_cid") ==
    Some(@host.client_request_scope_cid(request)) &&
    epoch_text(fields, "authority_scope_cid") ==
    Some(@host.client_request_authority_scope_cid(request)) &&
    epoch_text(fields, "request_id") ==
    Some(@host.client_request_caller_id(request)) &&
    epoch_text(fields, "run_definition_wire") ==
    Some(@publication.publication_contract_json(packet.definition)) else {
    return Err(Journal(CustodyLost))
  }
  guard self.capture.original_resources is Some(resources) else {
    return Err(OriginalResourceScopePending)
  }
  match
    prepare_saved_effect_capture_probe(
      resources,
      self._retained_constructor_bytes,
    ) {
    Ok(retained) => self._retained_constructor_bytes = retained
    Err(issue) => return Err(issue)
  }
  let capture = self.capture
  capture.with_current_adoption_material_in_original_read((
    host,
    material,
    operations,
  ) => {
    let require_current = fn() -> Result[Unit, NativeLocalAdoptionIssue] {
      guard !self.retired &&
        self.store.custody_location() is Ok(actual_location) &&
        actual_location == location &&
        self.store.retained_data_current() is Ok(_) else {
        return Err(Journal(CustodyLost))
      }
      match
        host.lookup_submitted_checkpoint_metadata_with_operations(
          capture.crypto,
          self.principal,
          self.connection,
          self.selected.reference,
          request,
          now,
          operations=Some(operations),
          capture=Some(capture),
        ) {
        Ok(Some(actual)) if actual.checkpoint_cid == original.checkpoint_cid &&
          actual.run_definition_cid == original.run_definition_cid &&
          actual.revision == original.revision &&
          !actual.cancellation_requested &&
          !self.retired &&
          capture.operation_scope(
            host,
            material,
            self.principal,
            self.connection,
          )
          is Ok(scope) &&
          scope == @host.client_request_authority_scope_cid(request) &&
          capture.operation_account(host, material, {
            principal: self.principal,
            connection: self.connection,
            resource: "run",
            operation: "read",
          })
          is Ok(@authorization.Allow(_)) => Ok(())
        Err(Journal(issue)) => Err(Journal(issue))
        _ => Err(Journal(CustodyLost))
      }
    }
    match require_current() {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    let (authority, device, inode) = location
    let binding = match
      installed_publication_binding(self.namespace_id, authority, device, inode) {
      Ok(value) => value
      Err(issue) => return Err(Journal(issue))
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
    let (extent, layout) = match
      self.store.effect_capture_restore_construction(packet.definition, cid) {
      Ok(value) => value
      Err(issue) => return Err(Journal(PublicationObservation(issue)))
    }
    match
      capture.prepare_private_store_layouts_construction(
        1,
        _ => Some(layout),
        additional_retained=self._retained_constructor_bytes,
      ) {
      Ok(retained) => self._retained_constructor_bytes = retained
      Err(Original(issue)) => return Err(issue)
      Err(_) => return Err(Encoding)
    }
    match require_current() {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    let wire = match extent.read_original_wire(capture.crypto, key) {
      Ok(value) => value
      Err(issue) => return Err(Journal(PublicationObservation(issue)))
    }
    require_current().map(_ => wire)
  })
}

///|
// The authenticated raw wire remains funded by the Read. Its scalar scan
// supplies the entered constructor's quote without building a second tree.
fn saved_effect_capture_geometry(
  wire : String,
  limits : @checkpoint.WireLimits,
) -> Result[@source.JsonSourceGeometry, NativeLocalAdoptionIssue] {
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
  while true {
    match @source.advance_json_source_preflight(preflight, 4096) {
      Ok(@source.JsonSourceContinue(..)) => continue
      Ok(@source.JsonSourceReady(value, ..)) => return Ok(value)
      _ => return Err(Journal(CustodyLost))
    }
  }
  Err(Journal(CustodyLost))
}

///|
fn saved_effect_constructor_issue(
  issue : @arena.InstalledArenaNonModelWorkEntryIssue,
) -> NativeLocalAdoptionIssue {
  match issue {
    Unavailable => OriginalResourceScopePending
    Resource(value) =>
      OriginalResources(
        @arena.Domain(@bootstrap.Accounting(@resources.Resource(value))),
      )
    Domain(value) => OriginalResources(@arena.Domain(value))
  }
}

///|
// The original input spelling bounds parser/decoded text and source collection
// storage, not compiled IR. The compiler hook separately supplies its actual
// measured artifact placement. Pinned headers/elements remain Native-owned.
fn native_saved_material_input_raw(units : Int) -> Int64? {
  guard units >= 0 &&
    @canonical_value.nfc_lf_retained_output_units(units.to_int64())
    is Some(normalized) else {
    return None
  }
  let text = Int64::max(units.to_int64() * 3L + 8L, normalized)
  native_saved_effect_constructor_placement(text, 16L + 4L * units.to_int64())
}

///|
// Preserve the complete recovery envelope for actual computation material.
// The surrounding review is already admitted JSON DATA: the same original
// cursor geometry supplies its tree/text roles, never compiler syntax nodes.
// Neither component is counted again as another whole compiler allowance.
fn saved_effect_restoration_capacity(
  material : String,
  review : String,
  geometry : @decode.SubtreeConstructionGeometry,
  depth : Int,
) -> @execution.ExecutionCapacity? {
  guard @execution.checked_preparation_add_product(
      0L,
      material.length().to_int64(),
      3L,
    )
    is Some(units) &&
    @local.request_model_recovery_capacity(units, 1) is Some(computation) &&
    @local.request_model_recovery_material_capacity(review, geometry, depth, 1)
    is Some(metadata) &&
    @execution.add_execution_capacity(computation, metadata) is Some(combined) &&
    @execution.execution_capacity(
      native_saved_restoration_control_bytes, native_saved_restoration_control_bytes,
    )
    is Some(controls) else {
    return None
  }
  @execution.add_execution_capacity(combined, controls)
}

///|
/// The same original business entry backs the complete pure reconstruction.
/// It must return to the original Read before current/custody can complete.
/// The single Core before-compile hook measures placement; its compiler is
/// never issued a second time and its bytes are not added to the whole recipe.
pub fn NativeLocalSavedEffectReview::construct_approval_in_entered_constructor(
  self : NativeLocalSavedEffectReview,
  entry : @arena.InstalledArenaNonModelWorkEntry,
  expressions : @context.ExpressionProfiles,
  operations : @context.PureOperationProfiles,
  manifests : @host.ClientCompilationManifests,
  limits : @host.ClientValuesRunMaterialsLimits,
  effect_limits : @host.ClientEffectComputationLimits,
  wire_limits : @checkpoint.WireLimits,
  before_compilation : (@host.ClientEffectCompilationConstructionInput) -> Result[
    Unit,
    @host.ClientEffectRunMaterialsIssue,
  ],
  request_value_policies? : ((@checked.EffectComputationCandidate) -> Result[
    Array[@checked.HostRequestValuePolicyEvidence],
    @host.ClientEffectComputationIssue,
  ])? = None,
  publication_required? : Bool = false,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  guard !self.retired &&
    self._retained_restoration is Some(restoration) &&
    !restoration.attempted &&
    !restoration.completed &&
    self.capture.original_resources is Some(resources) &&
    self.capture.read_callback_active &&
    self.capture.read_facts_valid &&
    !resources.interrupted &&
    resources.active_phase is None &&
    self._retained_continuation is Some(wire) &&
    self.retained_persisted is Some(persisted) else {
    return Err(OriginalResourceScopePending)
  }
  restoration.attempted = true
  let result = (fn() -> Result[
    NativeLocalSavedEffectApprovalOriginal,
    NativeLocalAdoptionIssue,
  ] {
    let input_units = Int::max(
      wire.length(),
      restoration.packet.materials_wire.length(),
    )
    let input_units = match restoration.capture_wire {
      None => input_units
      Some(captured) => Int::max(input_units, captured.length())
    }
    guard native_saved_material_input_raw(input_units) is Some(raw) else {
      return Err(ConfigurationLimit)
    }
    match
      entry.prepare_constructor_in_entered_scope(
        @execution.execution_capacity_retained_bytes(restoration.capacity),
        @execution.execution_capacity_execution_bytes(restoration.capacity),
        raw,
      ) {
      Err(issue) => return Err(saved_effect_constructor_issue(issue))
      Ok(_) => ()
    }
    guard !self.retired &&
      entry.constructor_scope_for(
        resources.host,
        resources.pair,
        resources.read,
      ) else {
      return Err(OriginalResourceScopePending)
    }
    let fields = restoration.fields
    let publication_present = @decode.lookup(fields, "result_derivation_wires")
      is Some(_)
    if publication_required && !publication_present {
      return Err(Journal(CustodyLost))
    }
    let request = self.selected.request
    if epoch_text(fields, "request_scope_cid") !=
      Some(@host.client_request_scope_cid(request)) ||
      epoch_text(fields, "authority_scope_cid") !=
      Some(@host.client_request_authority_scope_cid(request)) ||
      epoch_text(fields, "request_id") !=
      Some(@host.client_request_caller_id(request)) {
      return Err(Journal(CustodyLost))
    }
    let materials = match
      restore_original_effect_material_packet(
        restoration.packet,
        expressions,
        operations,
        manifests,
        limits,
        effect_limits,
        before_compilation=Some(before_compilation),
        request_value_policies~,
      ) {
      Ok(value) => value
      Err(issue) => {
        restoration.material_issue = Some(issue)
        return Err(Journal(CustodyLost))
      }
    }
    // Retain the restored preparation before the fallible approval builder.
    // The same review retires its custody cycle even if that builder refuses.
    restoration.materials = Some(materials)
    saved_effect_approval_original_from_fields(
      fields,
      materials,
      request,
      persisted,
      wire_limits,
      effect_limits,
      publication_present,
      schema_cursors=restoration.schema_cursors,
      capture_wire=restoration.capture_wire,
    )
  })()
  restoration.candidate = Some(result)
  result.map(_ => ())
}

///|
/// Observe the original typed material refusal without replacing its cause by
/// a public code. This is diagnostic DATA, never a refusal/success classifier.
pub fn NativeLocalSavedEffectReview::restored_material_issue(
  self : NativeLocalSavedEffectReview,
) -> NativeClientSubmittedEffectMaterialsIssue? {
  self._retained_restoration
  .bind(value => value.material_issue)
  .map(value => NativeClientSubmittedEffectMaterialsIssue::Materials(value))
}

///|
/// Complete only back on the SAME original Read. Recheck current original
/// Host/Account/packet and checkpoint even after a failed pure constructor.
/// A failed completion cannot be retried as a renewed approval capability.
pub fn NativeLocalSavedEffectReview::complete_approval_restoration_in_original_read(
  self : NativeLocalSavedEffectReview,
  now : Double,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  native_timing_begin(32)
  defer native_timing_end(32)
  guard !self.retired &&
    self._retained_restoration is Some(restoration) &&
    restoration.attempted &&
    !restoration.completed &&
    restoration.candidate is Some(candidate) &&
    self.capture.opening is JournalAcquired(host) &&
    self.capture.read_callback_active &&
    self.capture.read_facts_valid &&
    self.capture.original_resources is Some(resources) &&
    resources.active_phase is Some(@arena.HostRead) &&
    !resources.interrupted &&
    self._retained_original is Some(metadata) &&
    self.store.retained_data_current() is Ok(_) else {
    return Err(OriginalResourceScopePending)
  }
  restoration.completed = true
  match
    host.require_original_effect_material_current(
      self.capture.crypto,
      self.principal,
      self.connection,
      self.selected.reference,
      self.selected.request,
      now,
      restoration.packet,
    ) {
    Ok(_) => ()
    Err(Journal(issue)) => return Err(Journal(issue))
    Err(_) => return Err(Journal(CustodyLost))
  }
  let original = match candidate {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  self.approval_original = Some(original)
  if self.saved_approval_current_for(
      self.selected.request,
      metadata.run_definition_cid,
      metadata.checkpoint_cid,
      now,
    )
    is None {
    self.approval_original = None
    return Err(Journal(CustodyLost))
  }
  Ok(())
}

///|
/// Pinned Native constructor placement DATA from actual text/collection counts.
/// This prices no R/E and supplies no allocation, permission or owner.
pub fn native_saved_effect_constructor_placement(
  text_units : Int64,
  reference_slots : Int64,
) -> Int64? {
  let (header, width, terminator, array_header, pointer) = @bootstrap.native_managed_value_layout()
  if text_units < 0L ||
    reference_slots < 0L ||
    text_units > 2147483647L ||
    reference_slots > 2147483647L ||
    header <= 0L ||
    width != 2L ||
    terminator != width ||
    pointer <= 0L {
    return None
  }
  let mut text = 1L
  while text < text_units {
    text *= 2L
  }
  let mut slots = 64L
  while slots < reference_slots {
    slots *= 2L
  }
  Some(
    Int64::max(
      header + (text + 1L) * width,
      array_header + (slots + 1L) * pointer,
    ),
  )
}
