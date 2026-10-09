///|
fn retained_effect_producer_dependency(
  owner : @resident.ResidentSourceCompute,
  materials : @host.ClientEffectRunMaterials,
  source : @host.ClientEffectAcquiredEvidence,
  started_at? : String = "2026-10-09T01:00:00.000Z",
  completed_at? : String = "2026-10-09T01:00:01.000Z",
  original_invocation? : (
    @publication.RunEvidenceValue,
    @publication.PublicationContract,
  )? = None,
) -> (
  @strategy.CapturedEffectLocalUnitInputs,
  @host.ClientEffectLocalResultArtifact,
  @host.ClientEffectLocalManifest,
  @execution.CompletedRelationExportReceipt,
  @host.ClientEffectProducerArtifact,
) raise {
  println("retained-effect-evidence: producer-pins")
  let inputs = @strategy.pin_captured_effect_acquired_unit_results(
    owner.effect_run().unwrap(),
    0,
    4,
  ).unwrap()
  let limits = resident_compute_limits()
  let exported = @strategy.start_captured_effect_local_unit_result_export(
    inputs,
    0,
    {
      max_fields: limits.max_result_fields,
      max_mapping_work: limits.max_result_mapping_work,
      max_order_work: limits.max_result_order_work,
      max_workspace_entries: limits.max_result_workspace_entries,
    },
    limits.max_rows,
    limits.values,
    limits.payload_wire,
    limits.logical_wire,
    limits.schema,
    limits.max_batch_bytes,
  ).unwrap()
  let receipt = transferred_effect_result_receipt(exported)
  println("retained-effect-evidence: producer-export-complete")
  let (observation, invocation) = match original_invocation {
    Some(value) => value
    None =>
      producer_dependency_observation(
        materials,
        source,
        started_at~,
        completed_at~,
      )
  }
  let definition = @host.issue_client_effect_local_result_definition(
    materials.prepared,
    0,
    "r",
    65536,
    4096,
    64,
  ).unwrap()
  let artifact = @host.issue_acquired_client_effect_unit_result_artifact(
    materials.prepared,
    inputs,
    exported,
    source,
    definition,
    receipt,
    @host.client_effect_allowed_run_admission(materials.allowed),
    materials.run_definition,
    invocation,
    observation,
    65536,
    4096,
    64,
  ).unwrap()
  println("retained-effect-evidence: producer-artifact-complete")
  let manifest = @host.issue_client_effect_local_manifest(
    materials.prepared,
    @host.client_effect_acquired_invocation(source),
    [artifact],
    65536,
    4096,
    64,
  ).unwrap()
  let token = owner.bind_effect_producer_artifact(artifact).unwrap()
  let foreign_dispatch = @host.prepare_client_effect_source_dispatch(
    materials.allowed,
    materials.run_definition,
    @host.prepare_client_effect_request_identity(
      materials.prepared,
      retained_compute_cid("c"),
      "original-effect-caller",
      @host.source_free_caller_input_intent_cid(),
    ).unwrap(),
    2,
    "another-producer",
    retained_compute_selection(),
  ).unwrap()
  let foreign = @host.bind_client_effect_source_dispatch(
    materials,
    foreign_dispatch,
    @host.prepare_client_effect_source_input_binding(materials.compilation).unwrap(),
  ).unwrap()
  assert_true(
    @host.bind_client_effect_producer_artifact(
      foreign,
      owner.effect_run().unwrap(),
      artifact,
    )
    is Err(ForeignInput),
  )
  let unbound = @host.bind_client_effect_compiled_run(
    materials.prepared,
    materials.allowed,
    materials.run_definition,
  ).unwrap()
  assert_true(
    @host.bind_client_effect_producer_artifact(
      unbound,
      owner.effect_run().unwrap(),
      artifact,
    )
    is Err(ForeignInput),
  )
  (inputs, artifact, manifest, receipt, token)
}

///|
fn transferred_effect_result_receipt(
  exported : @strategy.CapturedEffectLocalResultExport,
) -> @execution.CompletedRelationExportReceipt {
  let preparation = @strategy.captured_effect_local_result_export_preparation(
    exported,
  )
  while !@execution.advance_completed_result_relation_export(preparation, 16).unwrap().0 {
    continue
  }
  let stream = @execution.finish_completed_result_relation_export_preparation(
    preparation,
  ).unwrap()
  while @execution.next_completed_output_export(stream).unwrap() is Some(_) {
    continue
  }
  @execution.finish_completed_relation_export(stream).unwrap().0
}

