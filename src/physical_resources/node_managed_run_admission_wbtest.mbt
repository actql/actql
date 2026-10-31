///|
fn atomic_managed_run_reservation_fixture(
  current : () -> Unit,
) -> (NodeManagedRunAdmission[Array[Int]], Array[Int], Ledger) {
  let child = prepare_imported_child_port(
    1L,
    _ => 0,
    _ => {
      current()
      0
    },
    (_, _) => 1000L,
    (_, _) => 0L,
    (_, _) => 0,
    _ => 0,
    fixed_capacities=false,
  ).unwrap()
  let prepared = [1]
  let admission = prepare_node_managed_run_original(child, prepared, () => {
    Ok(())
  })
  let ledger = start_node_managed_run_admission(admission).unwrap()
  (admission, prepared, ledger)
}

///|
test "atomic managed attempt keeps exact preparation and one original current across quota refusal and reservation" {
  let calls = Ref(0)
  let (admission, prepared, ledger) = atomic_managed_run_reservation_fixture(() => {
    calls.val += 1
  })
  let before = ledger_usage(ledger)
  let observed = calls.val
  assert_true(
    reserve_node_managed_run_attempt(admission, [1], ledger, 0L, 1L, 1L)
    is Err(ForeignOriginal),
  )
  assert_eq(calls.val, observed)
  assert_true(
    reserve_node_managed_run_attempt(admission, prepared, ledger, 0L, -1L, 1L)
    is Err(Resource(InvalidCharge)),
  )
  assert_eq(calls.val, observed)
  let limit = ledger_limits(ledger).retained_bytes
  assert_true(
    reserve_node_managed_run_attempt(
      admission,
      prepared,
      ledger,
      0L,
      limit + 1L,
      1L,
    )
    is Err(Resource(RetentionLimit)),
  )
  assert_eq(calls.val, observed + 1)
  assert_eq(ledger_usage(ledger), before)
  let original = reserve_node_managed_run_attempt(
    admission, prepared, ledger, 0L, 7L, 5L,
  ).unwrap()
  assert_eq(calls.val, observed + 2)
  assert_true(reservation_open(original))
  assert_eq(
    ledger_usage(ledger).reserved_retention_bytes,
    before.reserved_retention_bytes + 7L,
  )
  assert_eq(
    ledger_usage(ledger).reserved_execution_bytes,
    before.reserved_execution_bytes + 5L,
  )
  settle_reservation(ledger, original).unwrap()
  cleanup_node_managed_run_admission(admission).unwrap()
}

///|
test "atomic managed attempt refuses original lifetime or stop changes inside current before committing a reservation" {
  for stop in [false, true] {
    let selected : Ref[NodeManagedRunAdmission[Array[Int]]?] = Ref(None)
    let (admission, prepared, ledger) = atomic_managed_run_reservation_fixture(() => {
      if selected.val is Some(original) {
        if stop {
          original.child.origin.stopping = true
        } else {
          original.prepared = None
        }
      }
    })
    selected.val = Some(admission)
    let before = ledger_usage(ledger)
    let result = reserve_node_managed_run_attempt(
      admission, prepared, ledger, 0L, 7L, 5L,
    )
    assert_true(
      if stop {
        result is Err(Resource(ClosedReservation))
      } else {
        result is Err(ForeignOriginal)
      },
    )
    assert_eq(ledger_usage(ledger), before)
    // Only the explicit whitebox mutation is restored, to retire this fixture's
    // original admission. No new request, reservation or physical use is made.
    selected.val = None
    admission.prepared = Some(prepared)
    admission.child.origin.stopping = false
    cleanup_node_managed_run_admission(admission).unwrap()
  }
}

///|
// No admission, limits, Ledger or reservation is issued in these callback-
// outcome counters. The original child stays unstarted throughout.
fn unstarted_managed_run_child() -> ImportedChildLedger {
  prepare_imported_child_port(
    1L,
    _ => abort("NoAdmitInUnpublishedCounter"),
    _ => abort("NoCurrentInUnpublishedCounter"),
    (_, _) => abort("NoLimitsInUnpublishedCounter"),
    (_, _) => abort("NoCapacityInUnpublishedCounter"),
    (_, _) => abort("NoUsageInUnpublishedCounter"),
    _ => abort("NoStopInUnpublishedCounter"),
    fixed_capacities=false,
  ).unwrap()
}

///|
test "unpublished managed Run Unknown outcome is retained without another abort" {
  let calls = Ref(0)
  let admission = prepare_node_managed_run_original(
    unstarted_managed_run_child(),
    Ref(1),
    () => {
      calls.val += 1
      Err(Unknown)
    },
  )
  assert_true(cleanup_node_managed_run_admission(admission) is Err(Unknown))
  assert_true(cleanup_node_managed_run_admission(admission) is Err(Unknown))
  assert_eq(calls.val, 1)
  assert_true(admission.child.ledger is None)
}

///|
test "unpublished managed Run reentry sees the original unresolved stop flight" {
  let calls = Ref(0)
  let held : Ref[NodeManagedRunAdmission[Ref[Int]]?] = Ref(None)
  let nested : Ref[Result[Unit, ImportedChildLedgerIssue]?] = Ref(None)
  let admission = prepare_node_managed_run_original(
    unstarted_managed_run_child(),
    Ref(1),
    () => {
      calls.val += 1
      if calls.val == 1 {
        nested.val = Some(cleanup_node_managed_run_admission(held.val.unwrap()))
      }
      Ok(())
    },
  )
  held.val = Some(admission)
  assert_true(cleanup_node_managed_run_admission(admission) is Ok(_))
  assert_true(nested.val is Some(Err(Unknown)))
  assert_true(cleanup_node_managed_run_admission(admission) is Ok(_))
  assert_eq(calls.val, 1)
  assert_true(admission.child.ledger is None)
}
