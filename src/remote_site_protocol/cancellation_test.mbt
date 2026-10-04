///|
test "unseen cancellation is durable before admission and cannot start" {
  let request = coordinator_request("cancel-unseen", 91)
  let owner = journal()
  let admission = prepare_dispatch_cancellation(owner, request).unwrap()
  let body = dispatch_admission_durable_json(admission).unwrap()
  assert_true(
    commit_dispatch_acceptance(admission, false) is Err(DurabilityUnconfirmed),
  )
  let (_, record) = commit_dispatch_acceptance(admission, true).unwrap()
  assert_eq(dispatch_record_state_codes(record)[0], 5)
  assert_eq(dispatch_record_state_codes(record)[2], 2)
  assert_false(remote_runtime_record_startable(record))
  assert_eq(dispatch_record_durable_json(record).unwrap(), body)
  let restored = restore_durable_dispatch_record(
    journal(),
    admit_durable_dispatch_record(@utf8.encode(body)).unwrap(),
  ).unwrap()
  assert_eq(dispatch_record_state_codes(restored)[0], 5)
  assert_eq(dispatch_record_state_codes(restored)[2], 2)
  let (_, resent) = commit_dispatch_acceptance(
    prepare_dispatch_acceptance(owner, request).unwrap(),
    true,
  ).unwrap()
  assert_eq(dispatch_record_state_codes(resent)[0], 5)
  assert_eq(dispatch_record_revision(resent), dispatch_record_revision(record))
}

///|
test "cancellation admission preserves an existing dispatch owner" {
  let request = coordinator_request("cancel-existing", 92)
  let owner = journal()
  let (_, record) = commit_dispatch_acceptance(
    prepare_dispatch_acceptance(owner, request).unwrap(),
    true,
  ).unwrap()
  let (_, same) = commit_dispatch_acceptance(
    prepare_dispatch_cancellation(owner, request).unwrap(),
    true,
  ).unwrap()
  assert_eq(
    dispatch_record_state_codes(same)[0],
    dispatch_record_state_codes(record)[0],
  )
  assert_eq(dispatch_record_state_codes(same)[2], 0)
  assert_eq(dispatch_record_revision(same), dispatch_record_revision(record))
}

///|
test "cancel wire binds the original request and carries no start materials" {
  let original = coordinator_request("cancel-wire", 93)
  let body = remote_poll_cancel_json(original).unwrap()
  let admitted = admit_remote_poll_cancel_json(body).unwrap()
  assert_eq(
    dispatch_request_identity(admitted),
    dispatch_request_identity(original),
  )
  assert_true(admit_remote_poll_dispatch_json(body) is Err(InvalidDispatch))
  assert_true(
    admit_remote_poll_cancel_json(remote_poll_query_json(original).unwrap())
    is Err(InvalidDispatch),
  )
  assert_true(
    admit_remote_poll_cancel_json(body.replace(old="site-a", new="site-b"))
    is Err(InvalidDispatch),
  )
  assert_true(
    admit_remote_poll_cancel_json(
      body.replace(old="coordinator-a", new="coordinator-b"),
    )
    is Err(InvalidDispatch),
  )
}

///|
test "Coordinator admits durable unseen cancellation and replay without execution" {
  let request = coordinator_request("cancel-observation", 94)
  let (_, site_record) = commit_dispatch_acceptance(
    prepare_dispatch_cancellation(journal(), request).unwrap(),
    true,
  ).unwrap()
  let (_, coordinator) = commit_coordinator_dispatch_intent(
    prepare_coordinator_dispatch_intent(
      create_coordinator_dispatch_journal("coordinator-a").unwrap(),
      request,
    ).unwrap(),
    true,
  ).unwrap()
  commit_coordinator_dispatch_transition(
    prepare_coordinator_outcome_unknown(coordinator).unwrap(),
    true,
  ).unwrap()
  let status = remote_dispatch_status_json(site_record, None, None, None).unwrap()
  let response = admit_remote_dispatch_response_json(
    status,
    request,
    StatusReply,
  ).unwrap()
  let transition = prepare_coordinator_response_observation(
    coordinator, response,
  ).unwrap()
  commit_coordinator_dispatch_transition(transition, true).unwrap()
  let observation = coordinator_execution_observation(
    coordinator, "coordinator-a", "sha256:0000000000000000000000000000000000000000000000000000000000000000",
    "task-a",
  ).unwrap()
  assert_eq(observation.execution, Some(ExecutionCancelled))
  assert_true(observation.execution_terminal)
  assert_true(observation.cleanup_complete)
  let replay = prepare_coordinator_response_observation(coordinator, response).unwrap()
  assert_true(coordinator_dispatch_transition_is_replay(replay))
  let revision = coordinator_dispatch_record_revision(coordinator)
  commit_coordinator_dispatch_transition(replay, true).unwrap()
  assert_eq(coordinator_dispatch_record_revision(coordinator), revision)
}
