///|
priv struct StoredMockEffectPublicResult {
  output : @host.PublicationOutputExport
  artifact : @publication.PublicationContract
  retention : @publication.PublicationContract
}

///|
fn advance_original_mock_effect_public_results(
  drive : StoredMockEffectTaskDrive,
  targets : StoredMockEffectTargetDrive,
  original : MockEffectJournalObservationOriginal,
  artifacts : Array[StoredMockEffectArtifact],
  inputs : @strategy.CapturedEffectInputs,
  publication : @host.ClientEffectDirectSourcesPublication,
  unit : @host.ClientEffectCombinedSourceUnit,
) -> Int {
  let materials = original.journal.materials
  let count = @host.prepared_client_effect_result_count(materials.prepared)
  guard count > 0 && targets.bound is Some(_) && targets.workspace is None else {
    return -32
  }
  guard targets.public_results is Some(results) else {
    if !retire_original_mock_effect_preview_inputs(drive, targets) {
      return -9
    }
    guard @execution.preparation_array_representation(
        1L,
        count.to_int64(),
        false,
      )
      is Some(arrays) &&
      fund_original_mock_effect_target_data(drive, arrays) else {
      return -4
    }
    targets.public_results = Some(Array(capacity=count))
    return 1
  }
  let ordinal = results.length()
  if ordinal == count {
    let last = results[count - 1]
    guard last.output.ordering() is Ok(_) &&
      @publication.publication_contract_name(last.retention) ==
      "result_retention_policy" else {
      return -32
    }
    return advance_original_mock_effect_public_manifest(
      drive, targets, materials, results, publication,
    )
  }
  guard ordinal < count else { return -32 }
  let mut selected : StoredMockEffectArtifact? = None
  for artifact in artifacts {
    if @host.client_effect_local_result_artifact_matches_public_result(
        materials.prepared,
        inputs,
        artifact.artifact,
        ordinal,
      ) {
      guard selected is None else { return -32 }
      selected = Some(artifact)
    }
  }
  guard selected is Some(selected) else { return -32 }
  let result = match
    prepare_original_mock_effect_public_result(
      drive, targets, materials, selected, ordinal, inputs, publication, unit,
    ) {
    Ok(value) => value
    Err(code) => return code
  }
  results.push(result)
  if release_original_mock_effect_target_document(drive, targets) {
    1
  } else {
    -9
  }
}

