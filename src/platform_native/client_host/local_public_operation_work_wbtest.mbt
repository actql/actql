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
  journal.admitted_record = None
  journal.admitted_publications.clear()
  journal.operation_active = true
  let first = journal
    .transaction(() => journal.retained(request))
    .unwrap()
    .unwrap()
  let wire = first.publication_policy_originals.unwrap()
  let policies = journal.publication_originals(wire).unwrap()
  assert_eq(journal.admitted_publications.length(), 1)
  let second = journal
    .transaction(() => journal.retained(request))
    .unwrap()
    .unwrap()
  assert_true(physical_equal(first, second))
  assert_true(
    physical_equal(policies, journal.publication_originals(wire).unwrap()),
  )
  assert_eq(journal.admitted_publications.length(), 1)
  // These are the same typed originals across two actual transactions, not
  // newly admitted copies selected by a private helper/transaction frame.
  journal.operation_active = false
  journal.admitted_record = None
  journal.admitted_publications.clear()
  journal.operation_active = true
  let next = journal
    .transaction(() => journal.retained(request))
    .unwrap()
    .unwrap()
  assert_false(physical_equal(first, next))
  assert_false(
    physical_equal(policies, journal.publication_originals(wire).unwrap()),
  )
  assert_eq(journal.admitted_publications.length(), 1)
  journal.operation_active = false
  journal.admitted_record = None
  journal.admitted_publications.clear()
  host.close().unwrap()
}

///|
// Actual legacy Host/Account/SQLite originals plus a controlled cheap current
// predicate. The capture deliberately has no Native OriginalRead: its real
// lifetime check must fail. This tests invalidation, never a Native supplier,
// physical recovery, or a fabricated successful Read/cleanup acknowledgement.
test "failed operation lifetime retires the cached adoption before cheap current can recover" {
  for scope in [true, false] {
    let name = "operation-lifetime-invalidation-" + scope.to_string()
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
    capture.read_callback_active = true
    capture.read_facts_valid = true
    host.journal.operation_active = true
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
    capture.read_decisions.push((tuple, None, allowed))
    cheap_current.val = false
    if scope {
      assert_true(
        capture.operation_scope(host, material, "operator", "cli")
        is Err(OriginalResourceScopePending),
      )
    } else {
      assert_true(
        capture.operation_account(host, material, tuple)
        is Err(OriginalResourceScopePending),
      )
    }
    assert_false(capture.read_facts_valid)
    assert_true(capture.read_material is None)
    assert_eq(capture.read_scopes.length(), 0)
    assert_eq(capture.read_decisions.length(), 0)
    assert_true(host.journal.admitted_adoption is None)
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
    match
      host.database.compare_exchange(
        "client_runs",
        key,
        before.revision,
        b"changed target",
      ) {
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
  assert_true(physical_equal(first, restored))
  client_test_fail_commit_reply(host.database, 1)
  assert_true(
    journal.transaction(() => journal.retained(request))
    is Err(TransactionUnknown),
  )
  assert_true(journal.fenced && host.database.transaction_fenced())
  assert_true(journal.lookup(request, true) is Err(Fenced))
  journal.operation_active = false
  journal.admitted_record = None
  journal.admitted_publications.clear()
  host.close().unwrap()
}
