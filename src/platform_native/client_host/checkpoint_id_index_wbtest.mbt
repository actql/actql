///|
test "checkpoint ID lookup uses one exact same-transaction original Run locator" {
  let database = epoch_test_database("checkpoint-id-original")
  let (journal, request, waiting) = checkpoint_test_waiting(database, [])
  let scope = @host.client_request_authority_scope_cid(request)
  let id = "client-original-checkpoint"
  assert_true(
    journal.transaction(() => journal.checkpoint_request_by_id_locked(scope, id))
    is Ok(Some(_)),
  )
  assert_eq(
    journal.transaction(() => {
      journal.checkpoint_request_by_id_locked(scope, "checkpoint-run")
    }),
    Ok(None),
  )
  assert_eq(
    journal.transaction(() => {
      journal.checkpoint_request_by_id_locked(scope, "unknown")
    }),
    Ok(None),
  )
  assert_eq(
    journal.transaction(() => {
      journal.checkpoint_request_by_id_locked("sha256:" + "f".repeat(64), id)
    }),
    Ok(None),
  )
  let row = database
    .read("client_checkpoint_id_index", checkpoint_id_index_key(scope, id))
    .unwrap()
  let (retained, retained_id, cid) = read_checkpoint_id_index(row.body).unwrap()
  assert_eq(
    @host.client_request_identity_relation(retained, request),
    @host.SameRequest,
  )
  assert_eq(retained_id, id)
  assert_eq(cid, waiting.checkpoint.unwrap().artifact.checkpoint_cid)
  assert_eq(row.revision, 0L)
  assert_true(
    database.scan_after(
      "client_checkpoint_id_index",
      checkpoint_id_index_key(scope, id),
    )
    is Err(@sqlite.NotFound),
  )
  database.close_checked().unwrap()
}

///|
test "checkpoint locator survives reopen and missing legacy index never backfills" {
  let database = epoch_test_database("checkpoint-id-legacy-missing")
  let (_, request, _) = checkpoint_test_waiting(database, [])
  let journal = open_native_client_run_journal(database, 8).unwrap()
  let scope = @host.client_request_authority_scope_cid(request)
  let key = checkpoint_id_index_key(scope, "client-original-checkpoint")
  assert_true(
    journal.transaction(() => {
      journal.checkpoint_request_by_id_locked(
        scope, "client-original-checkpoint",
      )
    })
    is Ok(Some(_)),
  )
  let row = database.read("client_checkpoint_id_index", key).unwrap()
  database
  .remove_exact("client_checkpoint_id_index", key, row.revision, row.body)
  .unwrap()
  assert_eq(
    journal.transaction(() => {
      journal.checkpoint_request_by_id_locked(
        scope, "client-original-checkpoint",
      )
    }),
    Ok(None),
  )
  journal
  .transaction(() => {
    let record = journal.retained(request).unwrap().unwrap()
    journal.save(record).map(_ => ())
  })
  .unwrap()
  assert_true(
    database.read("client_checkpoint_id_index", key) is Err(@sqlite.NotFound),
  )
  database.close_checked().unwrap()
}

///|
test "checkpoint locator copied to another exact ID cannot select that Run" {
  let database = epoch_test_database("checkpoint-id-forged")
  let (journal, request, _) = checkpoint_test_waiting(database, [])
  let scope = @host.client_request_authority_scope_cid(request)
  let row = database
    .read(
      "client_checkpoint_id_index",
      checkpoint_id_index_key(scope, "client-original-checkpoint"),
    )
    .unwrap()
  database
  .insert(
    "client_checkpoint_id_index",
    checkpoint_id_index_key(scope, "another-checkpoint"),
    row.body,
  )
  .unwrap()
  |> ignore
  assert_eq(
    journal.transaction(() => {
      journal.checkpoint_request_by_id_locked(scope, "another-checkpoint")
    }),
    Err(CustodyLost),
  )
  assert_true(
    journal.transaction(() => {
      journal.checkpoint_request_by_id_locked(
        scope, "client-original-checkpoint",
      )
    })
    is Ok(Some(_)),
  )
  database.close_checked().unwrap()
}

///|
test "checkpoint locator collision refuses without replacing the original binding" {
  let database = epoch_test_database("checkpoint-id-collision")
  let (journal, request, waiting) = checkpoint_test_waiting(database, [])
  let (other, _, _, _) = journal_test_run(
    "different-checkpoint-request", "different-checkpoint-run",
  )
  let scope = @host.client_request_authority_scope_cid(request)
  assert_eq(scope, @host.client_request_authority_scope_cid(other))
  let key = checkpoint_id_index_key(scope, "client-original-checkpoint")
  let before = database.read("client_checkpoint_id_index", key).unwrap()
  assert_eq(
    journal.transaction(() => {
      journal.save_checkpoint_id_index({ ..waiting, checkpoint: None, }, {
        ..waiting,
        request: other,
      })
    }),
    Err(CustodyLost),
  )
  let after = database.read("client_checkpoint_id_index", key).unwrap()
  assert_eq(after.body, before.body)
  assert_eq(after.revision, before.revision)
  database.close_checked().unwrap()
}
