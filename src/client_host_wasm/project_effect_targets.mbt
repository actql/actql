///|
// Evidence remains on the original Compute until Preview consumes it. Only
// one collection projection owns scratch at a time. The file Owner still
// checks the admitted generation before and after every Compute advance.
priv struct StoredMockEffectTargetDrive {
  selections : FixedArray[StoredMockProjectWriteTarget?]
  members : Array[StoredMockEffectTargetMember]
  mut workspace : @resources.CapacityReservation?
  mut workspace_bytes : Int64
  mut observations_finished : Bool
  mut preview_member : Int
  mut preview_row : Int
  mut document : @row_host.RelationDocument?
  mut target : @row_host.RelationTargetDocument?
  mut draft : StoredMockEffectPreviewDraft?
  mut authored : @publication.AuthoredEffectPreview?
  mut dispatch_keys : @local_host.InstalledEffectPreviewDispatchKeys?
  mut completed : StoredMockEffectCompletedPreview?
  mut bound : @strategy.CapturedEffectPreviewInputs?
  mut plan_proofs : Array[@strategy.CapturedEffectPlanProof]?
  mut plan_verification : StoredMockEffectPlanVerification?
  mut public_results : Array[StoredMockEffectPublicResult]?
  mut public_manifest : StoredMockEffectPublicManifest?
  mut public_receipt : @publication.PublicationContract?
  mut public_snapshots : Array[@publication.CapturedResultSnapshot]?
  mut public_snapshot : @host.PublicationOutputSnapshotPreparation?
  mut local_manifest : @host.ClientEffectLocalManifest?
  mut captured_sources : Array[@publication.CapturedEffectSourceArtifact]?
  mut captured_local_sources : Array[
    @publication.CapturedLocalEffectSourceEvidence,
  ]?
  mut dependencies : @publication.CapturedEffectDependencyInventory?
  mut prepared_capture : StoredMockEffectPreparedCapture?
  mut review_projection : StoredMockEffectPublicReview?
  mut review_capacity : @resources.CapacityReservation?
  mut effect_review : StoredMockEffectReview?
  mut waiting_started : Bool
}

///|
priv struct StoredMockEffectTargetMember {
  capture : @local_host.InstalledEffectResultCapture
  artifact : @host.ClientEffectLocalResultArtifact
  original : StoredMockProjectWriteTarget
  count : Int
  rows : Array[StoredMockEffectTargetRow]
  mut preview_identity : @host.ClientEffectFilePreviewIdentity?
  mut preview_source : @publication.PublicationContract?
  mut effect_identity : @host.ClientEffectLocalIdentity?
  mut draft_fields : StoredMockEffectMemberDraft?
}

///|
priv struct StoredMockEffectTargetRow {
  proposal : @local_host.InstalledEffectResultProposal
  mut body : StoredMockEffectTargetRowBody
  version : String
  request : String
  request_cid : String
}

///|
priv enum StoredMockEffectTargetRowBody {
  PendingPreview(@encode.EncodedDocument, @encode.EncodedDocument, Int64)
  EncodedPreview(@encode.EncodedDocument)
  PreviewRetired
}

///|
fn fund_original_mock_effect_target_data(
  drive : StoredMockEffectTaskDrive,
  units : @execution.PreparationRepresentationUnits,
) -> Bool {
  guard @execution.preparation_representation_cost(units) is Some(bytes) else {
    return false
  }
  fund_original_mock_effect_target_bytes(drive, bytes)
}

///|
fn fund_original_mock_effect_target_bytes(
  drive : StoredMockEffectTaskDrive,
  bytes : Int64,
) -> Bool {
  guard @execution.execution_capacity(bytes, bytes) is Some(extra) &&
    @execution.add_execution_capacity(drive.charged, extra) is Some(next) &&
    @resources.grow_capacity_reservation(
      drive.ledger,
      drive.capacity,
      next.retained_bytes,
      next.execution_bytes,
    )
    is Ok(_) else {
    return false
  }
  drive.charged = next
  true
}

///|
// The consumer has already dropped every reference to the spent data.
// Shrink the original debit; refusal keeps its Cleanup responsibility.
fn return_original_mock_effect_target_bytes(
  drive : StoredMockEffectTaskDrive,
  amount : Int64,
) -> Bool {
  let charged = drive.charged
  guard amount >= 0L &&
    amount <= charged.retained_bytes &&
    amount <= charged.execution_bytes &&
    @execution.execution_capacity(
      charged.retained_bytes - amount,
      charged.execution_bytes - amount,
    )
    is Some(next) &&
    @resources.shrink_capacity_reservation(
      drive.ledger,
      drive.capacity,
      next.retained_bytes,
      next.execution_bytes,
    )
    is Ok(_) else {
    return false
  }
  drive.charged = next
  true
}

