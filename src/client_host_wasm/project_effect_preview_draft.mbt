///|
priv struct StoredMockEffectMemberDraft {
  fields : @host.ClientEffectFilePreviewMemberDraft
  permissions : Array[String]
  retained_bytes : Int64
}

///|
priv struct StoredMockEffectPreviewDraft {
  authoring : @publication.RunEvidenceValue
  mut document : @encode.EncodedDocument?
}

///|
// The checked terminal borrows field text. Cover its ordered field vectors,
// selection carriers and pipeline hash writer before the constructor.
fn mock_effect_preview_plan_workspace(fields : Int) -> Int64? {
  let slots = fields.to_int64()
  guard fields <= 536870903 &&
    @execution.preparation_array_representation(5L, 10L * slots, true)
    is Some(arrays) &&
    @encode.hash_writer_live_key_inventory(32 + 4 * fields, 10) is Some(hash) else {
    return None
  }
  @execution.preparation_representation_cost({
    record_headers: hash.record_headers +
    arrays.record_headers +
    48L +
    6L * slots,
    reference_slots: hash.reference_slots +
    arrays.reference_slots +
    72L +
    8L * slots,
    scalar_words: hash.scalar_words + arrays.scalar_words + 54L + 6L * slots,
    owned_utf16_units: hash.owned_utf16_units + 71L,
    owned_wire_bytes: hash.owned_wire_bytes,
  })
}

///|
fn prepare_original_mock_effect_member_draft(
  drive : StoredMockEffectTaskDrive,
  targets : StoredMockEffectTargetDrive,
  original : MockEffectJournalObservationOriginal,
  selected : StoredMockEffectTargetMember,
  inputs : @strategy.CapturedEffectInputs,
  index : Int,
) -> Result[StoredMockEffectMemberDraft, Int] {
  guard targets.workspace is None &&
    selected.draft_fields is None &&
    selected.preview_source is Some(_) &&
    selected.preview_identity is Some(capability) &&
    selected.effect_identity is Some(identity) else {
    return Err(-32)
  }
  let target = selected.original
  let mapping = target.write.mapping
  let fields = target.write.writable_fields.length()
  guard mock_effect_preview_plan_workspace(fields) is Some(bytes) &&
    @resources.reserve_capacity(drive.ledger, 0L, bytes) is Ok(workspace) else {
    return Err(-4)
  }
  targets.workspace = Some(workspace)
  let mut retained_bytes = 0L
  let declined = Ref(false)
  let (fields, permissions) = match
    @host.prepare_client_effect_file_preview_member_draft(
      original.journal.materials.prepared,
      original.effect.request,
      inputs,
      index,
      selected.artifact,
      identity,
      target.target,
      mapping.mapping_ref,
      mapping.mapping_cid,
      target.binding_cid,
      mapping.resource,
      capability,
      selected.rows.length(),
      fields,
      @host.client_standard_effect_computation_limits(),
      count => {
        let capacity = mock_effect_preview_member_draft_bytes(count)
        let funded = match capacity {
          Some(bytes) =>
            if fund_original_mock_effect_target_bytes(drive, bytes) {
              retained_bytes = bytes
              true
            } else {
              false
            }
          None => false
        }
        declined.val = !funded
        funded
      },
    ) {
    Ok(value) => value
    Err(_) => return Err(if declined.val { -4 } else { -32 })
  }
  Ok({ fields, permissions, retained_bytes, })
}

///|
fn mock_effect_preview_member_draft_bytes(count : Int) -> Int64? {
  @execution.preparation_array_representation(1L, count.to_int64(), true).bind(array => {
    @execution.preparation_representation_cost({
      ..array,
      record_headers: array.record_headers + 5L,
      reference_slots: array.reference_slots + 22L,
      scalar_words: array.scalar_words + 4L,
      owned_utf16_units: 71L,
    })
  })
}

///|
fn mock_effect_preview_draft_workspace(bytes : Int) -> Int64? {
  guard @encode.text_writer_live_key_inventory(bytes, 54, 8) is Some(writer) else {
    return None
  }
  @execution.preparation_representation_cost({
    // Root, member and footprint field emitter arrays may be nested.
    // Each member borrows already admitted row documents and scalars.
    record_headers: writer.record_headers + 168L,
    reference_slots: writer.reference_slots + 238L,
    scalar_words: writer.scalar_words + 118L,
    owned_utf16_units: writer.owned_utf16_units,
    owned_wire_bytes: 0L,
  })
}

