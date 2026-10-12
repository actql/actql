///|
// The existing cursor fixture isolates admitted contract references. Its
// index is not a full completed Run chain or a physical Store acceptance.
test "publisher port projects six original facts and reevaluates all stages" {
  let fixture = commit_cursor_fixture(["answer"]).reference_inputs
  let original = project_publication_request_context(fixture.request).unwrap()
  assert_eq(original.namespace_id, "local")
  assert_eq(original.authority_scope_cid, inventory_fixture_cid("3"))
  assert_eq(original.run_definition_cid, fixture.run_definition.identity)
  assert_eq(original.publication_policy_cid, inventory_fixture_cid("4"))
  assert_eq(original.publication_target_cid, inventory_fixture_cid("5"))
  assert_eq(original.publication_request_cid, fixture.request.identity)
  let facts : Array[PublicationPublisherAuthorization] = []
  let fence_calls = Ref(0)
  let store = inventory_fixture_cid("a")
  let port = install_publication_publisher_port(
    fixture.request,
    fixture.attempt,
    store,
    () => {
      fence_calls.val += 1
      true
    },
    fact => {
      facts.push(fact)
      true
    },
  ).unwrap()
  assert_eq(facts.length(), 0)
  for stage in [Request, Commit, ReturnCommitted] {
    port
    .check(
      fixture.request,
      fixture.attempt,
      store,
      stage,
      if stage == Request {
        None
      } else {
        Some(fixture.index_entry)
      },
    )
    .unwrap()
  }
  assert_eq(fence_calls.val, 7)
  assert_eq(facts.map(fact => fact.stage), [
    "request", "commit", "return_committed",
  ])
  for index, fact in facts {
    assert_eq(fact, {
      stage: ["request", "commit", "return_committed"][index],
      namespace_id: "local",
      authority_scope_cid: inventory_fixture_cid("3"),
      run_definition_cid: fixture.run_definition.identity,
      publication_request_cid: fixture.request.identity,
      public_index_entry_cid: if index == 0 {
        None
      } else {
        Some(fixture.index_entry.identity)
      },
    })
  }
}

///|
test "publisher port rejects copied intent foreign scope and Store before authorization" {
  let fixture = commit_cursor_fixture(["answer"]).reference_inputs
  let store = inventory_fixture_cid("a")
  let calls = Ref(0)
  let port = install_publication_publisher_port(
    fixture.request,
    fixture.attempt,
    store,
    () => true,
    _ => {
      calls.val += 1
      true
    },
  ).unwrap()
  let copy = admit_publication_contract(
    "publication_request",
    publication_contract_json(fixture.request),
    65536,
    4096,
    32,
  ).unwrap()
  assert_eq(copy.identity, fixture.request.identity)
  assert_eq(
    port.check(copy, fixture.attempt, store, Request, None),
    Err(ForeignRequest),
  )
  let attempt_copy = admit_publication_contract(
    "publication_attempt",
    publication_contract_json(fixture.attempt),
    65536,
    4096,
    32,
  ).unwrap()
  assert_eq(
    port.check(fixture.request, attempt_copy, store, Request, None),
    Err(ForeignRequest),
  )
  assert_eq(
    port.check(
      fixture.request,
      fixture.attempt,
      inventory_fixture_cid("b"),
      Request,
      None,
    ),
    Err(InvalidStore),
  )
  assert_eq(
    port.check(
      fixture.request,
      fixture.attempt,
      store,
      Request,
      Some(fixture.index_entry),
    ),
    Err(ReferenceMismatch),
  )
  assert_eq(
    port.check(fixture.request, fixture.attempt, store, Commit, None),
    Err(ReferenceMismatch),
  )
  for
    (field, value) in [
      ("namespace_id", "another-namespace"),
      ("authority_scope_cid", inventory_fixture_cid("b")),
      ("run_definition_cid", inventory_fixture_cid("b")),
      ("publication_request_cid", inventory_fixture_cid("b")),
      ("publication_attempt_cid", inventory_fixture_cid("b")),
    ] {
    let foreign = commit_cursor_reseal(fixture.index_entry, field, value)
    assert_eq(
      port.check(fixture.request, fixture.attempt, store, Commit, Some(foreign)),
      Err(ReferenceMismatch),
    )
  }
  assert_eq(calls.val, 0)
}

