///|
fn retained_handoff_fixture() -> (
  RemoteRetainedInputPlan,
  String,
  String,
  String,
) {
  let (intent, body, cid) = retained_plan_fixture()
  let plan = admit_remote_retained_input_plan_json(
    body, cid, intent, 8, 4096, 12L,
  ).unwrap()
  (
    plan, "{\"dispatch_request_cid\":\"sha256:3dd78060f4a610d0b1dbb10afaa65b653ca3f8b964e503cc6a2eb6e4783c21b1\",\"intent_cid\":\"sha256:ab435abfaa8cb07430d2f1da3a1eb278d5fa785e801b7e5c10038a2d3d806e61\",\"intent_json\":\"{\\\"consumer_input_port\\\":\\\"input-a\\\",\\\"consumer_logical_cid\\\":\\\"sha256:8888888888888888888888888888888888888888888888888888888888888888\\\",\\\"consumer_task_key\\\":\\\"task-b\\\",\\\"destination_grant_cid\\\":\\\"sha256:9999999999999999999999999999999999999999999999999999999999999999\\\",\\\"dispatch_request_cid\\\":\\\"sha256:3dd78060f4a610d0b1dbb10afaa65b653ca3f8b964e503cc6a2eb6e4783c21b1\\\",\\\"producer_evidence_cid\\\":\\\"sha256:9a93b4e759f3a16052e62069c1ded08c1d7902c095a40cc97223e75cb71b6a0e\\\",\\\"producer_logical_cid\\\":\\\"sha256:7777777777777777777777777777777777777777777777777777777777777777\\\",\\\"producer_output_port\\\":\\\"output-a\\\",\\\"producer_schema_cid\\\":\\\"sha256:4444444444444444444444444444444444444444444444444444444444444444\\\",\\\"producer_subject_cid\\\":\\\"sha256:fe48b038cbab169eccf6ce4d9f42a40603b92676724c361878b7a70df5b7a1b7\\\",\\\"route_capability_cid\\\":\\\"sha256:6666666666666666666666666666666666666666666666666666666666666666\\\",\\\"source_grant_cid\\\":\\\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\\\",\\\"transfer_attempt\\\":\\\"transfer-a\\\",\\\"transfer_expires_unix_ms\\\":\\\"4102444800000\\\",\\\"transfer_max_bytes\\\":\\\"12\\\",\\\"version\\\":\\\"actql-remote-retained-input-intent/0.1\\\"}\",\"plan_cid\":\"sha256:487410e2cdb9f081522f18f071d10b3b3ab3282f1cce2b7e825605380659df6c\",\"plan_json\":\"{\\\"dispatch_request_cid\\\":\\\"sha256:3dd78060f4a610d0b1dbb10afaa65b653ca3f8b964e503cc6a2eb6e4783c21b1\\\",\\\"evidence_cid\\\":\\\"sha256:9a93b4e759f3a16052e62069c1ded08c1d7902c095a40cc97223e75cb71b6a0e\\\",\\\"evidence_json\\\":\\\"{\\\\\\\"connector_registration\\\\\\\":\\\\\\\"local\\\\\\\",\\\\\\\"connector_revision\\\\\\\":\\\\\\\"local/1\\\\\\\",\\\\\\\"dispatch_request_cid\\\\\\\":\\\\\\\"sha256:3dd78060f4a610d0b1dbb10afaa65b653ca3f8b964e503cc6a2eb6e4783c21b1\\\\\\\",\\\\\\\"evidence_kind\\\\\\\":\\\\\\\"actql.remote.managed-output/0.1\\\\\\\",\\\\\\\"evidence_subject_cid\\\\\\\":\\\\\\\"sha256:fe48b038cbab169eccf6ce4d9f42a40603b92676724c361878b7a70df5b7a1b7\\\\\\\",\\\\\\\"holding_evidence_cid\\\\\\\":\\\\\\\"sha256:c1cc36df2c7dc31b43f8a4bcf2ac113bcdb0d6c1bc7dc28e1d822bc5d3e5ca8f\\\\\\\",\\\\\\\"issuer_capability_cid\\\\\\\":\\\\\\\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\\\\\\\",\\\\\\\"material_generation\\\\\\\":\\\\\\\"material-generation-a\\\\\\\",\\\\\\\"obligations_cid\\\\\\\":\\\\\\\"sha256:2222222222222222222222222222222222222222222222222222222222222222\\\\\\\",\\\\\\\"runtime_bundle_cid\\\\\\\":\\\\\\\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\\\\\\\",\\\\\\\"site_generation\\\\\\\":1,\\\\\\\"site_key\\\\\\\":\\\\\\\"site-a\\\\\\\",\\\\\\\"strategy_revision\\\\\\\":\\\\\\\"strategy/1\\\\\\\",\\\\\\\"version\\\\\\\":\\\\\\\"actql-remote-execution-evidence/0.1\\\\\\\"}\\\",\\\"intent_cid\\\":\\\"sha256:ab435abfaa8cb07430d2f1da3a1eb278d5fa785e801b7e5c10038a2d3d806e61\\\",\\\"physical_manifest_cid\\\":\\\"sha256:b5a3a559e3966493f9c9c91688876642cbcd83a9a28609f2a768e77e17b001e2\\\",\\\"physical_manifest_json\\\":\\\"{\\\\\\\"chunks\\\\\\\":[{\\\\\\\"byte_length\\\\\\\":12,\\\\\\\"cid\\\\\\\":\\\\\\\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\\\\\\\",\\\\\\\"row_count\\\\\\\":2}],\\\\\\\"codec_contract_cid\\\\\\\":\\\\\\\"sha256:6666666666666666666666666666666666666666666666666666666666666666\\\\\\\",\\\\\\\"row_count\\\\\\\":2,\\\\\\\"schema_contract_cid\\\\\\\":\\\\\\\"sha256:4444444444444444444444444444444444444444444444444444444444444444\\\\\\\",\\\\\\\"version\\\\\\\":\\\\\\\"actql-managed-physical-manifest/0.1\\\\\\\",\\\\\\\"view_contract_cid\\\\\\\":\\\\\\\"sha256:5555555555555555555555555555555555555555555555555555555555555555\\\\\\\"}\\\",\\\"subject_cid\\\":\\\"sha256:fe48b038cbab169eccf6ce4d9f42a40603b92676724c361878b7a70df5b7a1b7\\\",\\\"subject_json\\\":\\\"{\\\\\\\"dispatch_request_cid\\\\\\\":\\\\\\\"sha256:3dd78060f4a610d0b1dbb10afaa65b653ca3f8b964e503cc6a2eb6e4783c21b1\\\\\\\",\\\\\\\"holding_evidence_cid\\\\\\\":\\\\\\\"sha256:c1cc36df2c7dc31b43f8a4bcf2ac113bcdb0d6c1bc7dc28e1d822bc5d3e5ca8f\\\\\\\",\\\\\\\"logical_view_cid\\\\\\\":\\\\\\\"sha256:5555555555555555555555555555555555555555555555555555555555555555\\\\\\\",\\\\\\\"managed_profile_cid\\\\\\\":\\\\\\\"sha256:3333333333333333333333333333333333333333333333333333333333333333\\\\\\\",\\\\\\\"material_generation\\\\\\\":\\\\\\\"material-generation-a\\\\\\\",\\\\\\\"measurement_evidence_cid\\\\\\\":\\\\\\\"sha256:eecf2bab4ef5dc77dc89eee5b6bcc3c5d75d457d9d28d58fac85d5c0a6306a51\\\\\\\",\\\\\\\"physical_manifest_cid\\\\\\\":\\\\\\\"sha256:b5a3a559e3966493f9c9c91688876642cbcd83a9a28609f2a768e77e17b001e2\\\\\\\",\\\\\\\"representation_codec_cid\\\\\\\":\\\\\\\"sha256:6666666666666666666666666666666666666666666666666666666666666666\\\\\\\",\\\\\\\"result_schema_cid\\\\\\\":\\\\\\\"sha256:4444444444444444444444444444444444444444444444444444444444444444\\\\\\\",\\\\\\\"retained_bytes\\\\\\\":\\\\\\\"12\\\\\\\",\\\\\\\"row_count\\\\\\\":2,\\\\\\\"version\\\\\\\":\\\\\\\"actql-remote-managed-output-subject/0.1\\\\\\\"}\\\",\\\"transfer_request_cid\\\":\\\"sha256:78aff1554852902efb6bab94b2e0e0b97f6f5084b333c3329b530ecd81b7004c\\\",\\\"transfer_request_json\\\":\\\"{\\\\\\\"codec_contract_cid\\\\\\\":\\\\\\\"sha256:6666666666666666666666666666666666666666666666666666666666666666\\\\\\\",\\\\\\\"coordinator_authority\\\\\\\":\\\\\\\"coordinator-a\\\\\\\",\\\\\\\"destination_grant_cid\\\\\\\":\\\\\\\"sha256:9999999999999999999999999999999999999999999999999999999999999999\\\\\\\",\\\\\\\"destination_site_generation\\\\\\\":1,\\\\\\\"destination_site_key\\\\\\\":\\\\\\\"site-a\\\\\\\",\\\\\\\"expires_unix_ms\\\\\\\":\\\\\\\"4102444800000\\\\\\\",\\\\\\\"max_bytes\\\\\\\":\\\\\\\"12\\\\\\\",\\\\\\\"physical_manifest_cid\\\\\\\":\\\\\\\"sha256:b5a3a559e3966493f9c9c91688876642cbcd83a9a28609f2a768e77e17b001e2\\\\\\\",\\\\\\\"route\\\\\\\":\\\\\\\"direct\\\\\\\",\\\\\\\"route_capability_cid\\\\\\\":\\\\\\\"sha256:6666666666666666666666666666666666666666666666666666666666666666\\\\\\\",\\\\\\\"schema_contract_cid\\\\\\\":\\\\\\\"sha256:4444444444444444444444444444444444444444444444444444444444444444\\\\\\\",\\\\\\\"source_grant_cid\\\\\\\":\\\\\\\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\\\\\\\",\\\\\\\"source_material_generation\\\\\\\":\\\\\\\"material-generation-a\\\\\\\",\\\\\\\"source_site_generation\\\\\\\":1,\\\\\\\"source_site_key\\\\\\\":\\\\\\\"site-a\\\\\\\",\\\\\\\"transfer_attempt\\\\\\\":\\\\\\\"transfer-a\\\\\\\",\\\\\\\"version\\\\\\\":\\\\\\\"actql-remote-transfer-request/0.1\\\\\\\",\\\\\\\"view_contract_cid\\\\\\\":\\\\\\\"sha256:5555555555555555555555555555555555555555555555555555555555555555\\\\\\\"}\\\",\\\"version\\\":\\\"actql-remote-retained-input-plan/0.1\\\"}\",\"request_json\":\"{\\\"budget_cid\\\":\\\"sha256:3333333333333333333333333333333333333333333333333333333333333333\\\",\\\"connector_registration\\\":\\\"local\\\",\\\"connector_revision\\\":\\\"local/1\\\",\\\"coordinator_authority\\\":\\\"coordinator-a\\\",\\\"dispatch_id\\\":\\\"dispatch-a\\\",\\\"evidence_issuer_capability_cid\\\":\\\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\\\",\\\"grant_cid\\\":\\\"sha256:4444444444444444444444444444444444444444444444444444444444444444\\\",\\\"input_binding_cid\\\":\\\"sha256:1111111111111111111111111111111111111111111111111111111111111111\\\",\\\"obligations_cid\\\":\\\"sha256:2222222222222222222222222222222222222222222222222222222222222222\\\",\\\"run_definition_cid\\\":\\\"sha256:0000000000000000000000000000000000000000000000000000000000000000\\\",\\\"runtime_bundle_cid\\\":\\\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\\\",\\\"site_generation\\\":1,\\\"site_key\\\":\\\"site-a\\\",\\\"strategy_revision\\\":\\\"strategy/1\\\",\\\"task_attempt\\\":1,\\\"task_key\\\":\\\"task-a\\\",\\\"version\\\":\\\"actql-remote-dispatch-request/0.1\\\"}\",\"version\":\"actql-remote-poll-retained-input-transfer/0.1\"}",
    "{\"destination_receipt_cid\":\"sha256:932408b963f5ee333a6af487edaa6d8c6f6450a124651d732dad85c133b8aac0\",\"destination_receipt_json\":\"{\\\"destination_grant_cid\\\":\\\"sha256:9999999999999999999999999999999999999999999999999999999999999999\\\",\\\"destination_material_generation\\\":\\\"destination-generation-a\\\",\\\"destination_site_generation\\\":1,\\\"destination_site_key\\\":\\\"site-a\\\",\\\"physical_manifest_cid\\\":\\\"sha256:b5a3a559e3966493f9c9c91688876642cbcd83a9a28609f2a768e77e17b001e2\\\",\\\"request_cid\\\":\\\"sha256:78aff1554852902efb6bab94b2e0e0b97f6f5084b333c3329b530ecd81b7004c\\\",\\\"version\\\":\\\"actql-remote-transfer-destination-receipt/0.1\\\"}\",\"dispatch_request_cid\":\"sha256:3dd78060f4a610d0b1dbb10afaa65b653ca3f8b964e503cc6a2eb6e4783c21b1\",\"intent_cid\":\"sha256:ab435abfaa8cb07430d2f1da3a1eb278d5fa785e801b7e5c10038a2d3d806e61\",\"plan_cid\":\"sha256:487410e2cdb9f081522f18f071d10b3b3ab3282f1cce2b7e825605380659df6c\",\"transfer_reply_json\":\"{\\\"requestCid\\\":\\\"sha256:78aff1554852902efb6bab94b2e0e0b97f6f5084b333c3329b530ecd81b7004c\\\",\\\"state\\\":[3,2,0,1,0,1,1,1,1]}\",\"transfer_request_cid\":\"sha256:78aff1554852902efb6bab94b2e0e0b97f6f5084b333c3329b530ecd81b7004c\",\"version\":\"actql-remote-retained-input-result/0.1\"}",
    "sha256:20c27340e3b79e96803b355eeb0a2a4cfae38b5372bbed39c678e5e2b65d30ce",
  )
}