///|
fn begin_original_mock_effect_targets(
  value : Instance,
  drive : StoredMockEffectTaskDrive,
  original : MockEffectJournalObservationOriginal,
  count : Int,
) -> Int {
  guard @execution.preparation_array_representation(
      2L,
      2L * count.to_int64(),
      true,
    )
    is Some(arrays) &&
    fund_original_mock_effect_target_data(drive, {
      record_headers: arrays.record_headers + 4L + count.to_int64(),
      reference_slots: arrays.reference_slots + 20L + 4L * count.to_int64(),
      scalar_words: arrays.scalar_words + 9L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    }) else {
    return -4
  }
  let selections = FixedArray::make(count, None)
  let targets : StoredMockEffectTargetDrive = {
    selections,
    members: Array(capacity=count),
    workspace: None,
    workspace_bytes: 0L,
    observations_finished: false,
    preview_member: 0,
    preview_row: 0,
    document: None,
    target: None,
    draft: None,
    authored: None,
    dispatch_keys: None,
    completed: None,
    bound: None,
    plan_proofs: None,
    plan_verification: None,
    public_results: None,
    public_manifest: None,
    public_receipt: None,
    public_snapshots: None,
    public_snapshot: None,
    local_manifest: None,
    captured_sources: None,
    captured_local_sources: None,
    dependencies: None,
    prepared_capture: None,
    review_projection: None,
    review_capacity: None,
    effect_review: None,
    waiting_started: false,
  }
  drive.targets = Some(targets)
  let prepared = original.journal.materials.prepared
  let work = @host.client_standard_effect_computation_limits().effects.max_work
  let status = check_mock_project_effect_plan_targets(
    value,
    original.configuration,
    original.check,
    prepared,
    (selection, installed) => {
      // Selection order can differ from the captured header index.
      guard @host.client_effect_member_descriptor(
          prepared,
          selection.stage_index,
          selection.effect_id,
          work,
        )
        is Ok(descriptor) &&
        descriptor.0 >= 0 &&
        descriptor.0 < count &&
        selections[descriptor.0] is None else {
        return -32
      }
      selections[descriptor.0] = Some(installed)
      0
    },
  )
  if status != 0 {
    status
  } else {
    1
  }
}

///|
fn mock_effect_target_read_current(
  original : MockEffectJournalObservationOriginal,
  selected : StoredMockProjectWriteTarget,
) -> Bool {
  let account = original.configuration.account
  let principal = original.configuration.tuple.principal
  mock_project_write_visible(
    account,
    principal,
    selected.source,
    selected.write,
  ) &&
  @authorization.evaluate_account(account, {
    principal,
    connection: selected.source.connection,
    resource: selected.write.mapping.resource,
    operation: "read",
  })
  is Allow(_)
}

///|
// The declaration and file are already borrowed. The grammar-free preflight
// counts the exact selected View and every Contract read by Common Mapping.
// The real constructors still admit their original grammar and current owner.
fn mock_effect_target_wire_geometry(
  wire : String,
  policy : @row_host.RowPageLimits,
) -> @source.JsonSourceGeometry? {
  guard wire.length() <= policy.max_bytes &&
    @source.start_json_source_preflight(wire, {
      max_input_bytes: policy.max_bytes,
      max_nodes: policy.max_nodes,
      max_depth: policy.max_depth,
    })
    is Ok(preflight) else {
    return None
  }
  defer @source.cancel_json_source_preflight(preflight)
  guard @source.advance_json_source_preflight(preflight, wire.length() + 1)
    is Ok(JsonSourceReady(geometry, ..)) else {
    return None
  }
  Some(geometry)
}

