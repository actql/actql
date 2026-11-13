///|
test "READ metadata reconciles ended decode scratch to distinct actual retained roles and row overlap" {
  let input = [1]
  let owner = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  let before = @resources.ledger_usage(owner.ledger)
  let capacity = owner.capacity
  reserve_request_result_read_metadata(owner, input, 256).unwrap()
  assert_eq(
    @resources.ledger_usage(owner.ledger).reserved_execution_bytes,
    44544L,
  )
  retain_request_result_metadata_data(owner, input, 0, 3, 128).unwrap()
  finish_request_result_metadata(owner, input).unwrap()
  // Actual three-node/128-unit holding: 3*(4*16+8*8+4*8) + 2*128 = 736.
  assert_eq(
    @resources.ledger_usage(owner.ledger).reserved_execution_bytes,
    736L,
  )
  reserve_request_result_read_metadata(owner, input, 128).unwrap()
  retain_request_result_metadata_data(owner, input, 1, 2, 64).unwrap()
  finish_request_result_metadata(owner, input).unwrap()
  reserve_request_result_read_metadata(owner, input, 128).unwrap()
  retain_request_result_metadata_data(owner, input, 2, 2, 64).unwrap()
  finish_request_result_metadata(owner, input).unwrap()
  // Equal DATA in another live role is not the same holding.
  assert_eq(
    @resources.ledger_usage(owner.ledger).reserved_execution_bytes,
    1632L,
  )
  release_request_result_metadata(owner, input, 1).unwrap()
  release_request_result_metadata(owner, input, 2).unwrap()
  assert_eq(
    @resources.ledger_usage(owner.ledger).reserved_execution_bytes,
    736L,
  )
  assert_eq(
    reserve_request_result_read(owner, input, 64, 128, 64, 32, 64).unwrap(),
    64,
  )
  reserve_request_result_read_metadata(owner, input, 64).unwrap()
  retain_request_result_metadata_data(owner, input, 3, 1, 32).unwrap()
  finish_request_result_metadata(owner, input).unwrap()
  assert_eq(grow_request_result_read_row(owner, input, 50).unwrap(), (64, 64))
  let grown = @resources.ledger_usage(owner.ledger)
  assert_eq(
    grown.reserved_retention_bytes - before.reserved_retention_bytes,
    18304L,
  )
  assert_eq(grown.reserved_execution_bytes, 18304L)
  assert_eq(grown.live_reservations, before.live_reservations)
  assert_true(physical_equal(capacity, owner.capacity))
  abort_request_preparation_after_cleanup(owner).unwrap()
  assert_eq(@resources.ledger_usage(owner.ledger).reserved_retention_bytes, 0L)
}

///|
test "READ long-string holding uses actual nodes and reuses each completed metadata decode peak" {
  let input = [1]
  let owner = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  let before = @resources.ledger_usage(owner.ledger)
  reserve_request_result_read_metadata(owner, input, 100008).unwrap()
  retain_request_result_metadata_data(owner, input, 0, 2, 100001).unwrap()
  finish_request_result_metadata(owner, input).unwrap()
  let held = @resources.ledger_usage(owner.ledger)
  assert_eq(held.reserved_execution_bytes, 200322L)
  assert_true(
    retain_request_result_metadata_data(owner, input, 1, 2, 100001)
    is Err(WrongPhase),
  )
  assert_true(
    reserve_request_result_read_metadata(owner, [1], 32) is Err(ForeignOriginal),
  )
  assert_eq(@resources.ledger_usage(owner.ledger), held)
  for _ in 0..<3 {
    reserve_request_result_read_metadata(owner, input, 32).unwrap()
    assert_eq(
      @resources.ledger_usage(owner.ledger).reserved_execution_bytes,
      205890L,
    )
    finish_request_result_metadata(owner, input).unwrap()
    assert_eq(@resources.ledger_usage(owner.ledger), held)
  }
  release_request_result_metadata(owner, input, 0).unwrap()
  let released = @resources.ledger_usage(owner.ledger)
  assert_eq(released.reserved_retention_bytes, before.reserved_retention_bytes)
  assert_eq(released.reserved_execution_bytes, before.reserved_execution_bytes)
  assert_eq(released.live_reservations, before.live_reservations)
  assert_eq(released.peak_retention_bytes, held.peak_retention_bytes)
  abort_request_preparation_after_cleanup(owner).unwrap()
}

///|
test "READ metadata one-byte-short refuses before changing original capacity or authorizing a held role" {
  let policy = client_local_resource_policy()
  let baseline = client_request_preparation_control_capacity(policy).unwrap().0
  let limits = client_local_preparation_initial_limits(policy).unwrap()
  let input = [1]
  let owner = begin_request_preparation(
    request_parent_fixture(
      input,
      initial_limits=Some({
        ..limits,
        retained_bytes: baseline + 2261L,
        execution_bytes: 2262L,
      }),
    ),
    input,
    policy,
  ).unwrap()
  let before = @resources.ledger_usage(owner.ledger)
  assert_true(
    reserve_request_result_read_metadata(owner, input, 13)
    is Err(Capacity(Resource(@resources.RetentionLimit))),
  )
  assert_eq(@resources.ledger_usage(owner.ledger), before)
  assert_true(owner.phase == Open && owner.result_read is None)
  assert_true(
    retain_request_result_metadata_data(owner, input, 0, 1, 1)
    is Err(WrongPhase),
  )
  assert_true(
    reserve_request_result_read_metadata(owner, input, -1) is Err(Policy),
  )
  assert_eq(@resources.ledger_usage(owner.ledger), before)
  abort_request_preparation_after_cleanup(owner).unwrap()
}
