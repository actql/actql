///|
fn retained_intent_fixture() -> RemoteRetainedInputIntent {
  let request = admit_dispatch_request_json(
    "{\"budget_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"connector_registration\":\"local\",\"connector_revision\":\"local/1\",\"coordinator_authority\":\"coordinator-a\",\"dispatch_id\":\"dispatch-a\",\"evidence_issuer_capability_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"grant_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"input_binding_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"obligations_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"run_definition_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"runtime_bundle_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"site_generation\":1,\"site_key\":\"site-a\",\"strategy_revision\":\"strategy/1\",\"task_attempt\":1,\"task_key\":\"task-a\",\"version\":\"actql-remote-dispatch-request/0.1\"}",
    "sha256:3dd78060f4a610d0b1dbb10afaa65b653ca3f8b964e503cc6a2eb6e4783c21b1",
  ).unwrap()
  prepare_remote_retained_input_intent(request, {
    consumer_input_port: "input-a",
    consumer_logical_cid: "sha256:8888888888888888888888888888888888888888888888888888888888888888",
    consumer_task_key: "task-b",
    destination_grant_cid: "sha256:9999999999999999999999999999999999999999999999999999999999999999",
    producer_evidence_cid: "sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
    producer_logical_cid: "sha256:7777777777777777777777777777777777777777777777777777777777777777",
    producer_output_port: "output-a",
    producer_schema_cid: "sha256:4444444444444444444444444444444444444444444444444444444444444444",
    producer_subject_cid: "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
    route_capability_cid: "sha256:6666666666666666666666666666666666666666666666666666666666666666",
    source_grant_cid: "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    transfer_attempt: "transfer-a",
    transfer_expires_unix_ms: 4102444800000L,
    transfer_max_bytes: 12L,
  }).unwrap()
}

///|
test "retained input intent has an independent canonical preimage" {
  let intent = retained_intent_fixture()
  assert_eq(
    remote_retained_input_intent_identity(intent),
    "sha256:225465a17cee57f61100fcca77dbaff27171f8239dc083ce5d0f54089d1a29df",
  )
  assert_eq(
    remote_retained_input_intent_json(intent),
    "{\"consumer_input_port\":\"input-a\",\"consumer_logical_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"consumer_task_key\":\"task-b\",\"destination_grant_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"dispatch_request_cid\":\"sha256:3dd78060f4a610d0b1dbb10afaa65b653ca3f8b964e503cc6a2eb6e4783c21b1\",\"producer_evidence_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"producer_logical_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"producer_output_port\":\"output-a\",\"producer_schema_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"producer_subject_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"route_capability_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"source_grant_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"transfer_attempt\":\"transfer-a\",\"transfer_expires_unix_ms\":\"4102444800000\",\"transfer_max_bytes\":\"12\",\"version\":\"actql-remote-retained-input-intent/0.1\"}",
  )
  let body = remote_poll_retained_input_plan_json(intent).unwrap()
  assert_eq(
    body, "{\"dispatch_request_cid\":\"sha256:3dd78060f4a610d0b1dbb10afaa65b653ca3f8b964e503cc6a2eb6e4783c21b1\",\"intent_cid\":\"sha256:225465a17cee57f61100fcca77dbaff27171f8239dc083ce5d0f54089d1a29df\",\"intent_json\":\"{\\\"consumer_input_port\\\":\\\"input-a\\\",\\\"consumer_logical_cid\\\":\\\"sha256:8888888888888888888888888888888888888888888888888888888888888888\\\",\\\"consumer_task_key\\\":\\\"task-b\\\",\\\"destination_grant_cid\\\":\\\"sha256:9999999999999999999999999999999999999999999999999999999999999999\\\",\\\"dispatch_request_cid\\\":\\\"sha256:3dd78060f4a610d0b1dbb10afaa65b653ca3f8b964e503cc6a2eb6e4783c21b1\\\",\\\"producer_evidence_cid\\\":\\\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\\\",\\\"producer_logical_cid\\\":\\\"sha256:7777777777777777777777777777777777777777777777777777777777777777\\\",\\\"producer_output_port\\\":\\\"output-a\\\",\\\"producer_schema_cid\\\":\\\"sha256:4444444444444444444444444444444444444444444444444444444444444444\\\",\\\"producer_subject_cid\\\":\\\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\\\",\\\"route_capability_cid\\\":\\\"sha256:6666666666666666666666666666666666666666666666666666666666666666\\\",\\\"source_grant_cid\\\":\\\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\\\",\\\"transfer_attempt\\\":\\\"transfer-a\\\",\\\"transfer_expires_unix_ms\\\":\\\"4102444800000\\\",\\\"transfer_max_bytes\\\":\\\"12\\\",\\\"version\\\":\\\"actql-remote-retained-input-intent/0.1\\\"}\",\"request_json\":\"{\\\"budget_cid\\\":\\\"sha256:3333333333333333333333333333333333333333333333333333333333333333\\\",\\\"connector_registration\\\":\\\"local\\\",\\\"connector_revision\\\":\\\"local/1\\\",\\\"coordinator_authority\\\":\\\"coordinator-a\\\",\\\"dispatch_id\\\":\\\"dispatch-a\\\",\\\"evidence_issuer_capability_cid\\\":\\\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\\\",\\\"grant_cid\\\":\\\"sha256:4444444444444444444444444444444444444444444444444444444444444444\\\",\\\"input_binding_cid\\\":\\\"sha256:1111111111111111111111111111111111111111111111111111111111111111\\\",\\\"obligations_cid\\\":\\\"sha256:2222222222222222222222222222222222222222222222222222222222222222\\\",\\\"run_definition_cid\\\":\\\"sha256:0000000000000000000000000000000000000000000000000000000000000000\\\",\\\"runtime_bundle_cid\\\":\\\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\\\",\\\"site_generation\\\":1,\\\"site_key\\\":\\\"site-a\\\",\\\"strategy_revision\\\":\\\"strategy/1\\\",\\\"task_attempt\\\":1,\\\"task_key\\\":\\\"task-a\\\",\\\"version\\\":\\\"actql-remote-dispatch-request/0.1\\\"}\",\"version\":\"actql-remote-poll-retained-input-plan/0.1\"}",
  )
  let operation = admit_remote_poll_operation_json(body).unwrap()
  assert_true(remote_poll_operation_is_retained_input_plan(operation))
  assert_false(remote_poll_operation_is_output_plan(operation))
  assert_false(remote_poll_operation_is_output(operation))
  assert_false(remote_poll_operation_is_query(operation))
  assert_false(remote_poll_operation_is_release(operation))
  assert_false(remote_poll_operation_is_cancel(operation))
  assert_true(admit_remote_poll_dispatch_json(body) is Err(InvalidDispatch))
}

