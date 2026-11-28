///|
// Owner-only decision fixtures use an explicit private observation stub. The
// exported Host API accepts only a scoped, actual Store observation handle.
fn NativeClientRunJournal::cancellation_test_operation(
  self : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  namespace_id : String,
  cancel_id : String,
  expected_revision : Int,
  current : () -> Bool,
  terminal_observed : () -> Bool,
) -> Result[NativeClientCancellationRecord, NativeClientRunJournalIssue] {
  self.cancel_operation(
    request,
    namespace_id,
    cancel_id,
    expected_revision,
    current,
    { binding: None, observe: _ => Ok(terminal_observed()), },
  )
}

///|
// A race fixture commits through the real cancellation transaction before
// returning to its caller. It does not rewrite the Run control state directly.
fn NativeClientRunJournal::accept_fixture_cancellation(
  self : NativeClientRunJournal,
  record : NativeClientRunRecord,
) -> Unit {
  let result = self
    .cancel_operation(
      record.request,
      "namespace-a",
      "fixture-cancellation",
      record.revision.to_int(),
      () => true,
      { binding: record.publication_binding, observe: _ => Ok(false), },
    )
    .unwrap()
  guard result.action == @host.AcceptCancellation else {
    abort("fixture did not admit the original cancellation")
  }
}

///|
fn cancellation_test_run(
  name : String,
) -> (@sqlite.Database, NativeClientRunJournal, @host.ClientRequestIdentity) {
  let database = epoch_test_database(name)
  initialize_native_client_run_journal(database).unwrap()
  let journal = open_native_client_run_journal(database, 8).unwrap()
  let (request, prepared, compiled, definition) = journal_test_run(
    "cancel-request", "cancel-run",
  )
  journal.bind_run(request, prepared, compiled, definition, true).unwrap()
  |> ignore
  journal.reserve_dispatch(request, true).unwrap() |> ignore
  (database, journal, request)
}

///|
fn old_cancellation_run_row(
  database : @sqlite.Database,
  key : String,
  requested : Bool,
) -> @sqlite.NativeJournalValue {
  let original = database.read("client_runs", key).unwrap()
  let wire = @utf8.decode(original.body) catch {
    _ => abort("fixture Run UTF-8")
  }
  guard wire.find(",\"checkpoint\":") is Some(position) else {
    abort("fixture Run lacks its canonical Checkpoint field")
  }
  let legacy = @utf8.encode(
    "{\"cancellation_requested\":" +
    (if requested { "true" } else { "false" }) +
    wire[position:].to_owned(),
  )
  database
  .compare_exchange("client_runs", key, original.revision, legacy)
  .unwrap()
  |> ignore
  database.read("client_runs", key).unwrap()
}

///|
test "Native reopens exact old uncancelled and accepted Run originals without rewriting or replay" {
  for requested in [false, true] {
    let name = if requested {
      "old-client-accepted-cancellation"
    } else {
      "old-client-uncancelled-run"
    }
    let (database, journal, request) = cancellation_test_run(name)
    let original_run = journal.retained(request).unwrap().unwrap()
    let namespace_id = @publication.run_definition_namespace(
      original_run.definition,
    ).unwrap()
    let accepted = if requested {
      Some(
        journal
        .cancellation_test_operation(
          request,
          namespace_id,
          "old-original",
          1,
          () => true,
          () => false,
        )
        .unwrap(),
      )
    } else {
      None
    }
    let key = @host.client_request_scope_cid(request)
    let legacy = old_cancellation_run_row(database, key, requested)
    database.close_checked().unwrap()
    let reopened = epoch_test_database(name)
    let retained = open_native_client_run_journal(reopened, 8).unwrap()
    assert_true(run_journal_custody(reopened, 8) is Ok(_))
    guard retained.lookup(request, true) is Ok(Retained(run)) else {
      fail("legacy original missing")
    }
    assert_eq(run.cancellation_requested(), requested)
    assert_eq(run.revision, legacy.revision)
    if accepted is Some(original) {
      assert_eq(
        run.cancellation_head.unwrap().observed_revision,
        original.observed_revision,
      )
      assert_false(retained.claim_physical_start(request, true).unwrap())
      let repeated = retained
        .cancellation_test_operation(
          request,
          namespace_id,
          "old-original",
          1,
          () => true,
          () => abort("a replay must not observe a new terminal disposition"),
        )
        .unwrap()
      assert_eq(
        @host.client_cancellation_journal_row_body(repeated),
        @host.client_cancellation_journal_row_body(original),
      )
      assert_eq(
        reopened.read("client_cancel_custody", "issued").unwrap().body,
        b"1",
      )
    }
    let unchanged = reopened.read("client_runs", key).unwrap()
    assert_eq(
      (unchanged.revision, unchanged.body),
      (legacy.revision, legacy.body),
    )
    reopened.close_checked().unwrap()
  }
}

