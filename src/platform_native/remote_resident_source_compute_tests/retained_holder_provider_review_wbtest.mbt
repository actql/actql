///|
/// Real producer journal -> independent receiver -> real consumer -> physical
/// Provider observation -> encrypted original review Checkpoint. This is Native
/// integration, not a Cloud waiting commit, approval or external write.
fn retained_holder_provider_review(
  consumer : @resident.ResidentSourceCompute,
  source_owner : @resident.ResidentSourceCompute,
  materials : @host.ClientEffectRunMaterials,
  inputs : @strategy.CapturedEffectInputs,
  dispatch : @remote.DispatchRequest,
  invocation : @publication.PublicationContract,
  observation : @publication.RunEvidenceValue,
  producer : @resident.ResidentEffectProducerCapture,
  receiver : @host.ClientEffectLocalResultArtifact,
  imported : @host.ClientEffectImportedEvidence,
  root_index : Int,
  public_result : @resident.ResidentEffectResultCapture,
  root_path : String,
  name : String,
) -> Unit raise {
  let request = consumer.request_for_effect_review(inputs).unwrap()
  assert_eq(Some(request), materials.request)
  let facts = resident_provider_observe(
    consumer,
    materials,
    inputs,
    producer.acquired,
    dispatch,
    request,
    root_path,
    name,
    original_invocation=Some(invocation),
  ).unwrap()
  let mut result_index = -1
  for index in 0..<@strategy.captured_effect_local_result_count(inputs) {
    if @strategy.captured_effect_local_result_matches_member(inputs, index, 0) {
      result_index = index
    }
  }
  assert_true(result_index >= 0)
  let exported = consumer
    .prepare_effect_result_export(
      inputs,
      result_index,
      resident_compute_limits(),
    )
    .unwrap()
  let receipt = transferred_effect_result_receipt(exported)
  let local_result = @strategy.captured_effect_local_result_at(
    inputs, result_index,
  ).unwrap()
  let result_name = @execution.managed_result_occurrence_name(
    @strategy.captured_any_result_borrow_occurrence(
      @strategy.captured_effect_local_result_borrow(local_result),
    ),
  )
  let definition = @host.issue_client_effect_local_result_definition(
    materials.prepared,
    1,
    result_name,
    65536,
    4096,
    64,
  ).unwrap()
  let artifact = @host.issue_imported_client_effect_local_result_artifact(
    materials.prepared,
    inputs,
    exported,
    imported,
    definition,
    receipt,
    retained_compute_effect_retention(),
    @host.client_effect_allowed_run_admission(materials.allowed),
    materials.run_definition,
    invocation,
    observation,
    65536,
    4096,
    64,
  ).unwrap()
  let (preview, source) = resident_provider_preview(
    consumer, materials, inputs, result_index, artifact, invocation, facts,
  )
  let dependencies = retained_effect_dependency_capture(
    consumer,
    materials,
    inputs,
    receiver,
    artifact,
    root_index,
    result_index,
    exported,
    receipt,
    provider=true,
  )
  let manifest = @host.issue_client_effect_local_manifest(
    materials.prepared,
    @host.client_effect_imported_invocation(imported),
    [artifact],
    65536,
    4096,
    64,
  ).unwrap()
  // A genuine second observation of the retained Source must not replace
  // the original journal fact. It reads the held capture, never the Source.
  let (refreshed, refreshed_bodies) = retained_compute_acquired_evidence(
    source_owner,
  ).unwrap()
  assert_false(
    @publication.run_evidence_value_identity(
      @host.client_effect_acquired_observation(refreshed),
    ) ==
    @publication.run_evidence_value_identity(
      @host.client_effect_acquired_observation(producer.acquired),
    ),
  )
  assert_true(
    @host.issue_client_effect_capture_inventory(
      materials,
      inputs,
      0,
      source,
      manifest,
      artifact,
      imported,
      refreshed,
      refreshed_bodies.0,
      refreshed_bodies.1,
      dependencies,
      [],
      {
        max_entries: 100,
        max_total_bytes: 65536,
        max_depth: 64,
        max_references: 1000,
      },
      10000,
      64,
    )
    is Err(ForeignInput),
  )
  let (local_source, inventory) = retained_effect_capture_inventory(
    materials,
    inputs,
    source,
    manifest,
    artifact,
    imported,
    producer.acquired,
    producer.acquired_bodies,
    dependencies,
  )
  retained_effect_complete_capture(
    consumer,
    materials,
    inputs,
    invocation,
    preview.preview,
    preview.proof,
    source,
    local_source,
    inventory,
    preview.authoring,
    public_result,
    provider=true,
    checkpoint_custody=true,
    review_retention=true,
    private_preview=Some(
      (
        preview.wire,
        @publication.run_evidence_value_identity(preview.authoring),
      ),
    ),
  )
  assert_eq(consumer.request_for_effect_review(inputs), Some(request))
  @execution.cancel_completed_relation_export_receipt(receipt)
  @execution.cancel_completed_result_relation_export(
    @strategy.captured_effect_local_result_export_preparation(exported),
  )
  |> ignore
  println(
    "native-effect-original-review: physical Provider Preview and original Checkpoint retained; no approval or write",
  )
}
