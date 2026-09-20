///|
test "durable Transfer record re-admits request manifest and state" {
  let request = state_request(DirectStream)
  let record = open_record(request)
  ignore(apply(prepare_start(record).unwrap()))
  let body = remote_transfer_record_durable_json(record).unwrap()
  let durable = admit_durable_remote_transfer_record(
    @utf8.encode(body),
    1,
    4096,
    5L,
  ).unwrap()
  assert_eq(durable_remote_transfer_record_revision(durable), 1)
  assert_eq(
    durable_remote_transfer_record_request_identity(durable),
    request_cid(request),
  )
  assert_eq(durable_remote_transfer_record_json(durable), body)
  let restored = restore_durable_remote_transfer_record(durable).unwrap()
  assert_eq(record_projection(restored), record_projection(record))
}

///|
test "durable Transfer transition describes the exact next CAS body" {
  let request = state_request(TransferStore)
  let record = open_record(request)
  let transition = prepare_start(record).unwrap()
  assert_eq(remote_transfer_transition_expected_revision(transition), 0)
  assert_eq(
    remote_transfer_transition_request_identity(transition),
    request_cid(request),
  )
  let body = remote_transfer_transition_durable_json(transition).unwrap()
  let durable = admit_durable_remote_transfer_record(
    @utf8.encode(body),
    1,
    4096,
    5L,
  ).unwrap()
  assert_eq(durable_remote_transfer_record_revision(durable), 1)
  assert_eq(
    record_projection(restore_durable_remote_transfer_record(durable).unwrap()),
    [1, 1, 2, 0, 0, 0, 0, 0, 0],
  )
  ignore(commit_transition(transition, true).unwrap())
  assert_true(
    remote_transfer_transition_durable_json(transition) is Err(InvalidTransfer),
  )
}

///|
test "durable Transfer admission rejects forged and noncanonical records" {
  let record = open_record(state_request(DirectStream))
  let body = remote_transfer_record_durable_json(record).unwrap()
  assert_true(
    admit_durable_remote_transfer_record(@utf8.encode(body + " "), 1, 4096, 5L)
    is Err(InvalidTransfer),
  )
  assert_true(
    admit_durable_remote_transfer_record(
      @utf8.encode(
        body.replace(old="\"attempt_state\":0", new="\"attempt_state\":2"),
      ),
      1,
      4096,
      5L,
    )
    is Err(InvalidTransfer),
  )
  assert_true(
    admit_durable_remote_transfer_record(
      @utf8.encode(
        body.replace(
          old="\"source_access_stopped\":false",
          new="\"source_access_stopped\":true",
        ),
      ),
      1,
      4096,
      5L,
    )
    is Err(InvalidTransfer),
  )
  assert_true(
    admit_durable_remote_transfer_record(@utf8.encode(body), 0, 4096, 5L)
    is Err(InvalidTransfer),
  )
}