///|
fn mock_effect_target_mapping_limits(
  source : StoredMockProjectSource,
  row : @row_host.ProjectMockRowSelection,
  data : Bytes,
  policy : @row_host.RowPageLimits,
) -> (@row_host.RowPageLimits, @row_host.RowPageLimits)? {
  let relation = source.relation
  guard relation.views.search_by(view => view.resource == row.view.resource)
    is Some(index) &&
    relation.view_bodies.get(index) is Some(view) &&
    mock_effect_target_wire_geometry(view, policy) is Some(view_geometry) else {
    return None
  }
  let mut nodes = view_geometry.node_upper
  for wire in relation.contracts {
    guard mock_effect_target_wire_geometry(wire, policy) is Some(contract) else {
      return None
    }
    nodes += Int::min(
      contract.node_upper,
      policy.max_nodes - Int::min(nodes, policy.max_nodes),
    )
  }
  // The caller holds the original Bytes and funded this temporary decoding
  // before entry. Only lexical extent survives, not a second parsed document.
  let file = @utf8.decode(data) catch { _ => return None }
  guard mock_effect_target_wire_geometry(file, policy) is Some(geometry) else {
    return None
  }
  // Lexical maxima include malformed prefixes. The parser and row codec
  // still enforce the original policy. Only this exact file's quote uses
  // its byte size and the number/depth of Values it could construct.
  let raw : @row_host.RowPageLimits = {
    ..policy,
    max_bytes: data.length(),
    max_nodes: Int::max(1, Int::min(policy.max_nodes, geometry.node_upper)),
    max_depth: Int::min(policy.max_depth, geometry.depth_upper + 1),
  }
  let checked : @row_host.RowPageLimits = {
    ..policy,
    max_nodes: Int::min(
      policy.max_nodes,
      Int::max(relation.views.length(), Int::max(nodes, raw.max_nodes)),
    ),
  }
  Some((checked, raw))
}

///|
fn mock_effect_target_geometry_inventory(
  bytes : Int,
) -> @execution.PreparationRepresentationUnits {
  let geometry = @source.json_source_preflight_control_extent()
  {
    record_headers: geometry.record_headers + 12L,
    reference_slots: geometry.reference_slots + 20L,
    scalar_words: geometry.scalar_words + 16L,
    // The UTF-8 decoder's transient builder and finished String can overlap.
    owned_utf16_units: 3L * bytes.to_int64() + 16L,
    owned_wire_bytes: 0L,
  }
}

