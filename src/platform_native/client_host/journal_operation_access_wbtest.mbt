///|
// Real SQLite routing diagnostics. These callbacks are not an installed
// physical pair or evidence of a supplied business execution.
fn journal_test_operation_access(
  database : @sqlite.Database,
  calls : Array[String],
) -> NativeClientJournalOperationAccess {
  {
    reads: journal_test_read_access(database, calls),
    before_construction: None,
    install_read_evidence_schema: max_rows => {
      calls.push("install read evidence schema")
      database.install_client_read_evidence_schema(max_rows)
    },
    install_run_definition_schema: max_rows => {
      calls.push("install run definition schema")
      database.install_client_run_definition_schema(max_rows)
    },
    capacity_usage: table => {
      calls.push("capacity:" + table)
      database.capacity_usage(table)
    },
    read_evidence_usage: (wire, max_rows, max_bytes) => {
      calls.push("read-evidence-usage")
      database.client_read_evidence_usage(wire, max_rows, max_bytes)
    },
    read_capacity: (table, key) => {
      calls.push("read-capacity:" + table + ":" + key)
      database.read_capacity(table, key)
    },
    reserve_capacity: (table, key, bytes, objects, max_bytes, max_objects) => {
      calls.push("reserve:" + table + ":" + key)
      database.reserve_capacity_in_transaction(
        table, key, bytes, objects, max_bytes, max_objects,
      )
    },
    grow_capacity: (
      table,
      key,
      previous,
      bytes,
      objects,
      max_bytes,
      max_objects,
    ) => {
      calls.push("grow:" + table + ":" + key)
      grow_journal_capacity_in_transaction(
        database, table, key, previous, bytes, objects, max_bytes, max_objects,
      )
    },
    insert: (table, key, body) => {
      calls.push("insert:" + table + ":" + key)
      database.insert(table, key, body)
    },
    remove_exact: (table, key, revision, body) => {
      calls.push("remove_exact:" + table + ":" + key)
      database.remove_exact(table, key, revision, body)
    },
    compare_exchange: (table, key, revision, body) => {
      calls.push("compare_exchange:" + table + ":" + key)
      database.compare_exchange(table, key, revision, body)
    },
  }
}

///|
test "Model journal cumulative reservation keeps entries settlements and rollback on one original" {
  let host = policy_host_fixture("model-cumulative-census")
  let foreign = epoch_test_database("model-cumulative-census-foreign")
  let calls : Array[String] = []
  let access = journal_test_operation_access(host.database, calls)
  let table = "client_model_call_originals"
  let key = "original-scope"
  host.journal
  .transaction_with_reads(
    () => {
      for bytes in [10L, 20L, 3L, 4L] {
        let previous = match
          read_client_journal_capacity(host.database, table, key, Some(access)) {
          Ok(value) => value
          Err(@sqlite.NotFound) => { reserved_bytes: 0L, reserved_objects: 0L, }
          Err(issue) => return Err(Physical(issue))
        }
        match
          grow_client_journal_capacity(
            host.database,
            table,
            key,
            previous,
            bytes,
            1L,
            47L,
            6L,
            Some(access),
          ) {
          Ok(_) => ()
          Err(issue) => return Err(Physical(issue))
        }
      }
      reserve_client_journal_capacity(
        host.database,
        table,
        "other-scope",
        7L,
        1L,
        47L,
        6L,
        Some(access),
      )
      .map(_ => ())
      .map_err(issue => Physical(issue))
    },
    reads=Some(access.reads),
  )
  .unwrap()
  let previous = read_client_journal_capacity(
    host.database,
    table,
    key,
    Some(access),
  ).unwrap()
  assert_eq(previous.reserved_bytes, 37L)
  assert_eq(previous.reserved_objects, 4L)
  // The new cumulative row fits individually, but not beside the other
  // original reservation. Failure AFTER exact replacement must roll back.
  assert_true(
    host.journal.transaction_with_reads(
      () => {
        grow_client_journal_capacity(
          host.database,
          table,
          key,
          previous,
          4L,
          1L,
          47L,
          6L,
          Some(access),
        ).map_err(issue => Physical(issue))
      },
      reads=Some(access.reads),
    )
    is Err(Physical(@sqlite.CapacityExceeded)),
  )
  let retained = read_client_journal_capacity(
    host.database,
    table,
    key,
    Some(access),
  ).unwrap()
  assert_eq(retained.reserved_bytes, 37L)
  assert_eq(retained.reserved_objects, 4L)
  assert_eq(host.database.capacity_usage(table).unwrap().reserved_bytes, 44L)
  for selected in [key, "missing-scope"] {
    assert_true(
      host.journal.transaction_with_reads(
        () => {
          grow_client_journal_capacity(
            host.database,
            table,
            selected,
            { reserved_bytes: 36L, reserved_objects: 4L, },
            1L,
            1L,
            64L,
            6L,
            Some(access),
          ).map_err(issue => Physical(issue))
        },
        reads=Some(access.reads),
      )
      is Err(Physical(@sqlite.Collision)),
    )
  }
  calls.clear()
  assert_true(
    grow_client_journal_capacity(
      foreign,
      table,
      key,
      previous,
      1L,
      1L,
      64L,
      6L,
      Some(access),
    )
    is Err(@sqlite.Collision),
  )
  assert_eq(calls, [])
  assert_eq(host.database.capacity_usage(table).unwrap().reserved_bytes, 44L)
  assert_eq(foreign.capacity_usage(table).unwrap().reserved_bytes, 0L)
  foreign.close_checked().unwrap()
  host.close().unwrap()
}