///|
test "Native old requested Run refuses a missing or changed original witness" {
  for missing in [true, false] {
    let name = if missing {
      "old-cancellation-missing-witness"
    } else {
      "old-cancellation-changed-witness"
    }
    let (database, journal, request) = cancellation_test_run(name)
    let original_run = journal.retained(request).unwrap().unwrap()
    let namespace_id = @publication.run_definition_namespace(
      original_run.definition,
    ).unwrap()
    journal
    .cancellation_test_operation(
      request,
      namespace_id,
      "old-original",
      1,
      () => true,
      () => false,
    )
    .unwrap()
    |> ignore
    let head = journal.retained(request).unwrap().unwrap().cancellation_head.unwrap()
    let key = @host.client_request_scope_cid(request)
    let legacy = old_cancellation_run_row(database, key, true)
    if missing {
      let table = @utf8.encode("client_cancel_originals")
      let key = @utf8.encode(head.record_key)
      assert_true(
        submitted_test_remove_record(
          database,
          table,
          table.length(),
          key,
          key.length(),
        ),
      )
    } else {
      database
      .compare_exchange(
        "client_cancel_originals",
        head.record_key,
        0L,
        b"foreign",
      )
      .unwrap()
      |> ignore
    }
    assert_true(journal.lookup(request, true) is Err(CustodyLost))
    assert_true(run_journal_custody(database, 8) is Err(CustodyLost))
    let unchanged = database.read("client_runs", key).unwrap()
    assert_eq(
      (unchanged.revision, unchanged.body),
      (legacy.revision, legacy.body),
    )
    database.close_checked().unwrap()
  }
}

///|
test "Native old requested Run refuses an ambiguous accepted history" {
  let (database, journal, request) = cancellation_test_run(
    "old-cancellation-ambiguous",
  )
  let run = journal.retained(request).unwrap().unwrap()
  let namespace_id = @publication.run_definition_namespace(run.definition).unwrap()
  let accepted = journal
    .cancellation_test_operation(
      request,
      namespace_id,
      "old-original",
      1,
      () => true,
      () => false,
    )
    .unwrap()
  let key = @host.client_request_scope_cid(request)
  let legacy = old_cancellation_run_row(database, key, true)
  let authority = @host.client_request_authority_scope_cid(request)
  let identity = @host.prepare_client_cancellation_identity(
    namespace_id,
    authority,
    "other-original",
    run.definition,
    1,
  ).unwrap()
  let duplicate = { ..accepted, cancel_id: "other-original", identity, }
  let duplicate_key = @host.client_cancellation_journal_index(
    namespace_id,
    authority,
    duplicate.cancel_id,
  ).unwrap()
  let duplicate_body = @host.client_cancellation_journal_row_body(duplicate).unwrap()
  database
  .insert("client_cancellations", duplicate_key, duplicate_body)
  .unwrap()
  |> ignore
  database
  .insert(
    "client_cancel_originals",
    duplicate_key,
    @utf8.encode(@sha.hex(duplicate_body)),
  )
  .unwrap()
  |> ignore
  database
  .compare_exchange("client_cancel_custody", "issued", 1L, b"2")
  .unwrap()
  |> ignore
  assert_true(journal.lookup(request, true) is Err(CustodyLost))
  let unchanged = database.read("client_runs", key).unwrap()
  assert_eq(
    (unchanged.revision, unchanged.body),
    (legacy.revision, legacy.body),
  )
  database.close_checked().unwrap()
}