///|
test "retained handoff transports the independent original plan and never executable work" {
  let (plan, poll_body, _, _) = retained_handoff_fixture()
  assert_eq(remote_poll_retained_input_transfer_json(plan), Ok(poll_body))
  let operation = admit_remote_poll_operation_json(poll_body).unwrap()
  assert_true(remote_poll_operation_is_retained_input_transfer(operation))
  assert_false(remote_poll_operation_is_retained_input_plan(operation))
  assert_false(remote_poll_operation_is_output(operation))
  assert_false(remote_poll_operation_is_release(operation))
  assert_eq(
    dispatch_request_identity(remote_poll_operation_request(operation)),
    dispatch_request_identity(plan.intent.request),
  )
  let admitted = admit_remote_poll_retained_input_transfer_json(poll_body).unwrap()
  assert_eq(
    remote_retained_input_plan_identity(
      remote_poll_retained_transfer_plan(admitted),
    ),
    plan.cid,
  )
  assert_true(
    admit_remote_poll_retained_input_transfer_json(poll_body + " ")
    is Err(InvalidDispatch),
  )
  assert_true(
    admit_remote_poll_retained_input_transfer_json(
      poll_body.replace(old="task-b", new="task-c"),
    )
    is Err(InvalidDispatch),
  )
  assert_true(
    admit_remote_poll_retained_input_transfer_json(
      poll_body.replace(old="\"plan_cid\":\"", new="\"plan_cid\":\"x"),
    )
    is Err(InvalidDispatch),
  )
}

