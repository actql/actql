///|
fn state_request(route : RemoteTransferRoute) -> RemoteTransferRequest {
  let physical = @manifest.admit(
    "actql-managed-physical-manifest/0.1",
    transfer_cid("1"),
    transfer_cid("2"),
    transfer_cid("3"),
    1,
    [transfer_cid("a")],
    [5L],
    [1],
    1,
    4096,
    5L,
  ).unwrap()
  prepare_request(
    "coordinator-a",
    "transfer-state-1",
    route,
    "source-a",
    1,
    "destination-b",
    2,
    "material-a",
    physical,
    5L,
    2000000000000L,
    transfer_cid("4"),
    transfer_cid("5"),
    transfer_cid("6"),
  ).unwrap()
}

///|
fn apply(transition : RemoteTransferTransition) -> RemoteTransferRecord {
  commit_transition(transition, true).unwrap()
}

///|
test "direct Transfer commits only after stop and integrity" {
  let record = open_record(state_request(DirectStream))
  ignore(apply(prepare_start(record).unwrap()))
  assert_true(prepare_destination_commit(record) is Err(InvalidTransfer))
  ignore(apply(prepare_source_settled(record, true, false).unwrap()))
  ignore(apply(prepare_destination_commit(record).unwrap()))
  assert_eq(record_projection(record), [3, 2, 0, 1, 0, 1, 1, 1, 1])
  ignore(apply(prepare_cleanup(record, false, false, false).unwrap()))
  assert_eq(record_projection(record)[4], 1)
}

///|
test "Store failure releases source independently from destination cleanup" {
  let record = open_record(state_request(TransferStore))
  ignore(apply(prepare_start(record).unwrap()))
  ignore(apply(prepare_failure(record, false, true).unwrap()))
  assert_true(
    prepare_cleanup(record, false, false, false) is Err(InvalidTransfer),
  )
  assert_true(
    prepare_cleanup(record, false, true, false) is Err(InvalidTransfer),
  )
  ignore(apply(prepare_cleanup(record, false, true, true).unwrap()))
  assert_eq(record_projection(record), [3, 3, 2, 0, 1, 1, 1, 1, 0])
}

///|
test "unknown Transfer cannot become released by optimistic observations" {
  let record = open_record(state_request(DirectStream))
  ignore(apply(prepare_start(record).unwrap()))
  ignore(apply(prepare_unknown(record).unwrap()))
  assert_true(prepare_cleanup(record, true, true, true) is Err(InvalidTransfer))
  let transition = prepare_failure(record, true, true).unwrap()
  let (_, next) = transition_projection(transition)
  assert_eq(next[1], 4)
  assert_true(commit_transition(transition, false) is Err(InvalidTransfer))
  assert_eq(record_projection(record)[0], 2)
}

///|
test "durable Transfer state restores only valid route combinations" {
  let request = state_request(DirectStream)
  let record = open_record(request)
  ignore(apply(prepare_start(record).unwrap()))
  let restored = restore_record(request, record_projection(record)).unwrap()
  assert_eq(record_projection(restored), record_projection(record))
  assert_eq(record_revision(restored), 1)
  assert_eq(request_journal_key(request), [
    "coordinator-a", "destination-b", "2", "transfer-state-1",
  ])
  assert_true(
    restore_record(request, [1, 2, 0, 1, 0, 1, 1, 1, 1]) is Err(InvalidTransfer),
  )
  assert_true(
    restore_record(request, [1, 1, 0, 0, 0, 2, 0, 1, 0]) is Err(InvalidTransfer),
  )
}