///|
test "publisher port current fences reject revocation without replacing original custody" {
  let fixture = commit_cursor_fixture(["answer"]).reference_inputs
  let store = inventory_fixture_cid("a")
  let current = Ref(true)
  let revoke_in_callback = Ref(false)
  let calls = Ref(0)
  let original_request = publication_contract_json(fixture.request)
  let original_attempt = publication_contract_json(fixture.attempt)
  let port = install_publication_publisher_port(
    fixture.request,
    fixture.attempt,
    store,
    () => current.val,
    _ => {
      calls.val += 1
      if revoke_in_callback.val {
        current.val = false
      }
      true
    },
  ).unwrap()
  current.val = false
  assert_eq(
    port.check(fixture.request, fixture.attempt, store, Request, None),
    Err(NotCurrent),
  )
  assert_eq(calls.val, 0)
  current.val = true
  revoke_in_callback.val = true
  assert_eq(
    port.check(
      fixture.request,
      fixture.attempt,
      store,
      Commit,
      Some(fixture.index_entry),
    ),
    Err(NotCurrent),
  )
  assert_eq(calls.val, 1)
  assert_eq(publication_contract_json(fixture.request), original_request)
  assert_eq(publication_contract_json(fixture.attempt), original_attempt)
  assert_true(physical_equal(port.request, fixture.request))
  assert_true(physical_equal(port.attempt, fixture.attempt))
}

///|
test "publisher port keeps publisher denial separate from current Run Source access" {
  let fixture = commit_cursor_fixture(["answer"]).reference_inputs
  let store = inventory_fixture_cid("a")
  let permitted = Ref(true)
  let calls = Ref(0)
  let port = install_publication_publisher_port(
    fixture.request,
    fixture.attempt,
    store,
    () => true,
    _ => {
      calls.val += 1
      permitted.val
    },
  ).unwrap()
  port.check(fixture.request, fixture.attempt, store, Request, None).unwrap()
  permitted.val = false
  assert_eq(
    port.check(
      fixture.request,
      fixture.attempt,
      store,
      Commit,
      Some(fixture.index_entry),
    ),
    Err(AccessDenied),
  )
  assert_eq(
    port.check(
      fixture.request,
      fixture.attempt,
      store,
      ReturnCommitted,
      Some(fixture.index_entry),
    ),
    Err(AccessDenied),
  )
  assert_eq(calls.val, 3)
}

///|
test "publisher port return committed permits original request retry after separate validation" {
  let fixture = commit_cursor_fixture(["answer"]).reference_inputs
  let store = inventory_fixture_cid("a")
  let calls = Ref(0)
  let port = install_publication_publisher_port(
    fixture.request,
    fixture.attempt,
    store,
    () => true,
    _ => {
      calls.val += 1
      true
    },
  ).unwrap()
  // A previously committed attempt can differ from the retry's attempt. This
  // scope check does not validate that attempt or accept its durable chain.
  let earlier = commit_cursor_reseal(
    fixture.index_entry,
    "publication_attempt_cid",
    inventory_fixture_cid("b"),
  )
  assert_eq(
    port.check(fixture.request, fixture.attempt, store, Commit, Some(earlier)),
    Err(ReferenceMismatch),
  )
  port
  .check(
    fixture.request,
    fixture.attempt,
    store,
    ReturnCommitted,
    Some(earlier),
  )
  .unwrap()
  assert_eq(calls.val, 1)
  assert_true(
    install_publication_publisher_port(
      fixture.request,
      fixture.attempt,
      "not-a-CID",
      () => true,
      _ => true,
    )
    is Err(InvalidStore),
  )
}

///|
test "publisher port installation requires original admitted request attempt and current Host" {
  let fixture = commit_cursor_fixture(["answer"]).reference_inputs
  let store = inventory_fixture_cid("a")
  assert_true(
    project_publication_request_context(fixture.run_definition)
    is Err(WrongContract),
  )
  assert_true(
    install_publication_publisher_port(
      fixture.request,
      fixture.index_entry,
      store,
      () => true,
      _ => true,
    )
    is Err(WrongContract),
  )
  let foreign = commit_cursor_reseal(
    fixture.attempt,
    "publication_request_cid",
    inventory_fixture_cid("b"),
  )
  assert_true(
    install_publication_publisher_port(
      fixture.request,
      foreign,
      store,
      () => true,
      _ => true,
    )
    is Err(ReferenceMismatch),
  )
  let other_run = commit_cursor_reseal(
    fixture.attempt,
    "run_definition_cid",
    inventory_fixture_cid("b"),
  )
  assert_true(
    install_publication_publisher_port(
      fixture.request,
      other_run,
      store,
      () => true,
      _ => true,
    )
    is Err(ReferenceMismatch),
  )
  let calls = Ref(0)
  assert_true(
    install_publication_publisher_port(
      fixture.request,
      fixture.attempt,
      store,
      () => false,
      _ => {
        calls.val += 1
        true
      },
    )
    is Err(NotCurrent),
  )
  assert_eq(calls.val, 0)
}