///|
test "Native old requested Run does not borrow another Run's accepted history" {
  let (database, journal, request) = cancellation_test_run(
    "old-cancellation-foreign",
  )
  let (foreign, prepared, compiled, definition) = journal_test_run(
    "foreign-cancel-request", "foreign-cancel-run",
  )
  let namespace_id = @publication.run_definition_namespace(definition).unwrap()
  journal.bind_run(foreign, prepared, compiled, definition, true).unwrap()
  |> ignore
  journal.reserve_dispatch(foreign, true).unwrap() |> ignore
  journal
  .cancellation_test_operation(
    foreign,
    namespace_id,
    "other-original",
    1,
    () => true,
    () => false,
  )
  .unwrap()
  |> ignore
  let key = @host.client_request_scope_cid(request)
  let legacy = old_cancellation_run_row(database, key, true)
  assert_true(journal.lookup(request, true) is Err(CustodyLost))
  let unchanged = database.read("client_runs", key).unwrap()
  assert_eq(
    (unchanged.revision, unchanged.body),
    (legacy.revision, legacy.body),
  )
  database.close_checked().unwrap()
}

///|
test "Native cancellation keeps immutable original operation across replay and reopen" {
  let name = "client-cancel-original"
  let (database, journal, request) = cancellation_test_run(name)
  assert_true(
    journal.lookup_cancellation(request, "namespace-a", "cancel-a", 1, () => {
      true
    })
    is Ok(UnresolvedCancellationHistory),
  )
  assert_true(
    journal.cancellation_test_operation(
      request,
      "namespace-a",
      "cancel-a",
      1,
      () => false,
      () => false,
    )
    is Err(AuthorizationDenied),
  )
  let accepted = journal
    .cancellation_test_operation(
      request,
      "namespace-a",
      "cancel-a",
      1,
      () => true,
      () => false,
    )
    .unwrap()
  assert_eq(accepted.action, @host.AcceptCancellation)
  assert_eq(accepted.observed_revision, 2L)
  guard journal.lookup(request, true) is Ok(Retained(run)) else {
    fail("Run missing")
  }
  assert_true(run.cancellation_requested())
  assert_false(run.physical_start_claimed)
  assert_true(run.checkpoint is None)
  assert_false(journal.claim_physical_start(request, true).unwrap())
  journal.transaction(() => journal.save(run)).unwrap() |> ignore
  let terminal_reads = Ref(0)
  let replay = journal
    .cancellation_test_operation(
      request,
      "namespace-a",
      "cancel-a",
      1,
      () => true,
      () => {
        terminal_reads.val += 1
        true
      },
    )
    .unwrap()
  assert_eq(terminal_reads.val, 0)
  assert_eq(replay.action, @host.AcceptCancellation)
  assert_eq(replay.observed_revision, 2L)
  guard journal.lookup(request, true) is Ok(Retained(after)) else {
    fail("Run missing")
  }
  assert_eq(after.revision, 3L)
  database.close_checked().unwrap()
  let reopened = epoch_test_database(name)
  let journal = open_native_client_run_journal(reopened, 8).unwrap()
  guard journal.lookup_cancellation(request, "namespace-a", "cancel-a", 1, () => {
      true
    })
    is Ok(OriginalCancellation(original)) else {
    fail("original cancellation missing")
  }
  assert_eq(original.action, @host.AcceptCancellation)
  assert_eq(original.observed_revision, 2L)
  assert_true(
    journal.lookup_cancellation(request, "namespace-a", "never-sent", 3, () => {
      true
    })
    is Ok(UnresolvedCancellationHistory),
  )
  assert_true(
    journal.lookup_cancellation(request, "namespace-a", "cancel-a", 1, () => {
      false
    })
    is Err(AuthorizationDenied),
  )
  assert_true(
    journal.lookup_cancellation(request, "namespace-a", "cancel-a", 2, () => {
      true
    })
    is Err(CancellationOperation(@host.ChangedIntent)),
  )
  reopened.close_checked().unwrap()
}