///|
test "retained input intent rejects body and dispatch substitution" {
  let intent = retained_intent_fixture()
  let body = remote_retained_input_intent_json(intent)
  let request = remote_retained_input_intent_request(intent)
  let cid = remote_retained_input_intent_identity(intent)
  assert_true(
    admit_remote_retained_input_intent_json(
      body.replace(old="task-b", new="task-c"),
      cid,
      request,
    )
    is Err(InvalidDispatch),
  )
  assert_true(
    admit_remote_retained_input_intent_json(
      body,
      cid,
      coordinator_request("foreign-producer", 1),
    )
    is Err(InvalidDispatch),
  )
  let projection = remote_retained_input_intent_projection(intent)
  assert_true(
    prepare_remote_retained_input_intent(request, {
      ..projection,
      consumer_task_key: "task-a",
    })
    is Err(InvalidDispatch),
  )
  assert_true(
    prepare_remote_retained_input_intent(request, {
      ..projection,
      transfer_max_bytes: -1L,
    })
    is Err(InvalidDispatch),
  )
  assert_true(
    prepare_remote_retained_input_intent(request, {
      ..projection,
      transfer_expires_unix_ms: 0L,
    })
    is Err(InvalidDispatch),
  )
}

///|
test "retained input intent roundtrip preserves source string bytes" {
  let original = retained_intent_fixture()
  let request = remote_retained_input_intent_request(original)
  let projection = remote_retained_input_intent_projection(original)
  let decomposed = prepare_remote_retained_input_intent(request, {
    ..projection,
    transfer_attempt: "e\u{301}\r\n",
  }).unwrap()
  let composed = prepare_remote_retained_input_intent(request, {
    ..projection,
    transfer_attempt: "é\n",
  }).unwrap()
  assert_false(
    remote_retained_input_intent_identity(decomposed) ==
    remote_retained_input_intent_identity(composed),
  )
  let admitted = admit_remote_retained_input_intent_json(
    remote_retained_input_intent_json(decomposed),
    remote_retained_input_intent_identity(decomposed),
    request,
  ).unwrap()
  assert_eq(
    remote_retained_input_intent_projection(admitted).transfer_attempt,
    "e\u{301}\r\n",
  )
}

