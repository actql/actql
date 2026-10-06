///|
test "retained current poll binds a bounded exact query to the original plan" {
  let (plan, _, _, _) = retained_handoff_fixture()
  let body = remote_poll_retained_input_current_json(plan, "query-a").unwrap()
  let operation = admit_remote_poll_operation_json(body).unwrap()
  assert_true(remote_poll_operation_is_retained_input_current(operation))
  assert_false(remote_poll_operation_is_retained_input_transfer(operation))
  assert_false(remote_poll_operation_is_output(operation))
  assert_false(remote_poll_operation_is_query(operation))
  assert_eq(
    dispatch_request_identity(remote_poll_operation_request(operation)),
    dispatch_request_identity(plan.intent.request),
  )
  let query = admit_remote_poll_retained_input_current_json(body).unwrap()
  assert_eq(remote_retained_input_current_query_identity(query), "query-a")
  assert_eq(
    remote_retained_input_plan_identity(
      remote_retained_input_current_plan(query),
    ),
    plan.cid,
  )
  assert_true(
    admit_remote_poll_retained_input_current_json(body + " ")
    is Err(InvalidDispatch),
  )
  assert_true(
    admit_remote_poll_retained_input_current_json(
      body.replace(old="\"plan_cid\":\"", new="\"plan_cid\":\"x"),
    )
    is Err(InvalidDispatch),
  )
  assert_true(
    remote_poll_retained_input_current_json(plan, "") is Err(InvalidDispatch),
  )
  assert_true(
    remote_poll_retained_input_current_json(plan, "x".repeat(257))
    is Err(InvalidDispatch),
  )
  assert_true(
    remote_poll_retained_input_current_json(plan, "é".repeat(129))
    is Err(InvalidDispatch),
  )
  let exact = "e\u{0301}\r\n"
  let query = admit_remote_poll_retained_input_current_json(
    remote_poll_retained_input_current_json(plan, exact).unwrap(),
  ).unwrap()
  assert_eq(remote_retained_input_current_query_identity(query), exact)
}

///|
test "retained current reply reads durable revision and rejects another query" {
  let (plan, _, _, _) = retained_handoff_fixture()
  let query = admit_remote_poll_retained_input_current_json(
    remote_poll_retained_input_current_json(plan, "query-a").unwrap(),
  ).unwrap()
  let another = admit_remote_poll_retained_input_current_json(
    remote_poll_retained_input_current_json(plan, "query-b").unwrap(),
  ).unwrap()
  let record = @transfer.open_record(plan.transfer)
  let receipt = @transfer.prepare_destination_receipt(
    plan.transfer,
    "destination-generation-a",
  ).unwrap()
  assert_true(
    prepare_remote_retained_input_current_reply(query, record, receipt)
    is Err(InvalidDispatch),
  )
  @transfer.commit_transition(@transfer.prepare_start(record).unwrap(), true).unwrap()
  |> ignore
  @transfer.commit_transition(
    @transfer.prepare_source_settled(record, true, false).unwrap(),
    true,
  ).unwrap()
  |> ignore
  @transfer.commit_transition(
    @transfer.prepare_destination_commit(record).unwrap(),
    true,
  ).unwrap()
  |> ignore
  let reply = prepare_remote_retained_input_current_reply(
    query, record, receipt,
  ).unwrap()
  let body = remote_retained_input_current_reply_json(reply)
  let cid = remote_retained_input_current_reply_identity(reply)
  let admitted = admit_remote_retained_input_current_reply_json(
    body, cid, query, 8, 65536, 1048576L,
  ).unwrap()
  let durable = @transfer.admit_durable_remote_transfer_record(
    @utf8.encode(
      remote_retained_input_current_reply_transfer_record_json(admitted),
    ),
    8,
    65536,
    1048576L,
  ).unwrap()
  let snapshot = @transfer.restore_durable_remote_transfer_record(durable).unwrap()
  assert_eq(@transfer.record_projection(snapshot), [3, 2, 0, 1, 0, 1, 1, 1, 1])
  assert_eq(
    @transfer.destination_receipt_cid(
      remote_retained_input_current_reply_receipt(admitted),
    ),
    @transfer.destination_receipt_cid(receipt),
  )
  assert_true(
    admit_remote_retained_input_current_reply_json(
      body, cid, another, 8, 65536, 1048576L,
    )
    is Err(InvalidDispatch),
  )
  assert_true(
    admit_remote_retained_input_current_reply_json(
      body + " ",
      cid,
      query,
      8,
      65536,
      1048576L,
    )
    is Err(InvalidDispatch),
  )
  assert_true(
    admit_remote_retained_input_current_reply_json(
      body,
      "sha256:" + "0".repeat(64),
      query,
      8,
      65536,
      1048576L,
    )
    is Err(InvalidDispatch),
  )
  @transfer.commit_transition(
    @transfer.prepare_cleanup(record, true, true, true).unwrap(),
    true,
  ).unwrap()
  |> ignore
  // A captured response is immutable; only a new live query can observe change.
  assert_eq(remote_retained_input_current_reply_json(reply), body)
  assert_eq(@transfer.record_revision(snapshot), 3)
  assert_eq(@transfer.record_revision(record), 4)
}
