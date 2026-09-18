///|
test "publication request and attempt are issued from admitted intent" {
  let template = ordering_test_cid("1")
  let run = manifest_test_run(template)
  let first = result_definition_contract(
    prepare_result_definition(ordering_test_cid("2"), "zeta").unwrap(),
  )
  let second = result_definition_contract(
    prepare_result_definition(ordering_test_cid("2"), "answer").unwrap(),
  )
  let request = issue_publication_request(
    run,
    [first, second],
    "tenant-a",
    ordering_test_cid("3"),
    ordering_test_cid("4"),
    ordering_test_cid("5"),
    "2026-09-18T00:00:00.000Z",
    32768,
    256,
    8,
  ).unwrap()
  let expected_inventory = "\"inventory\":[{" +
    "\"result_definition_cid\":\"" +
    publication_contract_identity(second) +
    "\",\"result_name\":\"answer\"},{" +
    "\"result_definition_cid\":\"" +
    publication_contract_identity(first) +
    "\",\"result_name\":\"zeta\"}]"
  assert_true(publication_contract_json(request).contains(expected_inventory))
  let attempt = issue_publication_attempt(
    request,
    run,
    "attempt-1",
    ordering_test_cid("6"),
    Some("retry-key"),
    "2026-09-18T00:00:01.000Z",
    16384,
    128,
    6,
  ).unwrap()
  let attempt_wire = publication_contract_json(attempt)
  assert_true(
    attempt_wire.contains(
      "\"publication_request_cid\":\"" +
      publication_contract_identity(request) +
      "\"",
    ),
  )
  assert_true(attempt_wire.contains("\"attempt_id\":\"attempt-1\""))
  assert_true(!attempt_wire.contains("\"state\""))
  let preparing = issue_publication_record(
    attempt,
    None,
    "preparing",
    "2026-09-18T00:00:02.000Z",
    None,
    None,
    [ordering_test_cid("8"), ordering_test_cid("7")],
    false,
    16384,
    128,
    6,
  ).unwrap()
  let preparing_wire = publication_contract_json(preparing)
  assert_true(preparing_wire.contains("\"sequence\":0"))
  assert_true(
    preparing_wire.contains(
      "\"cleanup_owner_cids\":[\"" +
      ordering_test_cid("7") +
      "\",\"" +
      ordering_test_cid("8") +
      "\"]",
    ),
  )
  let committing = issue_publication_record(
    attempt,
    Some(preparing),
    "committing",
    "2026-09-18T00:00:03.000Z",
    None,
    None,
    [],
    false,
    16384,
    128,
    6,
  ).unwrap()
  assert_true(publication_contract_json(committing).contains("\"sequence\":1"))
  assert_true(
    issue_publication_record(
      attempt,
      Some(committing),
      "failed",
      "2026-09-18T00:00:04.000Z",
      None,
      Some(ordering_test_cid("9")),
      [],
      false,
      16384,
      128,
      6,
    )
    is Err(CommitIssuanceReferenceMismatch("state_transition")),
  )
}

///|
test "publication issuance rejects empty inventories and foreign Runs" {
  let run = manifest_test_run(ordering_test_cid("1"))
  let definition = result_definition_contract(
    prepare_result_definition(ordering_test_cid("2"), "answer").unwrap(),
  )
  assert_true(
    issue_publication_request(
      run,
      [],
      "tenant-a",
      ordering_test_cid("3"),
      ordering_test_cid("4"),
      ordering_test_cid("5"),
      "2026-09-18T00:00:00.000Z",
      32768,
      256,
      8,
    )
    is Err(CommitIssuanceEmptyInventory),
  )
  let request = issue_publication_request(
    run,
    [definition],
    "tenant-a",
    ordering_test_cid("3"),
    ordering_test_cid("4"),
    ordering_test_cid("5"),
    "2026-09-18T00:00:00.000Z",
    32768,
    256,
    8,
  ).unwrap()
  let foreign = manifest_test_run(ordering_test_cid("6"))
  assert_true(
    issue_publication_attempt(
      request,
      foreign,
      "attempt-1",
      ordering_test_cid("7"),
      None,
      "2026-09-18T00:00:01.000Z",
      16384,
      128,
      6,
    )
    is Err(CommitIssuanceReferenceMismatch("run_definition_cid")),
  )
}