///|
test "Model journal cumulative reservation keeps lost commit acknowledgement Unknown" {
  let host = policy_host_fixture("model-cumulative-commit-unknown")
  let calls : Array[String] = []
  let access = journal_test_operation_access(host.database, calls)
  host.journal
  .transaction_with_reads(
    () => {
      grow_client_journal_capacity(
        host.database,
        "client_model_call_originals",
        "original-scope",
        { reserved_bytes: 0L, reserved_objects: 0L, },
        10L,
        1L,
        64L,
        4L,
        Some(access),
      ).map_err(issue => Physical(issue))
    },
    reads=Some(access.reads),
  )
  .unwrap()
  client_test_fail_commit_reply(host.database, 1)
  assert_true(
    host.journal.transaction_with_reads(
      () => {
        grow_client_journal_capacity(
          host.database,
          "client_model_call_originals",
          "original-scope",
          { reserved_bytes: 10L, reserved_objects: 1L, },
          20L,
          1L,
          64L,
          4L,
          Some(access),
        ).map_err(issue => Physical(issue))
      },
      reads=Some(access.reads),
    )
    is Err(TransactionUnknown),
  )
  assert_true(host.journal.fenced)
  assert_true(host.database.transaction_fenced())
  // Historical bytes are present, but do not turn the missing COMMIT reply
  // into a Model persistence acknowledgement or a retry permission.
  let retained = host.database
    .read_capacity("client_model_call_originals", "original-scope")
    .unwrap()
  assert_eq(retained.reserved_bytes, 30L)
  assert_eq(retained.reserved_objects, 2L)
  host.close().unwrap()
}

