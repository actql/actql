///|
test "capture workspace independently accounts wire tree and handle overlap" {
  // Eight bounded wire/value copies, 256 tree slots, 32 existing control
  // slots and the two same-frame owner alias references (16 bytes).
  // Store byte objects and completed RowRun rows have separate charged owners.
  assert_eq(
    client_captured_content_workspace_capacity(4096),
    Some((49424L, 53264L)),
  )
  assert_eq(
    client_captured_content_workspace_capacity(1),
    Some((16664L, 20504L)),
  )
  assert_eq(client_captured_content_workspace_capacity(0), None)
  assert_eq(client_captured_content_workspace_capacity(1048577), None)
}

///|
test "captured inventory workspace includes every declared key before allocation" {
  // The existing frame is 49,424/53,264. Each saved Ref overlaps eight
  // 4,096-byte wire slots, 256 64-byte tree slots and 1,024 control bytes.
  // Three declared keys add 3 * 50,176, independently of actual row count.
  assert_eq(
    client_captured_content_workspace_capacity(4096, inventory_count=3),
    Some((199952L, 203792L)),
  )
  assert_eq(
    client_captured_content_workspace_capacity(4096, inventory_count=-1),
    None,
  )
  for shortage in 0..<3 {
    let ledger = @resources.create_ledger({
      planning_work: 0,
      attempts: 1,
      holdings: 0,
      transfer_bytes: 0L,
      retained_bytes: 199952L - (if shortage == 1 { 1L } else { 0L }),
      execution_bytes: 203792L - (if shortage == 2 { 1L } else { 0L }),
    }).unwrap()
    let reserved = @resources.reserve_attempt(ledger, 0L, 199952L, 203792L)
    if shortage == 0 {
      @resources.settle_reservation(ledger, reserved.unwrap()).unwrap()
    } else if shortage == 1 {
      assert_true(reserved is Err(@resources.RetentionLimit))
    } else {
      assert_true(reserved is Err(@resources.ExecutionLimit))
    }
    assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
    assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  }
}

///|
test "capture workspace exact and one short preserve the original ledger" {
  let (retained, execution) = client_captured_content_workspace_capacity(4096).unwrap()
  for shortage in 0..<3 {
    let limits : @resources.LedgerLimits = {
      planning_work: 1,
      attempts: 1,
      holdings: 0,
      transfer_bytes: 0L,
      retained_bytes: 49424L - (if shortage == 1 { 1L } else { 0L }),
      execution_bytes: 53264L - (if shortage == 2 { 1L } else { 0L }),
    }
    let ledger = @resources.create_ledger(limits).unwrap()
    let before = @resources.ledger_usage(ledger)
    let reservation = @resources.reserve_attempt(
      ledger, 0L, retained, execution,
    )
    if shortage == 0 {
      let reservation = reservation.unwrap()
      @resources.mark_cleanup_pending(ledger, reservation).unwrap()
      assert_true(@resources.reservation_pending(reservation))
      assert_eq(
        @resources.ledger_usage(ledger).reserved_retention_bytes,
        49424L,
      )
      assert_eq(
        @resources.ledger_usage(ledger).reserved_execution_bytes,
        53264L,
      )
      @resources.settle_reservation(ledger, reservation).unwrap()
      assert_false(@resources.reservation_pending(reservation))
      assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
      assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
      let settled = @resources.ledger_usage(ledger)
      // A repeated settlement must not subtract another owner's reservation.
      assert_true(
        @resources.settle_reservation(ledger, reservation)
        is Err(@resources.ClosedReservation),
      )
      assert_eq(@resources.ledger_usage(ledger), settled)
    } else {
      assert_true(
        if shortage == 1 {
          reservation is Err(@resources.RetentionLimit)
        } else {
          reservation is Err(@resources.ExecutionLimit)
        },
      )
      assert_eq(@resources.ledger_usage(ledger), before)
    }
  }
}

///|
test "measured captured inventory keeps one full frame and every actual Ref at exact backing" {
  // The original 1MiB constructor frame stays prepaid. These 101 independent
  // 2048-unit Ref wires each retain all eight wire/value/snapshot aliases,
  // 256 tree slots and 1024 control bytes. The two returned owner aliases
  // coexist with the fixed frame in both R/E. No Store bytes are discounted.
  let count = 101
  let units = 101L * 2048L
  let inventory = 8L * units + 101L * (256L * 64L + 1024L)
  let retained = 8L * 1048576L + 256L * 64L + 34L * 8L + inventory
  let executing = 8L * 1048576L + 256L * 64L + 4096L + 2L * 8L + inventory
  assert_true(retained < 536870912L && executing < 536870912L)
  assert_eq(
    client_captured_content_workspace_capacity(
      1048576,
      inventory_count=count,
      inventory_wire_units=Some(units),
    ),
    Some((retained, executing)),
  )
  for shortage in 0..<3 {
    let ledger = @resources.create_ledger({
      planning_work: 0,
      attempts: 1,
      holdings: 0,
      transfer_bytes: 0L,
      retained_bytes: retained - (if shortage == 1 { 1L } else { 0L }),
      execution_bytes: executing - (if shortage == 2 { 1L } else { 0L }),
    }).unwrap()
    let (frame_r, frame_e) = client_captured_content_workspace_capacity(1048576).unwrap()
    let original = @resources.reserve_attempt(ledger, 0L, frame_r, frame_e).unwrap()
    let grown = @resources.grow_execution_reservation_capacity(
      ledger, original, retained, executing,
    )
    if shortage == 0 {
      grown.unwrap()
    } else if shortage == 1 {
      assert_true(grown is Err(@resources.RetentionLimit))
    } else {
      assert_true(grown is Err(@resources.ExecutionLimit))
    }
    @resources.settle_reservation(ledger, original).unwrap()
    let usage = @resources.ledger_usage(ledger)
    assert_eq(usage.reserved_retention_bytes, 0L)
    assert_eq(usage.reserved_execution_bytes, 0L)
    assert_eq(usage.attempts, 0)
    assert_eq(usage.reserved_attempts, 0)
  }
}

///|
test "measured captured inventory rejects invalid extents and retains complete cold overlap" {
  for (count, units) in [(0, 1L), (1, -1L), (1, 4097L)] {
    assert_eq(
      client_captured_content_workspace_capacity(
        4096,
        inventory_count=count,
        inventory_wire_units=Some(units),
      ),
      None,
    )
  }
  // Two receiving copies coexist: retained issued originals + receiving
  // snapshot/duplicate index. The full single constructor frame stays separate.
  let units = 3L * 2048L
  let one = client_captured_content_workspace_capacity(
    1048576,
    inventory_count=3,
    inventory_wire_units=Some(units),
  ).unwrap()
  let receiving = client_captured_content_workspace_capacity(
    1048576,
    inventory_count=6,
    inventory_wire_units=Some(2L * units),
  ).unwrap()
  let initial = client_captured_content_workspace_capacity(1048576).unwrap()
  assert_eq(receiving.0 - initial.0, 2L * (one.0 - initial.0))
  assert_eq(receiving.1 - initial.1, 2L * (one.1 - initial.1))
}
