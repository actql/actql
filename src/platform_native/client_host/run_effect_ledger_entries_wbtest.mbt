///|
test "Native companion stores the first Effect history beyond the legacy Run row bound" {
  let database = epoch_test_database("client-row-companion-legacy-bound")
  let (journal, request, _) = resume_test_approved(database)
  let claim = effect_row_test_claim(journal, request)
  let scope = @host.client_request_scope_cid(request)
  let before = database.read("client_runs", scope).unwrap()
  assert_true(
    @host.decode_client_run_journal_row_with_observation_originals(before.body)
    is Ok(_),
  )
  guard journal.lookup(request, true) is Ok(Retained(original)) else {
    fail("Run missing")
  }
  assert_false(original.checkpoint_companion)
  assert_eq(database.read("client_runs", scope).unwrap().body, before.body)
  let expected : Array[String] = []
  let mut crossed = false
  for index in 0..<64 {
    let (locator, key, basis) = effect_row_test_binding(
      request,
      row="row-" + index.to_string(),
    )
    guard journal.record_effect_row_dispatch(
        claim,
        locator,
        key,
        basis,
        () => true,
        () => 1001L,
      )
      is Ok(DispatchRecorded(dispatch)) else {
      fail("original dispatch missing")
    }
    let limits = native_client_effect_ledger_limits()
    let prepared = @effect.issue_prepared_effect_ledger_entry(
      basis,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    ).unwrap()
    expected.push(@effect.effect_ledger_entry_wire(prepared))
    expected.push(@effect.effect_ledger_entry_wire(dispatch.dispatching))
    guard journal.lookup(request, true) is Ok(Retained(saved)) else {
      fail("committed Run missing")
    }
    assert_true(saved.checkpoint_companion)
    assert_eq(saved.checkpoint.unwrap().effect_ledger.length(), 2 * (index + 1))
    // Compare with the real unchanged inline writer, without changing the
    // database or attempting any external send.
    let legacy = run_record_body({ ..saved, checkpoint_companion: false, })
    match legacy {
      Ok(bytes) => assert_true(bytes.length() <= 131072)
      Err(CapacityExceeded) => {
        assert_true(index > 0)
        crossed = true
        break
      }
      Err(_) => fail("unexpected inline encoding failure")
    }
  }
  assert_true(crossed)
  database.close_checked().unwrap()
  let reopened = epoch_test_database("client-row-companion-legacy-bound")
  let journal = open_native_client_run_journal(reopened, 8).unwrap()
  guard journal.lookup(request, true) is Ok(Retained(restored)) else {
    fail("companion Run missing after reopen")
  }
  let checkpoint = restored.checkpoint.unwrap()
  assert_eq(
    checkpoint.artifact.checkpoint_cid,
    original.checkpoint.unwrap().artifact.checkpoint_cid,
  )
  assert_eq(
    checkpoint.resolution_cid,
    original.checkpoint.unwrap().resolution_cid,
  )
  assert_eq(
    checkpoint.effect_ledger.map(entry => {
      @effect.effect_ledger_entry_wire(entry)
    }),
    expected,
  )
  assert_true(
    @host.decode_client_run_journal_row_with_observation_originals(
      reopened.read("client_runs", scope).unwrap().body,
    )
    is Err(_),
  )
  reopened.close_checked().unwrap()
}

///|
test "Native companion refuses missing changed and underfunded entry custody" {
  let database = epoch_test_database("client-row-companion-custody")
  let (journal, request, _) = resume_test_approved(database)
  let claim = effect_row_test_claim(journal, request)
  let (locator, key, basis) = effect_row_test_binding(request)
  guard journal.record_effect_row_dispatch(
      claim,
      locator,
      key,
      basis,
      () => true,
      () => 1001L,
    )
    is Ok(DispatchRecorded(dispatch)) else {
    fail("original dispatch missing")
  }
  let entry = @effect.effect_ledger_entry_cid(dispatch.dispatching)
  let scope = @host.client_request_scope_cid(request)
  let checkpoint = dispatch.checkpoint_cid
  let key = native_effect_ledger_entry_key(scope, checkpoint, entry)
  let physical = database.read(effect_ledger_entry_table, key).unwrap()
  let geometry = native_effect_ledger_entry_admission_quote(
    physical.body.length(),
    native_client_effect_ledger_limits(),
  ).unwrap()
  for short in [true, false] {
    let requests : Array[(Int64, Int64, Int64)] = []
    let before = if short { geometry.1 - 1L } else { geometry.1 }
    let reads = {
      ..journal_test_read_access(database, []),
      before_metadata_construction: Some((retained, execution, raw) => {
        requests.push((retained, execution, raw))
        if execution > before {
          Err(CapacityExceeded)
        } else {
          Ok(())
        }
      }),
    }
    let read = read_native_client_effect_ledger_entry(
      database,
      scope,
      checkpoint,
      entry,
      Some(reads),
    )
    assert_eq(requests.length(), 2)
    assert_eq(requests[1], geometry)
    if short {
      assert_true(read is Err(CapacityExceeded))
    } else {
      assert_eq(
        @effect.effect_ledger_entry_wire(read.unwrap()),
        @effect.effect_ledger_entry_wire(dispatch.dispatching),
      )
    }
    assert_eq(
      database.read(effect_ledger_entry_table, key).unwrap().body,
      physical.body,
    )
  }
  let changed_revision = database
    .compare_exchange(
      effect_ledger_entry_table,
      key,
      physical.revision,
      physical.body,
    )
    .unwrap()
  assert_true(journal.lookup(request, true) is Err(CustodyLost))
  database.begin_immediate().unwrap()
  database
  .remove_exact(effect_ledger_entry_table, key, changed_revision, physical.body)
  .unwrap()
  database.commit().unwrap()
  assert_true(journal.lookup(request, true) is Err(CustodyLost))
  database.close_checked().unwrap()
}