///|
test "Original Journal capacity routing keeps the transaction and refuses foreign databases" {
  let database = epoch_test_database("journal-capacity-route")
  let foreign = epoch_test_database("journal-capacity-route-foreign")
  let calls : Array[String] = []
  let access = journal_test_operation_access(database, calls)
  (access.reads.transaction)(JournalBegin).unwrap()
  assert_true(
    reserve_client_journal_capacity(
      database,
      "read-evidence",
      "original",
      512L,
      1L,
      512L,
      1L,
      Some(access),
    ).unwrap(),
  )
  assert_false(
    reserve_client_journal_capacity(
      database,
      "read-evidence",
      "original",
      512L,
      1L,
      512L,
      1L,
      Some(access),
    ).unwrap(),
  )
  assert_true(
    reserve_client_journal_capacity(
      database,
      "read-evidence",
      "other",
      1L,
      1L,
      512L,
      1L,
      Some(access),
    )
    is Err(@sqlite.CapacityExceeded),
  )
  let usage = client_journal_capacity_usage(
    database,
    "read-evidence",
    Some(access),
  ).unwrap()
  assert_eq(usage.reserved_bytes, 512L)
  assert_eq(usage.reserved_objects, 1L)
  let selected = read_client_journal_capacity(
    database,
    "read-evidence",
    "original",
    Some(access),
  ).unwrap()
  assert_eq(selected.reserved_bytes, 512L)
  assert_eq(selected.reserved_objects, 1L)
  calls.clear()
  assert_true(
    read_client_journal_capacity(
      foreign,
      "read-evidence",
      "original",
      Some(access),
    )
    is Err(@sqlite.Collision),
  )
  assert_true(
    client_journal_capacity_usage(foreign, "read-evidence", Some(access))
    is Err(@sqlite.Collision),
  )
  assert_true(
    reserve_client_journal_capacity(
      foreign,
      "read-evidence",
      "foreign",
      1L,
      1L,
      512L,
      1L,
      Some(access),
    )
    is Err(@sqlite.Collision),
  )
  assert_eq(calls, [])
  (access.reads.transaction)(JournalRollback).unwrap()
  assert_eq(
    client_journal_capacity_usage(database, "read-evidence", Some(access)).unwrap().reserved_bytes,
    0L,
  )
  assert_true(
    read_client_journal_capacity(
      database,
      "read-evidence",
      "original",
      Some(access),
    )
    is Err(@sqlite.NotFound),
  )
  assert_eq(foreign.capacity_usage("read-evidence").unwrap().reserved_bytes, 0L)
  database.close_checked().unwrap()
  foreign.close_checked().unwrap()
}

///|
test "Epoch issue routes the original monotonic transaction and rejects a foreign compare exchange" {
  let database = epoch_test_database("journal-routed-issue")
  let foreign = epoch_test_database("journal-routed-issue-foreign")
  let crypto = epoch_test_crypto()
  initialize_native_client_epoch_authority(database, crypto).unwrap()
  let authority = open_native_client_epoch_authority(database, crypto, 100.0).unwrap()
  let calls : Array[String] = []
  let access = journal_test_operation_access(database, calls)
  let scope = "sha256:" + "a".repeat(64)
  let epoch = authority
    .issue_epoch_with_operations(scope, true, 1000.0, operations=Some(access))
    .unwrap()
  assert_eq(calls, [
    "fenced", "begin", "scan:client_submission_epoch:", "scan:client_submission_epoch:authority",
    "read:client_submission_epoch:authority", "compare_exchange:client_submission_epoch:authority",
    "commit",
  ])
  assert_eq(
    authority.verify_epoch(epoch, scope, true, 1001.0).unwrap(),
    @scope.Admissible,
  )
  calls.clear()
  assert_true(
    compare_exchange_client_journal_value(
      foreign,
      "client_submission_epoch",
      "authority",
      0L,
      b"foreign",
      Some(access),
    )
    is Err(@sqlite.Collision),
  )
  assert_eq(calls, [])
  assert_true(
    foreign.read("client_submission_epoch", "authority")
    is Err(@sqlite.NotFound),
  )
  database.close_checked().unwrap()
  foreign.close_checked().unwrap()
  crypto.close_checked().unwrap()
}

///|
test "Epoch routed commit loss preserves Unknown and fences without replacement issue" {
  let database = epoch_test_database("journal-routed-issue-unknown")
  let crypto = epoch_test_crypto()
  initialize_native_client_epoch_authority(database, crypto).unwrap()
  let authority = open_native_client_epoch_authority(database, crypto, 100.0).unwrap()
  let calls : Array[String] = []
  let ordinary = journal_test_read_access(database, calls)
  let reads : NativeClientJournalReadAccess = {
    ..ordinary,
    transaction: operation => {
      if operation is JournalCommit {
        calls.push("commit-lost")
        database.commit().unwrap()
        Err(@sqlite.Busy)
      } else {
        (ordinary.transaction)(operation)
      }
    },
  }
  let access = { ..journal_test_operation_access(database, calls), reads, }
  let scope = "sha256:" + "a".repeat(64)
  assert_true(
    authority.issue_epoch_with_operations(
      scope,
      true,
      1000.0,
      operations=Some(access),
    )
    is Err(TransactionUnknown),
  )
  assert_true(authority.fenced)
  assert_true(database.transaction_fenced())
  assert_true(calls.length() > 0)
  assert_eq(calls[calls.length() - 1], "fence")
  calls.clear()
  assert_true(
    authority.issue_epoch_with_operations(
      scope,
      true,
      1001.0,
      operations=Some(access),
    )
    is Err(Fenced),
  )
  assert_eq(calls, [])
  database.close_checked().unwrap()
  crypto.close_checked().unwrap()
}

