///|
fn coordinator_request(
  dispatch_id : String,
  task_attempt : Int,
  coordinator_authority? : String = "coordinator-a",
) -> DispatchRequest {
  prepare_dispatch_request(
    coordinator_authority, "sha256:0000000000000000000000000000000000000000000000000000000000000000",
    "task-a", task_attempt, dispatch_id, "site-a", 1, "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "local", "local/1", "strategy/1", "sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a",
    "sha256:2222222222222222222222222222222222222222222222222222222222222222", "sha256:3333333333333333333333333333333333333333333333333333333333333333",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "sha256:4444444444444444444444444444444444444444444444444444444444444444",
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
fn managed_output_for_coordinator(
  request : DispatchRequest,
  column_bytes? : Int = 2,
) -> (
  RemoteExecutionEvidence,
  RemoteManagedOutputSubject,
  RemoteManagedOutputMeasurement,
) {
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
  let holding = remote_output_holding_evidence_cid(
    request, "material-generation-a", 8L,
  ).unwrap()
  commit_dispatch_transition(
    prepare_retain_remote_output(site_record, "material-generation-a", holding).unwrap(),
    true,
  ).unwrap()
  let issuer = register_remote_evidence_issuer(
    site,
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "local",
    "local/1",
    "strategy/1",
    remote_managed_output_evidence_kind(),
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  ).unwrap()
  let measurement = prepare_remote_managed_output_measurement(
    2,
    0,
    0,
    0,
    [2],
    [column_bytes],
    [2],
    [1],
    [0],
    [10],
  ).unwrap()
  let subject = prepare_remote_managed_output_subject(
    dispatch_request_identity(request),
    "material-generation-a",
    holding,
    "sha256:3333333333333333333333333333333333333333333333333333333333333333",
    "sha256:5555555555555555555555555555555555555555555555555555555555555555",
    "sha256:6666666666666666666666666666666666666666666666666666666666666666",
    "sha256:7777777777777777777777777777777777777777777777777777777777777777",
    "sha256:8888888888888888888888888888888888888888888888888888888888888888",
    remote_managed_output_measurement_cid(measurement),
    2,
    8L,
  ).unwrap()
  (
    issue_remote_managed_output_evidence(issuer, site_record, subject).unwrap(),
    subject,
    measurement,
  )
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
  let (evidence, subject, measurement) = managed_output_for_coordinator(request)
  let evidence_only = prepare_coordinator_site_observation(
    record,
    5,
    3,
    2,
    0,
    true,
    false,
    Some(evidence),
  ).unwrap()
  commit_coordinator_dispatch_transition(evidence_only, true).unwrap()
  assert_false(coordinator_completion_evidence_available(record))
  let admitted = prepare_coordinator_managed_output_observation(
    record, 5, 3, 2, 0, true, false, evidence, subject, measurement,
  ).unwrap()
  commit_coordinator_dispatch_transition(admitted, true).unwrap()
  assert_true(coordinator_completion_evidence_available(record))
  assert_true(
    coordinator_managed_output_matches(
      record, request, evidence, subject, measurement,
    ),
  )
  assert_false(
    coordinator_managed_output_matches(
      record,
      coordinator_request("dispatch-foreign", 2),
      evidence,
      subject,
      measurement,
    ),
  )
}

///|
test "Coordinator owns managed observation completeness" {
  let request = coordinator_request("dispatch-completeness", 11)
  let journal = create_coordinator_dispatch_journal("coordinator-a").unwrap()
  let admission = prepare_coordinator_dispatch_intent(journal, request).unwrap()
  let (_, record) = commit_coordinator_dispatch_intent(admission, true).unwrap()
  let (evidence, subject, measurement) = managed_output_for_coordinator(request)
  assert_true(
    prepare_coordinator_observation(
      record,
      5,
      3,
      2,
      0,
      true,
      false,
      Some(evidence),
      Some(subject),
      None,
    )
    is Err(InvalidDispatch),
  )
  assert_true(
    prepare_coordinator_observation(
      record,
      5,
      3,
      2,
      0,
      true,
      false,
      None,
      None,
      Some(measurement),
    )
    is Err(InvalidDispatch),
  )
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
      Some(managed_output_for_coordinator(request).0),
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
      Some(
        managed_output_for_coordinator(coordinator_request("dispatch-b", 2)).0,
      ),
    )
    is Err(InvalidDispatch),
  )
}

///|
test "Coordinator evidence identity is monotonic across reconciliation" {
  let request = coordinator_request("dispatch-a", 1)
  let journal = create_coordinator_dispatch_journal("coordinator-a").unwrap()
  let admission = prepare_coordinator_dispatch_intent(journal, request).unwrap()
  let (_, record) = commit_coordinator_dispatch_intent(admission, true).unwrap()
  let (evidence, subject, measurement) = managed_output_for_coordinator(request)
  commit_coordinator_dispatch_transition(
    prepare_coordinator_managed_output_observation(
      record, 5, 3, 2, 0, true, false, evidence, subject, measurement,
    ).unwrap(),
    true,
  ).unwrap()
  assert_true(coordinator_completion_evidence_available(record))
  commit_coordinator_dispatch_transition(
    prepare_coordinator_site_observation(
      record,
      5,
      3,
      2,
      0,
      true,
      false,
      Some(evidence),
    ).unwrap(),
    true,
  ).unwrap()
  assert_true(coordinator_completion_evidence_available(record))
  let (conflicting_evidence, conflicting_subject, conflicting_measurement) = managed_output_for_coordinator(
    request,
    column_bytes=3,
  )
  assert_true(
    prepare_coordinator_managed_output_observation(
      record, 5, 3, 2, 0, true, false, conflicting_evidence, conflicting_subject,
      conflicting_measurement,
    )
    is Err(StateCollision),
  )
  assert_true(coordinator_completion_evidence_available(record))
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
    restored, 1, 1, -1, -1, -1, -1, false, false, "", "", "",
  ).unwrap()
  assert_eq(coordinator_dispatch_record_state_codes(restored), state)
  assert_false(coordinator_completion_evidence_available(restored))
}
