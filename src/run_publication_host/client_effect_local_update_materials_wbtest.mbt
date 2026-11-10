///|
fn original_local_update_materials_fixture(
  common? : Bool = false,
) -> (
  PreparedClientEffectComputation,
  ClientEffectAllowedRun,
  @publication.PublicationContract,
  ClientRequestIdentity,
  ClientEffectIssuedNormalizationMaterials,
) {
  let (document, environment, limits) = local_update_normalization_fixture()
  let prepared = if common {
    common_update_normalization_fixture()
  } else {
    prepare_client_effect_computation(
      document,
      Json,
      environment,
      None,
      [],
      limits,
    ).unwrap()
  }
  let proof = if common {
    issue_prepared_client_effect_selected_normalization(prepared).unwrap()
  } else {
    issue_prepared_client_effect_local_update_normalization(prepared).unwrap()
  }
  let bounds = run_materials_limits()
  let compilation = issue_prepared_client_effect_compilation(
    prepared,
    run_materials_manifests(),
    bounds.sequence,
    bounds.max_sequence_steps,
    bounds.max_sequence_work,
    bounds.max_evidence_bytes,
    bounds.max_evidence_nodes,
    bounds.max_evidence_depth,
    normalization=Some(proof),
  ).unwrap()
  let allowed = issue_client_effect_allowed_run(
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2026-10-10T00:00:00.000Z",
  ).unwrap()
  let definition = issue_client_effect_run_definition(
    allowed, "original-update-scope", "original-update-run", "2026-10-09T00:00:00.000Z",
    "2026-10-10T00:00:00.000Z",
  ).unwrap()
  let request = prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "original-update-caller",
    source_free_caller_input_intent_cid(),
  ).unwrap()
  let issued = issue_prepared_client_effect_normalization_materials(
    allowed,
    definition,
    proof,
    request=Some(request),
  ).unwrap()
  (prepared, allowed, definition, request, issued)
}

///|
test "update material restore retains the original Run request and exact journal without issuance" {
  let (_, _, definition, request, issued) = original_local_update_materials_fixture()
  let run = @publication.publication_contract_identity(definition)
  let wire = client_effect_issued_normalization_materials_wire(issued)
  let restored = normalization_materials_admit(wire, run, original=Some(issued))
  assert_true(restored.prepared.normalization is None)
  assert_true(
    restored.compilation.normalization_profile is Some(LocalUpdate(_)),
  )
  for _ in 0..<2 {
    assert_eq(
      @publication.run_evidence_value_identity(
        restore_client_effect_run_normalization(restored).unwrap(),
      ),
      "sha256:e9f69915b6368e0c8e1669b010e57e65f633bd5a8d589d3b3575c2b043f4b44d",
    )
    assert_true(restored.prepared.normalization is None)
    assert_eq(
      @publication.publication_contract_identity(restored.run_definition),
      run,
    )
    assert_eq(restored.request, Some(request))
  }
  let durable = normalization_materials_admit(
    wire,
    run,
    expected_request=Some(request),
  )
  assert_true(durable.prepared.normalization is None)
  assert_true(durable.normalization.unwrap().issued is None)
  assert_eq(
    @publication.run_evidence_value_identity(
      restore_client_effect_run_normalization(durable).unwrap(),
    ),
    "sha256:e9f69915b6368e0c8e1669b010e57e65f633bd5a8d589d3b3575c2b043f4b44d",
  )
  assert_true(
    normalization_materials_untrusted_admission(wire, run)
    is Err(Request(IdentityMismatch)),
  )
  assert_true(
    normalization_materials_untrusted_admission(
      wire,
      "sha256:" + "f".repeat(64),
      expected_request=Some(request),
    )
    is Err(RunMismatch),
  )
}