///|
test "Native companion upgrades an inline Effect history only on its next authorized update" {
  let database = epoch_test_database("client-row-companion-inline")
  let (journal, request, _) = resume_test_approved(database)
  let claim = effect_row_test_claim(journal, request)
  let (locator, key, basis) = effect_row_test_binding(request)
  guard journal.record_effect_row_dispatch(
      claim,
      locator,
      key,
      basis,
      () => true,
      () => 1001L,
    )
    is Ok(DispatchRecorded(_)) else {
    fail("original dispatch missing")
  }
  guard journal.lookup(request, true) is Ok(Retained(first)) else {
    fail("Run missing")
  }
  let scope = @host.client_request_scope_cid(request)
  let checkpoint = first.checkpoint.unwrap()
  let legacy = run_record_body({ ..first, checkpoint_companion: false, }).unwrap()
  // Set up an exact old physical row bearing the original admitted entries.
  // Its Run body is written by the still-supported inline codec.
  database.begin_immediate().unwrap()
  database
  .compare_exchange("client_runs", scope, first.revision, legacy)
  .unwrap()
  |> ignore
  for entry in checkpoint.effect_ledger {
    let key = native_effect_ledger_entry_key(
      scope,
      checkpoint.artifact.checkpoint_cid,
      @effect.effect_ledger_entry_cid(entry),
    )
    let stored = database.read(effect_ledger_entry_table, key).unwrap()
    database
    .remove_exact(effect_ledger_entry_table, key, stored.revision, stored.body)
    .unwrap()
  }
  database.commit().unwrap()
  let original = database.read("client_runs", scope).unwrap()
  assert_true(
    @host.decode_client_run_journal_row_with_observation_originals(
      original.body,
    )
    is Ok(_),
  )
  guard journal.lookup(request, true) is Ok(Retained(inline)) else {
    fail("inline Run missing")
  }
  assert_false(inline.checkpoint_companion)
  assert_eq(inline.checkpoint.unwrap().effect_ledger.length(), 2)
  assert_eq(database.read("client_runs", scope).unwrap().body, original.body)
  assert_eq(
    database.read("client_runs", scope).unwrap().revision,
    original.revision,
  )
  assert_true(
    database.scan_after(effect_ledger_entry_table, "") is Err(@sqlite.NotFound),
  )
  let (locator, key, basis) = effect_row_test_binding(request, row="row-2")
  assert_true(
    journal.record_effect_row_dispatch(claim, locator, key, basis, () => true, () => {
      1002L
    })
    is Ok(DispatchRecorded(_)),
  )
  guard journal.lookup(request, true) is Ok(Retained(upgraded)) else {
    fail("upgraded Run missing")
  }
  assert_true(upgraded.checkpoint_companion)
  for index in 0..<checkpoint.effect_ledger.length() {
    assert_eq(
      @effect.effect_ledger_entry_wire(
        upgraded.checkpoint.unwrap().effect_ledger[index],
      ),
      @effect.effect_ledger_entry_wire(checkpoint.effect_ledger[index]),
    )
  }
  assert_eq(upgraded.checkpoint.unwrap().effect_ledger.length(), 4)
  database.close_checked().unwrap()
}

