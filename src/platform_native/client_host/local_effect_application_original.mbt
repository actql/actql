///|
/// Borrow only the same fully restored Saved computation/Preview after its
/// successful Resolution. This is immutable DATA, not dispatch permission,
/// a renewed approval, a new Run or a constructor/backing supplier. The actual
/// caller separately checks current Account and the original lease before IO.
/// No Store, signer, clock or current callback runs inside this projection.
pub fn NativeLocalEffectResumeOriginal::application_original_in_original_read(
  self : NativeLocalEffectResumeOriginal,
) -> Result[
  NativeLocalSavedEffectApprovalOriginal,
  NativeLocalInitialHostAttestationIssue,
] {
  guard self.prepared &&
    !self.retired &&
    self.subject is Some(SavedSigningSubject(read)) &&
    read.owner.saved_approval_original_live(read.original) &&
    read.original.unit_definition_cid == self.unit_definition_cid &&
    @publication.publication_contract_identity(read.original.invocation) ==
    self.invocation_cid &&
    @publication.publication_contract_identity(
      read.original.materials.run_definition,
    ) ==
    @publication.publication_contract_identity(self.record.definition) &&
    read.original.materials.request == Some(self.request) else {
    return Err(HostAttestationUnavailable)
  }
  Ok(read.original)
}

///|
/// The exact existing checked preparation/compilation/Run tuple. It does not
/// issue another Request or rerun Source/Model/normalization.
pub fn NativeLocalSavedEffectApprovalOriginal::run_materials(
  self : Self,
) -> @host.ClientEffectRunMaterials {
  self.materials
}

///|
pub fn NativeLocalSavedEffectApprovalOriginal::effect_preview(
  self : Self,
) -> @publication.EffectPreviewIdentity {
  self.preview
}

///|
/// Same admitted private bytes, retained for adapter request projection. The
/// consumer must fund that projection; this getter supplies no allocation.
pub fn NativeLocalSavedEffectApprovalOriginal::effect_preview_wire(
  self : Self,
) -> String {
  self.preview_wire
}

///|
/// Execution order and raw admission order are different inventories. Join
/// once through the original row CID; never index the raw key vector by an
/// execution ordinal or recompute an already checked key.
pub fn NativeLocalSavedEffectApprovalOriginal::ordered_row_key(
  self : Self,
  member_index : Int,
  row_ordinal : Int,
) -> @effect.EffectDispatchKey? {
  retained_effect_ordered_row_key(
    self.preview,
    self.row_keys,
    member_index,
    row_ordinal,
  )
}

///|
pub fn NativeLocalSavedEffectApprovalOriginal::request_scope(
  self : Self,
) -> @scope.LogicalRequestScope {
  self.scope
}

///|
fn retained_effect_ordered_row_key(
  preview : @publication.EffectPreviewIdentity,
  row_keys : Array[Array[@effect.EffectDispatchKey]],
  member_index : Int,
  row_ordinal : Int,
) -> @effect.EffectDispatchKey? {
  guard @publication.effect_preview_ordered_row_identity(
      preview, member_index, row_ordinal,
    )
    is Some(row) &&
    @publication.effect_preview_row_index(preview, member_index, row)
    is Some(raw_index) else {
    return None
  }
  row_keys.get(member_index).bind(keys => keys.get(raw_index))
}

