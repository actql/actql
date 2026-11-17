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
  // Independent literal tariff: metadata5696 + initial frame3616 + row/buffers6624 + output1856 + two optional slots16.
  assert_eq(
    after.reserved_retention_bytes - before.reserved_retention_bytes,
    17808L,
  )
  assert_eq(after.reserved_execution_bytes, 17808L)
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
    19280L,
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
        retained_bytes: baseline + 17453L,
        execution_bytes: 17453L,
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
        retained_bytes: baseline + 15980L,
        execution_bytes: 15981L,
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

///|
test "same READ backs a row above the old sixteen MiB frame ceiling before construction" {
  let input = [1]
  let policy = client_local_resource_policy()
  let selected = client_local_preparation_initial_limits(
    policy,
    retained_bytes=Some(1073741824L),
    execution_bytes=Some(1073741824L),
  ).unwrap()
  let owner = begin_request_preparation(
    request_parent_fixture(input, initial_limits=Some(selected)),
    input,
    policy,
  ).unwrap()
  let original = owner.capacity
  let body_bytes = 16777216
  let row_bytes = body_bytes + 12
  let payload_bytes = row_bytes + 2
  let chunk_bytes = 65536
  let window = reserve_request_result_read(
    owner, input, row_bytes, chunk_bytes, 64, 32, chunk_bytes,
  ).unwrap()
  // Installed Request framing starts small. Back the actual complete row
  // before this deliberately eager component constructor.
  grow_request_result_read_row(owner, input, row_bytes).unwrap() |> ignore
  let held = @resources.ledger_usage(owner.ledger)
  assert_true(held.reserved_execution_bytes >= 5L * row_bytes.to_int64())
  assert_true(physical_equal(owner.capacity, original))
  let prepared = @publication.prepare_durable_result_row_frames(
    payload_bytes, 1, row_bytes, 8, chunk_bytes,
  )
  let frames = match prepared {
    Ok(value) => value
    Err(issue) => {
      abort_request_preparation_after_cleanup(owner).unwrap()
      fail(@debug.to_string(issue))
    }
  }
  assert_eq(window, chunk_bytes)
  assert_eq(
    @publication.feed_durable_result_row_frames(frames, b"[{\"value\":\""),
    Ok([]),
  )
  let chunk = Bytes::from_array(Array::make(chunk_bytes, 0x78))
  for _ in 0..<256 {
    assert_eq(
      @publication.feed_durable_result_row_frames(frames, chunk),
      Ok([]),
    )
  }
  let rows = @publication.feed_durable_result_row_frames(frames, b"\"}]").unwrap()
  assert_eq(rows.length(), 1)
  let row = rows[0]
  assert_eq(row.length(), row_bytes)
  // Walk the returned original String without a second giant expected body.
  let mut offset = 0
  for char in row {
    if offset >= 10 && offset < row_bytes - 2 {
      assert_eq(char, 'x')
    }
    offset += 1
  }
  assert_eq(offset, row_bytes)
  let grown = grow_request_result_read_row(owner, input, row.length()).unwrap()
  assert_eq(grown.0, row_bytes)
  assert_true(grown.1 <= chunk_bytes)
  assert_eq(
    @publication.finish_durable_result_row_frames(frames),
    Ok({ bytes: payload_bytes, rows: 1, }),
  )
  assert_true(physical_equal(owner.capacity, original))
  abort_request_preparation_after_cleanup(owner).unwrap()
  assert_eq(@resources.ledger_usage(owner.ledger).live_reservations, 0)
}
