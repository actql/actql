///|
// Immutable evidence read under the original saved Checkpoint's authenticated
// custody. This record owns no execution, permission, key use or cleanup duty.
struct NativeLocalSavedEffectApprovalOriginal {
  materials : @host.ClientEffectRunMaterials
  invocation : @publication.PublicationContract
  definitions : Array[@publication.PublicationContract]
  artifacts : Array[@publication.PublicationContract]
  manifest : @publication.PublicationContract
  receipt : @publication.PublicationContract
  captured : @publication.PublicationContract
  preview : @publication.EffectPreviewIdentity
  preview_wire : String
  scope : @scope.LogicalRequestScope
  row_keys : Array[Array[@effect.EffectDispatchKey]]
  checkpoint : @checkpoint.PersistedCheckpoint
  unit_definition_cid : String
  authority : String
}

///|
fn saved_effect_review_fields(
  wire : String,
  limits : @checkpoint.WireLimits,
) -> Result[@decode.ObjectView, NativeClientRunJournalIssue] {
  let source = match
    @source.parse_json_bytes_preserving(@utf8.encode(wire), {
      max_input_bytes: limits.max_wire_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let cursor = match
    @decode.admit(source, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_wire_bytes,
      max_total_string_bytes: limits.max_wire_bytes,
    }) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let names = [
    "version", "provider", "request_scope_cid", "authority_scope_cid", "request_id",
    "run_definition_wire", "invocation_wire", "result_manifest_wire", "computation_receipt_wire",
    "captured_run_wire", "review_wire", "authoring_context_cid", "result_definition_wires",
    "result_artifact_wires",
  ]
  let fields = match @decode.closed_object(cursor, names) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  for index in 0..<12 {
    guard epoch_text(fields, names[index]) is Some(text) && !text.is_empty() else {
      return Err(CustodyLost)
    }
  }
  if epoch_text(fields, "version") !=
    Some("actql-native-local-effect-review/0.1") ||
    epoch_text(fields, "provider") != Some("native-local-project-mock") {
    return Err(CustodyLost)
  }
  for name in ["result_definition_wires", "result_artifact_wires"] {
    guard @decode.lookup(fields, name) is Some(array) &&
      @decode.elements(array) is Ok(elements) else {
      return Err(CustodyLost)
    }
    for element in elements {
      guard @decode.text(element) is Ok(text) && !text.is_empty() else {
        return Err(CustodyLost)
      }
    }
  }
  Ok(fields)
}

///|
fn saved_effect_review_contract(
  fields : @decode.ObjectView,
  field : String,
  kind : String,
  limits : @checkpoint.WireLimits,
) -> Result[@publication.PublicationContract, NativeClientRunJournalIssue] {
  guard epoch_text(fields, field) is Some(wire) else { return Err(CustodyLost) }
  @publication.admit_publication_contract(
    kind,
    wire,
    limits.max_wire_bytes,
    limits.max_nodes,
    limits.max_depth,
  ).map_err(_ => CustodyLost)
}

///|
fn saved_effect_review_contracts(
  fields : @decode.ObjectView,
  field : String,
  kind : String,
  limits : @checkpoint.WireLimits,
) -> Result[
  Array[@publication.PublicationContract],
  NativeClientRunJournalIssue,
] {
  guard @decode.lookup(fields, field) is Some(array) &&
    @decode.elements(array) is Ok(elements) else {
    return Err(CustodyLost)
  }
  let result = []
  for element in elements {
    guard @decode.text(element) is Ok(wire) else { return Err(CustodyLost) }
    match
      @publication.admit_publication_contract(
        kind,
        wire,
        limits.max_wire_bytes,
        limits.max_nodes,
        limits.max_depth,
      ) {
      Ok(value) => result.push(value)
      Err(_) => return Err(CustodyLost)
    }
  }
  Ok(result)
}

///|
/// Restore the same journal-selected checked materials and complete original
/// computation chain. Persistence was confirmed by restore_in_original_read;
/// retained_data_current checks that SAME Store's idle DATA lifetime without
/// entering its different SQL coordinator during this Journal operation.
pub fn NativeLocalSavedEffectReview::restore_approval_in_original_read(
  self : NativeLocalSavedEffectReview,
  now : Double,
  expressions : @context.ExpressionProfiles,
  operations : @context.PureOperationProfiles,
  manifests : @host.ClientCompilationManifests,
  limits : @host.ClientValuesRunMaterialsLimits,
  effect_limits : @host.ClientEffectComputationLimits,
  wire_limits : @checkpoint.WireLimits,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  if self.approval_attempted || self.retired {
    return Err(Journal(CustodyLost))
  }
  self.approval_attempted = true
  guard self.capture.opening is JournalAcquired(host) &&
    self.capture.read_callback_active &&
    self.capture.read_facts_valid &&
    self._retained_continuation is Some(wire) &&
    self._retained_original is Some(metadata) &&
    self.retained_persisted is Some(persisted) &&
    self.store.retained_data_current() is Ok(_) else {
    return Err(Journal(CustodyLost))
  }
  match
    self.capture.prepare_model_entry_construction(
      Some(limits.max_evidence_bytes),
      nodes=limits.max_evidence_nodes,
      depth=limits.max_evidence_depth,
      additional=Some(
        (
          wire_limits.max_wire_bytes,
          wire_limits.max_nodes,
          wire_limits.max_depth,
        ),
      ),
      additional_controls=Some({
        // Original (14 refs), read view (2), two private sums (1 each),
        // returned Some/Result (1 each) and subject tuple (2). Borrowed DATA.
        record_headers: 7L,
        reference_slots: 22L,
        scalar_words: 0L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      }),
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let fields = match saved_effect_review_fields(wire, wire_limits) {
    Err(issue) => return Err(Journal(issue))
    Ok(value) => value
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
    host.restore_submitted_effect_material_original(
      self.capture.crypto,
      self.principal,
      self.connection,
      self.selected.reference,
      request,
      now,
      expressions,
      operations,
      manifests,
      limits,
      effect_limits,
    ) {
    Ok(value) => value
    Err(Journal(issue)) => return Err(Journal(issue))
    Err(_) => return Err(Journal(CustodyLost))
  }
  if epoch_text(fields, "run_definition_wire") !=
    Some(@publication.publication_contract_json(materials.run_definition)) {
    return Err(Journal(CustodyLost))
  }
  let invocation = match
    saved_effect_review_contract(
      fields, "invocation_wire", "run_invocation", wire_limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  let definitions = match
    saved_effect_review_contracts(
      fields, "result_definition_wires", "result_definition", wire_limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  let artifacts = match
    saved_effect_review_contracts(
      fields, "result_artifact_wires", "result_artifact", wire_limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  let manifest = match
    saved_effect_review_contract(
      fields, "result_manifest_wire", "result_manifest", wire_limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  let receipt = match
    saved_effect_review_contract(
      fields, "computation_receipt_wire", "computation_receipt", wire_limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  let captured = match
    saved_effect_review_contract(
      fields, "captured_run_wire", "captured_run", wire_limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  guard epoch_text(fields, "review_wire") is Some(preview_wire) else {
    return Err(Journal(CustodyLost))
  }
  let preview = match
    @host.admit_client_effect_review_checkpoint_preview(
      persisted.artifact,
      materials.allowed,
      materials.run_definition,
      persisted.artifact.wire,
      preview_wire,
      wire_limits,
    ) {
    Ok(value) => value
    Err(_) => return Err(Journal(CustodyLost))
  }
  if epoch_text(fields, "authoring_context_cid") !=
    Some(@publication.effect_preview_authoring_context_cid(preview)) {
    return Err(Journal(CustodyLost))
  }
  if @publication.validate_effectful_computation_evidence_chain(
      materials.run_definition,
      invocation,
      definitions,
      artifacts,
      manifest,
      receipt,
      captured,
      preview,
      wire_limits.max_wire_bytes,
      wire_limits.max_nodes,
      wire_limits.max_depth,
    )
    is Err(_) {
    return Err(Journal(CustodyLost))
  }
  let scope = match
    @host.prepared_client_effect_request_scope(materials.prepared, request) {
    Ok(value) => value
    Err(_) => return Err(Journal(CustodyLost))
  }
  let authority = @effect.logical_request_scope_authority(scope)
  if authority != @host.client_request_authority_scope_cid(request) {
    return Err(Journal(CustodyLost))
  }
  let members = @publication.effect_preview_member_count(preview)
  let mut declared_rows = 0L
  for member_index in 0..<members {
    if @publication.effect_preview_member_authority_scope_cid(
        preview, member_index,
      ) !=
      Some(authority) {
      return Err(Journal(CustodyLost))
    }
    guard @publication.effect_preview_member_max_items(preview, member_index)
      is Some(bound) &&
      bound >= 0L &&
      bound <= 2147483647L - declared_rows else {
      return Err(Journal(CustodyLost))
    }
    declared_rows += bound
  }
  let (key_bytes, key_nodes, key_depth) = @effect.effect_dispatch_key_codec_limits()
  // Keep the original checked inventory for continuation. Validation must
  // not derive every immutable key and then discard it before the caller.
  let row_keys = match
    @effect.recover_effect_preview_apply_keys(
      preview,
      scope,
      members,
      declared_rows.to_int(),
      effect_limits.effects.max_work,
      key_bytes,
      key_nodes,
      key_depth,
    ) {
    Ok(value) => value
    Err(_) => return Err(Journal(CustodyLost))
  }
  let unit = match
    @host.client_effect_review_checkpoint_unit_definition_cid(
      materials.allowed,
      materials.run_definition,
      persisted.artifact,
    ) {
    Ok(value) => value
    Err(_) => return Err(Journal(CustodyLost))
  }
  self.approval_original = Some({
    materials,
    invocation,
    definitions,
    artifacts,
    manifest,
    receipt,
    captured,
    preview,
    preview_wire,
    scope,
    row_keys,
    checkpoint: persisted,
    unit_definition_cid: unit,
    authority,
  })
  if self.saved_approval_current_for(
      request,
      metadata.run_definition_cid,
      metadata.checkpoint_cid,
      now,
    )
    is None {
    return Err(Journal(CustodyLost))
  }
  Ok(())
}

///|
// Terminal alias/lifetime check only. No Store read, clock/current callback,
// parsed body, authority decision, renewed holding or replacement evidence.
fn NativeLocalSavedEffectReview::saved_approval_original_live(
  self : NativeLocalSavedEffectReview,
  original : NativeLocalSavedEffectApprovalOriginal,
) -> Bool {
  !self.retired &&
  !self.capture.closing &&
  self.capture.read_callback_active &&
  self.capture.read_facts_valid &&
  self.capture.read_operation_issue is None &&
  self.capture.opening is JournalAcquired(host) &&
  !host.closed &&
  !host.journal.fenced &&
  self.capture.original_resources is Some(resources) &&
  !resources.interrupted &&
  resources.active_phase is Some(@arena.HostRead) &&
  self.approval_original is Some(actual) &&
  physical_equal(actual, original) &&
  self.retained_persisted == Some(original.checkpoint) &&
  self.store.retained_data_current() is Ok(_)
}

///|
fn NativeLocalSavedEffectReview::saved_approval_current_for(
  self : NativeLocalSavedEffectReview,
  request : @host.ClientRequestIdentity,
  run_definition_cid : String,
  checkpoint_cid : String,
  now : Double,
) -> String? {
  guard request == self.selected.request &&
    self.approval_original is Some(original) &&
    self._retained_original is Some(metadata) &&
    self.capture.opening is JournalAcquired(host) &&
    original.checkpoint.artifact.checkpoint_cid == checkpoint_cid &&
    @publication.publication_contract_identity(
      original.materials.run_definition,
    ) ==
    run_definition_cid &&
    self.saved_approval_original_live(original) else {
    return None
  }
  let current = host.lookup_submitted_checkpoint_metadata(
    self.capture.crypto,
    self.principal,
    self.connection,
    self.selected.reference,
    request,
    now,
  )
  guard current is Ok(Some(actual)) &&
    actual.checkpoint_cid == checkpoint_cid &&
    actual.run_definition_cid == run_definition_cid &&
    actual.revision == metadata.revision &&
    !actual.cancellation_requested &&
    self.saved_approval_original_live(original) else {
    return None
  }
  Some(original.authority)
}
