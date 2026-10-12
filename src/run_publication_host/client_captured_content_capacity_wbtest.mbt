///|
test "capture workspace independently accounts wire tree and handle overlap" {
  // Eight bounded wire/value copies, 256 tree slots and 32 control slots.
  // Store byte objects and completed RowRun rows have separate charged owners.
  assert_eq(
    client_captured_content_workspace_capacity(4096),
    Some((49408L, 53248L)),
  )
  assert_eq(
    client_captured_content_workspace_capacity(1),
    Some((16648L, 20488L)),
  )
  assert_eq(client_captured_content_workspace_capacity(0), None)
  assert_eq(client_captured_content_workspace_capacity(1048577), None)
}

///|
test "captured inventory workspace includes every declared key before allocation" {
  // The existing frame is 49,408/53,248. Each saved Ref overlaps eight
  // 4,096-byte wire slots, 256 64-byte tree slots and 1,024 control bytes.
  // Three declared keys add 3 * 50,176, independently of actual row count.
  assert_eq(
    client_captured_content_workspace_capacity(4096, inventory_count=3),
    Some((199936L, 203776L)),
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
      retained_bytes: 199936L - (if shortage == 1 { 1L } else { 0L }),
      execution_bytes: 203776L - (if shortage == 2 { 1L } else { 0L }),
    }).unwrap()
    let reserved = @resources.reserve_attempt(ledger, 0L, 199936L, 203776L)
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
      retained_bytes: 49408L - (if shortage == 1 { 1L } else { 0L }),
      execution_bytes: 53248L - (if shortage == 2 { 1L } else { 0L }),
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
        49408L,
      )
      assert_eq(
        @resources.ledger_usage(ledger).reserved_execution_bytes,
        53248L,
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
