///|
// Actual legacy Host/Account/read originals expose the cache's Native backing
// lifetime. This does not supply an installed pair or acknowledge its Library.
test "operation retirement releases native binding cache references" {
  let (host, binding, _, facts) = read_snapshot_selected_original(
    "operation-cache-retirement",
  )
  let capture = prepare_native_local_journal_capture(
    host.session,
    local_journal_test_library(),
    epoch_test_crypto(),
    100.0,
    8,
    8388608L,
  )
  capture.opening = JournalAcquired(host)
  let material = @host.bind_client_local_adopted_host_material(host.database, () => {
    host.current_adoption_material_with_reads(() => host.check_binding())
  }).unwrap()
  let tuple : @authorization.AccessTuple = {
    principal: "local-cli",
    connection: "local",
    resource: "run",
    operation: "read",
  }
  let outcome = @host.client_local_adopted_account_outcome(
    material,
    host.database,
    tuple,
  ).unwrap()
  assert_true(outcome is Allow(_))
  capture.read_material = Some(material)
  capture.read_scopes.push(
    ("local-cli", "local", facts.request.authority_scope_cid),
  )
  capture.read_decisions.push((tuple, outcome))
  // This is the same back-reference retained by a selected operation.
  {
    let selected = { ..binding, capture: Some(capture), }
    capture.read_bindings.push((selected, 0L))
  }
  assert_true(capture.read_scopes.capacity() > 0)
  assert_true(capture.read_decisions.capacity() > 0)
  assert_true(capture.read_bindings.capacity() > 0)
  capture.clear_read_operation_facts()
  assert_true(capture.read_material is None)
  assert_eq(capture.read_scopes.capacity(), 0)
  assert_eq(capture.read_decisions.capacity(), 0)
  assert_eq(capture.read_bindings.capacity(), 0)
  // Cache retirement is not physical cleanup. The actual original remains
  // live until its separate close, even though no cache retains a binding.
  assert_false(capture.cleanup_acknowledged)
  assert_false(host.closed)
  assert_eq(capture.close().issue_family(), 0)
}

///|
// Actual legacy SystemSQLite/explicit Crypto Journal operations. The private
// operation flag selects only typed-fact retention; it issues no permission,
// installed supplier, native Read claim or resource acknowledgement.
test "one selected Run revision and Policy original survive trusted read-only transactions" {
  let host = policy_host_fixture("public-operation-fact-reuse")
  let crypto = epoch_test_crypto()
  let scope = host.authority_scope_cid("operator", "cli", crypto).unwrap()
  let (request, prepared, unselected_compiled, definition) = journal_test_run(
    "one-target",
    "one-run",
    scope~,
  )
  // Preserve the real missing-original refusal, then supply the independent
  // existing Policy fixture through its original Owner before retaining it.
  assert_true(
    run_policy_originals_wire(prepared, compiled=unselected_compiled)
    is Err(PublicationPolicy(@checked.MissingDependency)),
  )
  let compiled = @host.with_client_source_free_result_policy(
    unselected_compiled, selected_policy_fixture_cid, selected_policy_fixture_wire,
    65536, 8192, 64,
  ).unwrap()
  host.journal.bind_run(request, prepared, compiled, definition, true).unwrap()
  |> ignore
  host
  .retain_publication_policy_originals(
    crypto, "operator", "cli", request, prepared, compiled, definition,
  )
  .unwrap()
  |> ignore
  let journal = host.journal
  journal.invalidate_operation_record()
  journal.admitted_publications.clear()
  journal.operation_active = true
  let calls : Array[String] = []
  let reads = journal_test_read_access(host.database, calls)
  let first = journal
    .transaction_with_reads(
      () => journal.retained(request, reads=Some(reads)),
      reads=Some(reads),
    )
    .unwrap()
    .unwrap()
  let wire = first.publication_policy_originals.unwrap()
  let policies = journal.publication_originals(wire).unwrap()
  assert_eq(journal.admitted_publications.length(), 1)
  let second = journal
    .transaction_with_reads(
      () => journal.retained(request, reads=Some(reads)),
      reads=Some(reads),
    )
    .unwrap()
    .unwrap()
  assert_true(physical_equal(first, second))
  assert_true(
    physical_equal(policies, journal.publication_originals(wire).unwrap()),
  )
  assert_eq(journal.admitted_publications.length(), 1)
  journal.retained_policy_wire(request, reads=Some(reads)).unwrap() |> ignore
  assert_eq(
    calls.filter(value => value.has_prefix("read:client_runs:")).length(),
    1,
  )
  assert_false(calls.any(value => value.has_prefix("scan:client_runs:")))
  let before_lookup = calls.length()
  assert_true(
    journal.lookup_with_reads(request, true, reads=Some(reads))
    is Ok(Retained(value)) &&
    physical_equal(first, value),
  )
  for index = before_lookup; index < calls.length(); index = index + 1 {
    let value = calls[index]
    assert_false(
      value.has_prefix("read:") ||
      value.has_prefix("scan:") ||
      value == "begin" ||
      value == "commit" ||
      value == "rollback",
    )
  }
  // These are the same typed originals across two actual transactions, not
  // newly admitted copies selected by a private helper/transaction frame.
  journal.operation_active = false
  journal.invalidate_operation_record()
  journal.admitted_publications.clear()
  journal.operation_active = true
  calls.clear()
  // The inverse order must also observe the target once: deferred Policy
  // metadata first, then full Run/Policy/custody admission of that same row.
  journal
  .transaction_with_reads(
    () => journal.retained_policy_wire(request, reads=Some(reads)),
    reads=Some(reads),
  )
  .unwrap()
  |> ignore
  let next = journal
    .transaction_with_reads(
      () => journal.retained(request, reads=Some(reads)),
      reads=Some(reads),
    )
    .unwrap()
    .unwrap()
  assert_false(physical_equal(first, next))
  assert_false(
    physical_equal(policies, journal.publication_originals(wire).unwrap()),
  )
  assert_eq(journal.admitted_publications.length(), 1)
  assert_eq(
    calls.filter(value => value.has_prefix("read:client_runs:")).length(),
    1,
  )
  journal.operation_active = false
  journal.invalidate_operation_record()
  journal.admitted_publications.clear()
  host.close().unwrap()
}

