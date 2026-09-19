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

///|
fn evidence_for_coordinator(
  request : DispatchRequest,
) -> RemoteExecutionEvidence {
  let site = @site.create_site(
    "site-a", 1, "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    4, 4, 1048576L, 1048576L,
  ).unwrap()
  let site_journal = create_site_dispatch_journal(site, "actql-remote-site/0.1").unwrap()
  let site_admission = prepare_dispatch_acceptance(site_journal, request).unwrap()
  let (_, site_record) = commit_dispatch_acceptance(site_admission, true).unwrap()
  let capability = register_remote_execution_capability(
    site, "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "local", "local/1", "strategy/1", "sha256:4444444444444444444444444444444444444444444444444444444444444444",
  ).unwrap()
  commit_dispatch_transition(
    prepare_begin_provisioning(site_record, capability).unwrap(),
    true,
  ).unwrap()
  commit_dispatch_transition(
    prepare_begin_remote_execution(site_record).unwrap(),
    true,
  ).unwrap()
  commit_dispatch_transition(
    prepare_confirm_native_settled(site_record).unwrap(),
    true,
  ).unwrap()
  commit_dispatch_transition(
    prepare_retain_remote_output(
      site_record, "material-generation-a", "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
    ).unwrap(),
    true,
  ).unwrap()
  let issuer = register_remote_evidence_issuer(
    site, "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "local", "local/1", "strategy/1", "actql.remote.physical-output/0.1", "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  ).unwrap()
  issue_remote_execution_evidence(
    issuer, site_record, "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
  ).unwrap()
}

///|
test "Site status alone cannot authorize Coordinator completion" {
  let request = coordinator_request("dispatch-a", 1)
  let journal = create_coordinator_dispatch_journal("coordinator-a").unwrap()
  let admission = prepare_coordinator_dispatch_intent(journal, request).unwrap()
  let (_, record) = commit_coordinator_dispatch_intent(admission, true).unwrap()
  let claimed = prepare_coordinator_site_observation(
    record,
    5,
    3,
    2,
    0,
    true,
    false,
    None,
  ).unwrap()
  commit_coordinator_dispatch_transition(claimed, true).unwrap()
  assert_false(coordinator_completion_evidence_available(record))
  let admitted = prepare_coordinator_site_observation(
    record,
    5,
    3,
    2,
    0,
    true,
    false,
    Some(evidence_for_coordinator(request)),
  ).unwrap()
  commit_coordinator_dispatch_transition(admitted, true).unwrap()
  assert_true(coordinator_completion_evidence_available(record))
}

///|
test "Coordinator rejects stale or altered Site observations" {
  let request = coordinator_request("dispatch-a", 1)
  let journal = create_coordinator_dispatch_journal("coordinator-a").unwrap()
  let admission = prepare_coordinator_dispatch_intent(journal, request).unwrap()
  let (_, record) = commit_coordinator_dispatch_intent(admission, true).unwrap()
  commit_coordinator_dispatch_transition(
    prepare_coordinator_site_observation(record, 2, 2, 0, 0, false, false, None).unwrap(),
    true,
  ).unwrap()
  assert_true(
    prepare_coordinator_site_observation(record, 1, 2, 0, 0, false, false, None)
    is Err(StateCollision),
  )
  assert_true(
    prepare_coordinator_site_observation(
      record,
      2,
      3,
      2,
      0,
      true,
      false,
      Some(evidence_for_coordinator(request)),
    )
    is Err(StateCollision),
  )
  assert_true(
    prepare_coordinator_site_observation(
      record,
      3,
      3,
      2,
      0,
      true,
      false,
      Some(evidence_for_coordinator(coordinator_request("dispatch-b", 2))),
    )
    is Err(InvalidDispatch),
  )
}

///|
test "Coordinator unknown state restores without inventing a Site fact" {
  let request = coordinator_request("dispatch-a", 1)
  let journal = create_coordinator_dispatch_journal("coordinator-a").unwrap()
  let admission = prepare_coordinator_dispatch_intent(journal, request).unwrap()
  let (_, record) = commit_coordinator_dispatch_intent(admission, true).unwrap()
  commit_coordinator_dispatch_transition(
    prepare_coordinator_outcome_unknown(record).unwrap(),
    true,
  ).unwrap()
  let state = coordinator_dispatch_record_state_codes(record)
  let restored_journal = create_coordinator_dispatch_journal("coordinator-a").unwrap()
  let restored = restore_coordinator_dispatch_intent(restored_journal, request).unwrap()
  restore_coordinator_dispatch_record(
    restored, 1, 1, -1, -1, -1, -1, false, false, "",
  ).unwrap()
  assert_eq(coordinator_dispatch_record_state_codes(restored), state)
  assert_false(coordinator_completion_evidence_available(restored))
}
