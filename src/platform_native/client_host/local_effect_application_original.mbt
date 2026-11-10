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
/// Borrow the SAME shape/identity-admitted row, joined through its ordered CID.
/// No parse, canonicalization, key derivation or authority callback is repeated.
/// The caller retains this body's original Read backing while using the alias.
pub fn NativeLocalSavedEffectApprovalOriginal::ordered_row_original(
  self : Self,
  member_index : Int,
  row_ordinal : Int,
) -> @canonical.CanonicalValue? {
  guard @publication.effect_preview_ordered_row_identity(
      self.preview,
      member_index,
      row_ordinal,
    )
    is Some(row) &&
    @publication.effect_preview_row_index(self.preview, member_index, row)
    is Some(raw_index) &&
    @canonical.object_field(self.preview_original, "effects")
    is Some(@canonical.Array(effects)) &&
    @canonical.array_at(effects, member_index) is Some(effect_value) &&
    @canonical.object_field(effect_value, "changes")
    is Some(@canonical.Array(changes)) else {
    return None
  }
  @canonical.array_at(changes, raw_index)
}

///|
/// The existing Mock UPDATE request's canonical six-field preimage. Warm and
/// saved callers share this writer; values are already admitted DATA, not IO
/// permissions. Its caller backs the writer and returned String before entry.
pub fn native_local_effect_update_request_wire(
  binding : String,
  mapping : String,
  target : @canonical.CanonicalValue,
  value : @canonical.CanonicalValue,
  before : @canonical.CanonicalValue,
  version : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, Unit] {
  try {
    let writer = @encode.writer(max_bytes, max_nodes, max_depth)
    emit_native_local_effect_update_request(
      writer, binding, mapping, target, value, before, version,
    )
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(())
  }
}

///|
// One protocol body for measurement and emission. Original canonical subtrees
// remain borrowed; measuring cannot issue a request, CID, grant or text body.
fn emit_native_local_effect_update_request(
  writer : @encode.Writer,
  binding : String,
  mapping : String,
  target : @canonical.CanonicalValue,
  value : @canonical.CanonicalValue,
  before : @canonical.CanonicalValue,
  version : String,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "before")
  @canonical.emit_value(before, writer)
  @encode.key(writer, "binding")
  @encode.string_value(writer, binding)
  @encode.key(writer, "mapping")
  @encode.string_value(writer, mapping)
  @encode.key(writer, "target")
  @canonical.emit_value(target, writer)
  @encode.key(writer, "value")
  @canonical.emit_value(value, writer)
  @encode.key(writer, "version")
  @encode.string_value(writer, version)
  @encode.end_object(writer)
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

