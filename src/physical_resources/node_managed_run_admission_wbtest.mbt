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

///|
test "closed managed operation keeps original refusal before any reservation history with one current" {
  let calls = Ref(0)
  let (admission, prepared, ledger) = atomic_managed_run_reservation_fixture(() => {
    calls.val += 1
  })
  let before = ledger_usage(ledger)
  let serials = (ledger.next_capacity_serial, ledger.next_attempt_serial)
  let observed = calls.val
  let original : () -> Result[Unit, String] = () => Err("retired")
  assert_true(
    reserve_node_managed_run_operation(
      admission,
      prepared,
      ledger,
      original,
      None,
      7L,
      5L,
      true,
      0L,
      1L,
      1L,
    )
    is Err(Original("retired")),
  )
  assert_eq(calls.val, observed + 1)
  assert_eq(ledger_usage(ledger), before)
  assert_eq((ledger.next_capacity_serial, ledger.next_attempt_serial), serials)
  cleanup_node_managed_run_admission(admission).unwrap()
}

///|
test "closed managed operation retains actual control on body refusal and reuses it for physical and construction" {
  let calls = Ref(0)
  let (admission, prepared, ledger) = atomic_managed_run_reservation_fixture(() => {
    calls.val += 1
  })
  let original : () -> Result[Unit, String] = () => Ok(())
  let before = ledger_usage(ledger)
  let observed = calls.val
  let (control, body) = reserve_node_managed_run_operation(
    admission,
    prepared,
    ledger,
    original,
    None,
    7L,
    5L,
    true,
    0L,
    ledger_limits(ledger).retained_bytes + 1L,
    1L,
  ).unwrap()
  assert_eq(calls.val, observed + 1)
  assert_true(body is Err(RetentionLimit))
  assert_true(capacity_reservation_matches(ledger, control, 7L, 5L))
  let refused = ledger_usage(ledger)
  assert_eq(refused.live_reservations, before.live_reservations + 1)
  assert_eq(
    refused.reserved_retention_bytes,
    before.reserved_retention_bytes + 7L,
  )
  assert_eq(
    refused.reserved_execution_bytes,
    before.reserved_execution_bytes + 5L,
  )
  assert_eq(refused.attempts, before.attempts)
  for physical_attempt in [true, false] {
    let observed = calls.val
    let (same, body) = reserve_node_managed_run_operation(
      admission,
      prepared,
      ledger,
      original,
      Some(control),
      7L,
      5L,
      physical_attempt,
      0L,
      1L,
      1L,
    ).unwrap()
    assert_eq(calls.val, observed + 1)
    assert_true(physical_equal(same, control))
    match body.unwrap() {
      Physical(token) => {
        assert_true(physical_attempt)
        settle_reservation(ledger, token).unwrap()
      }
      Construction(token) => {
        assert_false(physical_attempt)
        settle_capacity(ledger, token).unwrap()
      }
    }
  }
  assert_true(capacity_reservation_open(control))
  settle_capacity(ledger, control).unwrap()
  assert_eq(ledger_usage(ledger).live_reservations, 0)
  cleanup_node_managed_run_admission(admission).unwrap()
}

///|
test "closed managed operation rechecks Resource originals after the nonescaping consumer before mutation" {
  for replace_child in [false, true] {
    let calls = Ref(0)
    let (admission, prepared, ledger) = atomic_managed_run_reservation_fixture(() => {
      calls.val += 1
    })
    let before = ledger_usage(ledger)
    let serials = (ledger.next_capacity_serial, ledger.next_attempt_serial)
    let original : () -> Result[Unit, String] = () => {
      if replace_child {
        admission.child.origin.ledger = None
      } else {
        admission.prepared = None
      }
      Ok(())
    }
    let observed = calls.val
    assert_true(
      reserve_node_managed_run_operation(
        admission,
        prepared,
        ledger,
        original,
        None,
        7L,
        5L,
        true,
        0L,
        1L,
        1L,
      )
      is Err(Admission(ForeignOriginal)),
    )
    assert_eq(calls.val, observed + 1)
    assert_eq(ledger_usage(ledger), before)
    assert_eq(
      (ledger.next_capacity_serial, ledger.next_attempt_serial),
      serials,
    )
    // Restore only this deliberate whitebox mutation for the original cleanup.
    admission.prepared = Some(prepared)
    admission.child.origin.ledger = Some(ledger)
    cleanup_node_managed_run_admission(admission).unwrap()
  }
}