///|
test "Native cancellation key cannot change Run revision or opaque Unicode intent" {
  let (database, journal, request) = cancellation_test_run(
    "client-cancel-intent",
  )
  journal
  .cancellation_test_operation(
    request,
    "namespace-a",
    "e\u{0301}",
    1,
    () => true,
    () => false,
  )
  .unwrap()
  |> ignore
  let composed = journal
    .cancellation_test_operation(request, "namespace-a", "é", 2, () => true, () => {
      false
    })
    .unwrap()
  assert_eq(composed.action, @host.AlreadyRequested)
  assert_eq(composed.observed_revision, 2L)
  assert_true(
    journal.cancellation_test_operation(
      request,
      "namespace-a",
      "e\u{0301}",
      2,
      () => true,
      () => false,
    )
    is Err(CancellationOperation(@host.ChangedIntent)),
  )
  let (other, prepared, compiled, definition) = journal_test_run(
    "cancel-other", "cancel-other-run",
  )
  journal.bind_run(other, prepared, compiled, definition, true).unwrap()
  |> ignore
  assert_true(
    journal.cancellation_test_operation(
      other,
      "namespace-a",
      "e\u{0301}",
      0,
      () => true,
      () => false,
    )
    is Err(CancellationOperation(@host.ChangedIntent)),
  )
  assert_true(
    journal.lookup_cancellation(other, "namespace-a", "e\u{0301}", 0, () => true)
    is Err(CancellationOperation(@host.ChangedIntent)),
  )
  for id in ["", "cancel\r", "cancel\n", "cancel\r\n"] {
    assert_true(
      journal.cancellation_test_operation(
        request,
        "namespace-a",
        id,
        2,
        () => true,
        () => false,
      )
      is Err(CancellationIdentity(@host.InvalidOperationId)),
    )
  }
  database.close_checked().unwrap()
}

///|
test "Native cancellation observes revision race and late authority without an operation commit" {
  let (database, journal, request) = cancellation_test_run("client-cancel-race")
  let accepted = Ref(false)
  assert_true(
    journal.cancellation_test_operation(
      request,
      "namespace-a",
      "stale",
      1,
      () => {
        if !accepted.val {
          let other = journal
            .cancellation_test_operation(
              request,
              "namespace-a",
              "winner",
              1,
              () => true,
              () => false,
            )
            .unwrap()
          accepted.val = other.action == @host.AcceptCancellation
        }
        true
      },
      () => false,
    )
    is Err(CancellationOperation(@host.RevisionConflict)),
  )
  assert_true(accepted.val)
  assert_true(
    journal.lookup_cancellation(request, "namespace-a", "stale", 1, () => true)
    is Ok(UnresolvedCancellationHistory),
  )
  let checks = Ref(0)
  assert_true(
    journal.cancellation_test_operation(
      request,
      "namespace-a",
      "late",
      2,
      () => {
        checks.val += 1
        checks.val < 3
      },
      () => false,
    )
    is Err(AuthorizationDenied),
  )
  assert_eq(checks.val, 3)
  assert_true(
    journal.lookup_cancellation(request, "namespace-a", "late", 2, () => true)
    is Ok(UnresolvedCancellationHistory),
  )
  database.close_checked().unwrap()
}

///|
test "Native cancellation commit loss is looked up without deriving a retry from absence" {
  for reply_lost in [false, true] {
    let name = "client-cancel-commit-" + reply_lost.to_string()
    let (database, journal, request) = cancellation_test_run(name)
    if reply_lost {
      client_test_fail_commit_reply(database, 1)
    } else {
      client_test_fail_commit(database, 1)
    }
    assert_true(
      journal.cancellation_test_operation(
        request,
        "namespace-a",
        "original",
        1,
        () => true,
        () => false,
      )
      is Err(JournalStepFailed(step, None)) &&
      journal_test_original_commit_failure(step, reply_lost),
    )
    assert_true(
      journal.lookup_cancellation(request, "namespace-a", "original", 1, () => {
        true
      })
      is Err(Fenced),
    )
    if !reply_lost {
      database.rollback().unwrap()
    }
    database.close_checked().unwrap()
    let reopened = epoch_test_database(name)
    let journal = open_native_client_run_journal(reopened, 8).unwrap()
    let lookup = journal
      .lookup_cancellation(request, "namespace-a", "original", 1, () => true)
      .unwrap()
    assert_eq(lookup is OriginalCancellation(_), reply_lost)
    guard journal.lookup(request, true) is Ok(Retained(run)) else {
      fail("Run missing")
    }
    assert_eq(run.cancellation_requested(), reply_lost)
    assert_eq(run.revision, if reply_lost { 2L } else { 1L })
    let key = cancellation_index(
      "namespace-a",
      @host.client_request_authority_scope_cid(request),
      "original",
    ).unwrap()
    if reply_lost {
      guard run.cancellation_head is Some(head) &&
        lookup is OriginalCancellation(original) else {
        fail("accepted cancellation head missing")
      }
      assert_eq(head.record_key, key)
      assert_eq(head.observed_revision, 2L)
      let receipt = reopened.read("client_cancellations", key).unwrap()
      let witness = reopened.read("client_cancel_originals", key).unwrap()
      let issued = reopened.read("client_cancel_custody", "issued").unwrap()
      assert_eq(receipt.revision, 0L)
      assert_eq(
        receipt.body,
        @host.client_cancellation_journal_row_body(original).unwrap(),
      )
      assert_eq(witness.revision, 0L)
      assert_eq(witness.body, @utf8.encode(@sha.hex(receipt.body)))
      assert_eq(issued.revision, 1L)
      assert_eq(issued.body, b"1")
    } else {
      assert_true(
        reopened.read("client_cancellations", key) is Err(@sqlite.NotFound),
      )
      assert_true(
        reopened.read("client_cancel_originals", key) is Err(@sqlite.NotFound),
      )
      let issued = reopened.read("client_cancel_custody", "issued").unwrap()
      assert_eq(issued.revision, 0L)
      assert_eq(issued.body, b"0")
    }
    reopened.close_checked().unwrap()
  }
}

