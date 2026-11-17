///|
fn read_wire_test_scan(
  owner : ClientRequestPreparation[Array[Int]],
  input : Array[Int],
  wire : String,
) -> Result[(Int, Int), ClientRequestPreparationIssue] {
  match begin_request_result_read_wire_row(owner, input, wire) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  while true {
    let (ready, units, window) = match
      advance_request_result_read_wire_row(owner, input, 4096) {
      Err(issue) => return Err(issue)
      Ok(value) => value
    }
    if ready {
      return Ok((units, window))
    }
  } nobreak {
    Err(Policy)
  }
}

///|
test "READ actual long Text geometry retains the same one GiB parent before parse" {
  let input = [1]
  let policy = client_local_resource_policy()
  let limits = client_local_preparation_initial_limits(
    policy,
    retained_bytes=Some(1073741824L),
    execution_bytes=Some(1073741824L),
  ).unwrap()
  let owner = begin_request_preparation(
    request_parent_fixture(input, initial_limits=Some(limits)),
    input,
    policy,
  ).unwrap()
  let original = owner.capacity
  reserve_request_result_read(
    owner, input, 16834523, 65536, 64, 2147483646, 65536,
  ).unwrap()
  |> ignore
  begin_request_result_read_wire(owner, input, 16834525L, 1).unwrap()
  // Independent old quote: byte-as-node demand206*8MiB+32 exceeds one GiB.
  assert_true(206L * 8388608L + 32L > 1073741824L)
  assert_eq(
    grow_request_result_read_frame(owner, input, 8388608).unwrap(),
    (8388608, 65536),
  )
  let framed = @resources.ledger_usage(owner.ledger)
  assert_true(framed.reserved_retention_bytes < 500000000L)
  assert_true(physical_equal(owner.capacity, original))
  let wire = "{\"value\":\"" + "x\\\"[{},]".repeat(16384) + "\"}"
  let before = @resources.ledger_usage(owner.ledger)
  read_wire_test_scan(owner, input, wire).unwrap() |> ignore
  let after = @resources.ledger_usage(owner.ledger)
  // Quoted delimiters/escaped quotes do not create a byte-sized node forest.
  // Two actual Object/String nodes keep the unchanged160-byte forest tariff.
  assert_eq(
    after.reserved_retention_bytes - before.reserved_retention_bytes,
    320L,
  )
  assert_eq(
    after.reserved_execution_bytes - before.reserved_execution_bytes,
    320L,
  )
  assert_true(owner.result_read is Some(read) && read.wire_preflight is None)
  abort_request_preparation_after_cleanup(owner).unwrap()
  assert_eq(@resources.ledger_usage(owner.ledger).live_reservations, 0)
}

///|
test "READ scans actual same-size altered geometry and preserves node and work refusals" {
  let input = [2]
  let owner = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  reserve_request_result_read(owner, input, 512, 64, 8, 4, 64).unwrap()
  |> ignore
  begin_request_result_read_wire(owner, input, 1024L, 2).unwrap()
  grow_request_result_read_frame(owner, input, 256).unwrap() |> ignore
  read_wire_test_scan(owner, input, "\"" + "x".repeat(63) + "\"").unwrap()
  |> ignore
  assert_true(
    read_wire_test_scan(
      owner, input, "[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]",
    )
    is Err(Policy),
  )
  abort_request_preparation_after_cleanup(owner).unwrap()
  let second = [3]
  let exhausted = begin_request_preparation(
    request_parent_fixture(second),
    second,
    client_local_resource_policy(),
  ).unwrap()
  reserve_request_result_read(exhausted, second, 64, 64, 8, 64, 64).unwrap()
  |> ignore
  begin_request_result_read_wire(exhausted, second, 1L, 1).unwrap()
  grow_request_result_read_frame(exhausted, second, 64).unwrap() |> ignore
  assert_true(
    read_wire_test_scan(exhausted, second, "{\"a\":1}")
    is Err(Work(@resources.WorkLimit)),
  )
  abort_request_preparation_after_cleanup(exhausted).unwrap()
  assert_eq(@resources.ledger_usage(exhausted.ledger).live_reservations, 0)
}