///|
test "update live custody refuses foreign Run request and replacement physical compilation" {
  let (prepared, allowed, definition, request, issued) = original_local_update_materials_fixture()
  let limits = run_materials_limits()
  let another_compilation = issue_prepared_client_effect_compilation(
    prepared,
    run_materials_manifests(),
    limits.sequence,
    limits.max_sequence_steps,
    limits.max_sequence_work,
    limits.max_evidence_bytes,
    limits.max_evidence_nodes,
    limits.max_evidence_depth,
    normalization=Some(issued.original),
  ).unwrap()
  let another_allowed = issue_client_effect_allowed_run(
    another_compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2026-10-10T00:00:00.000Z",
  ).unwrap()
  assert_false(physical_equal(allowed.compilation, another_compilation))
  assert_true(
    bind_prepared_client_effect_original_materials(
      another_allowed,
      definition,
      issued,
      request=Some(request),
    )
    is Err(Normalization(ForeignMaterials)),
  )
  assert_true(prepared.normalization_custody is None)
  let another_request = prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "different-update-caller",
    source_free_caller_input_intent_cid(),
  ).unwrap()
  assert_true(
    bind_prepared_client_effect_original_materials(
      allowed,
      definition,
      issued,
      request=Some(another_request),
    )
    is Err(Normalization(ForeignMaterials)),
  )
  let materials = bind_prepared_client_effect_original_materials(
    allowed,
    definition,
    issued,
    request=Some(request),
  ).unwrap()
  let original = materials.normalization.unwrap()
  let other_run = issue_client_effect_run_definition(
    allowed, "original-update-scope", "different-update-run", "2026-10-09T00:00:00.000Z",
    "2026-10-10T00:00:00.000Z",
  ).unwrap()
  let other_issued = issue_prepared_client_effect_normalization_materials(
    allowed,
    other_run,
    issued.original,
    request=Some(request),
  ).unwrap()
  assert_true(
    bind_prepared_client_effect_original_materials(
      allowed,
      other_run,
      other_issued,
      request=Some(request),
    )
    is Err(Normalization(ForeignMaterials)),
  )
  assert_true(physical_equal(prepared.normalization_custody.unwrap(), original))
}

///|
test "update normalized materials refuse create journal and missing original request without repair" {
  let (prepared, allowed, definition, request, issued) = original_local_update_materials_fixture()
  let (_, _, create_run) = original_effect_materials_fixture(normalized=true)
  let create = normalization_fixture()
  let create_proof = issue_prepared_client_effect_normalization(create).unwrap()
  let wire = client_effect_issued_normalization_materials_wire(issued)
  let substituted = normalization_materials_replace(
    wire,
    @publication.run_evidence_value_json(create_proof.journal),
  )
  assert_true(
    normalization_materials_untrusted_admission(
      substituted,
      @publication.publication_contract_identity(definition),
      expected_request=Some(request),
    )
    is Err(Normalization(SubstitutedJournal)),
  )
  assert_true(
    normalization_materials_untrusted_admission(
      wire,
      @publication.publication_contract_identity(create_run),
      expected_request=Some(request),
    )
    is Err(RunMismatch),
  )
  let materials = bind_prepared_client_effect_original_materials(
    allowed,
    definition,
    issued,
    request=Some(request),
  ).unwrap()
  let original = materials.normalization.unwrap()
  let corrupt : ClientEffectNormalizationMaterialCustody = {
    ..original,
    journal_wire: "{}",
  }
  prepared.normalization_custody = Some(corrupt)
  assert_true(
    bind_prepared_client_effect_original_materials(
      allowed,
      definition,
      issued,
      request=Some(request),
    )
    is Err(Normalization(UnverifiedOriginalMaterials)),
  )
  assert_true(physical_equal(prepared.normalization_custody.unwrap(), corrupt))
}

///|
test "original update profile reaches the same physical compilation and material custody" {
  let (prepared, allowed, definition, request, issued) = original_local_update_materials_fixture()
  assert_true(
    issue_prepared_client_effect_run_materials(
      allowed,
      definition,
      request=Some(request),
    )
    is Err(Normalization(MissingOriginalJournal)),
  )
  let template = @publication.run_evidence_value_json(
    client_effect_compilation_template(allowed.compilation),
  )
  assert_true(template.contains("actql-local-update-completion-free/0.1"))
  assert_true(
    template.contains(client_effect_local_update_completion_free_catalog_cid()),
  )
  assert_false(template.contains("actql-resident-effect-completion-free/0.1"))
  let materials = bind_prepared_client_effect_original_materials(
    allowed,
    definition,
    issued,
    request=Some(request),
  ).unwrap()
  assert_true(physical_equal(materials.prepared, prepared))
  assert_true(physical_equal(materials.compilation, allowed.compilation))
  let custody = materials.normalization.unwrap()
  for _ in 0..<2 {
    let again = bind_prepared_client_effect_original_materials(
      allowed,
      definition,
      issued,
      request=Some(request),
    ).unwrap()
    assert_true(physical_equal(again.normalization.unwrap(), custody))
    let journal = restore_client_effect_run_normalization(again).unwrap()
    assert_eq(
      @publication.run_evidence_value_identity(journal),
      "sha256:e9f69915b6368e0c8e1669b010e57e65f633bd5a8d589d3b3575c2b043f4b44d",
    )
  }
}

