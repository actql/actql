///|
// Private port stand-ins only; production has no public callback factory.
// No physical child, actual VM, channel, FD or parent reservation is created.
fn imported_child_fixture(
  admit_code? : Int = 0,
  host_bytes? : Int64 = 4L,
  execution_bytes? : Int64 = 32L,
  report_code? : Int = 0,
) -> (ImportedChildLedger, Ref[Int], Ref[Int], Ref[Int], Array[LedgerUsage]) {
  let current = Ref(0)
  let admits = Ref(0)
  let reports = Ref(0)
  let observations : Array[LedgerUsage] = []
  let value = prepare_imported_child_port(
    7L,
    nonce => {
      if nonce != 7L {
        return -1
      }
      admits.val += 1
      admit_code
    },
    nonce => {
      if nonce != 7L {
        return -1
      }
      current.val
    },
    (nonce, ordinal) => {
      if nonce != 7L {
        return -1L
      }
      match ordinal {
        0 => 10L
        1 => 3L
        2 => 4L
        3 => 20L
        4 => 16L
        5 => execution_bytes
        _ => -1L
      }
    },
    (nonce, ordinal) => {
      if nonce != 7L {
        return -1L
      }
      if ordinal == 0 {
        8L
      } else {
        host_bytes
      }
    },
    (nonce, usage) => {
      if nonce != 7L {
        return -1
      }
      reports.val += 1
      observations.push(usage)
      report_code
    },
    nonce => {
      if nonce != 7L {
        return -1
      }
      0
    },
  ).unwrap()
  (value, current, admits, reports, observations)
}

///|
test "imported child ledger seeds existing VM Host capacity without another attempt" {
  let (value, _, admits, reports, observations) = imported_child_fixture()
  start_imported_child_ledger(value).unwrap()
  let (ledger, wasm, host) = take_imported_child_ledger(value).unwrap()
  assert_eq(admits.val, 1)
  assert_eq(shared_capacity_usage(wasm).capacity, 8L)
  assert_eq(shared_capacity_usage(wasm).allocated, 0L)
  assert_false(shared_capacity_usage(wasm).closing)
  assert_eq(shared_capacity_usage(host).capacity, 4L)
  assert_eq(ledger_usage(ledger).attempts, 0)
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 12L)
  assert_eq(ledger.next_capacity_serial, Some(-3))
  let read = reserve_capacity(ledger, 2L, 3L).unwrap()
  assert_eq(read.reservation.serial, -3)
  assert_eq(ledger_usage(ledger).attempts, 0)
  report_imported_child_ledger(value).unwrap()
  assert_eq(reports.val, 1)
  assert_eq(observations[0], ledger_usage(ledger))
  assert_eq(observations[0].reserved_execution_bytes, 15L)
}

///|
test "imported child ledger original admission and take reject copies and reissue" {
  let (value, _, admits, _, _) = imported_child_fixture()
  let copied = { ..value, }
  assert_true(start_imported_child_ledger(copied) is Err(ForeignOriginal))
  start_imported_child_ledger(value).unwrap()
  assert_true(start_imported_child_ledger(value) is Err(AlreadyConsumed))
  let (ledger, _, _) = take_imported_child_ledger(value).unwrap()
  assert_true(take_imported_child_ledger(value) is Err(AlreadyConsumed))
  let copied_ledger = { ..ledger, }
  assert_true(charge_planning(copied_ledger, 1) is Err(ForeignOwner))
  assert_true(reserve_capacity(copied_ledger, 0L, 0L) is Err(ForeignOwner))
  assert_eq(admits.val, 1)
  assert_eq(ledger_usage(ledger).planning_work, 0)
}

///|
test "imported child ledger Unknown admission keeps the same partial without retry" {
  let (value, _, admits, _, _) = imported_child_fixture(admit_code=-41)
  assert_true(start_imported_child_ledger(value) is Err(Unknown))
  assert_true(value.attempted && value.ledger is None)
  assert_true(
    value.original is Some(original) && physical_equal(original, value),
  )
  assert_true(start_imported_child_ledger(value) is Err(AlreadyConsumed))
  assert_true(take_imported_child_ledger(value) is Err(Unavailable))
  assert_eq(admits.val, 1)
}

