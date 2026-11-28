///|
// Build the physical Source contract from the selected member's original
// Result export and the admitted Run Invocation. The same drive retains it.
fn prepare_original_mock_effect_preview_source(
  drive : StoredMockEffectTaskDrive,
  targets : StoredMockEffectTargetDrive,
  original : MockEffectJournalObservationOriginal,
  selected : StoredMockEffectTargetMember,
  inputs : @strategy.CapturedEffectInputs,
  publication : @host.ClientEffectDirectSourcesPublication,
  member_index : Int,
) -> Result[@publication.PublicationContract, Int] {
  guard targets.workspace is None &&
    selected.preview_identity is Some(_) &&
    selected.preview_source is None &&
    original.configuration.sdk is Some(sdk) &&
    @strategy.captured_effect_input_at(inputs, member_index) is Some(input) else {
    return Err(-32)
  }
  let name = @execution.managed_result_occurrence_name(
    @strategy.captured_effect_input_occurrence(input),
  )
  guard @publication.effect_source_artifact_measurement_inventory(name.length())
    is Some(measurement) &&
    @execution.preparation_representation_cost({
      record_headers: measurement.record_headers,
      reference_slots: measurement.reference_slots,
      scalar_words: measurement.scalar_words,
      owned_utf16_units: measurement.owned_utf16_units,
      owned_wire_bytes: measurement.owned_wire_bytes,
    })
    is Some(entry) &&
    @resources.reserve_capacity(drive.ledger, 0L, entry) is Ok(workspace) else {
    return Err(-4)
  }
  targets.workspace = Some(workspace)
  let invocation = @host.client_effect_direct_sources_publication_invocation(
    publication,
  )
  let limits = @host.client_standard_effect_computation_limits().effects
  @host.issue_client_effect_local_source_artifact(
    original.journal.materials,
    inputs,
    member_index,
    selected.artifact,
    invocation,
    @host.client_effect_local_result_retention(selected.artifact),
    selected.original.binding_cid,
    sdk.store_authority_cid,
    limits.max_admission_text_bytes,
    limits.max_admission_nodes,
    limits.max_admission_depth,
    before_body=Some(geometry => {
      guard @publication.effect_source_artifact_construction_inventory(geometry)
        is Some((retained, seal)) &&
        @execution.preparation_representation_cost({
          record_headers: seal.record_headers,
          reference_slots: seal.reference_slots,
          scalar_words: seal.scalar_words,
          owned_utf16_units: seal.owned_utf16_units,
          owned_wire_bytes: seal.owned_wire_bytes,
        }).bind(bytes => {
          @execution.checked_preparation_add_product(entry, bytes, 1L)
        })
        is Some(peak) &&
        @resources.grow_capacity_reservation(drive.ledger, workspace, 0L, peak)
        is Ok(_) else {
        return false
      }
      fund_original_mock_effect_target_data(drive, {
        record_headers: retained.record_headers,
        reference_slots: retained.reference_slots,
        scalar_words: retained.scalar_words,
        owned_utf16_units: retained.owned_utf16_units,
        owned_wire_bytes: retained.owned_wire_bytes,
      })
    }),
  ).map_err(issue => {
    match issue {
      Artifact(EffectSourceCapacity) => -4
      ForeignInput | ForeignRun | ForeignInvocation | ForeignRetention => -32
      _ => -31
    }
  })
}
