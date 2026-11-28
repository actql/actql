///|
fn advance_original_mock_effect_local_source_evidence(
  drive : StoredMockEffectTaskDrive,
  targets : StoredMockEffectTargetDrive,
  prepared : @host.PreparedClientEffectComputation,
  sources : Array[@publication.CapturedEffectSourceArtifact],
  manifest : @host.ClientEffectLocalManifest,
  invocation : @host.ClientEffectLocalInvocation,
  inputs : @strategy.CapturedEffectInputs,
) -> Int {
  let count = sources.length()
  guard targets.captured_local_sources is Some(locals) else {
    guard @execution.preparation_array_representation(
        1L,
        count.to_int64(),
        false,
      )
      is Some(array) &&
      fund_original_mock_effect_target_data(drive, array) else {
      return -4
    }
    targets.captured_local_sources = Some(Array(capacity=count))
    return 1
  }
  let ordinal = locals.length()
  if ordinal == count {
    return 0
  }
  guard targets.members.get(ordinal) is Some(selected) else { return -32 }
  let limits = @host.client_standard_effect_computation_limits().effects
  let max_bytes = limits.max_admission_text_bytes
  let max_nodes = limits.max_admission_nodes
  let max_depth = limits.max_admission_depth
  let control = @source.json_source_preflight_control_extent()
  guard @execution.preparation_representation_cost({
      // Three lexical estimates, one scanner at a time, and the final
      // canonical representation walk bounded by the same depth.
      record_headers: control.record_headers + 48L + 2L * max_depth.to_int64(),
      reference_slots: control.reference_slots + 72L + 4L * max_depth.to_int64(),
      scalar_words: control.scalar_words + 60L + 3L * max_depth.to_int64(),
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(entry) &&
    @resources.reserve_capacity(drive.ledger, 0L, entry) is Ok(workspace) else {
    return -4
  }
  targets.workspace = Some(workspace)
  guard @host.client_effect_local_source_evidence_geometry(
      manifest,
      selected.artifact,
      max_bytes,
      max_nodes,
      max_depth,
    )
    is Some((bytes, nodes, depth)) else {
    return -31
  }
  guard @local_host.installed_effect_canonical_body_capacity(
      bytes, nodes, depth,
    )
    is Some(body) &&
    @execution.checked_preparation_add_product(
      entry,
      @execution.execution_capacity_execution_bytes(body),
      2L,
    )
    is Some(peak) &&
    @resources.grow_capacity_reservation(drive.ledger, workspace, 0L, peak)
    is Ok(_) else {
    return -4
  }
  guard @host.admit_client_effect_local_source_evidence(
      prepared,
      inputs,
      ordinal,
      manifest,
      invocation,
      selected.artifact,
      sources[ordinal],
      max_bytes,
      max_nodes,
      max_depth,
    )
    is Ok(evidence) else {
    return -31
  }
  guard @publication.captured_local_effect_source_representation_extent(
      evidence, max_nodes, max_depth, max_bytes,
    )
    is Some(extent) &&
    @execution.canonical_preparation_retained_bytes(extent, 1L, 2L, 0L, 0L)
    is Some(retained) &&
    fund_original_mock_effect_target_bytes(drive, retained) else {
    return -4
  }
  locals.push(evidence)
  if release_original_mock_effect_target_document(drive, targets) {
    1
  } else {
    -9
  }
}
