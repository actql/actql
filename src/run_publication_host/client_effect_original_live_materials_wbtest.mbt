///|
fn live_original_materials_fixture() -> (
  PreparedClientEffectComputation,
  ClientEffectAllowedRun,
  @publication.PublicationContract,
  ClientRequestIdentity,
  ClientEffectIssuedNormalizationMaterials,
) {
  let (prepared, allowed, definition) = original_effect_materials_fixture(
    normalized=true,
  )
  let request = prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "original-caller",
    source_free_caller_input_intent_cid(),
  ).unwrap()
  let issued = issue_prepared_client_effect_normalization_materials(
    allowed,
    definition,
    issue_prepared_client_effect_normalization(prepared).unwrap(),
    request=Some(request),
  ).unwrap()
  (prepared, allowed, definition, request, issued)
}

///|
test "issued Effect facts reuse canonical admission and retain one lazy digest and journal" {
  let (_, allowed, definition, request, issued) = live_original_materials_fixture()
  assert_eq(issued.materials_cid, None)
  let wire = client_effect_issued_normalization_materials_wire(issued)
  assert_eq(issued.materials_cid, None)
  let equivalent_allowed = issue_client_effect_allowed_run(
    allowed.compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2026-10-10T00:00:00.000Z",
  ).unwrap()
  let equivalent_definition = issue_client_effect_run_definition(
    equivalent_allowed, "original-scope", "original-effect-run", "2026-10-09T00:00:00.000Z",
    "2026-10-10T00:00:00.000Z",
  ).unwrap()
  assert_false(physical_equal(equivalent_allowed, allowed))
  assert_false(physical_equal(equivalent_definition, definition))
  assert_eq(
    @publication.publication_contract_identity(equivalent_definition),
    @publication.publication_contract_identity(definition),
  )
  let materials = bind_prepared_client_effect_original_materials(
    equivalent_allowed,
    equivalent_definition,
    issued,
    request=Some(request),
  ).unwrap()
  let digest = issued.materials_cid.unwrap()
  assert_eq(digest, "sha256:" + @sha.hex(@utf8.encode(wire)))
  for _ in 0..<3 {
    assert_true(
      physical_equal(
        restore_client_effect_run_normalization(materials).unwrap(),
        issued.original.journal,
      ),
    )
    assert_eq(
      client_effect_normalization_materials_cid(materials),
      Some(digest),
    )
    assert_eq(issued.materials_cid, Some(digest))
  }
  let changed_policy = issue_client_effect_allowed_run(
    allowed.compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "d".repeat(64),
    "2026-10-10T00:00:00.000Z",
  ).unwrap()
  assert_true(
    bind_prepared_client_effect_original_materials(
      changed_policy,
      definition,
      issued,
      request=Some(request),
    )
    is Err(_),
  )
  assert_eq(issued.materials_cid, Some(digest))
  assert_true(
    physical_equal(
      materials.prepared.normalization_custody.unwrap(),
      materials.normalization.unwrap(),
    ),
  )
}

///|
test "live original Effect materials retain the same prepared compilation request and custody" {
  let (prepared, allowed, definition, request, issued) = live_original_materials_fixture()
  let wire = client_effect_issued_normalization_materials_wire(issued)
  let restored = normalization_materials_admit(
    wire,
    @publication.publication_contract_identity(definition),
    original=Some(issued),
  )
  // The transported-material reader is intentional for process restoration,
  // but cannot be used for this live original admission/Work connection.
  assert_false(physical_equal(restored.prepared, prepared))
  assert_true(
    bind_client_effect_compiled_run(prepared, restored.allowed, definition)
    is Err(ForeignCompilation),
  )
  let materials = bind_prepared_client_effect_original_materials(
    allowed,
    definition,
    issued,
    request=Some(request),
  ).unwrap()
  assert_true(physical_equal(materials.prepared, prepared))
  assert_true(physical_equal(materials.compilation, allowed.compilation))
  assert_true(physical_equal(materials.allowed, allowed))
  assert_eq(materials.request, Some(request))
  assert_true(
    physical_equal(
      restore_client_effect_run_normalization(materials).unwrap(),
      issued.original.journal,
    ),
  )
  assert_true(
    bind_client_effect_compiled_run(prepared, materials.allowed, definition)
    is Ok(_),
  )
  assert_eq(
    @publication.run_evidence_value_identity(
      restore_client_effect_run_normalization(materials).unwrap(),
    ),
    "sha256:849788c9eede8ad674223eb06775c2dba2cf0ed1d02ceb0a5de6ccfeec2cb087",
  )
  let repeated = bind_prepared_client_effect_original_materials(
    allowed,
    definition,
    issued,
    request=Some(request),
  ).unwrap()
  assert_true(
    physical_equal(
      repeated.normalization.unwrap(),
      materials.normalization.unwrap(),
    ),
  )
  assert_eq(client_effect_issued_normalization_materials_wire(issued), wire)
}

