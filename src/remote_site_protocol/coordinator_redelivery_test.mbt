///|
test "initial delivery recovery requires durable unsent intent and current context" {
  let request = coordinator_request("initial-recovery", 1)
  let record = restore_coordinator_dispatch_intent(
    create_coordinator_dispatch_journal("coordinator-a").unwrap(),
    request,
  ).unwrap()
  let eligible = fn(authorized : Bool, cancelled : Bool) {
    coordinator_initial_delivery_eligible(
      record, request, "coordinator-a", "site-a", 1, authorized, cancelled, true,
    ).unwrap()
  }
  let before = coordinator_dispatch_record_state_codes(record)
  assert_true(eligible(true, false))
  assert_false(
    coordinator_initial_delivery_eligible(
      record, request, "coordinator-a", "site-a", 1, true, false, false,
    ).unwrap(),
  )
  assert_false(eligible(false, false))
  assert_false(eligible(true, true))
  assert_true(
    coordinator_initial_delivery_eligible(
      record, request, "other", "site-a", 1, true, false, true,
    )
    is Err(ForeignCoordinator),
  )
  assert_true(
    coordinator_initial_delivery_eligible(
      record, request, "coordinator-a", "other", 1, true, false, true,
    )
    is Err(ForeignSite),
  )
  assert_true(
    coordinator_initial_delivery_eligible(
      record, request, "coordinator-a", "site-a", 2, true, false, true,
    )
    is Err(StaleSiteGeneration),
  )
  assert_true(
    coordinator_initial_delivery_eligible(
      record,
      coordinator_request("other", 1),
      "coordinator-a",
      "site-a",
      1,
      true,
      false,
      true,
    )
    is Err(DispatchIdentityMismatch),
  )
  assert_eq(coordinator_dispatch_record_state_codes(record), before)
  commit_coordinator_dispatch_transition(
    prepare_coordinator_outcome_unknown(record).unwrap(),
    true,
  ).unwrap()
  assert_false(eligible(true, false))
  // Missing responses remain insufficient for uncertain sends, even though
  // the original initial intent was eligible before the unknown transition.
  assert_false(
    coordinator_redelivery_eligible(
      record, request, "", "coordinator-a", "site-a", 1, true, false,
    ).unwrap(),
  )
}

///|
test "initial delivery recovery does not turn Accepted or started history into unsent work" {
  let request = coordinator_request("initial-observed", 1)
  let record = restore_coordinator_dispatch_intent(
    create_coordinator_dispatch_journal("coordinator-a").unwrap(),
    request,
  ).unwrap()
  for execution in [0, 1] {
    commit_coordinator_dispatch_transition(
      prepare_coordinator_site_observation(
        record,
        execution,
        execution,
        0,
        0,
        false,
        false,
        None,
      ).unwrap(),
      true,
    ).unwrap()
    assert_false(
      coordinator_initial_delivery_eligible(
        record, request, "coordinator-a", "site-a", 1, true, false, true,
      ).unwrap(),
    )
  }
}

///|
test "R2 exact delivery is a canonical immutable poll envelope" {
  let request = coordinator_request("r2-envelope", 1)
  let binding = prepare_remote_input_binding("{}", 2).unwrap()
  let body = remote_poll_dispatch_json(request, binding).unwrap()
  assert_eq(coordinator_delivery_envelope_json(request, body).unwrap(), body)
  assert_true(
    coordinator_delivery_envelope_json(
      coordinator_request("different", 1),
      body,
    )
    is Err(DispatchIdentityMismatch),
  )
  assert_true(
    coordinator_delivery_envelope_json(request, body + " ")
    is Err(InvalidDispatch),
  )
  assert_true(
    remote_poll_dispatch_materials_json(
      request,
      binding,
      "x".repeat(REMOTE_RUN_MATERIALS_MAX_BYTES + 1),
    )
    is Err(InvalidDispatch),
  )
}

///|
test "R2 owner distinguishes typed not seen Accepted and started observations" {
  let request = coordinator_request("r2-decision", 1)
  let record = restore_coordinator_dispatch_intent(
    create_coordinator_dispatch_journal("coordinator-a").unwrap(),
    request,
  ).unwrap()
  let eligible = fn(body : String, authorized : Bool, cancelled : Bool) {
    coordinator_redelivery_eligible(
      record, request, body, "coordinator-a", "site-a", 1, authorized, cancelled,
    ).unwrap()
  }
  let absent = remote_poll_not_seen_json(request).unwrap()
  assert_false(eligible("", true, false))
  assert_true(eligible(absent, true, false))
  assert_false(eligible(absent, false, false))
  assert_false(eligible(absent, true, true))
  assert_true(
    coordinator_redelivery_eligible(
      record, request, absent, "coordinator-a", "site-a", 2, true, false,
    )
    is Err(StaleSiteGeneration),
  )
  assert_true(
    coordinator_redelivery_eligible(
      record, request, absent, "other", "site-a", 1, true, false,
    )
    is Err(ForeignCoordinator),
  )
  commit_coordinator_dispatch_transition(
    prepare_coordinator_site_observation(record, 0, 0, 0, 0, false, false, None).unwrap(),
    true,
  ).unwrap()
  let state = coordinator_dispatch_record_state_codes(record)
  assert_true(eligible("", true, false))
  assert_false(eligible(absent, true, false))
  assert_eq(coordinator_dispatch_record_state_codes(record), state)
  commit_coordinator_dispatch_transition(
    prepare_coordinator_site_observation(record, 2, 2, 0, 0, false, false, None).unwrap(),
    true,
  ).unwrap()
  assert_false(eligible("", true, false))
  let accepted_replay = prepare_coordinator_site_observation(
    record,
    0,
    0,
    0,
    0,
    false,
    false,
    None,
  ).unwrap()
  assert_true(coordinator_dispatch_transition_is_replay(accepted_replay))
  commit_coordinator_dispatch_transition(accepted_replay, true).unwrap()
  assert_false(eligible("", true, false))
}