///|
test "Native companion funds each SQLite write before retaining the original entry" {
  let database = epoch_test_database("client-row-companion-copy")
  let (journal, request, _) = resume_test_approved(database)
  let claim = effect_row_test_claim(journal, request)
  let (locator, key, basis) = effect_row_test_binding(request)
  let limits = native_client_effect_ledger_limits()
  let prepared = @effect.issue_prepared_effect_ledger_entry(
    basis,
    limits.max_wire_bytes,
    limits.max_nodes,
    limits.max_depth,
  ).unwrap()
  let dispatching = @effect.issue_next_effect_ledger_entry(
    prepared,
    "dispatching",
    None,
    limits.max_wire_bytes,
    limits.max_nodes,
    limits.max_depth,
  ).unwrap()
  let expected = [prepared, dispatching].map(entry => {
    let bytes = @utf8.encode(@effect.effect_ledger_entry_wire(entry))
      .length()
      .to_int64()
    let key_units = 71L + 1L + 71L + 1L + 71L
    let coheld_text = 2L * key_units * 2L
    let coheld_input = 3L * (16L + bytes)
    (coheld_input + coheld_text + 256L, Int64::max(16L + bytes, 448L))
  })
  let scope = @host.client_request_scope_cid(request)
  let before = database.read("client_runs", scope).unwrap()
  let custody = database.read("client_effect_custody", scope).unwrap()
  for short in [true, false] {
    let original = journal_test_operation_access(database, [])
    let observed : Array[(Int64, Int64)] = []
    let operations = {
      ..original,
      reads: {
        ..original.reads,
        before_metadata_construction: Some((retained, execution, raw) => {
          if retained > 0L {
            return Ok(())
          }
          let index = observed.length()
          observed.push((execution, raw))
          if index >= expected.length() ||
            execution > expected[index].0 - (if short { 1L } else { 0L }) {
            Err(CapacityExceeded)
          } else {
            Ok(())
          }
        }),
      },
    }
    let outcome = journal.record_effect_row_dispatch_with_operations(
      claim,
      locator,
      key,
      basis,
      () => true,
      () => 1001L,
      Some(operations),
    )
    if short {
      assert_true(outcome is Err(CapacityExceeded))
      assert_eq(observed, [expected[0]])
      assert_true(
        database.scan_after(effect_ledger_entry_table, "")
        is Err(@sqlite.NotFound),
      )
      assert_eq(database.read("client_runs", scope).unwrap().body, before.body)
      assert_eq(
        database.read("client_effect_custody", scope).unwrap().body,
        custody.body,
      )
    } else {
      assert_true(outcome is Ok(DispatchRecorded(_)))
      assert_eq(observed, expected)
    }
  }
  database.close_checked().unwrap()
}

///|
test "Native companion audits authenticated entries with headers only" {
  let database = epoch_test_database("client-row-companion-header-audit")
  let (journal, request, _) = resume_test_approved(database)
  let claim = effect_row_test_claim(journal, request)
  let (locator, key, basis) = effect_row_test_binding(request)
  guard journal.record_effect_row_dispatch(
      claim,
      locator,
      key,
      basis,
      () => true,
      () => 1001L,
    )
    is Ok(DispatchRecorded(dispatch)) else {
    fail("original dispatch missing")
  }
  let calls : Array[String] = []
  let ordinary = journal_test_read_access(database, calls)
  let reads = {
    ..ordinary,
    scan: (table, cursor) => {
      if table == effect_ledger_entry_table {
        return Err(@sqlite.Busy)
      }
      (ordinary.scan)(table, cursor)
    },
  }
  database.begin_deferred().unwrap()
  assert_eq(run_journal_custody(database, 8, reads=Some(reads)).unwrap().0, 1)
  database.commit().unwrap()
  assert_eq(
    calls
    .filter(call => call.has_prefix("read:" + effect_ledger_entry_table + ":"))
    .length(),
    2,
  )
  assert_eq(
    calls
    .filter(call => {
      call.has_prefix("scan-extent:" + effect_ledger_entry_table + ":")
    })
    .length(),
    3,
  )

  database
  .insert(effect_ledger_entry_table, "foreign-entry", b"unrelated")
  .unwrap()
  |> ignore
  database.begin_deferred().unwrap()
  assert_true(
    run_journal_custody(database, 8, reads=Some(reads)) is Err(CustodyLost),
  )
  database.commit().unwrap()

  let key = native_effect_ledger_entry_key(
    @host.client_request_scope_cid(request),
    dispatch.checkpoint_cid,
    @effect.effect_ledger_entry_cid(dispatch.dispatching),
  )
  let original = database.read(effect_ledger_entry_table, key).unwrap()
  database.begin_immediate().unwrap()
  database
  .remove_exact(
    effect_ledger_entry_table,
    key,
    original.revision,
    original.body,
  )
  .unwrap()
  database.commit().unwrap()
  database.begin_deferred().unwrap()
  assert_true(
    run_journal_custody(database, 8, reads=Some(reads)) is Err(CustodyLost),
  )
  database.commit().unwrap()
  database.close_checked().unwrap()
}