///|
fn prepare_original_mock_effect_preview_draft(
  drive : StoredMockEffectTaskDrive,
  targets : StoredMockEffectTargetDrive,
  original : MockEffectJournalObservationOriginal,
  publication : @host.ClientEffectDirectSourcesPublication,
) -> Result[StoredMockEffectPreviewDraft, Int] {
  guard targets.workspace is None &&
    targets.preview_member == targets.members.length() &&
    !targets.members.is_empty() else {
    return Err(-32)
  }
  if !targets.members.all(selected => {
      mock_effect_target_read_current(original, selected.original)
    }) {
    return Err(-20)
  }
  let materials = original.journal.materials
  let program = @host.prepared_client_effect_computation_definition_cid(
    materials.prepared,
  )
  let invocation = @host.client_effect_direct_sources_publication_invocation(
    publication,
  )
  guard program.length() == 71 &&
    @host.client_protocol_metadata_construction_bytes(512, 32L)
    is Some((authoring_bytes, _)) &&
    mock_effect_preview_draft_workspace(0) is Some(measure_bytes) &&
    @execution.checked_preparation_add_product(
      authoring_bytes, measure_bytes, 1L,
    )
    is Some(entry) &&
    @resources.reserve_capacity(drive.ledger, 0L, entry) is Ok(workspace) else {
    return Err(-4)
  }
  targets.workspace = Some(workspace)
  let authoring_wire = try {
    let writer = @encode.writer(512, 24, 4)
    @encode.begin_ordered_object(writer)
    @encode.ordered_key(writer, "annotations")
    @encode.begin_array(writer)
    @encode.end_array(writer)
    @encode.ordered_key(writer, "program_definition_cid")
    @encode.string_value(writer, program)
    @encode.ordered_key(writer, "version")
    @encode.string_value(writer, "actql-authoring-context/0.1")
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => return Err(-31)
  }
  guard @publication.seal_run_evidence_value(
      "authoring_context", authoring_wire, 512, 24, 4,
    )
    is Ok(authoring) else {
    return Err(-31)
  }
  let authoring_document = @publication.run_evidence_value_document(
    authoring, 512, 24, 4,
  ) catch {
    _ => return Err(-31)
  }
  let header : @host.ClientEffectFilePreviewDraftHeader = {
    check_environment_cid: @host.prepared_client_effect_computation_environment_cid(
      materials.prepared,
    ),
    compiled_plan_cid: @publication.publication_contract_identity(
      @host.client_effect_compilation_compiled_plan(materials.compilation),
    ),
    invocation_cid: @publication.publication_contract_identity(invocation),
    program_definition_cid: program,
    program_semantics_cid: @host.prepared_client_effect_computation_semantics_cid(
      materials.prepared,
    ),
    run_cid: @publication.publication_contract_identity(
      materials.run_definition,
    ),
    pending_cid: MOCK_EFFECT_PREVIEW_PENDING_CID,
    barriers: [],
    model_task: None,
    model_invocations: [],
    model_responses: [],
  }
  let emit : (@encode.Writer) -> Unit raise @encode.EncodeFailure = writer => {
    @host.emit_client_effect_file_preview_draft(
      writer,
      header,
      authoring_document,
      targets.members.length(),
      (index, out) => {
        guard targets.members.get(index) is Some(selected) &&
          selected.draft_fields is Some(draft) &&
          draft.fields.count == selected.rows.length() else {
          raise @encode.InvalidStructure
        }
        @host.emit_client_effect_file_preview_member(
          out,
          draft.fields,
          header.pending_cid,
          row => {
            guard selected.rows.get(row) is Some(row) &&
              row.body is EncodedPreview(document) else {
              return None
            }
            Some(document)
          },
          draft.permissions.length(),
          index => draft.permissions.get(index),
        )
      },
    )
  }
  let limits = @host.client_standard_effect_computation_limits().effects
  let (bytes, nodes, depth) = try {
    let writer = @encode.measuring_writer(
      limits.max_admission_text_bytes,
      limits.max_admission_nodes,
      limits.max_admission_depth,
    )
    emit(writer)
    @encode.finish_measurement_usage(writer)
  } catch {
    _ => return Err(-31)
  }
  guard mock_effect_preview_draft_workspace(bytes) is Some(final_bytes) &&
    @execution.checked_preparation_add_product(authoring_bytes, final_bytes, 1L)
    is Some(peak) &&
    @resources.grow_capacity_reservation(drive.ledger, workspace, 0L, peak)
    is Ok(_) else {
    return Err(-4)
  }
  let document = try {
    let writer = @encode.writer(bytes, nodes, depth)
    emit(writer)
    @encode.finish_document(writer)
  } catch {
    _ => return Err(-31)
  }
  guard @encode.document_usage(document) == (bytes, nodes, depth) &&
    mock_effect_preview_document_charge(document).bind(output => {
      @execution.checked_preparation_add_product(
        authoring_bytes + 32L,
        output,
        1L,
      )
    })
    is Some(retained) &&
    fund_original_mock_effect_target_bytes(drive, retained) else {
    return Err(-4)
  }
  Ok({ authoring, document: Some(document), })
}

