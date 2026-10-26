// Full common semantic Captured Run issuance from real Native rows and closed
// Source/import dependencies. The numeric fixture uses protocol target metadata;
// the Provider case uses the physical HTTPS observation and admitted Preview.
// Encryption/reconciliation is checked by the independent Store custody helper;
// waiting, Host restart, approval and physical writes are not claimed.

///|
fn retained_effect_complete_capture(
  consumer : @resident.ResidentSourceCompute,
  materials : @host.ClientEffectRunMaterials,
  inputs : @strategy.CapturedEffectInputs,
  invocation : @publication.PublicationContract,
  preview : @strategy.CapturedEffectPreviewInputs,
  proof : @strategy.CapturedEffectPlanProof,
  source : @publication.CapturedEffectSourceArtifact,
  local_source : @publication.CapturedLocalEffectSourceEvidence,
  inventory : @publication.CapturedEffectDependencyInventory,
  authoring : @publication.RunEvidenceValue,
  result : @resident.ResidentEffectResultCapture,
  provider? : Bool = false,
  private_preview? : (String, String)? = None,
  checkpoint_custody? : Bool = false,
  review_retention? : Bool = false,
  original_work? : (
    @client.NativeClientEffectSourceWork,
    @client.NativeClientRunJournal,
  )? = None,
  initial_reviewer? : (
    PairedInitialReviewerFixture,
    @client.NativeClientSubmissionReference,
  )? = None,
) -> Unit raise {
  let capture = (material, proofs, sources) => {
    consumer.capture_effect_run(
      material,
      inputs,
      result,
      invocation,
      preview,
      proofs,
      sources,
      [local_source],
      inventory,
      authoring,
      100,
      10000,
      65536,
      10000,
      64,
      10000,
    )
  }
  let foreign_run = @host.issue_client_effect_run_definition(
    materials.allowed,
    "retained-effect",
    "foreign-full-capture",
    "2026-10-09T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  assert_true(
    capture({ ..materials, run_definition: foreign_run, }, [proof], [source])
    is Err(Context(ForeignInput)),
  )
  assert_true(
    capture(materials, [], [source]) is Err(Context(Proof(MissingProof(0)))),
  )
  assert_true(capture(materials, [proof], []) is Err(Capture(_)))
  let captured = capture(materials, [proof], [source]).unwrap()
  assert_eq(@publication.publication_contract_name(captured), "captured_run")
  let wire = @publication.publication_contract_json(captured)
  let restored = @publication.admit_publication_contract(
    "captured_run", wire, 65536, 10000, 64,
  ).unwrap()
  assert_eq(
    @publication.publication_contract_identity(restored),
    @publication.publication_contract_identity(captured),
  )
  assert_true(
    wire.contains(
      @publication.publication_contract_identity(materials.run_definition),
    ),
  )
  assert_true(
    wire.contains(@publication.publication_contract_identity(invocation)),
  )
  assert_true(
    wire.contains("\"answer\":" + retained_effect_expected_rows(provider)),
  )
  // Captured Run contains computation and source custody, not target Preview
  // before/after. The independently admitted Preview is checked by its caller.
  assert_true(
    wire.contains(@publication.captured_effect_source_holding_cid(source)),
  )
  assert_true(
    wire.contains(
      @publication.captured_effect_dependency_inventory_json(inventory),
    ),
  )
  assert_true(wire.contains("\"effect_plans\":{\"save\":"))
  // Repeating semantic capture does not acquire/compute/apply or release any
  // original custody; the outer real Native fixture checks its entry counts.
  let retried = capture(materials, [proof], [source]).unwrap()
  assert_eq(
    @publication.publication_contract_identity(retried),
    @publication.publication_contract_identity(captured),
  )
  if review_retention {
    let (wire, authoring_cid) = private_preview.unwrap()
    retained_effect_review_retention_store(
      consumer,
      materials,
      inputs,
      result,
      invocation,
      preview,
      captured,
      @publication.captured_effect_source_store_authority_cid(source),
      wire,
      authoring_cid,
      original_work~,
      initial_reviewer~,
    )
  } else {
    retained_effect_capture_store(
      consumer,
      materials,
      inputs,
      result,
      invocation,
      preview,
      captured,
      @publication.captured_effect_source_store_authority_cid(source),
      provider~,
      private_preview~,
      checkpoint_custody~,
    )
  }
  println(
    "retained-effect-capture: complete original Run issued with actual public rows and checked plan",
  )
}
