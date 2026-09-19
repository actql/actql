///|
fn coordinator_request(
  dispatch_id : String,
  task_attempt : Int,
  coordinator_authority? : String = "coordinator-a",
) -> DispatchRequest {
  prepare_dispatch_request(
    coordinator_authority, "sha256:0000000000000000000000000000000000000000000000000000000000000000",
    "task-a", task_attempt, dispatch_id, "site-a", 1, "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "local", "local/1", "strategy/1", "sha256:1111111111111111111111111111111111111111111111111111111111111111",
    "sha256:2222222222222222222222222222222222222222222222222222222222222222", "sha256:3333333333333333333333333333333333333333333333333333333333333333",
    "sha256:4444444444444444444444444444444444444444444444444444444444444444",
  ).unwrap()
}

///|
test "Coordinator intent is durable before it authorizes a send" {
  let journal = create_coordinator_dispatch_journal("coordinator-a").unwrap()
  let request = coordinator_request("dispatch-a", 1)
  let admission = prepare_coordinator_dispatch_intent(journal, request).unwrap()
  assert_eq(coordinator_dispatch_intent_kind(admission), NewDispatch)
  assert_eq(
    coordinator_dispatch_intent_json(admission).unwrap(),
    dispatch_request_json(request).unwrap(),
  )
  assert_true(
    commit_coordinator_dispatch_intent(admission, false)
    is Err(DurabilityUnconfirmed),
  )
  let (kind, record) = commit_coordinator_dispatch_intent(admission, true).unwrap()
  assert_eq(kind, NewDispatch)
  assert_true(coordinator_dispatch_intent_matches_request(record, request))
}

///|
test "Coordinator retry reconciles exact intent and rejects reexecution" {
  let journal = create_coordinator_dispatch_journal("coordinator-a").unwrap()
  let first = coordinator_request("dispatch-a", 1)
  let admission = prepare_coordinator_dispatch_intent(journal, first).unwrap()
  ignore(commit_coordinator_dispatch_intent(admission, true).unwrap())
  let retry = prepare_coordinator_dispatch_intent(journal, first).unwrap()
  assert_eq(coordinator_dispatch_intent_kind(retry), ExistingDispatch)
  let (kind, _) = commit_coordinator_dispatch_intent(retry, true).unwrap()
  assert_eq(kind, ExistingDispatch)
  assert_true(
    prepare_coordinator_dispatch_intent(
      journal,
      coordinator_request("dispatch-b", 1),
    )
    is Err(AttemptAlreadyDispatched),
  )
  assert_true(
    prepare_coordinator_dispatch_intent(
      journal,
      coordinator_request(
        "dispatch-c",
        2,
        coordinator_authority="coordinator-b",
      ),
    )
    is Err(ForeignCoordinator),
  )
}

///|
test "Coordinator restart restores intent without creating a Site fact" {
  let request = coordinator_request("dispatch-a", 1)
  let restored = restore_coordinator_dispatch_intent(
    create_coordinator_dispatch_journal("coordinator-a").unwrap(),
    request,
  ).unwrap()
  assert_true(coordinator_dispatch_intent_matches_request(restored, request))
}
