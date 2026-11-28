///|
fn advance_original_mock_effect_local_capture(
  drive : StoredMockEffectTaskDrive,
  targets : StoredMockEffectTargetDrive,
  original : MockEffectJournalObservationOriginal,
  artifacts : Array[StoredMockEffectArtifact],
  inputs : @strategy.CapturedEffectInputs,
  publication : @host.ClientEffectDirectSourcesPublication,
  unit : @host.ClientEffectCombinedSourceUnit,
) -> Int {
  guard targets.workspace is None &&
    targets.completed is Some(completed) &&
    targets.bound is Some(bound) &&
    physical_equal(
      @strategy.captured_effect_preview_ledger_identity(bound),
      completed.identity,
    ) else {
    return -32
  }
  let invocation = @host.client_effect_combined_source_unit_invocation(unit)
  guard targets.local_manifest is Some(manifest) else {
    return retain_original_mock_effect_local_manifest(
      drive,
      targets,
      original.journal.materials.prepared,
      artifacts,
      invocation,
    )
  }
  let count = targets.members.length()
  guard @publication.effect_preview_member_count(completed.identity) == count else {
    return -32
  }
  guard targets.captured_sources is Some(sources) else {
    guard @execution.preparation_array_representation(
        1L,
        count.to_int64(),
        false,
      )
      is Some(array) &&
      fund_original_mock_effect_target_data(drive, array) else {
      return -4
    }
    targets.captured_sources = Some(Array(capacity=count))
    return 1
  }
  let ordinal = sources.length()
  if ordinal == count {
    return advance_original_mock_effect_local_source_evidence(
      drive,
      targets,
      original.journal.materials.prepared,
      sources,
      manifest,
      invocation,
      inputs,
    )
  }
  guard targets.members.get(ordinal) is Some(selected) &&
    selected.preview_source is Some(physical) &&
    physical_equal(
      @host.client_effect_local_artifact_invocation(selected.artifact),
      invocation,
    ) &&
    original.configuration.sdk is Some(sdk) else {
    return -32
  }
  // The holding hash emits the five closed fields of the original source
  // binding. The Result/source contracts and their CID inputs stay borrowed.
  guard @encode.hash_writer_construction_inventory(32, 2) is Some(writer) &&
    @execution.preparation_representation_cost({
      record_headers: writer.record_headers + 24L,
      reference_slots: writer.reference_slots + 40L,
      scalar_words: writer.scalar_words + 28L,
      owned_utf16_units: writer.owned_utf16_units + 71L,
      owned_wire_bytes: writer.owned_wire_bytes,
    })
    is Some(work) &&
    @resources.reserve_capacity(drive.ledger, 0L, work) is Ok(workspace) else {
    return -4
  }
  targets.workspace = Some(workspace)
  guard @publication.admit_captured_effect_source_from_result(
      completed.identity,
      ordinal,
      @host.client_effect_direct_sources_publication_invocation(publication),
      physical,
      @host.client_effect_local_result_artifact_contract(selected.artifact),
      sdk.store_authority_cid,
    )
    is Ok(source) else {
    return -31
  }
  // Keep each member's distinct holding identity. The physical Artifact,
  // Result, and admitted Preview still have their original owners.
  guard fund_original_mock_effect_target_data(drive, {
    record_headers: 3L,
    reference_slots: 5L,
    scalar_words: 1L,
    owned_utf16_units: 71L,
    owned_wire_bytes: 0L,
  }) else {
    return -4
  }
  sources.push(source)
  if release_original_mock_effect_target_document(drive, targets) {
    1
  } else {
    -9
  }
}

///|
fn retain_original_mock_effect_local_manifest(
  drive : StoredMockEffectTaskDrive,
  targets : StoredMockEffectTargetDrive,
  prepared : @host.PreparedClientEffectComputation,
  artifacts : Array[StoredMockEffectArtifact],
  invocation : @host.ClientEffectLocalInvocation,
) -> Int {
  let limits = @host.client_standard_effect_computation_limits().effects
  let max_bytes = limits.max_admission_text_bytes
  let max_nodes = limits.max_admission_nodes
  let max_depth = limits.max_admission_depth
  guard @execution.preparation_array_representation(
      1L,
      artifacts.length().to_int64(),
      false,
    ).bind(@execution.preparation_representation_cost)
    is Some(view) &&
    @resources.reserve_capacity(drive.ledger, 0L, view) is Ok(workspace) else {
    return -4
  }
  targets.workspace = Some(workspace)
  let selected = Array(capacity=artifacts.length())
  for artifact in artifacts {
    guard physical_equal(
      @host.client_effect_local_artifact_invocation(artifact.artifact),
      invocation,
    ) else {
      return -32
    }
    selected.push(artifact.artifact)
  }
  let cid = @host.client_effect_local_invocation_cid(invocation)
  let mut inventory_retained = 0L
  let mut inventory_peak = 0L
  let mut retained : Int64? = None
  let mut refused = false
  let manifest = @host.issue_client_effect_local_manifest(
    prepared,
    invocation,
    selected,
    max_bytes,
    max_nodes,
    max_depth,
    funding=Some(
      (
        (results, headers, artifacts) => {
          guard @local_host.installed_effect_local_manifest_inventory(
              results, headers, artifacts, max_nodes, max_depth,
            )
            is Some(capacity) &&
            @execution.checked_preparation_add_product(
              view,
              1L,
              @execution.execution_capacity_execution_bytes(capacity),
            )
            is Some(peak) &&
            @resources.grow_capacity_reservation(
              drive.ledger,
              workspace,
              0L,
              peak,
            )
            is Ok(_) else {
            refused = true
            return false
          }
          inventory_retained = @execution.execution_capacity_retained_bytes(
            capacity,
          )
          inventory_peak = peak
          true
        },
        shape => {
          guard @local_host.installed_effect_imported_model_evidence_body_capacity(
              "local_manifest", shape, cid, inventory_peak,
            )
            is Some(capacity) &&
            @resources.grow_capacity_reservation(
              drive.ledger,
              workspace,
              0L,
              @execution.execution_capacity_execution_bytes(capacity),
            )
            is Ok(_) else {
            refused = true
            return false
          }
          retained = @execution.checked_preparation_add_product(
            inventory_retained,
            1L,
            @execution.execution_capacity_retained_bytes(capacity),
          )
          refused = retained is None
          !refused
        },
      ),
    ),
  )
  guard manifest is Ok(manifest) && retained is Some(retained) else {
    return if refused { -4 } else { -31 }
  }
  if !fund_original_mock_effect_target_bytes(drive, retained) {
    return -4
  }
  targets.local_manifest = Some(manifest)
  if release_original_mock_effect_target_document(drive, targets) {
    1
  } else {
    -9
  }
}
