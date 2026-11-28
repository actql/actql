///|
// Reuse the complete checked UPDATE set. It bounds both identity indexes,
// the ordered header/ordinal vectors and all terminal construction already
// validated against these original writable fields during draft preparation.
fn bind_original_mock_effect_completed_preview(
  drive : StoredMockEffectTaskDrive,
  targets : StoredMockEffectTargetDrive,
  original : MockEffectJournalObservationOriginal,
  completed : StoredMockEffectCompletedPreview,
  run : @strategy.CapturedEffectRunDAG,
  inputs : @strategy.CapturedEffectInputs,
  publication : @host.ClientEffectDirectSourcesPublication,
) -> Result[@strategy.CapturedEffectPreviewInputs, Int] {
  let materials = original.journal.materials
  let count = targets.members.length()
  guard targets.workspace is None &&
    targets.bound is None &&
    targets.completed is Some(held) &&
    physical_equal(held, completed) &&
    @host.prepared_client_effect_update_target_count(materials.prepared) ==
    Some(count) &&
    @strategy.captured_effect_inputs_count(inputs) == count &&
    @strategy.captured_effect_input_at(inputs, 0) is Some(first) else {
    return Err(-32)
  }
  let limits = @host.client_standard_effect_computation_limits().effects
  let mut fields = 0
  let mut largest = 0
  for selected in targets.members {
    if !mock_effect_target_read_current(original, selected.original) {
      return Err(-20)
    }
    let member_fields = selected.original.write.writable_fields.length()
    guard member_fields <= 2147483647 - fields else { return Err(-4) }
    fields += member_fields
    largest = Int::max(largest, member_fields)
  }
  let members = count.to_int64()
  guard mock_effect_preview_plan_workspace(largest) is Some(plan) &&
    @shape.collection_construction_extent({
      // Static declaration/Member scans, admitted contracts and capture
      // checks borrow their text. Maps index exact, already admitted IDs.
      records: 68L + 12L * members,
      record_references: 112L + 17L * members,
      record_words: 92L + 9L * members,
      reference_arrays: 3L,
      reference_items: 4L * members,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 2L,
      map_entries: 2L * members,
    })
    is Some(controls) &&
    @execution.preparation_representation_cost({
      record_headers: controls.record_headers,
      reference_slots: controls.reference_slots,
      scalar_words: controls.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    }).bind(bytes => @execution.checked_preparation_add_product(plan, 1L, bytes))
    is Some(quote) &&
    @resources.reserve_capacity(drive.ledger, 0L, quote) is Ok(workspace) else {
    return Err(-4)
  }
  targets.workspace = Some(workspace)
  let identities = Array(capacity=count)
  for selected in targets.members {
    guard selected.effect_identity is Some(identity) else { return Err(-32) }
    identities.push(identity)
  }
  guard targets.draft is Some(draft) &&
    @host.bind_admitted_captured_client_effect_preview(
      materials,
      run,
      inputs,
      @host.client_effect_direct_sources_publication_invocation(publication),
      @strategy.captured_effect_input_stage(first),
      completed.identity,
      @publication.run_evidence_value_identity(draft.authoring),
      identities,
      limits.max_work,
      {
        max_work: limits.max_work,
        max_fields: fields,
        max_bytes: limits.max_admission_text_bytes,
        max_nodes: limits.max_admission_nodes,
        max_depth: limits.max_admission_depth,
      },
    )
    is Ok(bound) else {
    return Err(-32)
  }
  guard @execution.preparation_array_representation(1L, members, true)
    is Some(indexes) &&
    fund_original_mock_effect_target_data(drive, {
      // Captured Preview, run/static binding, original Option and at most
      // one scalar Some ordinal per completed Preview member.
      ..indexes,
      record_headers: indexes.record_headers + 4L + members,
      reference_slots: indexes.reference_slots + 9L,
      scalar_words: indexes.scalar_words + 2L + members,
    }) else {
    return Err(-4)
  }
  Ok(bound)
}
