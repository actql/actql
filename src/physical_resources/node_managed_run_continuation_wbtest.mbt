///|
test "Node managed continuation imports one same original and reports preserved cumulative state" {
  let limits = continuation_test_limits()
  let saved = continuation_test_decode(continuation_test_wire()).unwrap()
  let reports : Ref[LedgerUsage?] = Ref(None)
  let calls = Ref(0)
  let stops = Ref(0)
  let child = prepare_imported_child_port(
    1L,
    _ => {
      calls.val += 1
      0
    },
    _ => 0,
    (_, index) => {
      match index {
        0 => limits.planning_work.to_int64()
        1 => limits.attempts.to_int64()
        2 => limits.holdings.to_int64()
        3 => limits.transfer_bytes
        4 => limits.retained_bytes
        _ => limits.execution_bytes
      }
    },
    (_, _) => 0L,
    (_, usage) => {
      reports.val = Some(usage)
      0
    },
    _ => {
      stops.val += 1
      0
    },
    fixed_capacities=false,
  ).unwrap()
  let prepared = Ref(1)
  let admission = prepare_node_managed_run_original(child, prepared, () => {
    Ok(())
  })
  assert_true(
    restore_node_managed_run_admission(admission, Ref(1), saved)
    is Err(ChangedOriginal),
  )
  assert_eq(calls.val, 0)
  let ledger = restore_node_managed_run_admission(admission, prepared, saved).unwrap()
  assert_eq(calls.val, 1)
  assert_eq(ledger_usage(ledger).planning_work, 7)
  assert_eq(ledger_usage(ledger).attempts, 1)
  assert_eq(ledger_usage(ledger).uncertain_transfer_bytes, 3L)
  assert_true(
    restore_node_managed_run_admission(admission, prepared, saved)
    is Err(ChangedOriginal),
  )
  assert_eq(calls.val, 1)
  check_node_managed_run_admission(admission, ledger).unwrap()
  report_imported_child_ledger(child).unwrap()
  assert_eq(reports.val.unwrap(), ledger_usage(ledger))
  // Unknown dispatched transfer stays in the SAME cumulative budget after
  // physical cleanup. Retire only the original child; never zero its report,
  // reset history or acquire another admission on an idempotent cleanup call.
  let cumulative = ledger_usage(ledger)
  assert_eq(cleanup_node_managed_run_admission(admission), Ok(()))
  assert_eq(reports.val.unwrap(), cumulative)
  assert_eq(ledger_usage(ledger), cumulative)
  assert_eq(ledger_usage(ledger).uncertain_transfer_bytes, 3L)
  assert_eq(stops.val, 1)
  assert_eq(cleanup_node_managed_run_admission(admission), Ok(()))
  assert_eq(stops.val, 1)
  assert_eq(ledger_usage(ledger), cumulative)
  assert_true(
    restore_node_managed_run_admission(admission, prepared, saved)
    is Err(ChangedOriginal),
  )
  assert_eq(calls.val, 1)
}

///|
test "Node managed continuation changed import limits retain one original failed cleanup path" {
  let saved = continuation_test_decode(continuation_test_wire()).unwrap()
  let admits = Ref(0)
  let stops = Ref(0)
  let child = prepare_imported_child_port(
    1L,
    _ => {
      admits.val += 1
      0
    },
    _ => 0,
    (_, index) => {
      match index {
        0 => 20L
        1 => 5L
        2 => 1L
        3 => 10L
        _ => 8L
      }
    },
    (_, _) => 0L,
    (_, _) => 0,
    _ => {
      stops.val += 1
      0
    },
    fixed_capacities=false,
  ).unwrap()
  let prepared = Ref(1)
  let admission = prepare_node_managed_run_original(child, prepared, () => {
    Ok(())
  })
  assert_true(
    restore_node_managed_run_admission(admission, prepared, saved)
    is Err(ChangedLimits),
  )
  assert_eq(admits.val, 1)
  assert_true(admission.ledger is Some(_))
  assert_eq(ledger_usage(admission.ledger.unwrap()).attempts, 0)
  cleanup_node_managed_run_admission(admission).unwrap()
  cleanup_node_managed_run_admission(admission).unwrap()
  assert_eq(stops.val, 1)
  assert_true(
    restore_node_managed_run_admission(admission, prepared, saved)
    is Err(ChangedOriginal),
  )
  assert_eq(admits.val, 1)
}
