///|
fn effect_current_poll_fixture() -> (RemoteEffectCurrentQuery, String) {
  let (report, _, _, _, _) = effect_resume_fixture()
  let query = prepare_remote_effect_current_query(
    report,
    "write-1",
    "query-original",
    { ..review_limits(), max_wire_bytes: 65536, },
  ).unwrap()
  (
    query, "{\"dispatch_request_cid\":\"sha256:3b5d3a0baae35a4c3ed4f9d3a9bbf3bab875cdb325db11b18ea8b5dd1af04f93\",\"query_json\":\"{\\\"checkpoint_cid\\\":\\\"sha256:5f519ab12d76e539039de72a94b1b2f337654c8741ea17cee0266231a56ec10d\\\",\\\"dispatch_request_cid\\\":\\\"sha256:3b5d3a0baae35a4c3ed4f9d3a9bbf3bab875cdb325db11b18ea8b5dd1af04f93\\\",\\\"effect_id\\\":\\\"write-1\\\",\\\"query_id\\\":\\\"query-original\\\",\\\"report_cid\\\":\\\"sha256:31bcdabc6df955bda9b2f862d7a8ef59554b566b19ca4a3406ba13a861d85996\\\",\\\"version\\\":\\\"actql-remote-effect-current-query/0.1\\\"}\",\"request_json\":\"{\\\"budget_cid\\\":\\\"sha256:3333333333333333333333333333333333333333333333333333333333333333\\\",\\\"connector_registration\\\":\\\"local\\\",\\\"connector_revision\\\":\\\"local/1\\\",\\\"coordinator_authority\\\":\\\"coordinator-a\\\",\\\"dispatch_id\\\":\\\"consumer-a\\\",\\\"evidence_issuer_capability_cid\\\":\\\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\\\",\\\"grant_cid\\\":\\\"sha256:4444444444444444444444444444444444444444444444444444444444444444\\\",\\\"input_binding_cid\\\":\\\"sha256:1111111111111111111111111111111111111111111111111111111111111111\\\",\\\"obligations_cid\\\":\\\"sha256:2222222222222222222222222222222222222222222222222222222222222222\\\",\\\"run_definition_cid\\\":\\\"sha256:0000000000000000000000000000000000000000000000000000000000000000\\\",\\\"runtime_bundle_cid\\\":\\\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\\\",\\\"site_generation\\\":1,\\\"site_key\\\":\\\"site-a\\\",\\\"strategy_revision\\\":\\\"strategy/1\\\",\\\"task_attempt\\\":1,\\\"task_key\\\":\\\"task-a\\\",\\\"version\\\":\\\"actql-remote-dispatch-request/0.1\\\"}\",\"version\":\"actql-remote-poll-effect-current/0.1\"}",
  )
}

///|
test "Effect current poll retains exact query without dispatch or resume authority" {
  let (query, fixed) = effect_current_poll_fixture()
  assert_eq(remote_poll_effect_current_json(query), Ok(fixed))
  let operation = admit_remote_poll_operation_json(fixed).unwrap()
  assert_true(remote_poll_operation_is_effect_current(operation))
  assert_false(remote_poll_operation_is_effect_resume(operation))
  assert_false(remote_poll_operation_is_query(operation))
  assert_false(remote_poll_operation_is_output(operation))
  assert_false(remote_poll_operation_is_release(operation))
  assert_false(remote_poll_operation_is_cancel(operation))
  let routed = admit_remote_poll_effect_current_json(fixed).unwrap()
  assert_eq(remote_poll_effect_current_envelope_json(routed), Ok(fixed))
  assert_eq(
    dispatch_request_identity(remote_poll_effect_current_request(routed)),
    dispatch_request_identity(
      remote_effect_checkpoint_report_dispatch(
        remote_effect_current_query_report(query),
      ),
    ),
  )
  assert_eq(
    remote_poll_effect_current_query_json(routed),
    remote_effect_current_query_json(query),
  )
}

///|
test "Effect current poll rejects substituted dispatch and noncanonical query" {
  let (_, fixed) = effect_current_poll_fixture()
  for
    body in [
      fixed + " ",
      fixed.replace(old="query-original", new=""),
      fixed.replace(
        old="{\"dispatch_request_cid\"",
        new="{\"extra\":\"value\",\"dispatch_request_cid\"",
      ),
      fixed.replace(
        old="sha256:3b5d3a0baae35a4c3ed4f9d3a9bbf3bab875cdb325db11b18ea8b5dd1af04f93",
        new="sha256:0000000000000000000000000000000000000000000000000000000000000000",
      ),
      "x".repeat(131073),
    ] {
    assert_true(
      admit_remote_poll_effect_current_json(body) is Err(InvalidDispatch),
    )
  }
}

///|
test "Effect current routing cannot adopt a substituted holder report" {
  let (_, fixed) = effect_current_poll_fixture()
  let (report, _, _, _, _) = effect_resume_fixture()
  let changed = fixed.replace(
    old="sha256:31bcdabc6df955bda9b2f862d7a8ef59554b566b19ca4a3406ba13a861d85996",
    new="sha256:0000000000000000000000000000000000000000000000000000000000000000",
  )
  let routed = admit_remote_poll_effect_current_json(changed).unwrap()
  // Re-emission preserves the untrusted routing input; it cannot turn it
  // into evidence for the receiving holder's original report.
  assert_eq(remote_poll_effect_current_envelope_json(routed), Ok(changed))
  assert_true(
    admit_remote_effect_current_query_json(
      remote_poll_effect_current_query_json(routed),
      report,
      { ..review_limits(), max_wire_bytes: 65536, },
    )
    is Err(InvalidDispatch),
  )
}