///|
test "Submission original routing retains the exact intent and rejects changed or foreign operations" {
  let (database, journal, authority, reference) = submitted_test_setup(
    "journal-routed-submission",
  )
  let calls : Array[String] = []
  let access = journal_test_operation_access(database, calls)
  let intent = submitted_test_intent("SELECT 1 AS n")
  let scope = "sha256:" + "a".repeat(64)
  let record = journal
    .record_submitted_intent_with_operations(
      authority,
      reference,
      intent,
      scope,
      true,
      1001.0,
      operations=Some(access),
    )
    .unwrap()
  assert_eq(
    @host.client_submitted_intent_wire(record.intent),
    @host.client_submitted_intent_wire(intent),
  )
  assert_true(
    calls.contains("compare_exchange:client_submitted_intent_custody:issued"),
  )
  assert_true(
    calls.contains("insert:client_submitted_intents:" + reference.request_id),
  )
  assert_true(
    calls
    .filter(value => value.has_prefix("scan:"))
    .all(value => value.has_prefix("scan:client_submission_epoch:")),
  )
  assert_true(
    calls.contains("compare_exchange:client_submitted_intent_usage:retained"),
  )
  let original = database
    .read("client_submitted_intents", reference.request_id)
    .unwrap()
  let issued = database
    .read("client_submitted_intent_custody", "issued")
    .unwrap()
  assert_true(
    journal.record_submitted_intent_with_operations(
      authority,
      reference,
      submitted_test_intent("SELECT 2 AS n"),
      scope,
      true,
      1002.0,
      operations=Some(access),
    )
    is Err(ChangedIntent),
  )
  let after = database
    .read("client_submitted_intents", reference.request_id)
    .unwrap()
  assert_eq(after.body, original.body)
  assert_eq(after.revision, original.revision)
  let after_count = database
    .read("client_submitted_intent_custody", "issued")
    .unwrap()
  assert_eq(after_count.body, issued.body)
  assert_eq(after_count.revision, issued.revision)
  let foreign = epoch_test_database("journal-routed-submission-foreign")
  calls.clear()
  assert_true(
    insert_client_journal_value(
      foreign,
      "client_submitted_intents",
      reference.request_id,
      b"foreign",
      Some(access),
    )
    is Err(@sqlite.Collision),
  )
  assert_eq(calls, [])
  assert_true(
    foreign.read("client_submitted_intents", reference.request_id)
    is Err(@sqlite.NotFound),
  )
  database.close_checked().unwrap()
  foreign.close_checked().unwrap()
  authority.crypto.close_checked().unwrap()
}

///|
test "Submission original routing rolls back the same issued count after an insert refusal" {
  let (database, journal, authority, reference) = submitted_test_setup(
    "journal-routed-submission-rollback",
  )
  let issued = database
    .read("client_submitted_intent_custody", "issued")
    .unwrap()
  let usage = database
    .read("client_submitted_intent_usage", "retained")
    .unwrap()
  let calls : Array[String] = []
  let access : NativeClientJournalOperationAccess = {
    ..journal_test_operation_access(database, calls),
    insert: (_table, _key, _body) => {
      calls.push("insert-refused")
      Err(@sqlite.Busy)
    },
  }
  assert_true(
    journal.record_submitted_intent_with_operations(
      authority,
      reference,
      submitted_test_intent("SELECT 1 AS n"),
      "sha256:" + "a".repeat(64),
      true,
      1001.0,
      operations=Some(access),
    )
    is Err(Physical(@sqlite.Busy)),
  )
  assert_true(
    calls.contains("compare_exchange:client_submitted_intent_custody:issued"),
  )
  assert_true(calls.contains("insert-refused"))
  assert_eq(calls[calls.length() - 1], "rollback")
  let after_count = database
    .read("client_submitted_intent_custody", "issued")
    .unwrap()
  assert_eq(after_count.body, issued.body)
  assert_eq(after_count.revision, issued.revision)
  let after_usage = database
    .read("client_submitted_intent_usage", "retained")
    .unwrap()
  assert_eq(after_usage.body, usage.body)
  assert_eq(after_usage.revision, usage.revision)
  assert_true(
    database.read("client_submitted_intents", reference.request_id)
    is Err(@sqlite.NotFound),
  )
  assert_false(database.transaction_fenced())
  database.close_checked().unwrap()
  authority.crypto.close_checked().unwrap()
}

