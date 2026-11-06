///|
// Original journal/material checks only. These definitions do not execute
// Source acquisition, capture pins, Provider I/O or the public CLI.
fn local_capture_binding_fixture_call(
  host : NativeLocalHostConnection,
  reference : NativeClientSubmissionReference,
  request : @host.ClientRequestIdentity,
  journal : NativeClientRunJournal,
  materials : @host.ClientEffectRunMaterials,
  definition : @publication.PublicationContract,
  principal? : String = "operator",
) -> Result[Unit, NativeClientSubmittedEffectMaterialsIssue] {
  check_local_effect_capture_binding(
    host,
    epoch_test_crypto(),
    principal,
    "cli",
    reference,
    request,
    journal,
    materials,
    definition,
    1003.0,
  )
}

///|
test "Native Local capture binding reuses the original packet without changing Run control or starting work" {
  let (host, reference, request, _) = effect_original_restorable_host_fixture(
    "local-capture-binding-original",
  )
  let materials = effect_original_restore_fixture_call(host, reference, request).unwrap()
  let before = run_record_body(host.journal.retained(request).unwrap().unwrap()).unwrap()
  for _ in 0..<2 {
    local_capture_binding_fixture_call(
      host,
      reference,
      request,
      host.journal,
      materials,
      materials.run_definition,
    ).unwrap()
    assert_eq(
      run_record_body(host.journal.retained(request).unwrap().unwrap()).unwrap(),
      before,
    )
  }
  host.close().unwrap()
}

///|
test "Native Local capture binding refuses foreign journal request Run and missing normalization custody" {
  let (host, reference, request, _) = effect_original_restorable_host_fixture(
    "local-capture-binding-foreign",
  )
  let materials = effect_original_restore_fixture_call(host, reference, request).unwrap()
  let before = run_record_body(host.journal.retained(request).unwrap().unwrap()).unwrap()
  // Both live Hosts retain distinct exclusive Adoption parents.
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let parent = @filesystem.open_private_root(path).unwrap()
  let state_name = "local-capture-binding-other-parent"
  parent.create_directory(state_name).unwrap() |> ignore
  parent.close().unwrap()
  let other = policy_host_fixture(
    "local-capture-binding-other-host",
    state_parent=Some(path + "/" + state_name),
  )
  assert_true(
    local_capture_binding_fixture_call(
      host,
      reference,
      request,
      other.journal,
      materials,
      materials.run_definition,
    )
    is Err(ForeignPreparation),
  )
  assert_true(
    local_capture_binding_fixture_call(
      host,
      reference,
      request,
      host.journal,
      { ..materials, request: None, },
      materials.run_definition,
    )
    is Err(ChangedIntent),
  )
  let (_, _, _, foreign) = journal_test_run("other-request", "other-run")
  assert_true(
    local_capture_binding_fixture_call(
      host,
      reference,
      request,
      host.journal,
      materials,
      foreign,
    )
    is Err(ForeignRun),
  )
  assert_true(
    local_capture_binding_fixture_call(
      host,
      reference,
      request,
      host.journal,
      { ..materials, run_definition: foreign, },
      materials.run_definition,
    )
    is Err(ForeignRun),
  )
  assert_true(
    local_capture_binding_fixture_call(
      host,
      reference,
      request,
      host.journal,
      { ..materials, normalization: None, },
      materials.run_definition,
    )
    is Err(ForeignPreparation),
  )
  let record = host.journal.retained(request).unwrap().unwrap()
  assert_false(record.physical_start_claimed)
  assert_false(record.dispatch_reserved)
  assert_eq(run_record_body(record).unwrap(), before)
  other.close().unwrap()
  host.close().unwrap()
}

///|
test "Native Local capture preflight preserves accepted cancellation and original physical start responsibility" {
  let (host, reference, request, _) = effect_original_restorable_host_fixture(
    "local-capture-binding-cancel",
  )
  let materials = effect_original_restore_fixture_call(host, reference, request).unwrap()
  host.journal.reserve_dispatch(request, true).unwrap() |> ignore
  assert_true(host.journal.claim_physical_start(request, true).unwrap())
  let record = host.journal.retained(request).unwrap().unwrap()
  host.journal
  .cancellation_test_operation(
    request,
    "capture-cancel",
    "original-cancel",
    record.revision.to_int(),
    () => true,
    () => false,
  )
  .unwrap()
  |> ignore
  let cancelled = host.journal.retained(request).unwrap().unwrap()
  assert_true(cancelled.cancellation_requested)
  assert_true(cancelled.physical_start_claimed)
  let before = run_record_body(cancelled).unwrap()
  local_capture_binding_fixture_call(
    host,
    reference,
    request,
    host.journal,
    materials,
    materials.run_definition,
  ).unwrap()
  assert_eq(
    run_record_body(host.journal.retained(request).unwrap().unwrap()).unwrap(),
    before,
  )
  host.close().unwrap()
}

///|
test "Native Local capture binding requires current Run read even for a binding mismatch" {
  let (host, reference, request, _) = effect_original_restorable_host_fixture(
    "local-capture-binding-denied",
  )
  let materials = effect_original_restore_fixture_call(host, reference, request).unwrap()
  let before = run_record_body(host.journal.retained(request).unwrap().unwrap()).unwrap()
  assert_true(
    local_capture_binding_fixture_call(
      host,
      reference,
      request,
      host.journal,
      { ..materials, request: None, },
      materials.run_definition,
      principal="other",
    )
    is Err(Journal(AuthorizationDenied)),
  )
  assert_eq(
    run_record_body(host.journal.retained(request).unwrap().unwrap()).unwrap(),
    before,
  )
  host.close().unwrap()
  assert_true(
    local_capture_binding_fixture_call(
      host,
      reference,
      request,
      host.journal,
      materials,
      materials.run_definition,
    )
    is Err(Journal(AuthorizationDenied)),
  )
}

///|
test "Native Local capture binding does not fill a missing accepted packet from live materials" {
  let (host, reference, request, _) = effect_original_restorable_host_fixture(
    "local-capture-binding-missing",
  )
  let materials = effect_original_restore_fixture_call(host, reference, request).unwrap()
  let record = host.journal.retained(request).unwrap().unwrap()
  host.journal
  .transaction(() => {
    host.journal.save({ ..record, effect_material_originals: None, })
  })
  .unwrap()
  |> ignore
  assert_true(
    local_capture_binding_fixture_call(
      host,
      reference,
      request,
      host.journal,
      materials,
      materials.run_definition,
    )
    is Err(Journal(MissingEffectMaterialOriginal)),
  )
  assert_true(
    host.journal.retained(request).unwrap().unwrap().effect_material_originals
    is None,
  )
  host.close().unwrap()
}
