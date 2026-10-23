///|
// Actual legacy SQLite/Journal transactions. Typed lookup keys are locators,
// not Run authority; no Native Host pair or business permission is supplied.
test "definition uniqueness classifies only the authenticated indexed collision" {
  let database = epoch_test_database("definition-collision-classification")
  initialize_native_client_run_journal(database).unwrap()
  let journal = open_native_client_run_journal(database, 8).unwrap()
  let calls : Array[String] = []
  let access = journal_test_operation_access(database, calls)
  let (first_request, first_prepared, first_compiled, first_definition) = journal_test_run(
    "indexed-first", "indexed-shared",
  )
  validate_native_client_run_binding(
    first_request, first_prepared, first_compiled, first_definition,
  ).unwrap()
  journal
  .transaction_with_reads(
    () => {
      journal.bind_run_locked(
        first_request,
        first_definition,
        operations=Some(access),
      )
    },
    reads=Some(access.reads),
  )
  .unwrap()
  |> ignore
  assert_false(calls.any(value => value.has_prefix("run-definition-key:")))
  assert_false(calls.any(value => value.has_prefix("scan:")))
  let first_key = @host.client_request_scope_cid(first_request)
  let before = database.read("client_runs", first_key).unwrap()
  let issued = database.read("client_run_custody", "issued").unwrap()
  let (duplicate_request, prepared, compiled, definition) = journal_test_run(
    "indexed-duplicate", "indexed-shared",
  )
  assert_eq(
    @publication.publication_contract_identity(definition),
    @publication.publication_contract_identity(first_definition),
  )
  validate_native_client_run_binding(
    duplicate_request, prepared, compiled, definition,
  ).unwrap()
  calls.clear()
  assert_true(
    journal.transaction_with_reads(
      () => {
        journal.bind_run_locked(
          duplicate_request,
          definition,
          operations=Some(access),
        )
      },
      reads=Some(access.reads),
    )
    is Err(ForeignRun),
  )
  assert_eq(
    calls.filter(value => value.has_prefix("run-definition-key:")).length(),
    1,
  )
  assert_eq(
    calls.filter(value => value == "read:client_runs:" + first_key).length(),
    1,
  )
  assert_false(calls.any(value => value.has_prefix("scan:")))
  let after = database.read("client_runs", first_key).unwrap()
  assert_eq(after.body, before.body)
  assert_eq(after.revision, before.revision)
  let after_issued = database.read("client_run_custody", "issued").unwrap()
  assert_eq(after_issued.body, issued.body)
  assert_eq(after_issued.revision, issued.revision)
  assert_true(
    database.read(
      "client_runs",
      @host.client_request_scope_cid(duplicate_request),
    )
    is Err(@sqlite.NotFound),
  )
  // A different collision with no matching definition must retain its physical
  // cause. The existing typed routing seam injects only this failed insert;
  // the actual index lookup and transaction/rollback still use this Database.
  let (other_request, other_prepared, other_compiled, other_definition) = journal_test_run(
    "indexed-other", "indexed-independent",
  )
  validate_native_client_run_binding(
    other_request, other_prepared, other_compiled, other_definition,
  ).unwrap()
  let collision = {
    ..access,
    insert: (table, key, body) => {
      if table == "client_runs" {
        calls.push("controlled-insert-collision")
        Err(@sqlite.Collision)
      } else {
        (access.insert)(table, key, body)
      }
    },
  }
  calls.clear()
  assert_true(
    journal.transaction_with_reads(
      () => {
        journal.bind_run_locked(
          other_request,
          other_definition,
          operations=Some(collision),
        )
      },
      reads=Some(collision.reads),
    )
    is Err(Physical(@sqlite.Collision)),
  )
  assert_eq(
    calls.filter(value => value.has_prefix("run-definition-key:")).length(),
    1,
  )
  assert_false(calls.any(value => value.has_prefix("scan:")))
  assert_eq(
    database.read("client_run_custody", "issued").unwrap().body,
    issued.body,
  )
  // Even a typed returned key cannot misclassify an unrelated original.
  let foreign_locator = {
    ..collision,
    reads: { ..collision.reads, run_definition_key: _ => Ok(Some(first_key)), },
  }
  assert_true(
    journal.transaction_with_reads(
      () => {
        journal.bind_run_locked(
          other_request,
          other_definition,
          operations=Some(foreign_locator),
        )
      },
      reads=Some(foreign_locator.reads),
    )
    is Err(CustodyLost),
  )
  assert_eq(
    database.read("client_run_custody", "issued").unwrap().body,
    issued.body,
  )
  assert_true(
    database.read("client_runs", @host.client_request_scope_cid(other_request))
    is Err(@sqlite.NotFound),
  )
  database.close_checked().unwrap()
}