///|
test "retained result requires exact committed receiver and matches independent state preimage" {
  let (plan, _, expected, expected_cid) = retained_handoff_fixture()
  let request = plan.transfer
  let record = @transfer.open_record(request)
  let receipt = @transfer.prepare_destination_receipt(
    request, "destination-generation-a",
  ).unwrap()
  assert_true(
    prepare_remote_retained_input_result(plan, record, receipt)
    is Err(InvalidDispatch),
  )
  @transfer.commit_transition(@transfer.prepare_start(record).unwrap(), true).unwrap()
  |> ignore
  @transfer.commit_transition(
    @transfer.prepare_source_settled(record, true, false).unwrap(),
    true,
  ).unwrap()
  |> ignore
  assert_true(
    prepare_remote_retained_input_result(plan, record, receipt)
    is Err(InvalidDispatch),
  )
  @transfer.commit_transition(
    @transfer.prepare_destination_commit(record).unwrap(),
    true,
  ).unwrap()
  |> ignore
  let result = prepare_remote_retained_input_result(plan, record, receipt).unwrap()
  assert_eq(remote_retained_input_result_json(result), expected)
  assert_eq(remote_retained_input_result_identity(result), expected_cid)
  let admitted = admit_remote_retained_input_result_json(
    expected, expected_cid, plan,
  ).unwrap()
  // DirectStream has no TransferStore object use, so that release bit starts true.
  assert_eq(
    @transfer.record_projection(remote_retained_input_result_record(admitted)),
    [3, 2, 0, 1, 0, 1, 1, 1, 1],
  )
  assert_eq(
    @transfer.destination_receipt_cid(
      remote_retained_input_result_receipt(admitted),
    ),
    @transfer.destination_receipt_cid(receipt),
  )
  @transfer.commit_transition(
    @transfer.prepare_cleanup(record, true, true, true).unwrap(),
    true,
  ).unwrap()
  |> ignore
  // Transfer cleanup leaves committed receiver material available. The cached
  // report nevertheless retains its earlier immutable record revision.
  assert_true(@transfer.record_is_destination_committed(record))
  assert_true(
    @transfer.record_projection(record) !=
    @transfer.record_projection(remote_retained_input_result_record(result)),
  )
  assert_true(
    @transfer.record_is_destination_committed(
      remote_retained_input_result_record(result),
    ),
  )
  assert_eq(remote_retained_input_result_json(result), expected)
}

///|
test "retained result refuses another plan or receiver occurrence and noncanonical replay" {
  let (plan, _, body, cid) = retained_handoff_fixture()
  assert_true(
    admit_remote_retained_input_result_json(body + " ", cid, plan)
    is Err(InvalidDispatch),
  )
  assert_true(
    admit_remote_retained_input_result_json(
      body.replace(old="destination-generation-a", new="another-destination"),
      cid,
      plan,
    )
    is Err(InvalidDispatch),
  )
  let foreign_intent = prepare_remote_retained_input_intent(
    plan.intent.request,
    { ..plan.intent.projection, consumer_task_key: "task-c", },
  ).unwrap()
  let foreign_plan = prepare_remote_retained_input_plan(
    foreign_intent,
    plan.subject,
    plan.evidence,
    plan.transfer,
  ).unwrap()
  assert_true(
    admit_remote_retained_input_result_json(body, cid, foreign_plan)
    is Err(InvalidDispatch),
  )
}