///|
test "closed managed controls share the one original boundary without a dummy body" {
  let calls = Ref(0)
  let (admission, prepared, ledger) = atomic_managed_run_reservation_fixture(() => {
    calls.val += 1
  })
  let refused : () -> Result[Unit, String] = () => Err("retired")
  let before = ledger_usage(ledger)
  let serials = (ledger.next_capacity_serial, ledger.next_attempt_serial)
  let observed = calls.val
  assert_true(
    reserve_node_managed_run_operation_controls(
      admission,
      prepared,
      ledger,
      refused,
      None,
      7L,
      5L,
    )
    is Err(Original("retired")),
  )
  assert_eq(calls.val, observed + 1)
  assert_eq(ledger_usage(ledger), before)
  assert_eq((ledger.next_capacity_serial, ledger.next_attempt_serial), serials)
  let original : () -> Result[Unit, String] = () => Ok(())
  let observed = calls.val
  let control = reserve_node_managed_run_operation_controls(
    admission,
    prepared,
    ledger,
    original,
    None,
    7L,
    5L,
  ).unwrap()
  assert_eq(calls.val, observed + 1)
  let debited = ledger_usage(ledger)
  let observed = calls.val
  let reused = reserve_node_managed_run_operation_controls(
    admission,
    prepared,
    ledger,
    original,
    Some(control),
    7L,
    5L,
  ).unwrap()
  assert_eq(calls.val, observed + 1)
  assert_true(physical_equal(reused, control))
  assert_eq(ledger_usage(ledger), debited)
  assert_eq(debited.attempts, before.attempts)
  assert_eq(ledger.next_attempt_serial, serials.1)
  settle_capacity(ledger, control).unwrap()
  cleanup_node_managed_run_admission(admission).unwrap()
}

///|
// Actual Resource accounting with the existing original imported-child fixture.
// Model quantity observations and final settlement are explicit fixture ports,
// not an ordinary provider, Effect authorization or physical cleanup ACK.
test "non Model prepared physical operation preserves configured consumed and uncertain Model quantities" {
  for configured in [true, false] {
    let calls = Ref(0)
    let (admission, prepared, ledger) = atomic_managed_run_reservation_fixture(() => {
      calls.val += 1
    })
    if configured {
      configure_quantities(ledger, {
        tokens: 3L,
        cost_units: 2L,
        duration_ms: 1L,
      }).unwrap()
      let model = reserve_attempt(
        ledger,
        0L,
        0L,
        0L,
        quantities=Some({ tokens: 3L, cost_units: 2L, duration_ms: 1L, }),
      ).unwrap()
      mark_quantities_uncertain(ledger, model).unwrap()
      observe_quantities(ledger, model, tokens=Some(3L)).unwrap()
      settle_reservation(ledger, model).unwrap()
      assert_eq(quantity_usage(ledger).consumed.tokens, 3L)
      assert_eq(quantity_usage(ledger).uncertain.cost_units, 2L)
      assert_eq(quantity_usage(ledger).uncertain.duration_ms, 1L)
    }
    let quantities = quantity_usage(ledger)
    let limits = ledger.quantity_limits
    let before = ledger_usage(ledger)
    let observations = calls.val
    let (control, body) = reserve_node_managed_run_operation(
      admission,
      prepared,
      ledger,
      () => (Ok(()) : Result[Unit, Unit]),
      None,
      3L,
      2L,
      true,
      5L,
      7L,
      9L,
    ).unwrap()
    guard body.unwrap() is Physical(physical) else {
      fail(
        "selected non Model Effect must keep its original physical reservation",
      )
    }
    assert_eq(calls.val, observations + 1)
    assert_eq(quantity_usage(ledger), quantities)
    assert_true(ledger.quantity_limits == limits)
    assert_eq(
      ledger_usage(ledger).reserved_attempts,
      before.reserved_attempts + 1,
    )
    assert_eq(
      ledger_usage(ledger).reserved_transfer_bytes,
      before.reserved_transfer_bytes + 5L,
    )
    consume_reserved_attempt(ledger, physical).unwrap()
    charge_transfer(ledger, physical, 2L).unwrap()
    settle_reservation(ledger, physical).unwrap()
    settle_capacity(ledger, control).unwrap()
    assert_eq(ledger_usage(ledger).attempts, before.attempts + 1)
    assert_eq(
      ledger_usage(ledger).transferred_bytes,
      before.transferred_bytes + 2L,
    )
    assert_eq(quantity_usage(ledger), quantities)
    assert_true(ledger.quantity_limits == limits)
    cleanup_node_managed_run_admission(admission).unwrap()
  }
}