///|
fn prepare_original_mock_effect_semantic_preview(
  drive : StoredMockEffectTaskDrive,
  targets : StoredMockEffectTargetDrive,
  original : MockEffectJournalObservationOriginal,
  draft : StoredMockEffectPreviewDraft,
) -> Result[@publication.AuthoredEffectPreview, Int] {
  guard targets.workspace is None &&
    targets.authored is None &&
    draft.document is Some(document) else {
    return Err(-32)
  }
  if !targets.members.all(selected => {
      mock_effect_target_read_current(original, selected.original)
    }) {
    return Err(-20)
  }
  let (bytes, nodes, depth) = @encode.document_usage(document)
  let mut rows = 0
  for selected in targets.members {
    guard selected.rows.length() <= nodes - rows else { return Err(-32) }
    rows += selected.rows.length()
  }
  let limits = @host.client_standard_effect_computation_limits().effects
  let wire = @encode.document_text(document)
  guard @publication.effect_preview_semantic_authoring_construction_inventory(
      bytes,
      nodes,
      depth,
      rows,
      limits.max_admission_text_bytes,
      limits.max_admission_nodes,
    )
    is Some(inventory) &&
    @execution.preparation_representation_cost({
      record_headers: inventory.record_headers + 5L,
      reference_slots: inventory.reference_slots + 7L,
      scalar_words: inventory.scalar_words + 9L,
      owned_utf16_units: inventory.owned_utf16_units + wire.length().to_int64(),
      owned_wire_bytes: inventory.owned_wire_bytes,
    })
    is Some(quote) &&
    @resources.reserve_capacity(drive.ledger, 0L, quote) is Ok(workspace) else {
    return Err(-4)
  }
  targets.workspace = Some(workspace)
  let run = @publication.publication_contract_identity(
    original.journal.materials.run_definition,
  )
  let authoring = @publication.run_evidence_value_identity(draft.authoring)
  guard @publication.prepare_authored_effect_preview(
      wire,
      run,
      authoring,
      limits.max_admission_text_bytes,
      limits.max_admission_nodes,
      limits.max_admission_depth,
    )
    is Ok(authored) else {
    return Err(-31)
  }
  let identity = @publication.authored_effect_preview_identity(authored)
  guard @publication.effect_preview_member_count(identity) ==
    targets.members.length() else {
    return Err(-32)
  }
  for index, selected in targets.members {
    guard @publication.effect_preview_row_count(identity, index) ==
      Some(selected.rows.length()) else {
      return Err(-32)
    }
  }
  guard @publication.authored_effect_preview_retained_inventory(authored)
    is Some(retained) &&
    fund_original_mock_effect_target_data(drive, {
      record_headers: retained.record_headers,
      reference_slots: retained.reference_slots,
      scalar_words: retained.scalar_words,
      owned_utf16_units: retained.owned_utf16_units,
      owned_wire_bytes: retained.owned_wire_bytes,
    }) else {
    return Err(-4)
  }
  Ok(authored)
}

///|
// Authoring's synchronous borrow returned during the preceding advance. The
// context and the admitted Preview remain on this Compute; only the superseded
// document and its exact charge can return before the next constructor.
fn retire_original_mock_effect_preview_draft_document(
  drive : StoredMockEffectTaskDrive,
  draft : StoredMockEffectPreviewDraft,
) -> Bool {
  let bytes = match draft.document {
    Some(document) => mock_effect_preview_document_charge(document)
    None => return true
  }
  guard bytes is Some(amount) else { return false }
  draft.document = None
  return_original_mock_effect_target_bytes(drive, amount)
}