///|
test "live original Effect materials refuse equal wire from a foreign prepared Owner" {
  let (prepared, allowed, definition, request, _) = live_original_materials_fixture()
  let (_, _, _, _, foreign) = live_original_materials_fixture()
  assert_true(
    bind_prepared_client_effect_original_materials(
      allowed,
      definition,
      foreign,
      request=Some(request),
    )
    is Err(Normalization(ForeignPreparation)),
  )
  assert_true(prepared.normalization_custody is None)
}

///|
test "live original Effect materials refuse foreign Run request and unissued proof without replacing custody" {
  let (prepared, allowed, definition, request, issued) = live_original_materials_fixture()
  let original = bind_prepared_client_effect_original_materials(
    allowed,
    definition,
    issued,
    request=Some(request),
  ).unwrap().normalization.unwrap()
  let another_run = issue_client_effect_run_definition(
    allowed, "original-scope", "another-run", "2026-10-09T00:00:00.000Z", "2026-10-10T00:00:00.000Z",
  ).unwrap()
  assert_true(
    bind_prepared_client_effect_original_materials(
      allowed,
      another_run,
      issued,
      request=Some(request),
    )
    is Err(Normalization(UnverifiedOriginalMaterials)),
  )
  let another_request = prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "another-caller",
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
  let another_issued = issue_prepared_client_effect_normalization_materials(
    allowed,
    another_run,
    issued.original,
    request=Some(request),
  ).unwrap()
  assert_true(
    bind_prepared_client_effect_original_materials(
      allowed,
      another_run,
      another_issued,
      request=Some(request),
    )
    is Err(Normalization(ForeignMaterials)),
  )
  let copied : ClientEffectIssuedNormalizationMaterials = {
    ..issued,
    issuer: Ref(()),
  }
  assert_true(
    bind_prepared_client_effect_original_materials(
      allowed,
      definition,
      copied,
      request=Some(request),
    )
    is Err(Normalization(UnverifiedOriginalMaterials)),
  )
  assert_true(physical_equal(prepared.normalization_custody.unwrap(), original))
}