///|
// Actual legacy Host/Account/SQLite originals plus a controlled cheap current
// predicate. The capture deliberately has no Native OriginalRead: its real
// lifetime check must fail. This tests invalidation, never a Native supplier,
// physical recovery, or a fabricated successful Read/cleanup acknowledgement.
test "failed operation lifetime retires the cached adoption before cheap current can recover" {
  for mode in ["scope", "account", "phase-return"] {
    let name = "operation-lifetime-invalidation-" + mode
    let host = policy_host_fixture(name)
    let capture = prepare_native_local_journal_capture(
      host.session,
      local_journal_test_library(),
      epoch_test_crypto(),
      100.0,
      8,
      8388608L,
    )
    // Transfer this actual legacy opening into its test-owned capture. No
    // Native original resources or entered-scope result is manufactured.
    capture.opening = JournalAcquired(host)
    let scope_cid = host
      .authority_scope_cid("operator", "cli", epoch_test_crypto())
      .unwrap()
    let (request, prepared, compiled, definition) = journal_test_run(
      name + "-request",
      name + "-run",
      scope=scope_cid,
    )
    host.journal
    .bind_run(request, prepared, compiled, definition, true)
    .unwrap()
    |> ignore
    capture.read_callback_active = true
    capture.read_facts_valid = true
    host.journal.operation_active = true
    host.journal.transaction(() => host.journal.retained(request)).unwrap()
    |> ignore
    assert_true(host.journal.operation_record is Some(_))
    let cheap_current = Ref(true)
    let full = Ref(0)
    let observe = () => {
      host.current_adoption_material_with_reads(
        () => {
          full.val += 1
          host.check_binding()
        },
        snapshot_current=Some(() => {
          if cheap_current.val {
            Ok(())
          } else {
            Err(Closed)
          }
        }),
      )
    }
    let material = @host.bind_client_local_adopted_host_material(
      host.database,
      observe,
    ).unwrap()
    let tuple : @authorization.AccessTuple = {
      principal: "operator",
      connection: "cli",
      resource: "run",
      operation: "submit",
    }
    let allowed = @host.client_local_adopted_account_outcome(
      material,
      host.database,
      tuple,
    ).unwrap()
    assert_true(allowed is Allow(_))
    assert_eq(full.val, 1)
    assert_true(host.journal.admitted_adoption is Some(_))
    capture.read_material = Some(material)
    capture.read_scopes.push(("operator", "cli", "previous-scope"))
    capture.read_decisions.push((tuple, allowed))
    cheap_current.val = false
    if mode == "scope" {
      assert_true(
        capture.operation_scope(host, material, "operator", "cli")
        is Err(OriginalResourceScopePending),
      )
    } else if mode == "account" {
      assert_true(
        capture.operation_account(host, material, tuple)
        is Err(OriginalResourceScopePending),
      )
    } else {
      // The command flag and old Allow cannot replace the missing physical
      // pair, even while the original Read is nominally unentered.
      assert_true(
        capture.check_current_between_original_phases()
        is Err(OriginalResourceScopePending),
      )
    }
    assert_false(capture.read_facts_valid)
    assert_true(capture.read_material is None)
    assert_eq(capture.read_scopes.length(), 0)
    assert_eq(capture.read_decisions.length(), 0)
    assert_true(host.journal.admitted_adoption is None)
    assert_true(host.journal.operation_record is None)
    assert_true(
      capture.read_operation_issue is Some(OriginalResourceScopePending),
    )
    // Change the actual selected Account generation. This original Host must
    // refuse it; recovery cannot adopt the replacement or regrant the old Allow.
    let source = host.session.source_root
    source
    .reclaim_generation(
      host.session.source_name,
      host.session.source_generation,
    )
    .unwrap()
    let replacement = source
      .create_writer(name + ".replacement", 4096L)
      .unwrap()
    let denied = @utf8.encode(
      @utf8.decode(policy_account_original).replace_all(
        old="\"outcome\":\"allow\"",
        new="\"outcome\":\"deny\"",
      ),
    )
    replacement.append(denied).unwrap()
    replacement.seal(host.session.source_name).unwrap() |> ignore
    cheap_current.val = true
    // The escaped old material cannot reuse its retired observation even when
    // the controlled cheap predicate alone is restored.
    assert_true(
      @host.client_local_adopted_account_outcome(material, host.database, tuple)
      is Err(@host.Physical(SourceChanged)),
    )
    assert_eq(full.val, 2)
    assert_true(host.journal.admitted_adoption is None)
    assert_true(
      capture.operation_account(host, material, tuple)
      is Err(OriginalResourceScopePending),
    )
    assert_true(
      capture.check_current_in_original_read()
      is Err(OriginalResourceScopePending),
    )
    assert_true(
      capture.check_current_between_original_phases()
      is Err(OriginalResourceScopePending),
    )
    assert_eq(full.val, 2)
    capture.read_callback_active = false
    host.journal.operation_active = false
    // A later observation goes back to actual current state. It refuses this
    // changed original rather than reviving Allow or adopting replacement data.
    assert_true(observe() is Err(SourceChanged))
    assert_eq(full.val, 3)
    assert_eq(capture.close().issue_family(), 0)
  }
}

