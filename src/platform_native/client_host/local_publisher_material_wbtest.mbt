///|
// The observer wraps the real Host's current port; no fake adoption, Account,
// Store or retained Run can make material current. Names identify fresh roots.
test "Publisher predicate material preserves all three scope and Account current fences" {
  let (host, request, definition, store) = local_publisher_fixture(
    "publisher-material-fences", true,
  )
  let publisher = host
    .bind_run_publisher(
      epoch_test_crypto(),
      "operator",
      "cli",
      request,
      definition,
      "publisher-material-fences.run.json",
      store,
    )
    .unwrap()
  let calls = Ref(0)
  let material = @host.bind_client_local_adopted_host_material(host.database, () => {
    calls.val += 1
    host.current_adoption_material()
  }).unwrap()
  assert_eq(calls.val, 2)
  for _ in 0..<3 {
    assert_true(
      publisher.authority.current_with_material_for(
        host.journal,
        request,
        material,
      ),
    )
  }
  // Each of the three calls independently checks scope before/after and
  // Account before/after. Only repeated material binding is absent.
  assert_eq(calls.val, 14)
  assert_true(publisher.current())
  host.close().unwrap()
  assert_false(
    publisher.authority.current_with_material_for(
      host.journal,
      request,
      material,
    ),
  )
  assert_eq(calls.val, 15)
  assert_false(publisher.current())
  assert_true(store.close().unwrap())
}

///|
test "Publisher shared material refuses original custody lost in final Account callback" {
  let (host, request, definition, store) = local_publisher_fixture(
    "publisher-material-lost", true,
  )
  let publisher = host
    .bind_run_publisher(
      epoch_test_crypto(),
      "operator",
      "cli",
      request,
      definition,
      "publisher-material-lost.run.json",
      store,
    )
    .unwrap()
  let calls = Ref(0)
  let removed = Ref(false)
  let material = @host.bind_client_local_adopted_host_material(host.database, () => {
    calls.val += 1
    if calls.val == 6 {
      let table = @utf8.encode("client_local_adoption")
      let key = @utf8.encode("adoption")
      removed.val = submitted_test_remove_record(
        host.database,
        table,
        table.length(),
        key,
        key.length(),
      )
    }
    host.current_adoption_material()
  }).unwrap()
  assert_false(
    publisher.authority.current_with_material_for(
      host.journal,
      request,
      material,
    ),
  )
  assert_eq(calls.val, 6)
  assert_true(removed.val)
  assert_false(publisher.current())
  host.close().unwrap()
  assert_true(store.close().unwrap())
}

///|
test "Publisher shared material cannot use another Host or foreign request scope" {
  let original = policy_reuse_host_fixture("publisher-material-original")
  let other = policy_reuse_host_fixture("publisher-material-foreign")
  let crypto = epoch_test_crypto()
  let scope = original.authority_scope_cid("operator", "cli", crypto).unwrap()
  let (request, _, _, _) = journal_test_run("material", "material-run", scope~)
  let authority = native_local_policy_authority_for(
    original,
    crypto,
    "operator",
    "cli",
    request,
    ReadResultPolicy("answer"),
  ).unwrap()
  let calls = Ref(0)
  let foreign = @host.bind_client_local_adopted_host_material(other.database, () => {
    calls.val += 1
    other.current_adoption_material()
  }).unwrap()
  assert_eq(calls.val, 2)
  assert_false(
    authority.current_with_material_for(original.journal, request, foreign),
  )
  assert_false(
    authority.current_with_material_for(other.journal, request, foreign),
  )
  let (foreign_request, _, _, _) = journal_test_run(
    "foreign-material", "foreign-material-run",
  )
  assert_false(
    authority.current_with_material_for(
      original.journal,
      foreign_request,
      foreign,
    ),
  )
  assert_eq(calls.val, 2)
  original.close().unwrap()
  other.close().unwrap()
}