///|
test "READ pending scan retains its original input and current gate through cleanup" {
  let input = [4]
  let current = Ref(true)
  let pending = Ref(false)
  let owner = begin_request_preparation(
    request_parent_fixture(input, current=() => current.val, pending=() => {
      pending.val
    }),
    input,
    client_local_resource_policy(),
  ).unwrap()
  reserve_request_result_read(owner, input, 8192, 64, 8, 8192, 64).unwrap()
  |> ignore
  begin_request_result_read_wire(owner, input, 8192L, 1).unwrap()
  grow_request_result_read_frame(owner, input, 8192).unwrap() |> ignore
  assert_true(
    begin_request_result_read_wire_row(owner, [4], "[]") is Err(ForeignOriginal),
  )
  begin_request_result_read_wire_row(
    owner,
    input,
    "\"" + "x".repeat(5000) + "\"",
  ).unwrap()
  assert_true(
    begin_request_result_read_wire_row(owner, input, "[]") is Err(WrongPhase),
  )
  assert_true(
    grow_request_result_read_frame(owner, input, 8192) is Err(WrongPhase),
  )
  assert_true(
    grow_request_result_read_row(owner, input, 8192) is Err(WrongPhase),
  )
  assert_true(
    advance_request_result_read_wire_row(owner, input, 4097) is Err(Policy),
  )
  assert_eq(
    advance_request_result_read_wire_row(owner, input, 4096).unwrap().0,
    false,
  )
  current.val = false
  assert_true(
    advance_request_result_read_wire_row(owner, input, 4096) is Err(Capacity(_)),
  )
  current.val = true
  pending.val = true
  assert_true(abort_request_preparation_after_cleanup(owner) is Err(_))
  assert_true(owner.phase == Retiring && owner.result_read is None)
  assert_eq(@resources.ledger_usage(owner.ledger).live_reservations, 0)
  pending.val = false
  // Preserve the unchanged imported-owner law: a changed callback does not
  // issue the original stop acknowledgement after an uncertain stop.
  assert_true(abort_request_preparation_after_cleanup(owner) is Err(Initial(_)))
  assert_eq(@resources.ledger_usage(owner.ledger).live_reservations, 0)
  assert_true(
    advance_request_result_read_wire_row(owner, input, 4096) is Err(WrongPhase),
  )
}

///|
test "READ actual structural demand still refuses one-byte-short before parse" {
  let input = [5]
  let policy = client_local_resource_policy()
  let limits = client_local_preparation_initial_limits(policy).unwrap()
  let owner = begin_request_preparation(
    request_parent_fixture(
      input,
      initial_limits=Some({
        ..limits,
        retained_bytes: 198887L,
        execution_bytes: 183184L,
      }),
    ),
    input,
    policy,
  ).unwrap()
  reserve_request_result_read(owner, input, 2048, 64, 8, 2048, 64).unwrap()
  |> ignore
  begin_request_result_read_wire(owner, input, 2048L, 1).unwrap()
  grow_request_result_read_frame(owner, input, 2048).unwrap() |> ignore
  let before = @resources.ledger_usage(owner.ledger)
  // 512 scalar items plus the array need513 actual nodes. Old raw buffers
  // and the still-live64-byte output window remain charged alongside them.
  let wire = "[" + "0,".repeat(511) + "0]"
  assert_true(
    read_wire_test_scan(owner, input, wire)
    is Err(Capacity(Resource(@resources.RetentionLimit))),
  )
  assert_eq(@resources.ledger_usage(owner.ledger), before)
  abort_request_preparation_after_cleanup(owner).unwrap()
  assert_eq(@resources.ledger_usage(owner.ledger).live_reservations, 0)
}

///|
test "READ raw Unicode failure spends the same scan receipt and retires its cursor" {
  let input = [6]
  let owner = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  reserve_request_result_read(owner, input, 64, 64, 8, 64, 64).unwrap()
  |> ignore
  begin_request_result_read_wire(owner, input, 64L, 1).unwrap()
  grow_request_result_read_frame(owner, input, 64).unwrap() |> ignore
  let malformed = "\"" + String::from_array([(0xd800).unsafe_to_char()]) + "\""
  assert_true(read_wire_test_scan(owner, input, malformed) is Err(Policy))
  abort_request_preparation_after_cleanup(owner).unwrap()
  assert_eq(@resources.ledger_usage(owner.ledger).live_reservations, 0)
}

///|
test "READ aggregate work is wide independently of its bounded row frame" {
  let input = [7]
  let owner = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  reserve_request_result_read(owner, input, 64, 64, 8, 64, 64).unwrap()
  |> ignore
  let before = @resources.ledger_usage(owner.ledger)
  assert_true(
    begin_request_result_read_wire(owner, input, 9223372036854775807L, 1)
    is Err(Policy),
  )
  assert_eq(@resources.ledger_usage(owner.ledger), before)
  begin_request_result_read_wire(owner, input, 2147483648L, 1).unwrap()
  grow_request_result_read_frame(owner, input, 64).unwrap() |> ignore
  read_wire_test_scan(owner, input, "[]").unwrap() |> ignore
  abort_request_preparation_after_cleanup(owner).unwrap()
  assert_eq(@resources.ledger_usage(owner.ledger).live_reservations, 0)
}