///|
test "imported child ledger rejects missing Host overlarge capacities and foreign lifetime" {
  let (missing, _, missing_calls, _, _) = imported_child_fixture(host_bytes=-1L)
  assert_true(start_imported_child_ledger(missing) is Err(Unavailable))
  assert_true(missing.ledger is None && missing.wasm_capacity is None)
  assert_true(start_imported_child_ledger(missing) is Err(AlreadyConsumed))
  assert_eq(missing_calls.val, 1)
  let (unknown, _, _, _, _) = imported_child_fixture(host_bytes=-41L)
  assert_true(start_imported_child_ledger(unknown) is Err(Unknown))
  assert_true(unknown.ledger is None)
  let (short, _, _, _, _) = imported_child_fixture(execution_bytes=11L)
  assert_true(start_imported_child_ledger(short) is Err(InvalidOriginal))
  let (foreign, current, _, _, _) = imported_child_fixture()
  start_imported_child_ledger(foreign).unwrap()
  current.val = -41
  assert_true(
    take_imported_child_ledger(foreign)
    is Err(Resource(ChildFundingUnavailable)),
  )
  current.val = 0
  // Restoring visible currentness cannot erase an uncertain original import.
  assert_true(
    take_imported_child_ledger(foreign)
    is Err(Resource(ChildFundingUnavailable)),
  )
}

///|
test "imported child ledger closing keeps cleanup and fixed physical capacity responsibility" {
  let (value, current, _, _, _) = imported_child_fixture()
  start_imported_child_ledger(value).unwrap()
  let (ledger, wasm, host) = take_imported_child_ledger(value).unwrap()
  let allocation = allocate_shared_capacity(wasm, 2L).unwrap()
  let borrow = borrow_shared_capacity(wasm, allocation).unwrap()
  let before = ledger_usage(ledger)
  stop_imported_child_ledger(value).unwrap()
  current.val = 1
  assert_true(reserve_capacity(ledger, 0L, 0L) is Err(ClosedReservation))
  assert_true(reserve_attempt(ledger, 0L, 0L, 0L) is Err(ClosedReservation))
  assert_true(allocate_shared_capacity(wasm, 1L) is Err(ClosedReservation))
  assert_true(
    borrow_shared_capacity(wasm, allocation) is Err(ClosedReservation),
  )
  retire_shared_capacity(allocation).unwrap()
  return_shared_capacity(borrow).unwrap()
  release_shared_capacity(allocation).unwrap()
  close_shared_capacity(wasm).unwrap()
  close_shared_capacity(host).unwrap()
  assert_true(settle_shared_capacity(wasm) is Err(ChildFundingUnavailable))
  assert_true(
    settle_execution_reservation(ledger, host.reservation)
    is Err(ChildFundingUnavailable),
  )
  assert_true(
    settle_completed_output_reservation(ledger, wasm.reservation, None, 0L, 0L)
    is Err(ChildFundingUnavailable),
  )
  report_imported_child_ledger(value).unwrap()
  assert_eq(ledger_usage(ledger), before)
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 12L)
}

///|
test "imported child ledger lost report retains original snapshot without another send" {
  let (value, _, _, reports, observations) = imported_child_fixture(
    report_code=-41,
  )
  start_imported_child_ledger(value).unwrap()
  let (ledger, _, _) = take_imported_child_ledger(value).unwrap()
  charge_planning(ledger, 2).unwrap()
  assert_true(report_imported_child_ledger(value) is Err(Unknown))
  assert_true(value.pending_report is Some(usage) && usage.planning_work == 2)
  charge_planning(ledger, 1).unwrap()
  assert_true(report_imported_child_ledger(value) is Err(Unknown))
  assert_eq(reports.val, 1)
  assert_eq(observations[0].planning_work, 2)
  assert_eq(ledger_usage(ledger).planning_work, 3)
  let (refused, _, _, refused_reports, _) = imported_child_fixture(
    report_code=-1,
  )
  start_imported_child_ledger(refused).unwrap()
  assert_true(report_imported_child_ledger(refused) is Err(Unavailable))
  assert_true(report_imported_child_ledger(refused) is Err(Unavailable))
  assert_eq(refused_reports.val, 1)
}