///|
fn prepare_original_mock_effect_public_result(
  drive : StoredMockEffectTaskDrive,
  targets : StoredMockEffectTargetDrive,
  materials : @host.ClientEffectRunMaterials,
  selected : StoredMockEffectArtifact,
  ordinal : Int,
  inputs : @strategy.CapturedEffectInputs,
  publication : @host.ClientEffectDirectSourcesPublication,
  unit : @host.ClientEffectCombinedSourceUnit,
) -> Result[StoredMockEffectPublicResult, Int] {
  guard selected.capture.original() is Some((_, _, receipt)) &&
    physical_equal(
      receipt,
      @host.client_effect_local_relation_export_receipt(selected.artifact),
    ) else {
    return Err(-32)
  }
  let (_, _, relations) = @host.client_effect_combined_source_unit_catalog_subject(
    unit,
  )
  let (_, _, _, _, fields) = @execution.completed_relation_export_scalar_geometry(
    receipt,
  )
  let limits = @host.client_standard_effect_computation_limits().effects
  let slots = relations.to_int64() + fields.to_int64()
  // Measure three fixed metadata emitters and retain only the relation and
  // field reference vectors before the first measured constructor runs.
  guard @encode.measuring_writer_construction_extent(
      40,
      limits.max_admission_depth,
    )
    is Some(measure) &&
    @execution.preparation_array_representation(5L, 2L * slots + 12L, true)
    is Some(arrays) &&
    @execution.preparation_representation_cost({
      record_headers: measure.record_headers + arrays.record_headers + 46L,
      reference_slots: measure.reference_slots + arrays.reference_slots + 70L,
      scalar_words: measure.scalar_words + arrays.scalar_words + 48L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(entry) &&
    @resources.reserve_capacity(drive.ledger, 0L, entry) is Ok(workspace) else {
    return Err(-4)
  }
  targets.workspace = Some(workspace)
  let invocation = @host.client_effect_direct_sources_publication_invocation(
    publication,
  )
  let observation = @host.client_effect_direct_sources_publication_observation(
    publication,
  )
  let retention = @host.client_effect_local_result_retention(selected.artifact)
  guard selected.capture.borrow_publication_output(ordinal) is Ok(output) &&
    @host.client_effect_combined_source_public_result_evidence_refs(
      materials,
      inputs,
      unit,
      selected.artifact,
      ordinal,
      invocation,
      observation,
    )
    is Ok(refs) else {
    return Err(-32)
  }
  let max_bytes = limits.max_admission_text_bytes
  let max_nodes = limits.max_admission_nodes
  let max_depth = limits.max_admission_depth
  guard output.captured_effect_metadata_geometry(
      invocation, retention, refs, max_bytes, max_nodes, max_depth,
    )
    is Ok(shapes) else {
    return Err(-31)
  }
  guard @local_host.installed_effect_public_result_capacity(
      shapes,
      @publication.publication_contract_identity(materials.run_definition),
    )
    is Some(capacity) &&
    @execution.checked_preparation_add_product(
      entry,
      1L,
      @execution.execution_capacity_execution_bytes(capacity),
    )
    is Some(peak) &&
    @resources.grow_capacity_reservation(drive.ledger, workspace, 0L, peak)
    is Ok(_) else {
    return Err(-4)
  }
  let (computation, relations, scope, policy, authority) = refs
  guard output.issue_result_evidence(
      computation, relations, scope, policy, authority, max_bytes, max_nodes, max_depth,
    )
    is Ok(_) else {
    return Err(-31)
  }
  guard output.issue_artifact(
      invocation, retention, max_bytes, max_nodes, max_depth,
    )
    is Ok(artifact) else {
    return Err(-31)
  }
  guard output.captured_effect_metadata_retained_bytes(max_nodes, max_depth)
    is Some(retained) &&
    fund_original_mock_effect_target_bytes(drive, retained) else {
    return Err(-4)
  }
  Ok({ output, artifact, retention, })
}

///|
// The completed, bound Preview owns these intermediate row and member
// documents. Apply still retains each original proposal, request and version.
fn retire_original_mock_effect_preview_inputs(
  drive : StoredMockEffectTaskDrive,
  targets : StoredMockEffectTargetDrive,
) -> Bool {
  guard targets.completed is Some(_) && targets.bound is Some(_) else {
    return false
  }
  let mut amount = 0L
  for selected in targets.members {
    guard selected.draft_fields is Some(draft) &&
      @execution.checked_preparation_add_product(
        amount,
        1L,
        draft.retained_bytes,
      )
      is Some(total) else {
      return false
    }
    amount = total
    for row in selected.rows {
      guard row.body is EncodedPreview(document) &&
        mock_effect_preview_document_charge(document) is Some(bytes) &&
        @execution.checked_preparation_add_product(amount, 1L, bytes)
        is Some(total) else {
        return false
      }
      amount = total
    }
  }
  for selected in targets.members {
    selected.draft_fields = None
    for row in selected.rows {
      row.body = PreviewRetired
    }
  }
  return_original_mock_effect_target_bytes(drive, amount)
}

///|
fn advance_original_mock_effect_public_manifest(
  drive : StoredMockEffectTaskDrive,
  targets : StoredMockEffectTargetDrive,
  materials : @host.ClientEffectRunMaterials,
  results : Array[StoredMockEffectPublicResult],
  publication : @host.ClientEffectDirectSourcesPublication,
) -> Int {
  if targets.public_manifest is Some(manifest) {
    return advance_original_mock_effect_public_receipt(
      drive, targets, materials, manifest, publication,
    )
  }
  let count = results.length()
  let limits = @host.client_standard_effect_computation_limits().effects
  let max_bytes = limits.max_admission_text_bytes
  let max_nodes = limits.max_admission_nodes
  let max_depth = limits.max_admission_depth
  guard @execution.preparation_array_representation(
      2L,
      2L * count.to_int64(),
      false,
    )
    is Some(vectors) &&
    @execution.preparation_representation_cost({
      ..vectors,
      record_headers: vectors.record_headers + 3L,
      reference_slots: vectors.reference_slots + 6L,
      scalar_words: vectors.scalar_words + 1L,
    })
    is Some(inputs) &&
    @local_host.installed_effect_public_manifest_inventory(count, max_depth)
    is Some(inventory) &&
    @execution.checked_preparation_add_product(inputs, inventory, 1L)
    is Some(initial) &&
    @resources.reserve_capacity(drive.ledger, 0L, initial) is Ok(workspace) else {
    return -4
  }
  targets.workspace = Some(workspace)
  let definitions = Array(capacity=count)
  let artifacts = Array(capacity=count)
  for result in results {
    guard result.output.definition() is Ok(definition) else { return -32 }
    definitions.push(definition)
    artifacts.push(result.artifact)
  }
  let mut retained : Int64? = None
  let mut funding_refused = false
  let invocation = @host.client_effect_direct_sources_publication_invocation(
    publication,
  )
  let manifest = @publication.issue_result_manifest(
    materials.run_definition,
    invocation,
    definitions,
    artifacts,
    max_bytes,
    max_nodes,
    max_depth,
    funding=Some(
      (
        actual => actual == count,
        (bytes, nodes, depth) => {
          guard @local_host.installed_effect_public_manifest_capacity(
              artifacts, bytes, nodes, depth, max_bytes, max_nodes, inventory,
            )
            is Some(capacity) &&
            @execution.checked_preparation_add_product(
              inputs,
              @execution.execution_capacity_execution_bytes(capacity),
              1L,
            )
            is Some(peak) &&
            @resources.grow_capacity_reservation(
              drive.ledger,
              workspace,
              0L,
              peak,
            )
            is Ok(_) else {
            funding_refused = true
            return false
          }
          retained = Some(
            @execution.execution_capacity_retained_bytes(capacity),
          )
          true
        },
      ),
    ),
  )
  guard manifest is Ok(manifest) && retained is Some(retained) else {
    return if funding_refused { -4 } else { -31 }
  }
  guard @execution.checked_preparation_add_product(retained, 1L, inputs)
    is Some(hold) &&
    fund_original_mock_effect_target_bytes(drive, hold) else {
    return -4
  }
  targets.public_manifest = Some({ manifest, definitions, artifacts, })
  if release_original_mock_effect_target_document(drive, targets) {
    1
  } else {
    -9
  }
}