///|
// The existing actual DuckDB/SQLite/Direct Transfer fixture calls this after
// consumer completion. Original producer semantic evidence remains separate
// from the independently admitted receiver borrow and its actual Result view.
fn retained_effect_transferred_artifact(
  consumer : @resident.ResidentSourceCompute,
  materials : @host.ClientEffectRunMaterials,
  inputs : @strategy.CapturedEffectInputs,
  root_index : Int,
  result_index : Int,
  source : @host.ClientEffectAcquiredEvidence,
  acquired_bodies : (String, String),
  foreign_invocation : @host.ClientEffectLocalInvocation,
  sender_inputs : @strategy.CapturedEffectLocalUnitInputs,
  sender : @host.ClientEffectLocalResultArtifact,
  sender_manifest : @host.ClientEffectLocalManifest,
  producer_token : @host.ClientEffectProducerArtifact,
  common_input : @host.ClientRetainedTaskInput,
  site : @site.ExecutionSite,
  public_result : @host.PublicationOutputExport,
  stop_custodies : Array[(@resident.ResidentEffectSourceCustody, @store.Store)],
) -> Unit raise {
  println("retained-effect-evidence: receiver-export")
  let root_export = consumer
    .prepare_effect_result_export(inputs, root_index, resident_compute_limits())
    .unwrap()
  let receipt = transferred_effect_result_receipt(root_export)
  let imported = @strategy.capture_effect_result_import(inputs, 1, 0, 10000).unwrap()
  println("retained-effect-evidence: receiver-import-captured")
  // The ordinary local-view issuer still refuses the producer's distinct
  // acquired borrow. Equal bytes do not bypass that existing custody check.
  assert_true(
    @host.issue_client_effect_result_import_observation(
      materials.prepared,
      inputs,
      imported,
      sender_manifest,
      sender,
      65536,
      4096,
      64,
    )
    is Err(ForeignArtifact),
  )
  let receiver = consumer
    .bind_effect_retained_result_artifact(
      materials, inputs, imported, root_export, receipt, producer_token,
    )
    .unwrap()
  println("retained-effect-evidence: receiver-artifact-bound")
  assert_eq(
    @host.client_effect_local_result_artifact_json(receiver),
    @host.client_effect_local_result_artifact_json(sender),
  )
  assert_eq(
    @host.client_effect_local_invocation_cid(foreign_invocation),
    @host.client_effect_local_invocation_cid(
      @host.client_effect_acquired_invocation(source),
    ),
  )
  assert_true(
    @host.issue_client_effect_local_manifest(
      materials.prepared,
      foreign_invocation,
      [receiver],
      65536,
      4096,
      64,
    )
    is Err(ForeignArtifact),
  )
  let manifest = @host.issue_client_effect_local_manifest(
    materials.prepared,
    @host.client_effect_acquired_invocation(source),
    [receiver],
    65536,
    4096,
    64,
  ).unwrap()
  println("retained-effect-evidence: receiver-manifest-complete")
  assert_eq(
    @host.client_effect_local_manifest_json(manifest),
    @host.client_effect_local_manifest_json(sender_manifest),
  )
  let observation = @host.issue_client_effect_result_import_observation(
    materials.prepared,
    inputs,
    imported,
    manifest,
    receiver,
    65536,
    4096,
    64,
  ).unwrap()
  println("retained-effect-evidence: import-observation-complete")
  assert_true(
    @host.client_effect_result_import_observation_json(observation).contains(
      @host.client_effect_local_result_artifact_cid(sender),
    ),
  )
  let evidence = @host.issue_client_effect_imported_evidence(
    materials.prepared,
    inputs,
    1,
    [observation],
    65536,
    4096,
    64,
  ).unwrap()
  println("retained-effect-evidence: imported-evidence-complete")
  assert_eq(@host.client_effect_imported_relation_bodies(evidence).length(), 1)
  let result_export = consumer
    .prepare_effect_result_export(
      inputs,
      result_index,
      resident_compute_limits(),
    )
    .unwrap()
  let result_receipt = transferred_effect_result_receipt(result_export)
  assert_true(
    consumer.bind_effect_retained_result_artifact(
      materials, inputs, imported, result_export, result_receipt, producer_token,
    )
    is Err(ForeignInput),
  )
  assert_true(
    consumer.bind_effect_retained_result_artifact(
      materials, inputs, imported, root_export, result_receipt, producer_token,
    )
    is Err(ForeignExport),
  )
  let another_run = @host.issue_client_effect_run_definition(
    materials.allowed,
    "retained-effect",
    "another-original-run",
    "2026-10-09T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  assert_true(
    consumer.bind_effect_retained_result_artifact(
      { ..materials, run_definition: another_run, },
      inputs,
      imported,
      root_export,
      receipt,
      producer_token,
    )
    is Err(ForeignRun),
  )
  let denied = @host.install_client_retained_input_current(
    () => site,
    () => retained_compute_cid("c"),
    () => 1791504000000L,
    (_, _) => false,
  )
  assert_true(
    @host.bind_transferred_client_effect_local_result_artifact(
      materials,
      inputs,
      imported,
      root_export,
      receipt,
      producer_token,
      common_input,
      denied,
      () => true,
    )
    is Err(Current(AuthorizationUnavailable)),
  )
  let current = @host.install_client_retained_input_current(
    () => site,
    () => retained_compute_cid("c"),
    () => 1791504000000L,
    (_, _) => true,
  )
  assert_true(
    @host.bind_transferred_client_effect_local_result_artifact(
      materials,
      inputs,
      imported,
      root_export,
      receipt,
      producer_token,
      common_input,
      current,
      () => false,
    )
    is Err(Unavailable),
  )
  assert_true(
    @strategy.release_captured_effect_local_unit_inputs(sender_inputs),
  )
  assert_false(
    @strategy.release_captured_effect_local_unit_inputs(sender_inputs),
  )
  // Returning the sender's semantic borrow does not revoke the independent
  // receiver holding or its confirmed Artifact. Physical producer cleanup is
  // still performed separately by the existing Source Owner below.
  @host.client_effect_local_result_payload_binding(
    receiver,
    materials.run_definition,
  ).unwrap()
  |> ignore
  assert_true(
    consumer.bind_effect_retained_result_artifact(
      materials, inputs, imported, root_export, receipt, producer_token,
    )
    is Err(Unavailable),
  )
  let (run_observation, invocation) = producer_dependency_observation(
    materials, source,
  )
  let public_capture = retained_effect_result_capture(
    consumer, materials, inputs, evidence, invocation, run_observation, source, public_result,
  )
  let definition = @host.issue_client_effect_local_result_definition(
    materials.prepared,
    1,
    "r",
    65536,
    4096,
    64,
  ).unwrap()
  let result = @host.issue_imported_client_effect_local_result_artifact(
    materials.prepared,
    inputs,
    result_export,
    evidence,
    definition,
    result_receipt,
    retained_compute_effect_retention(),
    @host.client_effect_allowed_run_admission(materials.allowed),
    materials.run_definition,
    invocation,
    run_observation,
    65536,
    4096,
    64,
  ).unwrap()
  let dependencies = retained_effect_dependency_capture(
    consumer, materials, inputs, receiver, result, root_index, result_index, result_export,
    result_receipt,
  )
  let local_manifest = @host.issue_client_effect_local_manifest(
    materials.prepared,
    @host.client_effect_imported_invocation(evidence),
    [result],
    65536,
    4096,
    64,
  ).unwrap()
  retained_effect_preview_inputs(
    consumer, materials, inputs, invocation, result, result_index, stop_custodies,
    local_manifest, evidence, source, acquired_bodies, dependencies, public_capture,
  )
  // The observation identifies the Artifact; the derived input Relation
  // preserves its exact provenance and the consumer derivation names that
  // Relation. These three reference kinds must not be conflated.
  let relation_body = @host.client_effect_imported_relation_bodies(evidence)[0]
  let relation = @publication.admit_publication_contract(
    "acquisition_relation", relation_body, 65536, 4096, 64,
  ).unwrap()
  let producer_derivation = @publication.admit_publication_contract(
    "derivation_evidence",
    @host.client_effect_local_result_derivation_json(sender),
    65536,
    4096,
    64,
  ).unwrap()
  assert_true(
    relation_body.contains(
      @publication.publication_contract_identity(producer_derivation),
    ),
  )
  assert_true(
    @host.client_effect_local_result_derivation_json(result).contains(
      @publication.publication_contract_identity(relation),
    ),
  )
  @execution.cancel_completed_relation_export_receipt(receipt)
  @execution.cancel_completed_relation_export_receipt(result_receipt)
  @execution.cancel_completed_result_relation_export(
    @strategy.captured_effect_local_result_export_preparation(root_export),
  )
  |> ignore
  @execution.cancel_completed_result_relation_export(
    @strategy.captured_effect_local_result_export_preparation(result_export),
  )
  |> ignore
}
