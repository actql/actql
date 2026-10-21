///|
// Existing Resource accounting with private physical-port stand-ins. These
// tests issue no actual Node facility, Model purpose or public permission.
fn managed_run_bootstrap_fixture(
  observe_current? : () -> Unit = () => (),
  purpose? : NodeManagedRunPurpose = SourceCompute,
) -> (
  NodeManagedRunAdmission[Ref[Int]],
  Ref[Int],
  Ledger,
  Ref[Int],
  Ref[Int],
  Ref[Int],
  Array[LedgerUsage],
) {
  let current = Ref(0)
  let calls = Ref(0)
  let retire_at = Ref(2147483647)
  let reports : Array[LedgerUsage] = []
  let child = prepare_imported_child_port(
    17L,
    _ => 0,
    _ => {
      calls.val += 1
      observe_current()
      if calls.val >= retire_at.val {
        1
      } else {
        current.val
      }
    },
    (_, ordinal) => {
      match ordinal {
        0 => 20L
        1 => 10L
        2 => 10L
        3 => 100L
        4 => 100L
        5 => 100L
        _ => -1L
      }
    },
    (_, _) => abort("NoFixedCapacityForManagedBootstrap"),
    (_, usage) => {
      reports.push(usage)
      0
    },
    _ => 0,
    fixed_capacities=false,
  ).unwrap()
  let prepared = Ref(3)
  let admission = prepare_node_managed_run_original(
    child,
    prepared,
    () => abort("PublishedBootstrapCannotAbortUnpublished"),
    purpose~,
  )
  let ledger = start_node_managed_run_admission(admission).unwrap()
  (admission, prepared, ledger, current, calls, retire_at, reports)
}

///|
test "managed purpose cannot convert the original Source Compute child to Mock Model" {
  let (admission, prepared, ledger, _, _, _, reports) = managed_run_bootstrap_fixture()
  check_node_source_compute_run_preparation(admission, prepared).unwrap()
  let before = ledger_usage(ledger)
  assert_true(
    check_node_local_mock_model_run_preparation(admission, prepared)
    is Err(Unavailable),
  )
  assert_eq(ledger_usage(ledger), before)
  assert_eq(ledger.next_capacity_serial, Some(-1))
  cleanup_node_managed_run_admission(admission).unwrap()
  assert_eq(reports.length(), 1)
}

///|
test "managed purpose binds the separately selected Mock original and its early bootstrap" {
  let (admission, prepared, ledger, _, _, _, reports) = managed_run_bootstrap_fixture(
    purpose=LocalMockModel,
  )
  check_node_local_mock_model_run_preparation(admission, prepared).unwrap()
  assert_true(
    check_node_source_compute_run_preparation(admission, prepared)
    is Err(Unavailable),
  )
  let bootstrap = reserve_node_managed_run_read_bootstrap(
    admission, prepared, ledger, 3L, 2L,
  ).unwrap()
  begin_original_ledger_inventory(ledger, bootstrap, 2, 0, 0).unwrap() |> ignore
  let source_sibling = reserve_capacity(ledger, 5L, 4L).unwrap()
  assert_true(cleanup_node_managed_run_admission(admission) is Err(Unavailable))
  assert_true(capacity_reservation_open(bootstrap))
  assert_eq(reports.length(), 0)
  settle_capacity(ledger, source_sibling).unwrap()
  cleanup_node_managed_run_admission(admission).unwrap()
  assert_false(capacity_reservation_open(bootstrap))
  assert_eq(reports.length(), 1)
}

///|
test "managed purpose rejects copied admission and equal other preparation before resource changes" {
  let (admission, prepared, ledger, _, _, _, _) = managed_run_bootstrap_fixture(
    purpose=LocalMockModel,
  )
  let before = ledger_usage(ledger)
  assert_true(
    check_node_local_mock_model_run_preparation({ ..admission, }, prepared)
    is Err(ForeignOriginal),
  )
  assert_true(
    check_node_local_mock_model_run_preparation(admission, Ref(3))
    is Err(ForeignOriginal),
  )
  assert_eq(ledger_usage(ledger), before)
  assert_eq(ledger.next_capacity_serial, Some(-1))
  cleanup_node_managed_run_admission(admission).unwrap()
}

///|
test "managed bootstrap current reentry cannot consume another initialization" {
  let held : Ref[(NodeManagedRunAdmission[Ref[Int]], Ref[Int], Ledger)?] = Ref(
    None,
  )
  let nested : Ref[Result[CapacityReservation, ImportedChildLedgerIssue]?] = Ref(
    None,
  )
  let (admission, prepared, ledger, _, _, _, _) = managed_run_bootstrap_fixture(observe_current=() => {
      if held.val is Some((admission, prepared, ledger)) && nested.val is None {
        nested.val = Some(
          reserve_node_managed_run_read_bootstrap(
            admission, prepared, ledger, 3L, 2L,
          ),
        )
      }
    },
  )
  held.val = Some((admission, prepared, ledger))
  let bootstrap = reserve_node_managed_run_read_bootstrap(
    admission, prepared, ledger, 3L, 2L,
  ).unwrap()
  assert_true(nested.val is Some(Err(AlreadyConsumed)))
  assert_eq(ledger.next_capacity_serial, Some(-2))
  cleanup_node_managed_run_admission(admission).unwrap()
  assert_false(capacity_reservation_open(bootstrap))
}

