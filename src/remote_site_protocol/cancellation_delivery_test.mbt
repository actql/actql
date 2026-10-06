///|
test "response and durable Coordinator project the same Cancel delivery decision" {
  // Wire values and expected decisions are independent of product encoders.
  for
    (state, expected) in [
      ("[6,0,2,0,0]", false), // Unknown execution despite zero physical holds.
      ("[5,0,1,0,0]", false), // Cancellation persisted, cleanup pending.
      ("[3,1,0,1,0]", false), // Success still retains material.
      ("[6,0,4,0,1]", false), // Quarantine responsibility remains.
      ("[3,0,5,0,0]", false), // Recovery after loss is not explicit release.
      ("[3,0,2,0,0]", true), // Success won the cancellation race.
      ("[4,0,2,0,0]", true), // Failed execution, physically released.
      ("[5,0,2,0,0]", true), // Cancelled execution, physically released.
    ] {
    let request = coordinator_request("cancel-delivery", 95)
    let admission = prepare_coordinator_dispatch_intent(
      create_coordinator_dispatch_journal("coordinator-a").unwrap(),
      request,
    ).unwrap()
    let initial = admit_durable_coordinator_dispatch_record(
      @utf8.encode(
        coordinator_dispatch_admission_durable_json(admission).unwrap(),
      ),
    ).unwrap()
    let (_, record) = commit_coordinator_dispatch_intent(admission, true).unwrap()
    assert_false(coordinator_can_retire_cancellation_delivery(record))
    let body = "{\"version\":\"actql-remote-dispatch-response/0.1\",\"dispatch_request_cid\":\"" +
      dispatch_request_identity(request) +
      "\",\"revision\":1,\"state\":" +
      state +
      "}"
    let response = admit_remote_dispatch_response_json(
      body,
      request,
      DispatchReply,
    ).unwrap()
    assert_eq(
      remote_dispatch_response_can_retire_cancellation_delivery(response),
      expected,
    )
    let transition = prepare_coordinator_response_observation(record, response).unwrap()
    assert_true(
      commit_coordinator_dispatch_transition(transition, false)
      is Err(DurabilityUnconfirmed),
    )
    assert_false(coordinator_can_retire_cancellation_delivery(record))
    let persisted = coordinator_dispatch_transition_durable_json(
      initial, transition,
    ).unwrap()
    commit_coordinator_dispatch_transition(transition, true).unwrap()
    assert_eq(coordinator_can_retire_cancellation_delivery(record), expected)
    // Reconstruct after losing the acknowledgement; replay changes no decision.
    let durable = admit_durable_coordinator_dispatch_record(
      @utf8.encode(persisted),
    ).unwrap()
    let restored = restore_durable_coordinator_dispatch_record(
      create_coordinator_dispatch_journal("coordinator-a").unwrap(),
      durable,
    ).unwrap()
    assert_eq(coordinator_can_retire_cancellation_delivery(restored), expected)
    let replay = prepare_coordinator_response_observation(restored, response).unwrap()
    assert_true(coordinator_dispatch_transition_is_replay(replay))
    commit_coordinator_dispatch_transition(replay, true).unwrap()
    assert_eq(coordinator_can_retire_cancellation_delivery(restored), expected)
  }
}
