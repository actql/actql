///|
fn effect_original_restore_limits() -> @host.ClientValuesRunMaterialsLimits {
  {
    preparation: @host.client_standard_program_preparation_limits(),
    sequence: @host.client_standard_values_sequence_limits(),
    max_sequence_steps: 32,
    max_sequence_work: 64,
    max_evidence_bytes: 100000,
    max_evidence_nodes: 10000,
    max_evidence_depth: 100,
  }
}

///|
fn effect_original_restore_manifests() -> @host.ClientCompilationManifests {
  @host.admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    10000,
    1000,
    20,
  ).unwrap()
}

///|
// Issue the genuine normalization before the first compilation. Replacing an
// already accepted legacy Template with a newly normalized one is not recovery.
fn effect_original_restorable_host_fixture(
  name : String,
) -> (
  NativeLocalHostConnection,
  NativeClientSubmissionReference,
  @host.ClientRequestIdentity,
  String,
) raise {
  let host = policy_host_fixture(name)
  let scope = host
    .authority_scope_cid("operator", "cli", epoch_test_crypto())
    .unwrap()
  let epoch = host.epoch.issue_epoch(scope, true, 1000.0).unwrap()
  let reference = prepare_native_client_submission_reference(
    epoch, "original-submit",
  ).unwrap()
  let intent = @host.prepare_client_submitted_intent(
    "{\"kind\":\"program\",\"input\":" +
    native_client_effect_fixture_document +
    ",\"parameters\":null}",
    65536,
    8192,
    64,
  ).unwrap()
  let preparation = native_client_effect_fixture_preparation(intent)
  guard preparation.preparation is EffectComputation(prepared) else {
    fail("missing original Effect preparation")
  }
  let normalization = @host.issue_prepared_client_effect_normalization(prepared).unwrap()
  let compilation = @host.issue_prepared_client_effect_compilation(
    prepared,
    effect_original_restore_manifests(),
    @host.client_standard_values_sequence_limits(),
    32,
    64,
    100000,
    10000,
    100,
    normalization=Some(normalization),
  ).unwrap()
  let allowed = @host.issue_client_effect_allowed_run(
    compilation,
    scope,
    host.configuration().unwrap().configuration_cid(),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = @host.issue_client_effect_run_definition(
    allowed, "local-test", "original-effect-run", "2026-10-10T00:00:00.000Z", "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let request = @host.prepare_client_effect_request_identity(
    prepared,
    scope,
    reference.request_id,
    @host.source_free_caller_input_intent_cid(),
  ).unwrap()
  host.journal
  .record_submitted_intent(host.epoch, reference, intent, scope, true, 1001.0)
  .unwrap()
  |> ignore
  let issued = @host.issue_prepared_client_effect_normalization_materials(
    allowed,
    definition,
    normalization,
    request=Some(request),
  ).unwrap()
  host
  .accept_submitted_effect_material_original(
    epoch_test_crypto(),
    "operator",
    "cli",
    reference,
    preparation,
    request,
    allowed,
    definition,
    issued,
    1002.0,
  )
  .unwrap()
  |> ignore
  (
    host,
    reference,
    request,
    @host.client_effect_issued_normalization_materials_wire(issued),
  )
}

///|
fn effect_original_restore_fixture_call(
  host : NativeLocalHostConnection,
  reference : NativeClientSubmissionReference,
  request : @host.ClientRequestIdentity,
  limits? : @host.ClientValuesRunMaterialsLimits = effect_original_restore_limits(),
) -> Result[
  @host.ClientEffectRunMaterials,
  NativeClientSubmittedEffectMaterialsIssue,
] {
  host.restore_submitted_effect_material_original(
    epoch_test_crypto(),
    "operator",
    "cli",
    reference,
    request,
    1003.0,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    effect_original_restore_manifests(),
    limits,
    @host.client_standard_effect_computation_limits(),
  )
}

///|
test "Native readonly restoration binds saved packet to original Run request and does not claim work after reopen" {
  let name = "local-effect-original-restore"
  let (host, reference, request, wire) = effect_original_restorable_host_fixture(
    name,
  )
  let original = host.journal.retained(request).unwrap().unwrap()
  let row = run_record_body(original).unwrap()
  host.close().unwrap()
  let host = policy_host_fixture(name, existing=true)
  for _ in 0..<2 {
    let materials = effect_original_restore_fixture_call(
      host, reference, request,
    ).unwrap()
    assert_eq(materials.request, Some(request))
    assert_eq(
      @publication.publication_contract_identity(materials.run_definition),
      @publication.publication_contract_identity(original.definition),
    )
    assert_eq(
      @host.client_effect_normalization_materials_cid(materials),
      Some(
        local_adoption_digest(epoch_test_crypto(), @utf8.encode(wire)).unwrap(),
      ),
    )
    assert_true(
      @host.restore_client_effect_run_normalization(materials) is Ok(_),
    )
    let retained = host.journal.retained(request).unwrap().unwrap()
    assert_eq(run_record_body(retained).unwrap(), row)
    assert_eq(retained.revision, original.revision)
    assert_false(retained.dispatch_reserved)
    assert_false(retained.physical_start_claimed)
    assert_eq(run_journal_custody(host.database, 8).unwrap().0, 1)
  }
  host.close().unwrap()
}

///|
test "Native readonly restoration does not upgrade a legacy unbound normalization profile" {
  let (host, reference, preparation, request, allowed, definition, issued) = effect_material_original_host_fixture(
    "local-effect-original-restore-legacy",
  )
  host
  .accept_submitted_effect_material_original(
    epoch_test_crypto(),
    "operator",
    "cli",
    reference,
    preparation,
    request,
    allowed,
    definition,
    issued,
    1002.0,
  )
  .unwrap()
  |> ignore
  let row = run_record_body(host.journal.retained(request).unwrap().unwrap()).unwrap()
  assert_true(
    effect_original_restore_fixture_call(host, reference, request)
    is Err(Materials(_)),
  )
  assert_eq(
    run_record_body(host.journal.retained(request).unwrap().unwrap()).unwrap(),
    row,
  )
  assert_eq(
    native_client_retained_effect_materials_wire(
      host
      .lookup_submitted_effect_material_original(
        epoch_test_crypto(),
        "operator",
        "cli",
        reference,
        request,
        1003.0,
      )
      .unwrap(),
    ),
    @host.client_effect_issued_normalization_materials_wire(issued),
  )
  host.close().unwrap()
}

///|
test "Native readonly restoration preserves missing custody and capacity refusal without a new Run" {
  let (host, reference, _, request, _, _, _) = local_original_effect_material_fixture(
    "local-effect-original-restore-missing", true, true,
  )
  let row = run_record_body(host.journal.retained(request).unwrap().unwrap()).unwrap()
  assert_true(
    effect_original_restore_fixture_call(host, reference, request)
    is Err(Journal(MissingEffectMaterialOriginal)),
  )
  assert_eq(
    run_record_body(host.journal.retained(request).unwrap().unwrap()).unwrap(),
    row,
  )
  host.close().unwrap()
  let (host, reference, request, _) = effect_original_restorable_host_fixture(
    "local-effect-original-restore-limit",
  )
  let original = host.journal.retained(request).unwrap().unwrap()
  let row = run_record_body(original).unwrap()
  let limits = effect_original_restore_limits()
  assert_true(
    effect_original_restore_fixture_call(host, reference, request, limits={
      ..limits,
      max_sequence_steps: 0,
    })
    is Err(Materials(Compilation(_))),
  )
  assert_eq(
    run_record_body(host.journal.retained(request).unwrap().unwrap()).unwrap(),
    row,
  )
  assert_eq(run_journal_custody(host.database, 8).unwrap().0, 1)
  assert_false(original.dispatch_reserved)
  assert_false(original.physical_start_claimed)
  host.close().unwrap()
}

///|
test "Native original material bytes previously read do not retain authority after adopted Account revocation" {
  let name = "local-effect-original-restore-revoked"
  let (host, reference, request, wire) = effect_original_restorable_host_fixture(
    name,
  )
  let saved = host
    .lookup_submitted_effect_material_original(
      epoch_test_crypto(),
      "operator",
      "cli",
      reference,
      request,
      1003.0,
    )
    .unwrap()
  assert_eq(native_client_retained_effect_materials_wire(saved), wire)
  let record = host.journal.retained(request).unwrap().unwrap()
  let row = run_record_body(record).unwrap()
  let parent = host.session.source_root
  let account = name + ".account.json"
  parent
  .reclaim_generation(
    account,
    parent.inspect_generation(account).unwrap().unwrap(),
  )
  .unwrap()
  assert_true(
    effect_original_restore_fixture_call(host, reference, request)
    is Err(Journal(AuthorizationDenied)),
  )
  assert_eq(
    run_record_body(host.journal.retained(request).unwrap().unwrap()).unwrap(),
    row,
  )
  assert_false(record.dispatch_reserved)
  assert_false(record.physical_start_claimed)
  assert_eq(run_journal_custody(host.database, 8).unwrap().0, 1)
  host.close().unwrap()
}
