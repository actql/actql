///|
// Caller custody on the existing review, not a Request, execution or cleanup
// owner. Partial candidate/material failures remain until that review retires.
priv struct NativeLocalSavedEffectRestoration {
  packet : NativeClientRetainedEffectMaterials
  capacity : @execution.ExecutionCapacity
  fields : @decode.ObjectView
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
// Outer review DATA uses its SAME admitted JSON geometry; only the actual
// computation material uses the complete conservative compiler recovery recipe.
let native_saved_restoration_control_bytes : Int64 = @execution.preparation_representation_cost({
    record_headers: 128L,
    reference_slots: 512L,
    scalar_words: 256L,
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
  self._retained_restoration = Some({
    packet,
    capacity,
    fields,
    attempted: false,
    completed: false,
    candidate: None,
    materials: None,
    material_issue: None,
  })
  Ok(capacity)
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
    guard native_saved_material_input_raw(
        Int::max(wire.length(), restoration.packet.materials_wire.length()),
      )
      is Some(raw) else {
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
      fields, materials, request, persisted, wire_limits, effect_limits, publication_present,
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
