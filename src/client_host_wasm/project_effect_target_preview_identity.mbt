///|
// Derive the preview evidence from the same checked installation, Mapping
// and ordered physical request CIDs. The row bodies remain borrowed.
fn prepare_original_mock_effect_preview_identity(
  drive : StoredMockEffectTaskDrive,
  targets : StoredMockEffectTargetDrive,
  check : StoredMockProjectCheck,
  selected : StoredMockEffectTargetMember,
) -> Result[@host.ClientEffectFilePreviewIdentity, Int] {
  guard targets.workspace is None &&
    selected.preview_identity is None &&
    selected.count == selected.rows.length() &&
    check.runtime_cid is Some(runtime) &&
    selected.original.preparation is Some(prepared) else {
    return Err(-32)
  }
  guard @encode.hash_writer_live_key_inventory(12, 2) is Some(hash) &&
    @execution.preparation_representation_cost({
      record_headers: 2L * hash.record_headers + 28L,
      reference_slots: 2L * hash.reference_slots + 47L,
      scalar_words: 2L * hash.scalar_words + 36L,
      owned_utf16_units: 2L * hash.owned_utf16_units + 2L * 71L,
      owned_wire_bytes: 2L * hash.owned_wire_bytes,
    })
    is Some(bytes) &&
    @resources.reserve_capacity(drive.ledger, 0L, bytes) is Ok(workspace) else {
    return Err(-4)
  }
  targets.workspace = Some(workspace)
  let original = selected.original
  let source = original.source
  let limits = @host.client_standard_effect_computation_limits().effects
  let evidence = match
    @host.client_effect_file_preview_identity(
      {
        connector_registration: source.relation.connector_registration,
        connector_revision: source.relation.connector_version,
        runtime_bundle_cid: runtime,
        binding_cid: original.binding_cid,
        connection: source.connection,
        resource: original.write.mapping.resource,
        mapping_cid: original.write.mapping.mapping_cid,
        primary_identity: prepared.row.primary_identity,
      },
      "update",
      selected.rows.length(),
      index => {
        guard selected.rows.get(index) is Some(row) &&
          row.body is EncodedPreview(_) else {
          return None
        }
        Some(row.request_cid)
      },
      limits.max_admission_text_bytes,
      limits.max_admission_nodes,
      limits.max_admission_depth,
    ) {
    Ok(identity) => identity
    Err(_) => return Err(-31)
  }
  guard fund_original_mock_effect_target_data(drive, {
    record_headers: 4L,
    reference_slots: 4L,
    scalar_words: 0L,
    owned_utf16_units: evidence.capability_cid.length().to_int64() +
    evidence.resource_identity_cid.length().to_int64(),
    owned_wire_bytes: 0L,
  }) else {
    return Err(-4)
  }
  Ok(evidence)
}

///|
// The member retains the checked computation’s exact nominal identity on
// its original capture. Fund the syntax walk before either writer allocates.
fn prepare_original_mock_effect_member_identity(
  drive : StoredMockEffectTaskDrive,
  targets : StoredMockEffectTargetDrive,
  original : MockEffectJournalObservationOriginal,
  selected : StoredMockEffectTargetMember,
  inputs : @strategy.CapturedEffectInputs,
  member_index : Int,
) -> Result[@host.ClientEffectLocalIdentity, Int] {
  guard targets.workspace is None &&
    selected.preview_source is Some(_) &&
    selected.effect_identity is None else {
    return Err(-32)
  }
  guard @execution.preparation_representation_cost({
      record_headers: 36L,
      reference_slots: 52L,
      scalar_words: 44L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(entry) &&
    @resources.reserve_capacity(drive.ledger, 0L, entry) is Ok(workspace) else {
    return Err(-4)
  }
  targets.workspace = Some(workspace)
  let limits = @host.client_standard_effect_computation_limits().effects
  let peak = Ref(entry)
  @host.issue_source_free_client_effect_local_identity(
    original.journal.materials.prepared,
    inputs,
    member_index,
    selected.artifact,
    limits.max_work,
    limits.max_admission_text_bytes,
    limits.max_admission_nodes,
    limits.max_admission_depth,
    fund=Some((working, retained) => {
      guard @execution.preparation_representation_cost(working).bind(bytes => {
          @execution.checked_preparation_add_product(entry, bytes, 1L)
        })
        is Some(total) else {
        return false
      }
      if total > peak.val {
        guard @resources.grow_capacity_reservation(
            drive.ledger,
            workspace,
            0L,
            total,
          )
          is Ok(_) else {
          return false
        }
        peak.val = total
      }
      fund_original_mock_effect_target_data(drive, retained)
    }),
  ).map_err(issue => {
    match issue {
      Capacity => -4
      ForeignInput | MissingMember | ForeignArtifact | MissingMapping => -32
      _ => -31
    }
  })
}
