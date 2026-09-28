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
    "namespace-a",
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
fn committed_content_test_index(
  attempt_cid : String,
  receipt_cid : String,
  binding_cid : String,
  committed_at : String,
) -> PublicationContract {
  let common = ordering_test_cid("1")
  let body = "{\"version\":\"actql-public-index-entry/0.1\"," +
    "\"namespace_id\":\"namespace-a\",\"authority_scope_cid\":\"" +
    common +
    "\",\"run_definition_cid\":\"" +
    common +
    "\",\"invocation_cid\":\"" +
    common +
    "\",\"result_manifest_cid\":\"" +
    common +
    "\",\"run_receipt_cid\":\"" +
    receipt_cid +
    "\",\"captured_run_cid\":\"" +
    common +
    "\",\"durable_result_binding_cids\":[\"" +
    binding_cid +
    "\"],\"publication_request_cid\":\"" +
    common +
    "\",\"publication_attempt_cid\":\"" +
    attempt_cid +
    "\",\"committed_at\":\"" +
    committed_at +
    "\"}"
  seal_publication_contract("public_index_entry", body, 8192, 256, 12).unwrap()
}

///|
test "commit retries cannot relabel final receipt or Result custody" {
  let first = committed_content_test_index(
    ordering_test_cid("2"),
    ordering_test_cid("3"),
    ordering_test_cid("4"),
    "2026-09-18T00:00:00.000Z",
  )
  let retry = committed_content_test_index(
    ordering_test_cid("5"),
    ordering_test_cid("3"),
    ordering_test_cid("4"),
    "2026-09-18T00:01:00.000Z",
  )
  assert_true(public_index_same_committed_content(first, retry))
  assert_true(
    !public_index_same_committed_content(
      first,
      committed_content_test_index(
        ordering_test_cid("5"),
        ordering_test_cid("6"),
        ordering_test_cid("4"),
        "2026-09-18T00:01:00.000Z",
      ),
    ),
  )
  assert_true(
    !public_index_same_committed_content(
      first,
      committed_content_test_index(
        ordering_test_cid("5"),
        ordering_test_cid("3"),
        ordering_test_cid("6"),
        "2026-09-18T00:01:00.000Z",
      ),
    ),
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
      "namespace-a",
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
    "namespace-a",
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
test "public index storage key fixes one commit per scoped Run" {
  let (index, _, _) = delivery_test_root()
  let key = publication_index_storage_key(index, 32768, 256, 16).unwrap()
  assert_eq(key.length(), 64)
  assert_eq(
    publication_index_scope_storage_key(
      "namespace_id",
      delivery_test_cid("4"),
      delivery_test_cid("3"),
      32768,
      256,
      16,
    ).unwrap(),
    key,
  )
  assert_true(
    publication_index_scope_storage_key(
      "namespace_id",
      delivery_test_cid("4"),
      delivery_test_cid("0"),
      32768,
      256,
      16,
    ).unwrap() !=
    key,
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
    "namespace-a",
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
  let early_metadata_deletion = seal_publication_contract(
    "result_retention_policy",
    "{\"version\":\"actql-result-retention-policy/0.1\"," +
    "\"retention_contract_cid\":\"" +
    ordering_test_cid("5") +
    "\",\"effective_data_policy_cid\":\"" +
    ordering_test_cid("7") +
    "\",\"available_until\":\"2026-09-18T01:00:00.000Z\"," +
    "\"delete_by\":\"2026-09-18T03:00:00.000Z\"," +
    "\"extension_ceiling_at\":\"2026-09-18T03:00:00.000Z\"," +
    "\"metadata_retention_policy_cid\":\"" +
    ordering_test_cid("6") +
    "\",\"metadata_delete_by\":\"2026-09-18T02:00:00.000Z\"," +
    "\"clock_contract_cid\":\"" +
    ordering_test_cid("7") +
    "\"}",
    8192,
    64,
    5,
  ).unwrap()
  assert_false(
    publication_preflight_valid(
      admission,
      run,
      invocation,
      [first, second],
      [early_metadata_deletion, early_metadata_deletion],
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
  let different_metadata_schedule = seal_publication_contract(
    "result_retention_policy",
    "{\"version\":\"actql-result-retention-policy/0.1\"," +
    "\"retention_contract_cid\":\"" +
    ordering_test_cid("5") +
    "\",\"effective_data_policy_cid\":\"" +
    ordering_test_cid("7") +
    "\",\"available_until\":\"2026-09-18T01:00:00.000Z\"," +
    "\"delete_by\":\"2026-09-18T02:00:00.000Z\"," +
    "\"extension_ceiling_at\":\"2026-09-18T03:00:00.000Z\"," +
    "\"metadata_retention_policy_cid\":\"" +
    ordering_test_cid("a") +
    "\",\"metadata_delete_by\":\"2026-09-18T05:00:00.000Z\"," +
    "\"clock_contract_cid\":\"" +
    ordering_test_cid("7") +
    "\"}",
    8192,
    64,
    5,
  ).unwrap()
  assert_false(
    publication_preflight_valid(
      admission,
      run,
      invocation,
      [first, second],
      [retention, different_metadata_schedule],
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
    "namespace-a",
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
