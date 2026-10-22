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