///|
test "publication preflight fixes the complete immutable inventory" {
  let program = ordering_test_cid("2")
  let template = receipt_test_template(program)
  let admission = receipt_test_admission(template, program)
  let run = issue_run_definition(
    admission,
    "scope-a",
    "run-a",
    ordering_test_cid("a"),
    "2026-09-18T00:00:00.000Z",
    "2026-09-18T04:00:00.000Z",
    65536,
    1024,
    12,
  ).unwrap()
  let invocation = issue_run_invocation(
    template,
    receipt_test_observation(template),
    65536,
    1024,
    12,
  ).unwrap()
  let first = result_definition_contract(
    prepare_result_definition(ordering_test_cid("2"), "answer").unwrap(),
  )
  let second = result_definition_contract(
    prepare_result_definition(ordering_test_cid("2"), "summary").unwrap(),
  )
  let request = issue_publication_request(
    run,
    [first, second],
    "tenant-a",
    ordering_test_cid("3"),
    ordering_test_cid("4"),
    ordering_test_cid("5"),
    "2026-09-18T00:00:00.000Z",
    32768,
    256,
    8,
  ).unwrap()
  let attempt = issue_publication_attempt(
    request,
    run,
    "attempt-1",
    ordering_test_cid("6"),
    None,
    "2026-09-18T00:00:01.000Z",
    16384,
    128,
    6,
  ).unwrap()
  let retention = manifest_test_retention(ordering_test_cid("7"))
  let computations = [ordering_test_cid("8"), ordering_test_cid("8")]
  let inputs : Array[Array[String]] = [[], []]
  let scopes = [ordering_test_cid("9"), ordering_test_cid("9")]
  let policies = [ordering_test_cid("7"), ordering_test_cid("7")]
  let authorities = [ordering_test_cid("3"), ordering_test_cid("3")]
  assert_true(
    publication_preflight_valid(
      admission,
      run,
      invocation,
      [first, second],
      [retention, retention],
      computations,
      inputs,
      scopes,
      policies,
      authorities,
      request,
      attempt,
      ordering_test_cid("2"),
    ),
  )
  assert_true(
    !publication_preflight_valid(
      admission,
      run,
      invocation,
      [first, second],
      [retention],
      computations,
      inputs,
      scopes,
      policies,
      authorities,
      request,
      attempt,
      ordering_test_cid("2"),
    ),
  )
  assert_true(
    !publication_preflight_valid(
      admission,
      run,
      manifest_test_invocation(ordering_test_cid("8")),
      [first, second],
      [retention, retention],
      computations,
      inputs,
      scopes,
      policies,
      authorities,
      request,
      attempt,
      ordering_test_cid("2"),
    ),
  )
  let incomplete_request = issue_publication_request(
    run,
    [first],
    "tenant-a",
    ordering_test_cid("3"),
    ordering_test_cid("4"),
    ordering_test_cid("5"),
    "2026-09-18T00:00:00.000Z",
    32768,
    256,
    8,
  ).unwrap()
  let incomplete_attempt = issue_publication_attempt(
    incomplete_request,
    run,
    "attempt-2",
    ordering_test_cid("6"),
    None,
    "2026-09-18T00:00:01.000Z",
    16384,
    128,
    6,
  ).unwrap()
  assert_true(
    !publication_preflight_valid(
      admission,
      run,
      invocation,
      [first, second],
      [retention, retention],
      computations,
      inputs,
      scopes,
      policies,
      authorities,
      incomplete_request,
      incomplete_attempt,
      ordering_test_cid("2"),
    ),
  )
  assert_true(
    !publication_preflight_valid(
      admission,
      run,
      invocation,
      [first, second],
      [retention, retention],
      computations,
      inputs,
      scopes,
      policies,
      authorities,
      request,
      attempt,
      ordering_test_cid("9"),
    ),
  )
  assert_true(
    !publication_preflight_valid(
      admission,
      run,
      invocation,
      [first, second],
      [retention, retention],
      computations,
      inputs,
      scopes,
      [ordering_test_cid("0"), ordering_test_cid("7")],
      authorities,
      request,
      attempt,
      ordering_test_cid("2"),
    ),
  )
  assert_true(
    !publication_preflight_valid(
      admission,
      run,
      invocation,
      [first, second],
      [retention, retention],
      computations,
      inputs,
      scopes,
      policies,
      [ordering_test_cid("0"), ordering_test_cid("3")],
      request,
      attempt,
      ordering_test_cid("2"),
    ),
  )
  let foreign_template = receipt_test_template(ordering_test_cid("b"))
  let foreign_admission = receipt_test_admission(
    foreign_template,
    ordering_test_cid("b"),
  )
  assert_true(
    !publication_preflight_valid(
      foreign_admission,
      run,
      invocation,
      [first, second],
      [retention, retention],
      computations,
      inputs,
      scopes,
      policies,
      authorities,
      request,
      attempt,
      ordering_test_cid("2"),
    ),
  )
}