///|
/// Construct this original row's file request without reopening Source/Model.
/// The caller supplies only its actual already-retained request inventory for
/// simultaneous String/control backing. These counts grant no IO or budget.
pub fn NativeLocalEffectResumeOriginal::prepare_application_file_request_in_original_read(
  self : NativeLocalEffectResumeOriginal,
  member_index : Int,
  row_ordinal : Int,
  binding : String,
  mapping : String,
  retained_request_units : Int64,
  retained_requests : Int,
  request_limits : @checkpoint.WireLimits,
) -> Result[
  (String, String, String, String, String),
  NativeLocalInitialHostAttestationIssue,
] {
  let original = match self.application_original_in_original_read() {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard self.subject is Some(SavedSigningSubject(read)) &&
    retained_request_units >= 0L &&
    retained_requests >= 0 &&
    @publication.effect_preview_member_source_binding_cid(
      original.preview,
      member_index,
    ) ==
    Some(binding) &&
    @publication.effect_preview_member_resolved_contract(
      original.preview,
      member_index,
    )
    is Some(@publication.Mapping(_, original_mapping)) &&
    original_mapping == mapping &&
    original.ordered_row_original(member_index, row_ordinal) is Some(row) &&
    @canonical.object_field(row, "target_row_identity") is Some(target) &&
    target is @canonical.String(identity) &&
    @canonical.object_field(row, "intended_changes") is Some(intended) &&
    @canonical.object_field(intended, "state")
    is Some(@canonical.String("present")) &&
    @canonical.object_field(intended, "value") is Some(changes) &&
    @canonical.object_field(row, "before") is Some(before) &&
    @canonical.object_field(before, "state")
    is Some(@canonical.String("present")) &&
    @canonical.object_field(before, "value") is Some(full_before) &&
    @canonical.object_field(row, "target_guard") is Some(target_guard) &&
    @canonical.object_field(target_guard, "state")
    is Some(@canonical.String("version")) &&
    @canonical.object_field(target_guard, "version_cid")
    is Some(@canonical.String(version)) else {
    return Err(HostAttestationUnavailable)
  }
  let limits = request_limits
  // A request adds three structural scalar fields to the admitted data
  // subtrees. Its existing installed request limit is checked by the writer;
  // no separate subtree admission multiplies the accepted JSON limits.
  // Before learning output size, back only the non-text observation frame.
  // The outer request has six unordered keys; canonical children use ordered
  // keys. Each active canonical container retains one rest cursor and at most
  // one pending key/value cursor, bounded by the admitted traversal depth.
  guard limits.max_depth >= 1 &&
    limits.max_depth < 1073741823 &&
    @encode.text_writer_construction_inventory(0, 6, limits.max_depth)
    is Some(measurement) &&
    @shape.collection_construction_extent({
      records: 4L * limits.max_depth.to_int64() + 8L,
      record_references: 8L * limits.max_depth.to_int64() + 16L,
      record_words: 4L * limits.max_depth.to_int64() + 8L,
      reference_arrays: 1L,
      reference_items: 2L * (limits.max_depth.to_int64() + 1L),
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(traversal) else {
    return Err(HostAttestationUnavailable)
  }
  match
    read.owner.capture.prepare_model_entry_construction(
      None,
      additional_controls=Some({
        record_headers: measurement.record_headers + traversal.record_headers,
        reference_slots: measurement.reference_slots + traversal.reference_slots,
        scalar_words: measurement.scalar_words + traversal.scalar_words,
        owned_utf16_units: measurement.owned_utf16_units +
        retained_request_units,
        owned_wire_bytes: 0L,
      }),
    ) {
    Ok(_) => ()
    Err(issue) => return Err(HostAttestationOriginal(issue))
  }
  if !read.owner.saved_approval_original_live(original) || self.retired {
    return Err(HostAttestationUnavailable)
  }
  let (bytes, nodes, depth) = try {
    let measure = @encode.measuring_writer(
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    emit_native_local_effect_update_request(
      measure, binding, mapping, target, changes, full_before, version,
    )
    @encode.finish_measurement_usage(measure)
  } catch {
    _ => return Err(HostAttestationUnavailable)
  }
  guard @execution.checked_preparation_add_product(
      retained_request_units,
      bytes.to_int64(),
      3L,
    )
    is Some(owned_units) &&
    @execution.checked_preparation_add_product(owned_units, 270L, 1L)
    is Some(total_owned_units) &&
    @execution.checked_preparation_add_product(
      16L,
      retained_requests.to_int64(),
      16L,
    )
    is Some(headers) else {
    return Err(HostAttestationUnavailable)
  }
  match
    read.owner.capture.prepare_model_entry_construction(
      Some(bytes),
      nodes~,
      depth~,
      additional_controls=Some({
        // Existing retained row records/tuples and growable outer backing,
        // Current request/changes, original selector and prepared outcome
        // overlap at most three copies of this request bound: the request
        // already contains target and intended changes. Two hashes include
        // their temporary hex/final CIDs. This closed constructor inventory
        // uses no unrelated Value slack. All sums are checked before entry.
        record_headers: headers + traversal.record_headers,
        reference_slots: 32L +
        retained_requests.to_int64() * 24L +
        traversal.reference_slots,
        scalar_words: 8L +
        retained_requests.to_int64() * 4L +
        traversal.scalar_words,
        owned_utf16_units: total_owned_units,
        owned_wire_bytes: 0L,
      }),
    ) {
    Ok(_) => ()
    Err(issue) => return Err(HostAttestationOriginal(issue))
  }
  if !read.owner.saved_approval_original_live(original) || self.retired {
    return Err(HostAttestationUnavailable)
  }
  let request = match
    native_local_effect_update_request_wire(
      binding,
      mapping,
      target,
      changes,
      full_before,
      version,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    ) {
    Ok(value) => value
    Err(_) => return Err(HostAttestationUnavailable)
  }
  let changes_wire = @canonical.stringify_value(
    changes,
    limits.max_wire_bytes,
    limits.max_nodes,
    limits.max_depth,
  ) catch {
    _ => return Err(HostAttestationUnavailable)
  }
  let cid = match @sha.text_hex(request) {
    Ok(value) => "sha256:" + value
    Err(_) => return Err(HostAttestationUnavailable)
  }
  Ok((request, cid, identity, changes_wire, version))
}

///|
/// The saved computation's SAME member selects its existing retention policy;
/// no caller CID stands in for a missing contract or physical Store holding.
pub fn NativeLocalEffectResumeOriginal::prepare_application_file_row_in_original_read(
  self : Self,
  member_index : Int,
  row_ordinal : Int,
  canonical_request_cid : String,
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
  guard @publication.effect_preview_member_effect_id(
      original.preview,
      member_index,
    )
    is Some(effect_id) &&
    @publication.captured_run_effect_source_retention_cid(
      original.captured,
      effect_id,
    )
    is Some(retention) else {
    return Err(HostAttestationUnavailable)
  }
  self.prepare_application_row_in_original_read(
    member_index, row_ordinal, canonical_request_cid, retention,
  )
}

///|
/// Settle the SAME actual file ACK under this original dispatch. The caller
/// retains the physical ACK before entry and across any ambiguous append.
/// This observes original custody/read authority, never another send permit.
pub fn NativeLocalEffectResumeOriginal::record_file_row_receipt_in_original_read(
  self : Self,
  dispatch : NativeClientEffectDispatchClaim,
  member_index : Int,
  row_ordinal : Int,
  locator : @effect.LogicalItemLocator,
  key : @effect.EffectDispatchKey,
  installation_cid : String,
  target_cid : String,
  canonical_request_cid : String,
  ack : @row_file.NativeRelationFileReplacementAck,
  outcome_wire : String,
  max_response_bytes : Int,
) -> Result[
  (@publication.PublicationContract, @effect.EffectLedgerEntry),
  NativeLocalInitialHostAttestationIssue,
] {
  let original = match self.application_original_in_original_read() {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard !self.retired &&
    physical_equal(dispatch.journal, self.host.journal) &&
    dispatch.request == self.request &&
    self.record.checkpoint is Some(checkpoint) &&
    checkpoint.resolution_cid is Some(resolution) else {
    return Err(HostAttestationUnavailable)
  }
  let operation = match
    @publication.prepare_effect_file_operation(
      original.preview,
      member_index,
      row_ordinal,
      installation_cid,
      target_cid,
      canonical_request_cid,
      @effect.effect_ledger_entry_cid(dispatch.dispatching),
      @host.client_request_authority_scope_cid(self.request),
      resolution,
      ack.expected_version(),
    ) {
    Ok(value) => value
    Err(_) => return Err(HostAttestationUnavailable)
  }
  match
    self.host.journal.record_effect_file_response(
      dispatch,
      original.preview,
      member_index,
      row_ordinal,
      locator,
      key,
      operation,
      ack,
      outcome_wire,
      () => self.authority_current(),
      max_response_bytes,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(HostAttestationJournal(issue))
  }
  self.host.journal
  .record_effect_row_receipt(
    dispatch,
    original.preview,
    member_index,
    row_ordinal,
    locator,
    key,
    canonical_request_cid,
    outcome_wire,
    () => self.authority_current(),
    max_response_bytes,
  )
  .map_err(issue => HostAttestationJournal(issue))
}

///|
/// Before the file application's entry/controller exists, fund its distinct
/// Read-owned frame alongside the SAME already retained Saved materials and
/// requests. The business child/ACK has its separate actual capacity plan.
pub fn NativeLocalEffectResumeOriginal::prepare_file_application_controls_in_original_read(
  self : Self,
) -> Result[Unit, NativeLocalInitialHostAttestationIssue] {
  let original = match self.application_original_in_original_read() {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard self.subject is Some(SavedSigningSubject(read)) &&
    read.owner.capture.original_resources is Some(resources) &&
    resources.active_phase is Some(@arena.HostRead) &&
    !resources.interrupted else {
    return Err(HostAttestationUnavailable)
  }
  match read.owner.prepare_saved_effect_file_entry_in_original_read() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  // Backing/current may call out. Preserve this SAME Saved subject.
  if self.retired || !read.owner.saved_approval_original_live(original) {
    return Err(HostAttestationUnavailable)
  }
  Ok(())
}

///|
/// Borrow the SAME public Result originals restored from authenticated review
/// custody. These DATA projections allocate no arrays and issue no evidence,
/// permission, new Request or physical Store acknowledgment.
pub fn NativeLocalSavedEffectApprovalOriginal::result_publication_originals(
  self : Self,
) -> (
  Array[@publication.PublicationContract],
  Array[@publication.PublicationContract],
  Array[@publication.PublicationContract],
  Array[@publication.PublicationContract],
  Array[@publication.PublicationContract],
  Array[String],
  Array[String],
) {
  (
    self.definitions,
    self.artifacts,
    self.derivations,
    self.orderings,
    self.retentions,
    self.schema_wires,
    self.codec_cids,
  )
}

///|
/// Same already admitted schema occurrence; no parse, encoder or issuer runs.
pub fn NativeLocalSavedEffectApprovalOriginal::result_schema_original(
  self : Self,
  index : Int,
) -> @publication.CapturedEffectDependencyBody? {
  self.schema_originals.get(index)
}

///|
pub fn NativeLocalSavedEffectApprovalOriginal::computation_publication_originals(
  self : Self,
) -> (
  @publication.PublicationContract,
  @publication.PublicationContract,
  @publication.PublicationContract,
  @publication.PublicationContract,
  @publication.RetainedEffectfulComputation,
) {
  (
    self.invocation,
    self.manifest,
    self.receipt,
    self.captured,
    self.computation,
  )
}

///|
fn saved_effect_file_entry_control_bytes() -> Int64 {
  @execution.preparation_representation_cost({
    // Direct original entry H33/R34/S73 (same existing entry constructor).
    // Work H1/R7/S3; its two empty/growing array controls H4/R18/S4.
    // Eight Option/Result/closure/failure frontiers H8/R12/S8. All
    // variable requests are already retained on this SAME original Read.
    record_headers: 33L + 1L + 4L + 8L,
    reference_slots: 34L + 7L + 18L + 12L,
    scalar_words: 73L + 3L + 4L + 8L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
}

///|
// The exact existing entry/controller inventory, funded on the SAME original
// command Read before either restoration construction or later dispatch.
// This supplies no entry, capacity token, signing/dispatch permission or ACK.
pub fn NativeLocalSavedEffectReview::prepare_saved_effect_file_entry_in_original_read(
  self : NativeLocalSavedEffectReview,
) -> Result[Unit, NativeLocalInitialHostAttestationIssue] {
  let capture = self.capture
  guard !self.retired &&
    !capture.closing &&
    capture.read_callback_active &&
    capture.read_facts_valid &&
    capture.original_resources is Some(resources) &&
    resources.active_phase is Some(@arena.HostRead) &&
    !resources.interrupted else {
    return Err(HostAttestationUnavailable)
  }
  if self._retained_file_entry_control is Some(original) {
    return original
  }
  let controls = saved_effect_file_entry_control_bytes()
  guard @execution.checked_preparation_add_product(
      self._retained_constructor_bytes,
      controls,
      1L,
    )
    is Some(retained) else {
    return Err(HostAttestationOriginal(ConfigurationLimit))
  }
  // The SAME review owns the complete Store/cursor/entry-frame inventory.
  // A prior temporary high-water mark is not another simultaneously live
  // forest. Preserve it as a maximum; never append this frame to that peak.
  // Keep an in-flight refusal before the physical current/grow callback, so
  // reentry cannot issue a duplicate frame or upgrade a failed preparation.
  self._retained_constructor_bytes = retained
  self._retained_file_entry_control = Some(Err(HostAttestationUnavailable))
  let prepared = match
    resources.host.prepare_domain_original_read_construction(
      resources.read,
      retained,
      retained,
      controls,
    ) {
    Err(issue) =>
      Err(HostAttestationOriginal(OriginalResources(@arena.Read(issue))))
    Ok(_) =>
      if self.retired ||
        capture.closing ||
        !(capture.original_resources is Some(actual) &&
        physical_equal(actual, resources)) ||
        !capture.read_callback_active ||
        !capture.read_facts_valid ||
        resources.interrupted ||
        !(resources.active_phase is Some(@arena.HostRead)) {
        Err(HostAttestationUnavailable)
      } else {
        Ok(())
      }
  }
  self._retained_file_entry_control = Some(prepared)
  prepared
}