///|
fn retained_plan_fixture() -> (RemoteRetainedInputIntent, String, String) {
  let request = remote_retained_input_intent_request(retained_intent_fixture())
  let intent = admit_remote_retained_input_intent_json(
    "{\"consumer_input_port\":\"input-a\",\"consumer_logical_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"consumer_task_key\":\"task-b\",\"destination_grant_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"dispatch_request_cid\":\"sha256:3dd78060f4a610d0b1dbb10afaa65b653ca3f8b964e503cc6a2eb6e4783c21b1\",\"producer_evidence_cid\":\"sha256:9a93b4e759f3a16052e62069c1ded08c1d7902c095a40cc97223e75cb71b6a0e\",\"producer_logical_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"producer_output_port\":\"output-a\",\"producer_schema_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"producer_subject_cid\":\"sha256:fe48b038cbab169eccf6ce4d9f42a40603b92676724c361878b7a70df5b7a1b7\",\"route_capability_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"source_grant_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"transfer_attempt\":\"transfer-a\",\"transfer_expires_unix_ms\":\"4102444800000\",\"transfer_max_bytes\":\"12\",\"version\":\"actql-remote-retained-input-intent/0.1\"}",
    "sha256:ab435abfaa8cb07430d2f1da3a1eb278d5fa785e801b7e5c10038a2d3d806e61", request,
  ).unwrap()
  (
    intent, "{\"dispatch_request_cid\":\"sha256:3dd78060f4a610d0b1dbb10afaa65b653ca3f8b964e503cc6a2eb6e4783c21b1\",\"evidence_cid\":\"sha256:9a93b4e759f3a16052e62069c1ded08c1d7902c095a40cc97223e75cb71b6a0e\",\"evidence_json\":\"{\\\"connector_registration\\\":\\\"local\\\",\\\"connector_revision\\\":\\\"local/1\\\",\\\"dispatch_request_cid\\\":\\\"sha256:3dd78060f4a610d0b1dbb10afaa65b653ca3f8b964e503cc6a2eb6e4783c21b1\\\",\\\"evidence_kind\\\":\\\"actql.remote.managed-output/0.1\\\",\\\"evidence_subject_cid\\\":\\\"sha256:fe48b038cbab169eccf6ce4d9f42a40603b92676724c361878b7a70df5b7a1b7\\\",\\\"holding_evidence_cid\\\":\\\"sha256:c1cc36df2c7dc31b43f8a4bcf2ac113bcdb0d6c1bc7dc28e1d822bc5d3e5ca8f\\\",\\\"issuer_capability_cid\\\":\\\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\\\",\\\"material_generation\\\":\\\"material-generation-a\\\",\\\"obligations_cid\\\":\\\"sha256:2222222222222222222222222222222222222222222222222222222222222222\\\",\\\"runtime_bundle_cid\\\":\\\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\\\",\\\"site_generation\\\":1,\\\"site_key\\\":\\\"site-a\\\",\\\"strategy_revision\\\":\\\"strategy/1\\\",\\\"version\\\":\\\"actql-remote-execution-evidence/0.1\\\"}\",\"intent_cid\":\"sha256:ab435abfaa8cb07430d2f1da3a1eb278d5fa785e801b7e5c10038a2d3d806e61\",\"physical_manifest_cid\":\"sha256:b5a3a559e3966493f9c9c91688876642cbcd83a9a28609f2a768e77e17b001e2\",\"physical_manifest_json\":\"{\\\"chunks\\\":[{\\\"byte_length\\\":12,\\\"cid\\\":\\\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\\\",\\\"row_count\\\":2}],\\\"codec_contract_cid\\\":\\\"sha256:6666666666666666666666666666666666666666666666666666666666666666\\\",\\\"row_count\\\":2,\\\"schema_contract_cid\\\":\\\"sha256:4444444444444444444444444444444444444444444444444444444444444444\\\",\\\"version\\\":\\\"actql-managed-physical-manifest/0.1\\\",\\\"view_contract_cid\\\":\\\"sha256:5555555555555555555555555555555555555555555555555555555555555555\\\"}\",\"subject_cid\":\"sha256:fe48b038cbab169eccf6ce4d9f42a40603b92676724c361878b7a70df5b7a1b7\",\"subject_json\":\"{\\\"dispatch_request_cid\\\":\\\"sha256:3dd78060f4a610d0b1dbb10afaa65b653ca3f8b964e503cc6a2eb6e4783c21b1\\\",\\\"holding_evidence_cid\\\":\\\"sha256:c1cc36df2c7dc31b43f8a4bcf2ac113bcdb0d6c1bc7dc28e1d822bc5d3e5ca8f\\\",\\\"logical_view_cid\\\":\\\"sha256:5555555555555555555555555555555555555555555555555555555555555555\\\",\\\"managed_profile_cid\\\":\\\"sha256:3333333333333333333333333333333333333333333333333333333333333333\\\",\\\"material_generation\\\":\\\"material-generation-a\\\",\\\"measurement_evidence_cid\\\":\\\"sha256:eecf2bab4ef5dc77dc89eee5b6bcc3c5d75d457d9d28d58fac85d5c0a6306a51\\\",\\\"physical_manifest_cid\\\":\\\"sha256:b5a3a559e3966493f9c9c91688876642cbcd83a9a28609f2a768e77e17b001e2\\\",\\\"representation_codec_cid\\\":\\\"sha256:6666666666666666666666666666666666666666666666666666666666666666\\\",\\\"result_schema_cid\\\":\\\"sha256:4444444444444444444444444444444444444444444444444444444444444444\\\",\\\"retained_bytes\\\":\\\"12\\\",\\\"row_count\\\":2,\\\"version\\\":\\\"actql-remote-managed-output-subject/0.1\\\"}\",\"transfer_request_cid\":\"sha256:78aff1554852902efb6bab94b2e0e0b97f6f5084b333c3329b530ecd81b7004c\",\"transfer_request_json\":\"{\\\"codec_contract_cid\\\":\\\"sha256:6666666666666666666666666666666666666666666666666666666666666666\\\",\\\"coordinator_authority\\\":\\\"coordinator-a\\\",\\\"destination_grant_cid\\\":\\\"sha256:9999999999999999999999999999999999999999999999999999999999999999\\\",\\\"destination_site_generation\\\":1,\\\"destination_site_key\\\":\\\"site-a\\\",\\\"expires_unix_ms\\\":\\\"4102444800000\\\",\\\"max_bytes\\\":\\\"12\\\",\\\"physical_manifest_cid\\\":\\\"sha256:b5a3a559e3966493f9c9c91688876642cbcd83a9a28609f2a768e77e17b001e2\\\",\\\"route\\\":\\\"direct\\\",\\\"route_capability_cid\\\":\\\"sha256:6666666666666666666666666666666666666666666666666666666666666666\\\",\\\"schema_contract_cid\\\":\\\"sha256:4444444444444444444444444444444444444444444444444444444444444444\\\",\\\"source_grant_cid\\\":\\\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\\\",\\\"source_material_generation\\\":\\\"material-generation-a\\\",\\\"source_site_generation\\\":1,\\\"source_site_key\\\":\\\"site-a\\\",\\\"transfer_attempt\\\":\\\"transfer-a\\\",\\\"version\\\":\\\"actql-remote-transfer-request/0.1\\\",\\\"view_contract_cid\\\":\\\"sha256:5555555555555555555555555555555555555555555555555555555555555555\\\"}\",\"version\":\"actql-remote-retained-input-plan/0.1\"}",
    "sha256:487410e2cdb9f081522f18f071d10b3b3ab3282f1cce2b7e825605380659df6c",
  )
}