///|
test "an update journal cannot bind an unprofiled Template or a foreign original inventory" {
  let (prepared, _, _, request, issued) = original_local_update_materials_fixture()
  let bounds = run_materials_limits()
  let unprofiled = issue_prepared_client_effect_compilation(
    prepared,
    run_materials_manifests(),
    bounds.sequence,
    bounds.max_sequence_steps,
    bounds.max_sequence_work,
    bounds.max_evidence_bytes,
    bounds.max_evidence_nodes,
    bounds.max_evidence_depth,
  ).unwrap()
  let allowed = issue_client_effect_allowed_run(
    unprofiled,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2026-10-10T00:00:00.000Z",
  ).unwrap()
  let definition = issue_client_effect_run_definition(
    allowed, "original-update-scope", "original-update-run", "2026-10-09T00:00:00.000Z",
    "2026-10-10T00:00:00.000Z",
  ).unwrap()
  assert_true(
    issue_prepared_client_effect_run_materials(
      allowed,
      definition,
      request=Some(request),
      normalization=Some(issued.original),
    )
    is Err(Normalization(ForeignCatalog)),
  )
  let (document, environment, limits) = local_update_normalization_fixture()
  let equal_document_owner = prepare_client_effect_computation(
    document,
    Json,
    environment,
    None,
    [],
    limits,
  ).unwrap()
  assert_true(
    issue_client_effect_compilation_internal(
      equal_document_owner,
      run_materials_manifests(),
      bounds.sequence,
      bounds.max_sequence_steps,
      bounds.max_sequence_work,
      bounds.max_evidence_bytes,
      bounds.max_evidence_nodes,
      bounds.max_evidence_depth,
      Some(issued.original.inventory),
    )
    is Err(Normalization(ForeignPreparation)),
  )
  assert_true(prepared.normalization_custody is None)
  assert_true(equal_document_owner.normalization_custody is None)
}

///|
test "common update material restore retains its original first compilation profile without issuance" {
  let (_, _, definition, request, issued) = original_local_update_materials_fixture(
    common=true,
  )
  let run = @publication.publication_contract_identity(definition)
  let wire = client_effect_issued_normalization_materials_wire(issued)
  for original in [Some(issued), None] {
    let restored = normalization_materials_admit(
      wire,
      run,
      original~,
      expected_request=Some(request),
    )
    assert_true(restored.prepared.normalization is None)
    assert_true(
      restored.compilation.normalization_profile is Some(CommonUpdate(_)),
    )
    assert_eq(restored.request, Some(request))
    let proof = restore_client_effect_run_normalization(restored).unwrap()
    assert_eq(
      @publication.run_evidence_value_identity(proof),
      "sha256:8b5172ca35db5cd4f35b8e6bbde52243d92b9e9027c2fc4568b8d66a5334ffb1",
    )
    assert_true(
      physical_equal(
        proof,
        restore_client_effect_run_normalization(restored).unwrap(),
      ),
    )
    assert_true(restored.prepared.normalization is None)
  }
  let (_, _, _, _, legacy) = original_local_update_materials_fixture()
  let replaced = normalization_materials_replace(
    wire,
    @publication.run_evidence_value_json(legacy.original.journal),
  )
  assert_true(
    normalization_materials_untrusted_admission(
      replaced,
      run,
      expected_request=Some(request),
    )
    is Err(Normalization(SubstitutedJournal)),
  )
}
