///|
test "Native HTTP Work attachment observes the accepted original Store before first start" {
  let name = "model-http-work-attachment"
  let host = policy_host_fixture(name)
  let scope = host
    .authority_scope_cid("operator", "cli", epoch_test_crypto())
    .unwrap()
  let (request, prepared, compiled, definition) = journal_test_run(
    "attachment-request",
    "attachment-run",
    scope~,
  )
  let (_, _, _, foreign_definition) = journal_test_run(
    "attachment-other-request",
    "attachment-other-run",
    scope~,
  )
  let journal = host.journal
  journal.bind_run(request, prepared, compiled, definition, true).unwrap()
  |> ignore
  let base = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let parent = @filesystem.open_private_root(base).unwrap()
  parent.create_directory(name).unwrap() |> ignore
  parent.create_directory(name + "-foreign").unwrap() |> ignore
  let library = local_journal_test_library()
  let authority = "sha256:" + "c".repeat(64)
  let store = @publication_store.open_store(
    library,
    base + "/" + name,
    authority,
    65536L,
    8L,
    131072L,
  ).unwrap()
  let foreign = @publication_store.open_store(
    library,
    base + "/" + name + "-foreign",
    authority,
    65536L,
    8L,
    131072L,
  ).unwrap()
  let reads = journal_test_read_access(host.database, [])
  let binding = run_observation_store_binding(store, name).unwrap()
  let replacement = run_observation_store_binding(foreign, name).unwrap()
  let check = (selected_definition, selected_store, current) => {
    journal.require_unstarted_model_work_run(
      request, selected_definition, selected_store, false, reads, current,
    )
  }
  assert_true(check(definition, binding, () => true) is Err(ForeignRun))
  let publication = install_native_client_cancellation_publication(
    store, name, 65536, 8192, 64,
  ).unwrap()
  journal.bind_installed_publication(request, publication, () => true).unwrap()
  let accepted = journal.retained(request).unwrap().unwrap()
  assert_true(check(definition, binding, () => true) is Ok(_))
  assert_true(check(definition, replacement, () => true) is Err(ForeignRun))
  assert_true(check(foreign_definition, binding, () => true) is Err(ForeignRun))
  let current_checks = Ref(0)
  assert_true(
    check(definition, binding, () => {
      current_checks.val += 1
      current_checks.val == 1
    })
    is Err(AuthorizationDenied),
  )
  let retained = journal.retained(request).unwrap().unwrap()
  assert_eq(retained.revision, accepted.revision)
  assert_false(retained.dispatch_reserved)
  assert_false(retained.physical_start_claimed)
  journal.reserve_dispatch(request, true).unwrap() |> ignore
  assert_true(journal.claim_physical_start(request, true).unwrap())
  assert_true(check(definition, binding, () => true) is Err(ForeignRun))
  assert_true(foreign.close() is Ok(true))
  assert_true(store.close() is Ok(true))
  host.close().unwrap()
}

///|
// Actual Native Journal rows and retained reads. Synthetic publication
// location facts exercise the comparison without opening a provider or Store.
test "Native Raw save requires the claimed uncancelled Run and its original Store binding" {
  let host = policy_host_fixture("raw-save-original-run")
  let crypto = epoch_test_crypto()
  let scope = host.authority_scope_cid("operator", "cli", crypto).unwrap()
  let (request, prepared, compiled, definition) = journal_test_run(
    "raw-save-request",
    "raw-save-run",
    scope~,
  )
  let journal = host.journal
  journal.bind_run(request, prepared, compiled, definition, true).unwrap()
  |> ignore
  let authority = "sha256:" + "a".repeat(64)
  let binding = installed_publication_binding(
    "raw-save-namespace", authority, 11UL, 21UL,
  ).unwrap()
  let replacement = installed_publication_binding(
    "raw-save-namespace", authority, 11UL, 22UL,
  ).unwrap()
  journal.bind_publication(request, binding, () => true).unwrap()
  journal.reserve_dispatch(request, true).unwrap() |> ignore
  let reads = journal_test_read_access(host.database, [])
  assert_true(
    native_model_raw_run_current(host, request, definition, binding, reads)
    is Err(Journal(ForeignRun)),
  )
  assert_true(journal.claim_physical_start(request, true).unwrap())
  assert_true(
    native_model_raw_run_current(host, request, definition, binding, reads)
    is Ok(_),
  )
  assert_true(
    native_model_raw_run_current(host, request, definition, replacement, reads)
    is Err(Journal(ForeignRun)),
  )
  let run = journal.retained(request).unwrap().unwrap()
  journal
  .transaction(() => journal.save({ ..run, cancellation_requested: true, }))
  .unwrap()
  |> ignore
  assert_true(
    native_model_raw_run_current(host, request, definition, binding, reads)
    is Err(Journal(ForeignRun)),
  )
  host.close().unwrap()
}

///|
test "Native Model HTTP rejects a durable cancellation after its Run was cached" {
  let name = "model-http-current-run-cut"
  let reader = epoch_test_database(name)
  initialize_native_client_run_journal(reader).unwrap()
  let journal = open_native_client_run_journal(reader, 8).unwrap()
  let (request, prepared, compiled, definition) = journal_test_run(
    "model-http-current-request", "model-http-current-run",
  )
  journal.bind_run(request, prepared, compiled, definition, true).unwrap()
  |> ignore
  journal.reserve_dispatch(request, true).unwrap() |> ignore
  assert_true(journal.claim_physical_start(request, true).unwrap())
  journal.operation_active = true
  let original = journal.retained(request).unwrap().unwrap()
  let reads = journal_test_read_access(reader, [])
  assert_false(original.cancellation_requested)
  assert_true(journal.recheck_model_run_cut(request, reads) is Ok(_))

  let peer = epoch_test_database(name)
  let writer = open_native_client_run_journal(peer, 8).unwrap()
  let current = writer.retained(request).unwrap().unwrap()
  writer
  .transaction(() => writer.save({ ..current, cancellation_requested: true, }))
  .unwrap()
  |> ignore

  let cached = journal.retained(request).unwrap().unwrap()
  assert_eq(cached.revision, original.revision)
  assert_false(cached.cancellation_requested)
  assert_true(journal.recheck_model_run_cut(request, reads) is Err(ForeignRun))
  let changed = writer.retained(request).unwrap().unwrap()
  assert_true(changed.revision > original.revision)
  assert_true(changed.cancellation_requested)
  peer.close_checked().unwrap()
  journal.operation_active = false
  reader.close_checked().unwrap()
}