///|
test "Native original cancellation refuses missing altered or lost witness custody" {
  for
    loss in [
      "row", "body", "witness", "original", "original_body", "orphan_original",
    ] {
    let name = "client-cancel-loss-" + loss
    let (database, journal, request) = cancellation_test_run(name)
    journal
    .cancellation_test_operation(
      request,
      "namespace-a",
      "original",
      1,
      () => true,
      () => false,
    )
    .unwrap()
    |> ignore
    let table = if loss == "original" ||
      loss == "original_body" ||
      loss == "orphan_original" {
      "client_cancel_originals"
    } else if loss == "witness" {
      "client_cancel_custody"
    } else {
      "client_cancellations"
    }
    let key = if loss == "witness" {
      "issued"
    } else {
      cancellation_index(
        "namespace-a",
        @host.client_request_authority_scope_cid(request),
        "original",
      ).unwrap()
    }
    if loss == "orphan_original" {
      database.insert(table, "orphan", b"unissued").unwrap() |> ignore
    } else if loss == "original_body" {
      database.compare_exchange(table, key, 0L, b"changed-original").unwrap()
      |> ignore
    } else if loss == "body" {
      database.compare_exchange(table, key, 0L, b"{}").unwrap() |> ignore
    } else {
      let ns = @utf8.encode(table)
      let key = @utf8.encode(key)
      assert_true(
        submitted_test_remove_record(
          database,
          ns,
          ns.length(),
          key,
          key.length(),
        ),
      )
    }
    assert_true(
      journal.lookup_cancellation(request, "namespace-a", "original", 1, () => {
        true
      })
      is Err(CustodyLost),
    )
    let selected_key = if loss == "orphan_original" { "orphan" } else { key }
    let corrupt = database.read(table, selected_key)
    database.close_checked().unwrap()
    let reopened = epoch_test_database(name)
    let reopened_journal = open_native_client_run_journal(reopened, 8).unwrap()
    assert_true(run_journal_custody(reopened, 8) is Err(CustodyLost))
    assert_true(
      reopened_journal.transaction(() => {
        initialize_native_client_run_journal_rows(reopened)
      })
      is Err(CustodyLost),
    )
    match (corrupt, reopened.read(table, selected_key)) {
      (Ok(before), Ok(after)) => {
        assert_eq(after.body, before.body)
        assert_eq(after.revision, before.revision)
      }
      (Err(@sqlite.NotFound), Err(@sqlite.NotFound)) => ()
      _ =>
        fail("integrity inspection changed the original cancellation custody")
    }

    reopened.close_checked().unwrap()
  }
}

///|
test "Native cancellation head cannot be removed by an ordinary Run CAS" {
  let (database, journal, request) = cancellation_test_run(
    "client-cancel-head-cas",
  )
  journal.accept_fixture_cancellation(
    journal.retained(request).unwrap().unwrap(),
  )
  let key = @host.client_request_scope_cid(request)
  let current = journal.retained(request).unwrap().unwrap()
  let before = database.read("client_runs", key).unwrap()
  assert_true(current.cancellation_head is Some(_))
  assert_true(
    journal.transaction(() => {
      journal.save({ ..current, cancellation_head: None, })
    })
    is Err(CustodyLost),
  )
  let after = database.read("client_runs", key).unwrap()
  assert_eq(after.revision, before.revision)
  assert_eq(after.body, before.body)
  database.close_checked().unwrap()
}