///|
test "operation retention refuses changed target bytes and preserves rollback and Unknown" {
  let host = policy_host_fixture("public-operation-target-change")
  let scope = host
    .authority_scope_cid("operator", "cli", epoch_test_crypto())
    .unwrap()
  let (request, prepared, compiled, definition) = journal_test_run(
    "changed-target",
    "changed-run",
    scope~,
  )
  host.journal.bind_run(request, prepared, compiled, definition, true).unwrap()
  |> ignore
  let journal = host.journal
  journal.operation_active = true
  let first = journal
    .transaction(() => journal.retained(request))
    .unwrap()
    .unwrap()
  let key = @host.client_request_scope_cid(request)
  let before = host.database.read("client_runs", key).unwrap()
  let changed = journal.transaction(() => {
    // This is an actual controlled mutation, not a trusted metadata getter.
    // Retire the same operation fact before replacing the selected target.
    journal.invalidate_operation_record()
    // The existing Run-definition index requires valid JSON on writes.
    // Keep the original row corrupt so its current check performs the refusal.
    match
      host.database.compare_exchange("client_runs", key, before.revision, b"{}") {
      Ok(_) => ()
      Err(issue) => return Err(Physical(issue))
    }
    journal.retained(request)
  })
  assert_true(changed is Err(CustodyLost))
  let after = host.database.read("client_runs", key).unwrap()
  assert_eq(after.revision, before.revision)
  assert_eq(after.body, before.body)
  let restored = journal
    .transaction(() => journal.retained(request))
    .unwrap()
    .unwrap()
  assert_eq(restored.revision, first.revision)
  assert_eq(run_record_body(restored).unwrap(), before.body)
  client_test_fail_commit_reply(host.database, 1)
  assert_true(
    journal.transaction(() => journal.retained(request))
    is Err(TransactionUnknown),
  )
  assert_true(journal.fenced && host.database.transaction_fenced())
  assert_true(journal.lookup(request, true) is Err(Fenced))
  journal.operation_active = false
  journal.invalidate_operation_record()
  journal.admitted_publications.clear()
  host.close().unwrap()
}