///|
fn begin_original_mock_effect_target_document(
  drive : StoredMockEffectTaskDrive,
  targets : StoredMockEffectTargetDrive,
  selected : StoredMockProjectWriteTarget,
  data : Bytes,
) -> Int {
  let source = selected.source
  let resource = selected.write.mapping.resource
  guard selected.preparation is Some(prepared) &&
    physical_equal(prepared.data, data) &&
    targets.workspace is None else {
    return -32
  }
  let row = prepared.row
  let limits = prepared.limits
  let contract = prepared.contract
  let typed = @row_host.relation_document_prepared_contract(contract)
  let writable = selected.write.writable_fields
  // In a flat Text contract each cell consumes one original raw node and
  // borrows its input text. Sizing still includes all declared field controls,
  // including an object that refuses before every field is returned.
  let projection_limits = match
    @row_host.relation_document_text_contract_nodes(typed) {
    Some(schema_nodes) =>
      {
        ..prepared.raw_limits,
        max_nodes: Int::max(prepared.raw_limits.max_nodes, schema_nodes),
      }
    None => limits
  }
  guard @row_host.relation_document_raw_construction_inventory(
      prepared.raw_limits,
    ).bind(@execution.preparation_representation_cost)
    is Some(raw) &&
    @row_host.relation_document_projection_construction_inventory(
      {
        original: typed,
        items_path_depth: row.items_path.length(),
        key_path_depth: Some(row.key_path.length()),
        writable_fields: writable.length(),
      },
      projection_limits,
    ).bind(@execution.preparation_representation_cost)
    is Some(projected) &&
    @encode.text_writer_construction_inventory(
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    is Some(writer) &&
    @encode.hash_writer_construction_inventory(
      limits.max_nodes,
      limits.max_depth,
    )
    is Some(hash) &&
    @execution.preparation_representation_cost({
      record_headers: writer.record_headers + hash.record_headers + 20L,
      reference_slots: writer.reference_slots + hash.reference_slots + 31L,
      scalar_words: writer.scalar_words + hash.scalar_words + 17L,
      owned_utf16_units: writer.owned_utf16_units + hash.owned_utf16_units + 71L,
      owned_wire_bytes: hash.owned_wire_bytes,
    })
    is Some(observe) &&
    @execution.checked_preparation_add_product(raw, 1L, projected).bind(bytes => {
      @execution.checked_preparation_add_product(bytes, 1L, observe)
    })
    is Some(total) &&
    @resources.reserve_capacity(drive.ledger, 0L, total) is Ok(workspace) else {
    return -4
  }
  targets.workspace = Some(workspace)
  targets.workspace_bytes = total
  guard @row_host.admit_relation_document(data, limits, 16777216)
    is Ok(document) else {
    return -31
  }
  targets.document = Some(document)
  guard @row_host.project_relation_target_document(
      document,
      source.relation,
      resource,
      row.items_path,
      Some(row.key_path),
      row.primary_identity,
      writable,
      prepared_contract=Some(contract),
    )
    is Ok(target) else {
    return -31
  }
  targets.target = Some(target)
  1
}

///|
fn release_original_mock_effect_target_document(
  drive : StoredMockEffectTaskDrive,
  targets : StoredMockEffectTargetDrive,
) -> Bool {
  if targets.target is Some(target) {
    if !@row_host.discard_relation_target_document_original(target) {
      return false
    }
    targets.target = None
  }
  if targets.document is Some(document) {
    if !@row_host.discard_relation_document_original(document) {
      return false
    }
    targets.document = None
  }
  if targets.workspace is Some(workspace) {
    if @resources.settle_capacity(drive.ledger, workspace) is Err(_) {
      return false
    }
    targets.workspace = None
    targets.workspace_bytes = 0L
  }
  true
}

///|
fn retain_original_mock_effect_target_member(
  drive : StoredMockEffectTaskDrive,
  targets : StoredMockEffectTargetDrive,
  artifacts : Array[StoredMockEffectArtifact],
  inputs : @strategy.CapturedEffectInputs,
  member_index : Int,
  selected : StoredMockProjectWriteTarget,
) -> Int {
  let mut found : (StoredMockEffectArtifact, Int)? = None
  for index, artifact in artifacts {
    if @strategy.captured_effect_local_result_matches_member(
        inputs, index, member_index,
      ) {
      guard found is None &&
        artifact.capture.proposal_row_count(member_index) is Some(count) else {
        return -32
      }
      found = Some((artifact, count))
    }
  }
  guard found is Some((artifact, count)) else { return -32 }
  guard @execution.preparation_array_representation(1L, count.to_int64(), true)
    is Some(array) &&
    fund_original_mock_effect_target_data(drive, {
      ..array,
      record_headers: array.record_headers + 1L,
      reference_slots: array.reference_slots + 10L,
      scalar_words: array.scalar_words + 1L,
    }) else {
    return -4
  }
  targets.members.push({
    capture: artifact.capture,
    artifact: artifact.artifact,
    original: selected,
    count,
    rows: Array(capacity=count),
    preview_identity: None,
    preview_source: None,
    effect_identity: None,
    draft_fields: None,
  })
  1
}

///|
fn advance_original_mock_effect_targets(
  value : Instance,
  compute : StoredMockEffectCompute,
  drive : StoredMockEffectTaskDrive,
  managed : @local_host.ClientInstalledManagedRun,
  original : MockEffectJournalObservationOriginal,
  inputs : @strategy.CapturedEffectInputs,
  publication : @host.ClientEffectDirectSourcesPublication,
  unit : @host.ClientEffectCombinedSourceUnit,
  at : String,
) -> Int {
  let count = @strategy.captured_effect_inputs_count(inputs)
  guard count > 0 &&
    drive.artifacts is Some(artifacts) &&
    mock_project_effect_plan_current(value, original.check, original.effect) ==
    0 else {
    return -32
  }
  guard drive.targets is Some(targets) else {
    return begin_original_mock_effect_targets(value, drive, original, count)
  }
  if targets.observations_finished {
    let preview = advance_original_mock_effect_file_preview_rows(
      drive,
      targets,
      original,
      inputs,
      publication,
      compute.dag,
    )
    if preview != 0 {
      return preview
    }
    let plans = advance_original_mock_effect_plan_proofs(
      drive, targets, original,
    )
    if plans != 0 {
      return plans
    }
    if targets.public_receipt is Some(_) {
      let snapshots = advance_original_mock_effect_public_snapshots(
        drive,
        targets,
        @strategy.captured_effect_run_dag(compute.dag),
      )
      if snapshots != 0 {
        return snapshots
      }
      let evidence = advance_original_mock_effect_local_capture(
        drive, targets, original, artifacts, inputs, publication, unit,
      )
      if evidence != 0 {
        return evidence
      }
      if targets.dependencies is Some(dependencies) {
        return advance_original_mock_effect_prepared_capture(
          drive, targets, managed, original, inputs, publication, dependencies, at,
        )
      }
      let dependencies = prepare_original_mock_effect_dependencies(
        value, drive, managed, targets, original, artifacts, inputs, unit,
      )
      if dependencies != 0 {
        return dependencies
      }
      // The projection has returned and its carrier vectors and imports no
      // longer live. The installed dependency controller owns the inventory.
      return if release_original_mock_effect_target_document(drive, targets) {
        1
      } else {
        -9
      }
    }
    return advance_original_mock_effect_public_results(
      drive, targets, original, artifacts, inputs, publication, unit,
    )
  }
  let mut member_index = targets.members.length() - 1
  if member_index < 0 ||
    targets.members[member_index].rows.length() ==
    targets.members[member_index].count {
    if member_index >= 0 {
      let completed = targets.members[member_index]
      if !mock_effect_target_read_current(original, completed.original) {
        return -20
      }
      for row_index, observed in completed.rows {
        guard completed.capture.proposal_row(member_index, row_index)
          is Some(proposal) &&
          physical_equal(proposal, observed.proposal) &&
          observed.body is PendingPreview(_, _, _) &&
          !observed.request.is_empty() &&
          observed.request_cid.has_prefix("sha256:") &&
          observed.request_cid.length() == 71 &&
          observed.version.has_prefix("sha256:") &&
          observed.version.length() == 71 else {
          return -32
        }
      }
    }
    // Release constructor locals and the original document before the next
    // collection can enter. Only immutable row evidence survives.
    if !release_original_mock_effect_target_document(drive, targets) {
      return -9
    }
    member_index += 1
    if member_index == count {
      targets.observations_finished = true
      return 1
    }
    guard targets.selections[member_index] is Some(selected) else { return -32 }
    if !mock_effect_target_read_current(original, selected) {
      return -20
    }
    return retain_original_mock_effect_target_member(
      drive, targets, artifacts, inputs, member_index, selected,
    )
  }
  let held = targets.members[member_index]
  if !mock_effect_target_read_current(original, held.original) {
    return -20
  }
  guard targets.target is Some(target) else {
    return begin_original_mock_effect_target_document(
      drive,
      targets,
      held.original,
      original.effect.data,
    )
  }
  guard held.capture.proposal_row(member_index, held.rows.length())
    is Some(proposal) &&
    proposal.selector().value is @values.Text(identity) else {
    return -32
  }
  let (version, request, request_cid, before, changes) = match
    prepare_observed_mock_effect_file_request(
      drive,
      targets,
      held.original,
      proposal,
      target,
      identity,
    ) {
    Ok(result) => result
    Err(code) => return code
  }
  guard mock_effect_preview_document_charge(before).bind(bytes => {
      mock_effect_preview_document_charge(changes).bind(changes_bytes => {
        @execution.checked_preparation_add_product(bytes, 1L, changes_bytes)
      })
    })
    is Some(source_bytes) &&
    @execution.preparation_representation_cost({
      record_headers: 6L,
      reference_slots: 11L,
      scalar_words: 1L,
      owned_utf16_units: request.length().to_int64() +
      request_cid.length().to_int64() +
      version.length().to_int64(),
      owned_wire_bytes: 0L,
    }).bind(bytes => {
      @execution.checked_preparation_add_product(bytes, 1L, source_bytes)
    })
    is Some(retained) &&
    fund_original_mock_effect_target_bytes(drive, retained) &&
    targets.workspace is Some(workspace) &&
    @resources.shrink_capacity_reservation(
      drive.ledger,
      workspace,
      0L,
      targets.workspace_bytes,
    )
    is Ok(_) else {
    return -4
  }
  held.rows.push({
    proposal,
    body: PendingPreview(before, changes, source_bytes),
    version,
    request,
    request_cid,
  })
  1
}

///|
fn retire_original_mock_effect_targets(
  drive : StoredMockEffectTaskDrive,
) -> Bool {
  if drive.targets is Some(targets) {
    if targets.public_snapshot is Some(issuer) {
      issuer.cancel_after_unwind()
      targets.public_snapshot = None
    }
    if !release_original_mock_effect_target_document(drive, targets) {
      return false
    }
    if targets.plan_verification is Some(active) {
      @strategy.cancel_captured_effect_plan_verifier(active.verifier)
      targets.plan_verification = None
    }
    targets.effect_review = None
    if targets.review_capacity is Some(capacity) {
      if @resources.settle_capacity(drive.ledger, capacity) is Err(_) {
        return false
      }
      targets.review_capacity = None
    }
    targets.plan_proofs = None
    targets.members.clear()
    drive.targets = None
  }
  true
}