///|
test "Submission usage CAS refusal rolls back issuance before original intent insertion" {
  let (database, journal, authority, reference) = submitted_test_setup(
    "journal-usage-rollback",
  )
  let calls : Array[String] = []
  let access : NativeClientJournalOperationAccess = {
    ..journal_test_operation_access(database, calls),
    compare_exchange: (table, key, revision, body) => {
      calls.push("cas:" + table)
      if table == "client_submitted_intent_usage" {
        Err(@sqlite.Busy)
      } else {
        database.compare_exchange(table, key, revision, body)
      }
    },
  }
  assert_true(
    journal.record_submitted_intent_with_operations(
      authority,
      reference,
      submitted_test_intent("SELECT 1 AS n"),
      "sha256:" + "a".repeat(64),
      true,
      1001.0,
      operations=Some(access),
    )
    is Err(Physical(@sqlite.Busy)),
  )
  assert_true(calls.contains("cas:client_submitted_intent_custody"))
  assert_true(calls.contains("cas:client_submitted_intent_usage"))
  assert_eq(calls[calls.length() - 1], "rollback")
  assert_eq(
    database.read("client_submitted_intent_custody", "issued").unwrap().body,
    b"0",
  )
  assert_eq(
    database.read("client_submitted_intent_usage", "retained").unwrap().body,
    b"0:0",
  )
  assert_true(
    database.read("client_submitted_intents", reference.request_id)
    is Err(@sqlite.NotFound),
  )
  database.close_checked().unwrap()
  authority.crypto.close_checked().unwrap()
}

///|
test "Submission original routing retains real commit loss and never creates a replacement admission" {
  for reply_lost in [false, true] {
    let (database, journal, authority, reference) = submitted_test_setup(
      "journal-routed-submission-unknown-" + reply_lost.to_string(),
    )
    let calls : Array[String] = []
    let access = journal_test_operation_access(database, calls)
    let intent = submitted_test_intent("SELECT 1 AS n")
    let scope = "sha256:" + "a".repeat(64)
    // Advance the original epoch clock, then fault only the intent/count COMMIT.
    submitted_test_fail_commit_after(database, 1, reply_lost)
    assert_true(
      journal.record_submitted_intent_with_operations(
        authority,
        reference,
        intent,
        scope,
        true,
        1001.0,
        operations=Some(access),
      )
      is Err(TransactionUnknown),
    )
    assert_true(journal.fenced)
    assert_true(database.transaction_fenced())
    let retained = database.read(
      "client_submitted_intents",
      reference.request_id,
    )
    assert_true(
      journal.record_submitted_intent_with_operations(
        authority,
        reference,
        intent,
        scope,
        true,
        1002.0,
        operations=Some(access),
      )
      is Err(Epoch(Fenced)),
    )
    let after = database.read("client_submitted_intents", reference.request_id)
    match retained {
      Ok(original) => {
        let same = after.unwrap()
        assert_eq(same.body, original.body)
        assert_eq(same.revision, original.revision)
      }
      Err(@sqlite.NotFound) => assert_true(after is Err(@sqlite.NotFound))
      Err(_) => fail("original physical row observation failed")
    }
    if !reply_lost {
      database.rollback().unwrap()
    }
    database.close_checked().unwrap()
    authority.crypto.close_checked().unwrap()
  }
}