///|
test "Native cancellation audit detects an accepted head after receipt and witness loss" {
  let (database, journal, request) = cancellation_test_run(
    "client-cancel-orphan-head",
  )
  journal.accept_fixture_cancellation(
    journal.retained(request).unwrap().unwrap(),
  )
  let original = journal.retained(request).unwrap().unwrap()
  guard original.cancellation_head is Some(head) else {
    fail("original accepted cancellation head missing")
  }
  let run_key = @host.client_request_scope_cid(request)
  let before = database.read("client_runs", run_key).unwrap()
  for
    (table, key) in [
      ("client_cancellations", head.record_key),
      ("client_cancel_originals", head.record_key),
      ("client_cancel_custody", "issued"),
    ] {
    let table = @utf8.encode(table)
    let key = @utf8.encode(key)
    assert_true(
      submitted_test_remove_record(
        database,
        table,
        table.length(),
        key,
        key.length(),
      ),
    )
  }
  database.insert("client_cancel_custody", "issued", b"0").unwrap() |> ignore
  assert_true(run_journal_custody(database, 8) is Err(CustodyLost))
  let after = database.read("client_runs", run_key).unwrap()
  assert_eq(after.revision, before.revision)
  assert_eq(after.body, before.body)
  database.close_checked().unwrap()
}

///|
test "Native already-terminal cancellation records exact result without a stop or revision change" {
  let (database, journal, request) = cancellation_test_run(
    "client-cancel-terminal",
  )
  let outcome = journal
    .cancellation_test_operation(
      request,
      "namespace-a",
      "terminal",
      1,
      () => true,
      () => true,
    )
    .unwrap()
  assert_eq(outcome.action, @host.AlreadyTerminal)
  assert_eq(outcome.observed_revision, 1L)
  guard journal.lookup(request, true) is Ok(Retained(run)) else {
    fail("Run missing")
  }
  assert_false(run.cancellation_requested())
  assert_false(run.physical_start_claimed)
  assert_eq(run.revision, 1L)
  database.close_checked().unwrap()
}

///|
test "Native cancellation finite issuance refuses another operation without consuming its identity" {
  let (database, _, request) = cancellation_test_run("client-cancel-capacity")
  let journal = open_native_client_run_journal(database, 1).unwrap()
  journal
  .cancellation_test_operation(request, "namespace-a", "one", 1, () => true, () => {
    false
  })
  .unwrap()
  |> ignore
  assert_true(
    journal.cancellation_test_operation(
      request,
      "namespace-a",
      "two",
      2,
      () => true,
      () => false,
    )
    is Err(CapacityExceeded),
  )
  assert_true(
    journal.lookup_cancellation(request, "namespace-a", "two", 2, () => true)
    is Ok(UnresolvedCancellationHistory),
  )
  assert_eq(
    journal
    .cancellation_test_operation(request, "namespace-a", "one", 1, () => true, () => {
      false
    })
    .unwrap().observed_revision,
    2L,
  )
  database.close_checked().unwrap()
}

///|
test "Native publication fence permits only original readback and blocks nested cancellation" {
  let (database, journal, request) = cancellation_test_run(
    "client-publication-fence",
  )
  assert_true(journal.claim_physical_start(request, true).unwrap())
  journal
  .bind_publication(request, "private-fence-fixture", () => true)
  .unwrap()
  guard journal.lookup(request, true) is Ok(Retained(before)) else {
    fail("Run missing")
  }
  let reads = Ref(0)
  let original_read = Ref(false)
  let nested_refused = Ref(false)
  assert_true(
    journal.fence_publication(
      request,
      before.definition,
      "private-fence-fixture",
      () => true,
      () => {
        original_read.val = match journal.lookup(request, true) {
          Ok(Retained(inside)) => inside.revision == before.revision
          _ => false
        }
        reads.val += 1
        nested_refused.val = journal.cancellation_test_operation(
            request,
            "namespace-a",
            "nested",
            before.revision.to_int(),
            () => true,
            () => false,
          )
          is Err(Physical(@sqlite.Busy))
        Err(@native_publication.AccessDenied)
      },
    )
    is Err(@native_publication.AccessDenied),
  )
  assert_eq(reads.val, 1)
  assert_true(original_read.val)
  assert_true(nested_refused.val)
  assert_true(
    journal.lookup_cancellation(
      request,
      "namespace-a",
      "nested",
      before.revision.to_int(),
      () => true,
    )
    is Ok(UnresolvedCancellationHistory),
  )
  guard journal.lookup(request, true) is Ok(Retained(after)) else {
    fail("Run missing")
  }
  assert_eq(after.revision, before.revision)
  assert_false(after.cancellation_requested())
  database.close_checked().unwrap()
}

