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