///|
test "retained plan re-admits independent manifest and evidence preimages" {
  let (intent, body, cid) = retained_plan_fixture()
  let plan = admit_remote_retained_input_plan_json(
    body, cid, intent, 8, 4096, 12L,
  ).unwrap()
  assert_eq(remote_retained_input_plan_json(plan), body)
  assert_eq(remote_retained_input_plan_identity(plan), cid)
  let request = remote_retained_input_plan_transfer(plan)
  assert_eq(
    @transfer.request_cid(request),
    "sha256:78aff1554852902efb6bab94b2e0e0b97f6f5084b333c3329b530ecd81b7004c",
  )
  assert_eq(@transfer.request_journal_key(request), [
    "coordinator-a", "site-a", "1", "transfer-a",
  ])
  assert_true(
    admit_remote_retained_input_plan_json(body, cid, intent, 8, 4096, 11L)
    is Err(InvalidDispatch),
  )
  let foreign = prepare_remote_retained_input_intent(
    remote_retained_input_intent_request(intent),
    {
      ..remote_retained_input_intent_projection(intent),
      transfer_attempt: "another-transfer",
    },
  ).unwrap()
  assert_true(
    admit_remote_retained_input_plan_json(body, cid, foreign, 8, 4096, 12L)
    is Err(InvalidDispatch),
  )
}

///|
test "retained plan refuses a valid Transfer to a different generation" {
  let (intent, body, cid) = retained_plan_fixture()
  let plan = admit_remote_retained_input_plan_json(
    body, cid, intent, 8, 4096, 12L,
  ).unwrap()
  let original = remote_retained_input_plan_transfer(plan)
  let selected = remote_retained_input_intent_projection(intent)
  let request = @transfer.prepare_request(
    "coordinator-a",
    selected.transfer_attempt,
    @transfer.DirectStream,
    "site-a",
    1,
    "site-a",
    2,
    "material-generation-a",
    @transfer.request_manifest(original),
    selected.transfer_max_bytes,
    selected.transfer_expires_unix_ms,
    selected.source_grant_cid,
    selected.destination_grant_cid,
    selected.route_capability_cid,
  ).unwrap()
  assert_true(
    prepare_remote_retained_input_plan(
      intent,
      plan.subject,
      plan.evidence,
      request,
    )
    is Err(InvalidDispatch),
  )
}
