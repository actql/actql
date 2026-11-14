///|
test "READ grows one original capacity for bounded frame output and geometric row overlap" {
  let input = [1]
  let owner = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  let original = owner.capacity
  let before = @resources.ledger_usage(owner.ledger)
  let window = reserve_request_result_read(owner, input, 64, 128, 64, 32, 64).unwrap()
  assert_eq(window, 64)
  let after = @resources.ledger_usage(owner.ledger)
  // Independent literal tariff: metadata5696 + initial frame3616 + row/buffers6624 + output1856.
  assert_eq(
    after.reserved_retention_bytes - before.reserved_retention_bytes,
    17792L,
  )
  assert_eq(after.reserved_execution_bytes, 17792L)
  assert_eq(after.live_reservations, before.live_reservations)
  assert_true(physical_equal(owner.capacity, original))
  assert_true(
    grow_request_result_read_row(owner, [1], 50) is Err(ForeignOriginal),
  )
  assert_eq(@resources.ledger_usage(owner.ledger), after)
  assert_eq(grow_request_result_read_row(owner, input, 50).unwrap(), (64, 64))
  let grown = @resources.ledger_usage(owner.ledger)
  assert_eq(
    grown.reserved_retention_bytes - before.reserved_retention_bytes,
    19264L,
  )
  assert_eq(grow_request_result_read_row(owner, input, 49).unwrap(), (64, 64))
  assert_eq(@resources.ledger_usage(owner.ledger), grown)
  assert_true(reserve_request_snapshot(owner, input, 1L, 1L) is Err(WrongPhase))
  abort_request_preparation_after_cleanup(owner).unwrap()
  assert_eq(@resources.ledger_usage(owner.ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(owner.ledger).reserved_execution_bytes, 0L)
}

///|
test "READ admits a real minimum shrinks its disposed window and refuses one-byte-short backing" {
  let policy = client_local_resource_policy()
  let baseline = client_request_preparation_control_capacity(policy).unwrap().0
  let limits = client_local_preparation_initial_limits(policy).unwrap()
  let input = [1]
  let owner = begin_request_preparation(
    request_parent_fixture(
      input,
      initial_limits=Some({
        ..limits,
        retained_bytes: baseline + 17437L,
        execution_bytes: 17437L,
      }),
    ),
    input,
    policy,
  ).unwrap()
  assert_eq(
    reserve_request_result_read(owner, input, 64, 128, 64, 32, 16).unwrap(),
    16,
  )
  // The existing caller has flushed its old staged text before this grow.
  assert_eq(grow_request_result_read_row(owner, input, 50).unwrap(), (64, 1))
  abort_request_preparation_after_cleanup(owner).unwrap()
  let refused_input = [1]
  let refused = begin_request_preparation(
    request_parent_fixture(
      refused_input,
      initial_limits=Some({
        ..limits,
        retained_bytes: baseline + 15964L,
        execution_bytes: 15965L,
      }),
    ),
    refused_input,
    policy,
  ).unwrap()
  let before = @resources.ledger_usage(refused.ledger)
  assert_true(
    reserve_request_result_read(refused, refused_input, 64, 128, 64, 32, 64)
    is Err(Capacity(Resource(@resources.RetentionLimit))),
  )
  assert_eq(@resources.ledger_usage(refused.ledger), before)
  assert_true(refused.phase == Open && refused.result_read is None)
  abort_request_preparation_after_cleanup(refused).unwrap()
}

///|
test "concurrent READ originals with equal DATA keep independent current reservations" {
  let first_input = [7]
  let second_input = [7]
  let policy = client_local_resource_policy()
  let first = begin_request_preparation(
    request_parent_fixture(first_input),
    first_input,
    policy,
  ).unwrap()
  let second = begin_request_preparation(
    request_parent_fixture(second_input),
    second_input,
    policy,
  ).unwrap()
  reserve_request_result_read(first, first_input, 64, 128, 64, 32, 64).unwrap()
  |> ignore
  reserve_request_result_read(second, second_input, 64, 128, 64, 32, 64).unwrap()
  |> ignore
  let a = @resources.ledger_usage(first.ledger).reserved_retention_bytes
  let b = @resources.ledger_usage(second.ledger).reserved_retention_bytes
  assert_true(a > 0L && b > 0L && a + b > a)
  assert_true(
    grow_request_result_read_row(first, second_input, 40)
    is Err(ForeignOriginal),
  )
  abort_request_preparation_after_cleanup(first).unwrap()
  assert_eq(@resources.ledger_usage(first.ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(second.ledger).reserved_retention_bytes, b)
  grow_request_result_read_row(second, second_input, 40).unwrap() |> ignore
  abort_request_preparation_after_cleanup(second).unwrap()
  assert_eq(@resources.ledger_usage(second.ledger).reserved_retention_bytes, 0L)
}

///|
test "same READ parent pays actual growing row frames beyond legacy one MiB before allocation" {
  let input = [1]
  let owner = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  let original = owner.capacity
  let prefix = b"[{\"value\":\""
  let chunk = @utf8.encode("x".repeat(65536))
  let suffix = b"\"}]"
  let total = prefix.length() + 17 * chunk.length() + suffix.length()
  reserve_request_result_read(owner, input, total, 65536, 64, 32, 65536).unwrap()
  |> ignore
  let frames = @publication.prepare_growing_durable_result_row_frames(
    total, 1, 19000000, 8, 65536,
  ).unwrap()
  for index in 0..<19 {
    let bytes = if index == 0 {
      prefix
    } else if index == 18 {
      suffix
    } else {
      chunk
    }
    let needed = @publication.durable_result_row_frame_growth(
      frames,
      bytes.length(),
    ).unwrap()
    let (admitted, _) = grow_request_result_read_row(owner, input, needed).unwrap()
    @publication.grow_durable_result_row_frame_buffer(frames, admitted).unwrap()
    let rows = @publication.feed_durable_result_row_frames(frames, bytes).unwrap()
    if index == 18 {
      assert_eq(rows.length(), 1)
      assert_eq(rows[0].length(), total - 2)
      assert_eq(rows[0], "{\"value\":\"" + "x".repeat(17 * 65536) + "\"}")
    } else {
      assert_eq(rows, [])
    }
  }
  assert_eq(
    @publication.finish_durable_result_row_frames(frames).unwrap().bytes,
    total,
  )
  assert_true(physical_equal(owner.capacity, original))
  abort_request_preparation_after_cleanup(owner).unwrap()
  assert_eq(@resources.ledger_usage(owner.ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(owner.ledger).reserved_execution_bytes, 0L)
}
