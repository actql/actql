///|
// The capture's checked fields are sorted, unique and retain their admitted
// values. The installed Mapping supplies the exact expected field set.
fn emit_original_mock_effect_target_changes(
  proposal : @local_host.InstalledEffectResultProposal,
  writable : Array[String],
  writer : @encode.Writer,
) -> Bool raise @encode.EncodeFailure {
  if writable.is_empty() || proposal.field_at(writable.length()) is Some(_) {
    return false
  }
  @encode.begin_object(writer)
  for index in 0..<writable.length() {
    guard proposal.field_at(index) is Some((name, value)) &&
      writable.contains(name) else {
      return false
    }
    @encode.key(writer, name)
    @values.emit_checked_wire_value(value, writer)
  }
  @encode.end_object(writer)
  true
}

///|
// Both the initial measurement and the authored change body use this same
// writer envelope. The retained Row and its source values are still borrowed.
fn mock_effect_target_changes_workspace(
  limits : @row_host.RowPageLimits,
  bytes : Int,
) -> Int64? {
  let slots = 8 + limits.max_nodes + 2 * limits.max_depth
  guard @encode.text_writer_construction_inventory(
      bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    is Some(writer) &&
    @values.wire_emit_workspace_construction_inventory(slots) is Some(emitter) else {
    return None
  }
  @execution.preparation_representation_cost({
    record_headers: writer.record_headers + emitter.record_headers + 21L,
    reference_slots: writer.reference_slots + emitter.reference_slots + 41L,
    scalar_words: writer.scalar_words + emitter.scalar_words + 31L,
    owned_utf16_units: writer.owned_utf16_units + emitter.owned_utf16_units,
    owned_wire_bytes: 0L,
  })
}

///|
fn validate_original_mock_effect_target_changes(
  drive : StoredMockEffectTaskDrive,
  targets : StoredMockEffectTargetDrive,
  selected : StoredMockProjectWriteTarget,
  proposal : @local_host.InstalledEffectResultProposal,
  target : @row_host.RelationTargetDocument,
  row : @row_host.RelationTargetRow,
  version : String,
) -> Result[@encode.EncodedDocument, Int] {
  guard selected.preparation is Some(prepared) &&
    targets.workspace is Some(workspace) else {
    return Err(-32)
  }
  let limits = prepared.limits
  let writable = selected.write.mapping.write_fields
  guard mock_effect_target_changes_workspace(limits, 0).bind(bytes => {
      @execution.checked_preparation_add_product(
        targets.workspace_bytes,
        1L,
        bytes,
      )
    })
    is Some(measurement) &&
    @resources.grow_capacity_reservation(
      drive.ledger,
      workspace,
      0L,
      measurement,
    )
    is Ok(_) else {
    return Err(-4)
  }
  let (bytes, _, _) = try {
    let writer = @encode.measuring_writer(
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    if !emit_original_mock_effect_target_changes(proposal, writable, writer) {
      return Err(-31)
    }
    @encode.finish_measurement_usage(writer)
  } catch {
    _ => return Err(-31)
  }
  let contract = @row_host.relation_document_prepared_contract(
    prepared.contract,
  )
  guard @row_host.relation_target_write_wire_construction(
      contract,
      limits,
      prepared.data.length(),
      bytes,
      deleting=false,
    )
    is Some(layout) &&
    @execution.preparation_representation_cost(layout.placement) is Some(check) &&
    mock_effect_target_changes_workspace(limits, bytes)
    .bind(emit => {
      @execution.checked_preparation_add_product(
        targets.workspace_bytes,
        1L,
        emit,
      )
    })
    .bind(emit => @execution.checked_preparation_add_product(emit, 1L, check))
    is Some(total) &&
    @resources.grow_capacity_reservation(drive.ledger, workspace, 0L, total)
    is Ok(_) else {
    return Err(-4)
  }
  let changes = try {
    let writer = @encode.writer(bytes, limits.max_nodes, limits.max_depth)
    if !emit_original_mock_effect_target_changes(proposal, writable, writer) {
      return Err(-31)
    }
    @encode.finish_document(writer)
  } catch {
    _ => return Err(-31)
  }
  match
    @row_host.check_relation_target_update(
      target,
      row,
      version,
      @encode.document_text(changes),
      16777216,
    ) {
    Ok(_) => Ok(changes)
    Err(_) => Err(-31)
  }
}