///|
test "Native original cancellation refuses a structurally valid immutable outcome substitution" {
  let (database, journal, request) = cancellation_test_run(
    "client-cancel-valid-substitution",
  )
  let original = journal
    .cancellation_test_operation(
      request,
      "namespace-a",
      "original",
      1,
      () => true,
      () => false,
    )
    .unwrap()
  assert_eq(original.action, @host.AcceptCancellation)
  let key = cancellation_index(
    "namespace-a",
    @host.client_request_authority_scope_cid(request),
    "original",
  ).unwrap()
  let ns = @utf8.encode("client_cancellations")
  let bytes = @utf8.encode(key)
  assert_true(
    submitted_test_remove_record(
      database,
      ns,
      ns.length(),
      bytes,
      bytes.length(),
    ),
  )
  // Keep exact key, intent and immutable physical revision zero. Only the
  // original operation outcome is substituted, so syntax/revision checks alone
  // cannot establish original-result custody.
  let changed = {
    ..original,
    action: @host.AlreadyRequested,
    observed_revision: 1L,
  }
  database
  .insert(
    "client_cancellations",
    key,
    @host.client_cancellation_journal_row_body(changed).unwrap(),
  )
  .unwrap()
  |> ignore
  assert_true(
    journal.lookup_cancellation(request, "namespace-a", "original", 1, () => {
      true
    })
    is Err(CustodyLost),
  )
  database.close_checked().unwrap()
}

///|
// Actual SQLite with explicit private routing ports. This is not an installed
// Read/Store positive or a physical cancellation acknowledgement.
test "Native cancellation routes the same original through its actual Journal operations" {
  let (database, journal, request) = cancellation_test_run(
    "client-cancel-original-operations",
  )
  let calls : Array[String] = []
  let operations = journal_test_operation_access(database, calls)
  let recorded = journal
    .cancel_operation_with_operations(
      request,
      "namespace-a",
      "cancel-original",
      1,
      () => true,
      { binding: None, observe: _ => Ok(false), },
      operations=Some(operations),
    )
    .unwrap()
  assert_eq(recorded.action, @host.AcceptCancellation)
  assert_eq(recorded.observed_revision, 2L)
  assert_true(calls.contains("begin"))
  assert_true(calls.contains("commit"))
  assert_true(
    calls.contains(
      "compare_exchange:client_runs:" + @host.client_request_scope_cid(request),
    ),
  )
  assert_true(calls.contains("compare_exchange:client_cancel_custody:issued"))
  assert_eq(
    calls
    .filter(value => value.has_prefix("insert:client_cancellations:"))
    .length(),
    1,
  )
  calls.clear()
  let observed = journal
    .lookup_cancellation_with_reads(
      request,
      "namespace-a",
      "cancel-original",
      1,
      () => true,
      reads=Some(operations.reads),
    )
    .unwrap()
  guard observed is OriginalCancellation(original) else {
    fail("original cancellation missing")
  }
  assert_eq(original.action, recorded.action)
  assert_eq(original.observed_revision, recorded.observed_revision)
  assert_true(calls.contains("begin"))
  assert_true(calls.contains("commit"))
  assert_false(
    calls.any(value => {
      value.has_prefix("insert:") || value.has_prefix("compare_exchange:")
    }),
  )
  let foreign = epoch_test_database("client-cancel-original-operations-foreign")
  let foreign_calls : Array[String] = []
  let foreign_operations = journal_test_operation_access(foreign, foreign_calls)
  assert_true(
    journal.cancel_operation_with_operations(
      request,
      "namespace-a",
      "cancel-foreign",
      2,
      () => true,
      { binding: None, observe: _ => Ok(false), },
      operations=Some(foreign_operations),
    )
    is Err(Physical(@sqlite.Collision)),
  )
  assert_eq(foreign_calls.length(), 0)
  assert_true(
    journal.lookup_cancellation_with_reads(
      request,
      "namespace-a",
      "cancel-original",
      1,
      () => true,
      reads=Some(foreign_operations.reads),
    )
    is Err(Physical(@sqlite.Collision)),
  )
  assert_eq(foreign_calls.length(), 0)
  foreign.close_checked().unwrap()
  database.close_checked().unwrap()
}
