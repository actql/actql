///|
fn coordinator_with_output_dispatch(
  output : RemotePollOutput,
) -> CoordinatorDispatchJournal {
  let request = remote_poll_output_request(output)
  let journal = create_coordinator_dispatch_journal(
    dispatch_request_journal_key(request)[0],
  ).unwrap()
  ignore(
    commit_coordinator_dispatch_intent(
      prepare_coordinator_dispatch_intent(journal, request).unwrap(),
      true,
    ).unwrap(),
  )
  journal
}

///|
test "Coordinator output success follows durable intent and unknown state" {
  let (output, payload_request, transfer_request, transfer_record) = output_result_fixture()
  let journal = coordinator_with_output_dispatch(output)
  let admission = prepare_coordinator_output_intent(
    journal, output, payload_request, transfer_request,
  ).unwrap()
  assert_eq(coordinator_output_intent_kind(admission), NewDispatch)
  assert_true(
    commit_coordinator_output_intent(admission, false)
    is Err(DurabilityUnconfirmed),
  )
  let record = commit_coordinator_output_intent(
      prepare_coordinator_output_intent(
        journal, output, payload_request, transfer_request,
      ).unwrap(),
      true,
    ).unwrap().1
  assert_eq(coordinator_output_record_status(record), ["0", "0", ""])
  ignore(
    commit_coordinator_output_transition(
      prepare_coordinator_output_unknown(record).unwrap(),
      true,
    ).unwrap(),
  )
  assert_eq(coordinator_output_record_status(record), ["1", "1", ""])
  let result = prepare_remote_output_result(
    output,
    payload_request,
    cid("eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"),
    transfer_record,
  ).unwrap()
  ignore(
    commit_coordinator_output_transition(
      prepare_coordinator_output_success(record, result).unwrap(),
      true,
    ).unwrap(),
  )
  assert_eq(coordinator_output_record_status(record), [
    "2",
    "2",
    remote_output_result_identity(result),
  ])
  assert_true(
    prepare_coordinator_output_unknown(record) is Err(InvalidTransition),
  )
  assert_eq(
    coordinator_output_record_result_json(record),
    remote_output_result_json(result),
  )
}

///|
test "Coordinator restores an exact successful output without new execution" {
  let (output, payload_request, transfer_request, transfer_record) = output_result_fixture()
  let result = prepare_remote_output_result(
    output,
    payload_request,
    cid("eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"),
    transfer_record,
  ).unwrap()
  let journal = coordinator_with_output_dispatch(output)
  let record = commit_coordinator_output_intent(
      prepare_coordinator_output_intent(
        journal, output, payload_request, transfer_request,
      ).unwrap(),
      true,
    ).unwrap().1
  ignore(
    restore_coordinator_output_record(
      record,
      4,
      2,
      remote_output_result_json(result).unwrap(),
    ).unwrap(),
  )
  assert_eq(coordinator_output_record_status(record), [
    "4",
    "2",
    remote_output_result_identity(result),
  ])
  let retry = prepare_coordinator_output_intent(
    journal, output, payload_request, transfer_request,
  ).unwrap()
  assert_eq(coordinator_output_intent_kind(retry), ExistingDispatch)
  let same = commit_coordinator_output_intent(retry, true).unwrap().1
  assert_eq(
    coordinator_output_record_result_projection(same).unwrap()[0],
    remote_output_result_identity(result),
  )
}

///|
test "Coordinator output transitions issue exact durable bodies" {
  let (output, payload_request, transfer_request, transfer_record) = output_result_fixture()
  let subject = output_plan_subject(output, payload_request, transfer_request)
  let plan = prepare_remote_output_plan(
    output, subject, payload_request, transfer_request,
  ).unwrap()
  let journal = coordinator_with_output_dispatch(output)
  let record = commit_coordinator_output_intent(
      prepare_coordinator_output_intent(
        journal, output, payload_request, transfer_request,
      ).unwrap(),
      true,
    ).unwrap().1
  let initial = prepare_durable_coordinator_output_record(output, plan).unwrap()
  let unknown = prepare_coordinator_output_unknown(record).unwrap()
  assert_eq(coordinator_output_transition_expected_revision(unknown), 0)
  let uncertain = advance_durable_coordinator_output_record(initial, unknown).unwrap()
  let unknown_body = durable_coordinator_output_record_json(uncertain)
  assert_eq(
    coordinator_output_transition_durable_json(initial, unknown),
    Ok(unknown_body),
  )
  assert_true(unknown_body.contains("\"progress_state\":1"))
  ignore(commit_coordinator_output_transition(unknown, true).unwrap())
  let stale = prepare_coordinator_output_unknown(record).unwrap()
  assert_true(
    coordinator_output_transition_durable_json(initial, stale)
    is Err(StateCollision),
  )
  let result = prepare_remote_output_result(
    output,
    payload_request,
    cid("eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"),
    transfer_record,
  ).unwrap()
  let success = prepare_coordinator_output_success_json(
    record,
    remote_output_result_json(result).unwrap(),
  ).unwrap()
  assert_eq(coordinator_output_transition_expected_revision(success), 1)
  let success_body = coordinator_output_transition_durable_json(
    uncertain, success,
  ).unwrap()
  assert_true(success_body.contains("\"progress_state\":2"))
  assert_true(success_body.contains(remote_output_result_identity(result)))
  assert_true(
    prepare_coordinator_output_success_json(
      record,
      remote_output_result_json(result)
      .unwrap()
      .replace(
        old=@transfer.request_cid(transfer_request),
        new=cid(
          "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
        ),
      ),
    )
    is Err(InvalidDispatch),
  )
  ignore(commit_coordinator_output_transition(success, true).unwrap())
  assert_eq(
    coordinator_output_record_result_json(record),
    remote_output_result_json(result),
  )
}
