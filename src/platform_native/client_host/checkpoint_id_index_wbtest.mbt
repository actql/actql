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
  assert_true(
    journal.transaction(() => {
      journal.checkpoint_request_by_id_locked(scope, "checkpoint-run")
    })
    is Ok(None),
  )
  assert_true(
    journal.transaction(() => {
      journal.checkpoint_request_by_id_locked(scope, "unknown")
    })
    is Ok(None),
  )
  assert_true(
    journal.transaction(() => {
      journal.checkpoint_request_by_id_locked("sha256:" + "f".repeat(64), id)
    })
    is Ok(None),
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
  journal
  .transaction(() => {
    database
    .remove_exact("client_checkpoint_id_index", key, row.revision, row.body)
    .map_err(issue => Physical(issue))
  })
  .unwrap()
  assert_true(
    journal.transaction(() => {
      journal.checkpoint_request_by_id_locked(
        scope, "client-original-checkpoint",
      )
    })
    is Ok(None),
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
  assert_true(
    journal.transaction(() => {
      journal.checkpoint_request_by_id_locked(scope, "another-checkpoint")
    })
    is Err(CustodyLost),
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
  assert_true(
    journal.transaction(() => {
      journal.save_checkpoint_id_index({ ..waiting, checkpoint: None, }, {
        ..waiting,
        request: other,
      })
    })
    is Err(CustodyLost),
  )
  let after = database.read("client_checkpoint_id_index", key).unwrap()
  assert_eq(after.body, before.body)
  assert_eq(after.revision, before.revision)
  database.close_checked().unwrap()
}

///|
test "Journal rolls back the Run CAS and prior locator after checkpoint index collision" {
  let database = epoch_test_database("checkpoint-id-cas-rollback")
  let (journal, request, waiting) = checkpoint_test_waiting(database, [])
  let scope = @host.client_request_authority_scope_cid(request)
  let run_key = @host.client_request_scope_cid(request)
  let original_key = checkpoint_id_index_key(
    scope, "client-original-checkpoint",
  )
  let collision_key = checkpoint_id_index_key(scope, "occupied-checkpoint")
  let original_run = database.read("client_runs", run_key).unwrap()
  let original_locator = database
    .read("client_checkpoint_id_index", original_key)
    .unwrap()
  let checkpoint = waiting.checkpoint.unwrap()
  let replacement = @checkpoint.seal_checkpoint(
    { ..checkpoint.artifact.checkpoint, checkpoint_id: "occupied-checkpoint", },
    native_checkpoint_limits(),
  ).unwrap()
  // An existing locator forces the index failure after the Run compare-exchange
  // and removal of the prior locator, inside the actual Journal transaction.
  database
  .insert("client_checkpoint_id_index", collision_key, original_locator.body)
  .unwrap()
  |> ignore
  let occupied = database
    .read("client_checkpoint_id_index", collision_key)
    .unwrap()
  let original_custody = database
    .read("client_effect_custody", run_key)
    .unwrap()
  // Use the same persisted-artifact/state issuers as the original fixture;
  // neither a mismatched state nor an early custody refusal reaches the CAS.
  database
  .insert(
    "test_checkpoint_artifacts",
    replacement.checkpoint_cid,
    @utf8.encode(replacement.wire),
  )
  .unwrap()
  |> ignore
  let persisted = @checkpoint.confirm_checkpoint_persisted(
    replacement,
    @utf8.decode(
      database
      .read("test_checkpoint_artifacts", replacement.checkpoint_cid)
      .unwrap().body,
    ),
  ).unwrap()
  let state_wire = @checkpoint.issue_waiting_run_state(
    persisted,
    checkpoint.updated_at,
    checkpoint.declared_results,
    native_checkpoint_limits(),
  ).unwrap()
  let next_checkpoint = {
    ..checkpoint,
    artifact: replacement,
    state: @checkpoint.admit_run_state_wire(
      state_wire,
      native_checkpoint_limits(),
    ).unwrap(),
  }
  let next_body = checkpoint_record_body(next_checkpoint).unwrap()
  assert_true(read_checkpoint_record(next_body, waiting.definition) is Ok(_))
  let next = { ..waiting, checkpoint: Some(next_checkpoint), }
  let mut observed_cas = false
  let mut observed_locator_removal = false
  let mut observed_collision = false
  assert_true(
    journal.transaction(() => {
      // Test-only staged checkpoint custody must match before save's original
      // conjunctive custody check. The same outer transaction owns its rollback.
      match
        database.remove_exact(
          "client_effect_custody",
          run_key,
          original_custody.revision,
          original_custody.body,
        ) {
        Err(issue) => return Err(Physical(issue))
        Ok(_) => ()
      }
      match
        database.insert(
          "client_effect_custody",
          run_key,
          effect_ledger_custody_body(next).unwrap(),
        ) {
        Err(issue) => return Err(Physical(issue))
        Ok(_) => ()
      }
      let result = journal.save(next)
      observed_collision = result is Err(CustodyLost)
      let changed = database.read("client_runs", run_key).unwrap()
      observed_cas = changed.revision == original_run.revision + 1L &&
        changed.body != original_run.body
      observed_locator_removal = database.read(
          "client_checkpoint_id_index", original_key,
        )
        is Err(@sqlite.NotFound)
      result.map(_ => ())
    })
    is Err(CustodyLost),
  )
  assert_true(observed_collision)
  assert_true(observed_cas)
  assert_true(observed_locator_removal)
  let retained_run = database.read("client_runs", run_key).unwrap()
  let retained_locator = database
    .read("client_checkpoint_id_index", original_key)
    .unwrap()
  let retained_collision = database
    .read("client_checkpoint_id_index", collision_key)
    .unwrap()
  let retained_custody = database
    .read("client_effect_custody", run_key)
    .unwrap()
  assert_eq(retained_custody.revision, original_custody.revision)
  assert_eq(retained_custody.body, original_custody.body)
  assert_eq(retained_run.revision, original_run.revision)
  assert_eq(retained_run.body, original_run.body)
  assert_eq(retained_locator.revision, original_locator.revision)
  assert_eq(retained_locator.body, original_locator.body)
  assert_eq(retained_collision.revision, occupied.revision)
  assert_eq(retained_collision.body, occupied.body)
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
