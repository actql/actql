///|
// Portable original admission/control, with the existing nominal backed ports.
// These are Resource/current-counter tests, not physical STORE acceptance.
test "same operation Work segment observes physical current once and expires its original view" {
  let (access, input, admission, body, ledger, frame, retirement, holder) = backed_prepared_operation_fixture()
  let control = reserve_prepared_run_operation_controls(
    admission,
    body,
    ledger,
    () => (Ok(()) : Result[Unit, Unit]),
    None,
    1L,
    1L,
  ).unwrap()
  let current = frame.origin.current
  let calls = Ref(0)
  frame.origin.current = nonce => {
    calls.val += 1
    current(nonce)
  }
  let escaped : Ref[((Int) -> Result[Unit, LedgerIssue])?] = Ref(None)
  let before = ledger_usage(ledger).planning_work
  let result : Result[Int, NodeManagedRunOperationIssue[Unit]] = with_prepared_run_operation_control_work(
    admission,
    body,
    ledger,
    () => Ok(()),
    control,
    () => true,
    spend => {
      escaped.val = Some(spend)
      // Availability probes do not invent work. Positive steps below still
      // debit the original finite four-unit fixture, without a quota raise.
      for _ in 0..<4097 {
        spend(0).unwrap()
      }
      for _ in 0..<3 {
        spend(1).unwrap()
      }
      Ok(3)
    },
  )
  assert_true(result is Ok(3))
  assert_eq(calls.val, 1)
  assert_eq(ledger_usage(ledger).planning_work, before + 3)
  assert_eq(escaped.val.unwrap()(1), Err(ForeignOwner))
  assert_eq(calls.val, 1)
  assert_eq(ledger_usage(ledger).planning_work, before + 3)
  frame.origin.current = current
  escaped.val = None
  settle_capacity(ledger, control).unwrap()
  assert_false(retire_transferred_preparation(retirement).unwrap())
  return_preparation_body_borrow(holder).unwrap() |> ignore
  release_prepared_run_holder(admission).unwrap() |> ignore
  assert_true(retire_transferred_preparation(retirement).unwrap())
  report_imported_child_ledger(frame).unwrap()
  retire_backed_execution_live_child_after_owner_ack(access, input).unwrap()
  cleanup_prepared_run_admission(admission).unwrap()
}

///|
test "operation Work refusal preserves spent prefix and closes the same view before retry" {
  let (_, _, admission, body, ledger, _, _, _) = backed_prepared_operation_fixture()
  let control = reserve_prepared_run_operation_controls(
    admission,
    body,
    ledger,
    () => (Ok(()) : Result[Unit, Unit]),
    None,
    1L,
    1L,
  ).unwrap()
  let before = ledger_usage(ledger)
  let result : Result[Unit, NodeManagedRunOperationIssue[Unit]] = with_prepared_run_operation_control_work(
    admission,
    body,
    ledger,
    () => Ok(()),
    control,
    () => true,
    spend => {
      spend(3).unwrap()
      assert_eq(spend(2), Err(PlanningLimit)) catch {
        _ => panic()
      }
      assert_eq(spend(1), Err(ForeignOwner)) catch {
        _ => panic()
      }
      Err(Control(PlanningLimit))
    },
  )
  assert_true(result is Err(Control(PlanningLimit)))
  assert_eq(ledger_usage(ledger).planning_work, before.planning_work + 3)
  assert_eq(ledger_usage(ledger).live_reservations, before.live_reservations)
  assert_true(capacity_reservation_open(control))
}

///|
test "operation Work checks foreign original and reentrant or stopped lifetime before debit" {
  let (_, _, admission, body, ledger, frame, _, _) = backed_prepared_operation_fixture()
  let control = reserve_prepared_run_operation_controls(
    admission,
    body,
    ledger,
    () => (Ok(()) : Result[Unit, Unit]),
    None,
    1L,
    1L,
  ).unwrap()
  let entered = Ref(false)
  let foreign : Result[Unit, NodeManagedRunOperationIssue[Unit]] = with_prepared_run_operation_control_work(
    admission,
    Ref(4),
    ledger,
    () => Ok(()),
    control,
    () => true,
    _ => {
      entered.val = true
      Ok(())
    },
  )
  assert_true(foreign is Err(_))
  assert_false(entered.val)
  let same : Ref[((Int) -> Result[Unit, LedgerIssue])?] = Ref(None)
  let reenter = Ref(false)
  let result : Result[Unit, NodeManagedRunOperationIssue[Unit]] = with_prepared_run_operation_control_work(
    admission,
    body,
    ledger,
    () => Ok(()),
    control,
    () => {
      if reenter.val && same.val is Some(spend) {
        assert_eq(spend(1), Err(ForeignOwner)) catch {
          _ => panic()
        }
      }
      true
    },
    spend => {
      same.val = Some(spend)
      reenter.val = true
      assert_eq(spend(1), Err(ForeignOwner)) catch {
        _ => panic()
      }
      Err(Control(ForeignOwner))
    },
  )
  assert_true(result is Err(Control(ForeignOwner)))
  assert_eq(ledger_usage(ledger).planning_work, 0)
  frame.origin.stopping = true
  let stopped : Result[Unit, NodeManagedRunOperationIssue[Unit]] = with_prepared_run_operation_control_work(
    admission,
    body,
    ledger,
    () => Ok(()),
    control,
    () => true,
    _ => {
      entered.val = true
      Ok(())
    },
  )
  assert_true(stopped is Err(_))
  assert_false(entered.val)
  assert_eq(ledger_usage(ledger).planning_work, 0)
}

///|
test "operation Work view expires across another existing reservation resize" {
  let (_, _, admission, body, ledger, _, _, _) = backed_prepared_operation_fixture()
  let control = reserve_prepared_run_operation_controls(
    admission,
    body,
    ledger,
    () => (Ok(()) : Result[Unit, Unit]),
    None,
    1L,
    1L,
  ).unwrap()
  let other = reserve_capacity(ledger, 0L, 0L).unwrap()
  let result : Result[Unit, NodeManagedRunOperationIssue[Unit]] = with_prepared_run_operation_control_work(
    admission,
    body,
    ledger,
    () => Ok(()),
    control,
    () => true,
    spend => {
      spend(1).unwrap()
      // An existing token can grow without changing the capacity serial.
      // The original usage fence still catches that allocating boundary.
      grow_capacity_reservation(ledger, other, 1L, 1L).unwrap()
      assert_eq(spend(1), Err(ForeignOwner)) catch {
        _ => panic()
      }
      Err(Control(ForeignOwner))
    },
  )
  assert_true(result is Err(Control(ForeignOwner)))
  assert_eq(ledger_usage(ledger).planning_work, 1)
  assert_true(capacity_reservation_open(control))
  assert_true(capacity_reservation_open(other))
}