///|
test "live original Effect materials refuse replacement compilation and corrupted custody without repair" {
  let (prepared, allowed, definition, request, issued) = live_original_materials_fixture()
  let limits = run_materials_limits()
  let compilation = issue_prepared_client_effect_compilation(
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
  let changed = issue_client_effect_allowed_run(
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2026-10-10T00:00:00.000Z",
  ).unwrap()
  assert_false(physical_equal(compilation, allowed.compilation))
  assert_true(
    bind_prepared_client_effect_original_materials(
      changed,
      definition,
      issued,
      request=Some(request),
    )
    is Err(Normalization(ForeignMaterials)),
  )
  assert_true(prepared.normalization_custody is None)
  let materials = bind_prepared_client_effect_original_materials(
    allowed,
    definition,
    issued,
    request=Some(request),
  ).unwrap()
  let original = materials.normalization.unwrap()
  assert_true(
    bind_prepared_client_effect_original_materials(
      changed,
      definition,
      issued,
      request=Some(request),
    )
    is Err(Normalization(ForeignMaterials)),
  )
  assert_true(physical_equal(prepared.normalization_custody.unwrap(), original))
  let corrupted : ClientEffectNormalizationMaterialCustody = {
    ..original,
    journal_wire: "{}",
  }
  prepared.normalization_custody = Some(corrupted)
  assert_true(
    bind_prepared_client_effect_original_materials(
      allowed,
      definition,
      issued,
      request=Some(request),
    )
    is Err(Normalization(UnverifiedOriginalMaterials)),
  )
  assert_true(
    physical_equal(prepared.normalization_custody.unwrap(), corrupted),
  )
}

///|
// Common Owner records, not Native transaction or physical-cleanup evidence.
// Reading material cannot reset an existing unknown row or cancellation fence.
test "live original Effect materials preserve unknown ledger identity and cancellation settlement" {
  let (prepared, allowed, definition, request, issued) = live_original_materials_fixture()
  let scope = @effect.prepare_logical_request_scope(
    "sha256:" + "a".repeat(64),
    "original-caller",
    128,
  ).unwrap()
  let key = @effect.prepare_effect_dispatch_key(
    scope,
    "sha256:" + "b".repeat(64),
    "\"row-1\"",
    32,
    8,
    3,
  ).unwrap()
  let locator = @effect.prepare_logical_item_locator(
    scope, "original-program", "original-node", "WriteOne", "{\"row\":\"row-1\"}",
    128, 128, 8, 3,
  ).unwrap()
  let basis = @effect.prepare_effect_ledger_basis(
    scope,
    locator,
    key,
    "sha256:" + "c".repeat(64),
    "sha256:" + "d".repeat(64),
    client_request_intent_cid(request),
    "sha256:" + "f".repeat(64),
    "sha256:" + "0".repeat(64),
    "unavailable",
    "sha256:" + "1".repeat(64),
    "sha256:" + "2".repeat(64),
  ).unwrap()
  let pending = @effect.issue_prepared_effect_ledger_entry(basis, 4096, 64, 3).unwrap()
  let sending = @effect.issue_next_effect_ledger_entry(
    pending,
    "dispatching",
    None,
    4096,
    64,
    3,
  ).unwrap()
  let unknown = @effect.issue_next_effect_ledger_entry(
    sending,
    "unknown",
    None,
    4096,
    64,
    3,
  ).unwrap()
  let original_row = @effect.effect_ledger_entry_wire(unknown)
  let original_reservation = basis.reservation_evidence_cid
  let original_retention = basis.retention_contract_cid
  let binding : @checkpoint.ResumeBinding = {
    authorization_context_cid: "sha256:" + "a".repeat(64),
    environment_binding_cid: "sha256:" + "b".repeat(64),
  }
  let original_resume : @checkpoint.ResumeIntentView = {
    state: ResumePending,
    generation: 0L,
    claimant: "",
    lease_expires_ms: 0L,
  }
  for _ in 0..<2 {
    let materials = bind_prepared_client_effect_original_materials(
      allowed,
      definition,
      issued,
      request=Some(request),
    ).unwrap()
    assert_true(physical_equal(materials.prepared, prepared))
    assert_eq(materials.request, Some(request))
    assert_eq(@effect.effect_ledger_entry_wire(unknown), original_row)
    assert_true(@effect.effect_ledger_entry_matches_basis(unknown, basis))
    assert_eq(basis.reservation_evidence_cid, original_reservation)
    assert_eq(basis.retention_contract_cid, original_retention)
    assert_eq(
      @effect.effect_row_recovery_action_from_entry(
        locator,
        client_request_intent_cid(request),
        key,
        "sha256:" + "f".repeat(64),
        Some(unknown),
        false,
      ),
      4,
    )
    assert_false(
      @effect.effect_ledger_entry_admits_dispatch(
        unknown,
        scope,
        locator,
        key,
        "sha256:" + "f".repeat(64),
      ),
    )
    assert_eq(
      @checkpoint.decide_effect_resume_claim(
        original_resume, "observer", 1000L, 500L, binding, binding, true,
      ),
      Ok(@checkpoint.ClaimSettlement(1L, 1500L)),
    )
  }
}
