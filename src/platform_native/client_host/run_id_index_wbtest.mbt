///|
test "Run ID locator admits arbitrary original IDs and reads only its selected target" {
  let (database, journal, authority, reference) = submitted_test_setup(
    "run-id-target",
  )
  let scope = "sha256:" + "a".repeat(64)
  let (intent, preparation, request, compiled, definition) = submitted_run_test_input(
    reference, "arbitrary-original-run-id",
  )
  journal
  .record_submitted_intent(authority, reference, intent, scope, true, 1001.0)
  .unwrap()
  |> ignore
  journal
  .accept_submitted_run(
    authority, reference, preparation, request, compiled, definition, scope, true,
    1002.0,
  )
  .unwrap()
  |> ignore
  database
  .insert("client_submitted_intents", "unrelated", b"invalid unrelated history")
  .unwrap()
  |> ignore
  let calls : Array[String] = []
  let reads = journal_test_read_access(database, calls)
  let selected = journal
    .transaction_with_reads(
      () => {
        journal.select_saved_state_run_id_locked(
          authority,
          scope,
          "arbitrary-original-run-id",
          reads=Some(reads),
        )
      },
      reads=Some(reads),
    )
    .unwrap()
    .unwrap()
  assert_eq(selected.0.wire, reference.wire)
  assert_eq(
    @host.client_request_scope_cid(selected.1),
    @host.client_request_scope_cid(request),
  )
  assert_false(
    calls.any(value => {
      value.has_prefix("scan:client_runs:") ||
      value.has_prefix("scan:client_submitted_intents:") ||
      value.has_prefix("scan:client_effect_")
    }),
  )
  assert_false(
    calls.any(value => value == "read:client_submitted_intents:unrelated"),
  )
  database.close_checked().unwrap()
  authority.crypto.close_checked().unwrap()
}

///|
test "Run ID locator collision rolls back the original new admission" {
  let (database, journal, authority, reference) = submitted_test_setup(
    "run-id-rollback",
  )
  let scope = "sha256:" + "a".repeat(64)
  let (intent, preparation, request, compiled, definition) = submitted_run_test_input(
    reference, "collision-original-run",
  )
  journal
  .record_submitted_intent(authority, reference, intent, scope, true, 1001.0)
  .unwrap()
  |> ignore
  let before = database
    .read("client_submitted_intents", reference.request_id)
    .unwrap()
  database
  .insert(
    "client_run_id_index",
    run_id_index_key(scope, "collision-original-run"),
    b"not an original reference",
  )
  .unwrap()
  |> ignore
  assert_true(
    journal.accept_submitted_run(
      authority, reference, preparation, request, compiled, definition, scope, true,
      1002.0,
    )
    is Err(CustodyLost),
  )
  let after = database
    .read("client_submitted_intents", reference.request_id)
    .unwrap()
  assert_eq(after.revision, before.revision)
  assert_eq(after.body, before.body)
  assert_true(journal.retained(request).unwrap() is None)
  assert_eq(run_journal_custody(database, 8).unwrap().0, 0)
  database.close_checked().unwrap()
  authority.crypto.close_checked().unwrap()
}

///|
test "legacy arbitrary Run ID indexing is explicit and preserves its existing original" {
  let (database, journal, authority, reference) = submitted_test_setup(
    "run-id-legacy",
  )
  let scope = "sha256:" + "a".repeat(64)
  let id = "legacy-arbitrary-run"
  let (intent, preparation, request, compiled, definition) = submitted_run_test_input(
    reference, id,
  )
  journal
  .record_submitted_intent(authority, reference, intent, scope, true, 1001.0)
  .unwrap()
  |> ignore
  journal
  .accept_submitted_run(
    authority, reference, preparation, request, compiled, definition, scope, true,
    1002.0,
  )
  .unwrap()
  |> ignore
  let before = database
    .read("client_runs", @host.client_request_scope_cid(request))
    .unwrap()
  let table = @utf8.encode("client_run_id_index")
  let key = @utf8.encode(run_id_index_key(scope, id))
  assert_true(
    submitted_test_remove_record(
      database,
      table,
      table.length(),
      key,
      key.length(),
    ),
  )
  assert_true(
    journal.transaction(() => {
      journal.select_saved_state_run_id_locked(authority, scope, id)
    })
    is Err(RunIdIndexIncomplete),
  )
  journal
  .transaction(() => {
    journal.migrate_append_metadata_locked(1024L, authority, scope)
  })
  .unwrap()
  let selected = journal
    .transaction(() => {
      journal.select_saved_state_run_id_locked(authority, scope, id)
    })
    .unwrap()
    .unwrap()
  assert_eq(selected.0.wire, reference.wire)
  let after = database
    .read("client_runs", @host.client_request_scope_cid(request))
    .unwrap()
  assert_eq(after.body, before.body)
  assert_eq(after.revision, before.revision)
  assert_true(
    journal
    .transaction(() => {
      journal.select_saved_state_run_id_locked(authority, scope, "missing-id")
    })
    .unwrap()
    is None,
  )
  let coverage = database.read("client_run_id_index_coverage", scope).unwrap()
  database
  .compare_exchange(
    "client_run_id_index_coverage",
    scope,
    coverage.revision,
    b"0:0",
  )
  .unwrap()
  |> ignore
  assert_true(
    journal.transaction(() => {
      journal.select_saved_state_run_id_locked(authority, scope, "missing-id")
    })
    is Err(RunIdIndexIncomplete),
  )
  database.close_checked().unwrap()
  authority.crypto.close_checked().unwrap()
}