///|
/// Prepare only the original row's immutable Ledger inputs. The public
/// continuation selects Program/Unit, Preview and key from its retained Saved
/// owner; the caller supplies its actual finalized request and selected
/// retention contract. Neither CID is a permission, holding or send grant.
/// The existing original Read backs these constructors before they run.
pub fn NativeLocalEffectResumeOriginal::prepare_application_row_in_original_read(
  self : NativeLocalEffectResumeOriginal,
  member_index : Int,
  row_ordinal : Int,
  canonical_request_cid : String,
  retention_contract_cid : String,
) -> Result[
  (
    @effect.LogicalItemLocator,
    @effect.EffectDispatchKey,
    @effect.EffectLedgerBasis,
  ),
  NativeLocalInitialHostAttestationIssue,
] {
  let original = match self.application_original_in_original_read() {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard self.subject is Some(SavedSigningSubject(read)) &&
    original.ordered_row_key(member_index, row_ordinal) is Some(key) else {
    return Err(HostAttestationUnavailable)
  }
  let headers = @checked.effect_program_static_headers(
    @host.prepared_client_effect_computation_candidate(
      original.materials.prepared,
    ),
  )
  let program = @syntax.effect_headers_owner(headers)
  // The existing compiled Unit getter copies only the outer Stage vector.
  // Back that exact temporary inventory before invoking it; the Stage and
  // returned ID remain original borrowed values. This vector dies before the
  // subsequent locator/hash construction peak, so its debit is not added twice.
  match
    read.owner.capture.prepare_model_entry_construction(
      None,
      additional_controls=Some({
        record_headers: 2L,
        reference_slots: @syntax.stage_count(program).to_int64(),
        scalar_words: 3L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      }),
    ) {
    Ok(_) => ()
    Err(issue) => return Err(HostAttestationOriginal(issue))
  }
  if !read.owner.saved_approval_original_live(original) || self.retired {
    return Err(HostAttestationUnavailable)
  }
  let node = @host.client_effect_compilation_unit_id(
    original.materials.compilation,
  )
  // The same bounded locator codec has an explicit hashing-writer prelude:
  // max_item_bytes + 18 * max_name_bytes + 512, nodes + 8, depth + 2.
  // Names are already checked; 3 bytes per retained UTF16 unit bounds their
  // UTF8 representation without allocating an unbacked measurement buffer.
  guard @publication.effect_preview_member_effect_id(
      original.preview,
      member_index,
    )
    is Some(effect_id) else {
    return Err(HostAttestationUnavailable)
  }
  let name_units = Int::max(
    program.id.length(),
    Int::max(node.length(), effect_id.length()),
  )
  let name_bytes = name_units.to_int64() * 3L
  let (item_bytes, item_nodes, item_depth) = @effect.effect_dispatch_key_codec_limits()
  let locator_bytes = item_bytes.to_int64() + 18L * name_bytes + 512L
  if name_bytes < 1L || name_bytes > 1000000L || locator_bytes > 2147483647L {
    return Err(HostAttestationUnavailable)
  }
  match
    read.owner.capture.prepare_model_entry_construction(
      Some(locator_bytes.to_int()),
      nodes=item_nodes + 8,
      depth=item_depth + 2,
      // Dispatch and recovery hash writers are sequential. Their two returned
      // CIDs overlap the locator/basis; this second envelope also retains them.
      additional=Some((1024 + effect_id.length() * 6, 8, 3)),
      additional_controls=Some({
        // Locator (6 refs), basis (12), returned tuple (3), Result (1),
        // retained key/selection and the temporary original/header references.
        record_headers: 8L,
        reference_slots: 32L,
        scalar_words: 8L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      }),
    ) {
    Ok(_) => ()
    Err(issue) => return Err(HostAttestationOriginal(issue))
  }
  // A constructor port may observe mutable lifetime. Keep the original
  // receiver current after it returns without repeating Account/clock/IO.
  if !read.owner.saved_approval_original_live(original) || self.retired {
    return Err(HostAttestationUnavailable)
  }
  retained_effect_application_row_basis(
    original.preview,
    original.scope,
    key,
    program.id,
    node,
    original.unit_definition_cid,
    self.invocation_cid,
    member_index,
    row_ordinal,
    canonical_request_cid,
    retention_contract_cid,
    name_bytes.to_int(),
  ).map_err(_ => HostAttestationUnavailable)
}

///|
// The existing installed row owner's dispatch/recovery preimages. This is
// deliberately not a RemoteDispatch issuer and does not recompute the already
// checked Preview capability, key or original source/request ordering.
fn retained_effect_application_row_basis(
  preview : @publication.EffectPreviewIdentity,
  scope : @scope.LogicalRequestScope,
  key : @effect.EffectDispatchKey,
  program_id : String,
  node_id : String,
  unit_definition_cid : String,
  invocation_cid : String,
  member_index : Int,
  row_ordinal : Int,
  canonical_request_cid : String,
  retention_contract_cid : String,
  max_name_bytes : Int,
) -> Result[
  (
    @effect.LogicalItemLocator,
    @effect.EffectDispatchKey,
    @effect.EffectLedgerBasis,
  ),
  Unit,
] {
  guard @publication.effect_preview_member_effect_id(preview, member_index)
    is Some(effect_id) &&
    @publication.effect_preview_member_kind(preview, member_index) is Some(kind) &&
    @publication.effect_preview_member_identity(preview, member_index)
    is Some(member_cid) &&
    @publication.effect_preview_member_capability_evidence_cid(
      preview, member_index,
    )
    is Some(capability) &&
    @publication.effect_preview_ordered_row_identity(
      preview, member_index, row_ordinal,
    )
    is Some(row) &&
    @publication.effect_preview_ordered_row_correlation_wire(
      preview, member_index, row_ordinal,
    )
    is Some(correlation) else {
    return Err(())
  }
  let (item_bytes, item_nodes, item_depth) = @effect.effect_dispatch_key_codec_limits()
  let locator = match
    @effect.prepare_logical_item_locator(
      scope, program_id, node_id, effect_id, correlation, max_name_bytes, item_bytes,
      item_nodes, item_depth,
    ) {
    Ok(value) => value
    Err(_) => return Err(())
  }
  if @effect.admit_effect_single_row(
      preview, member_index, row_ordinal, kind, scope, row, locator, key,
    )
    is Err(_) {
    return Err(())
  }
  let recovery = try {
    let writer = @encode.hashing_writer(1024 + effect_id.length() * 6, 8, 3)
    @encode.begin_object(writer)
    @encode.key(writer, "effect_id")
    @encode.string_value(writer, effect_id)
    @encode.key(writer, "run_invocation_cid")
    @encode.string_value(writer, invocation_cid)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-installed-row-effect-dispatch/0.1")
    @encode.end_object(writer)
    let dispatch = "sha256:" + @encode.finish_hash(writer)
    let writer = @encode.hashing_writer(1024, 4, 2)
    @encode.begin_object(writer)
    @encode.key(writer, "dispatch_request_cid")
    @encode.string_value(writer, dispatch)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-installed-row-effect-recovery/0.1")
    @encode.end_object(writer)
    "sha256:" + @encode.finish_hash(writer)
  } catch {
    _ => return Err(())
  }
  match
    @effect.prepare_effect_ledger_basis(
      scope, locator, key, unit_definition_cid, member_cid, row, canonical_request_cid,
      recovery, "unavailable", capability, retention_contract_cid,
    ) {
    Ok(basis) => Ok((locator, key, basis))
    Err(_) => Err(())
  }
}
