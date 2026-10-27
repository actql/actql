///|
// Explicit original physical-owner ports only; no child IO, Host allocation,
// Account, durable journal or physical retirement acknowledgement.
fn mutable_managed_current_fixture(
  current : () -> Unit,
) -> (NodeManagedRunAdmission[Ref[Int]], Ref[Int], Ledger) {
  let child = prepare_imported_child_port(
    1L,
    _ => 0,
    _ => {
      current()
      0
    },
    (_, _) => 100000L,
    (_, _) => abort("MutableOriginalUsesNoVMCapacity"),
    (_, _) => 0,
    _ => 0,
    fixed_capacities=false,
  ).unwrap()
  let prepared = Ref(1)
  let admission = prepare_node_managed_run_original(child, prepared, () => {
    Ok(())
  })
  let ledger = start_node_managed_run_admission(admission).unwrap()
  (admission, prepared, ledger)
}

///|
test "mutable managed admission retains parked refusal after one original current" {
  let calls = Ref(0)
  let (admission, prepared, ledger) = mutable_managed_current_fixture(() => {
    calls.val += 1
  })
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = begin_original_ledger_inventory(ledger, bootstrap, 16, 4, 4).unwrap()
  let origin = original_read_test_origin()
  let (_, consumer) = resource_park_test_consumer(identity, origin)
  let park = park_original_resource_consumer(consumer, origin).unwrap()
  calls.val = 0
  assert_true(
    check_node_managed_run_mutable_admission(admission, prepared, ledger)
    is Err(Resource(ResourceParked)),
  )
  assert_eq(calls.val, 1)
  // The existing private test invalidation is not a product unpark/ACK API.
  resource_park_test_invalidate(park)
  settle_funded_read_consumer(consumer, true).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  retire_original_resource_park(park).unwrap()
  cleanup_node_managed_run_admission(admission).unwrap()
}

///|
test "mutable managed current cannot replace child correspondence or retire preparation" {
  for retire in [false, true] {
    let calls = Ref(0)
    let armed = Ref(false)
    let selected : Ref[NodeManagedRunAdmission[Ref[Int]]?] = Ref(None)
    let (admission, prepared, ledger) = mutable_managed_current_fixture(() => {
      calls.val += 1
      if armed.val && selected.val is Some(original) {
        armed.val = false
        if retire {
          original.cleaned = true
          original.prepared = None
        } else {
          original.child.origin.ledger = None
        }
      }
    })
    selected.val = Some(admission)
    calls.val = 0
    armed.val = true
    let result = check_node_managed_run_mutable_admission(
      admission, prepared, ledger,
    )
    if retire {
      assert_true(result is Err(AlreadyConsumed))
    } else {
      assert_true(result is Err(ForeignOriginal))
    }
    assert_eq(calls.val, 1)
    // Undo only the private fixture's artificial mutation, then use the same
    // original admission cleanup. No retry/new original or refund is issued.
    admission.cleaned = false
    admission.prepared = Some(prepared)
    admission.child.origin.ledger = Some(ledger)
    cleanup_node_managed_run_admission(admission).unwrap()
  }
}