///|
test "managed read bootstrap stays with admission when Scope construction refuses" {
  let (admission, prepared, ledger, _, _, _, reports) = managed_run_bootstrap_fixture()
  let bootstrap = reserve_node_managed_run_read_bootstrap(
    admission, prepared, ledger, 3L, 2L,
  ).unwrap()
  assert_true(
    begin_original_ledger_inventory(ledger, bootstrap, -1, 0, 0)
    is Err(IncompleteInventory),
  )
  assert_true(capacity_reservation_open(bootstrap))
  cleanup_node_managed_run_admission(admission).unwrap()
  assert_false(capacity_reservation_open(bootstrap))
  assert_eq(ledger.next_capacity_serial, Some(-2))
  assert_eq(reports.length(), 1)
  assert_eq(reports[0].reserved_retention_bytes, 0L)
  assert_eq(reports[0].reserved_execution_bytes, 0L)
  cleanup_node_managed_run_admission(admission).unwrap()
  assert_eq(reports.length(), 1)
}

///|
test "managed read bootstrap never retires before a recorded zero-byte child" {
  let (admission, prepared, ledger, _, _, _, reports) = managed_run_bootstrap_fixture()
  let bootstrap = reserve_node_managed_run_read_bootstrap(
    admission, prepared, ledger, 3L, 2L,
  ).unwrap()
  begin_original_ledger_inventory(ledger, bootstrap, 2, 0, 0).unwrap() |> ignore
  let child = reserve_capacity(ledger, 0L, 0L).unwrap()
  assert_true(cleanup_node_managed_run_admission(admission) is Err(Unavailable))
  assert_true(capacity_reservation_open(bootstrap))
  assert_eq(reports.length(), 0)
  settle_capacity(ledger, child).unwrap()
  cleanup_node_managed_run_admission(admission).unwrap()
  assert_false(capacity_reservation_open(bootstrap))
  assert_eq(ledger.next_capacity_serial, Some(-3))
}

///|
test "managed bootstrap post-reservation current refusal keeps original cleanup reachable" {
  let (admission, prepared, ledger, _, calls, retire_at, reports) = managed_run_bootstrap_fixture()
  retire_at.val = calls.val + 3
  assert_true(
    reserve_node_managed_run_read_bootstrap(admission, prepared, ledger, 3L, 2L)
    is Err(Resource(ClosedReservation)),
  )
  let bootstrap = admission.read_bootstrap.unwrap()
  assert_true(capacity_reservation_open(bootstrap))
  cleanup_node_managed_run_admission(admission).unwrap()
  assert_false(capacity_reservation_open(bootstrap))
  assert_eq(reports.length(), 1)
}

///|
test "managed bootstrap copied prepared or admission cannot consume the original" {
  let (admission, prepared, ledger, _, _, _, _) = managed_run_bootstrap_fixture()
  assert_true(
    reserve_node_managed_run_read_bootstrap(admission, Ref(3), ledger, 3L, 2L)
    is Err(ForeignOriginal),
  )
  assert_true(
    reserve_node_managed_run_read_bootstrap(
      { ..admission, },
      prepared,
      ledger,
      3L,
      2L,
    )
    is Err(ForeignOriginal),
  )
  assert_eq(ledger.next_capacity_serial, Some(-1))
  reserve_node_managed_run_read_bootstrap(admission, prepared, ledger, 3L, 2L).unwrap()
  |> ignore
  let before = ledger_usage(ledger)
  assert_true(
    reserve_node_managed_run_read_bootstrap(admission, prepared, ledger, 3L, 2L)
    is Err(AlreadyConsumed),
  )
  assert_eq(ledger_usage(ledger), before)
  cleanup_node_managed_run_admission(admission).unwrap()
}

///|
test "managed bootstrap cannot replace spent capacity or ordinary zero-byte identities" {
  for capacity_only in [true, false] {
    let (admission, prepared, ledger, _, _, _, _) = managed_run_bootstrap_fixture()
    if capacity_only {
      let spent = reserve_capacity(ledger, 0L, 0L).unwrap()
      settle_capacity(ledger, spent).unwrap()
    } else {
      let spent = reserve_attempt(ledger, 0L, 0L, 0L).unwrap()
      settle_reservation(ledger, spent).unwrap()
    }
    let before = ledger_usage(ledger)
    assert_true(
      reserve_node_managed_run_read_bootstrap(
        admission, prepared, ledger, 3L, 2L,
      )
      is Err(Resource(InvalidCharge)),
    )
    assert_true(admission.read_bootstrap is None)
    assert_eq(ledger_usage(ledger), before)
    cleanup_node_managed_run_admission(admission).unwrap()
  }
}

///|
test "managed bootstrap uncertain original remains retained after callback restoration" {
  let (admission, prepared, ledger, current, _, _, reports) = managed_run_bootstrap_fixture()
  let bootstrap = reserve_node_managed_run_read_bootstrap(
    admission, prepared, ledger, 3L, 2L,
  ).unwrap()
  current.val = -41
  assert_true(
    check_node_managed_run_admission(admission, ledger)
    is Err(Resource(ChildFundingUnavailable)),
  )
  assert_true(
    cleanup_node_managed_run_admission(admission)
    is Err(Resource(ChildFundingUnavailable)),
  )
  current.val = 0
  assert_true(
    cleanup_node_managed_run_admission(admission)
    is Err(Resource(ChildFundingUnavailable)),
  )
  assert_true(capacity_reservation_open(bootstrap))
  assert_eq(reports.length(), 0)
}
