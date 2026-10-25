///|
fn preparation_lifetime_child() -> ImportedChildLedger {
  prepare_imported_child_port(
    1L,
    _ => 0,
    _ => 0,
    (_, _) => 1000L,
    (_, _) => 1000L,
    (_, _) => 0,
    _ => 0,
  ).unwrap()
}

///|
test "managed preparation lifetime successful unpublished cleanup drops original once" {
  let prepared = [1, 2, 3]
  let calls = [0]
  let value = prepare_node_managed_run_original(
    preparation_lifetime_child(),
    prepared,
    () => {
      calls[0] = calls[0] + 1
      Ok(())
    },
  )
  assert_eq(check_node_managed_run_preparation(value, prepared), Ok(()))
  assert_eq(cleanup_node_managed_run_admission(value), Ok(()))
  assert_true(value.prepared is None)
  assert_eq(
    check_node_managed_run_preparation(value, prepared),
    Err(AlreadyConsumed),
  )
  assert_eq(cleanup_node_managed_run_admission(value), Ok(()))
  assert_eq(calls[0], 1)
}

///|
test "managed preparation lifetime uncertain unpublished cleanup retains original without retry" {
  let prepared = [1, 2, 3]
  let calls = [0]
  let value = prepare_node_managed_run_original(
    preparation_lifetime_child(),
    prepared,
    () => {
      calls[0] = calls[0] + 1
      Err(Unknown)
    },
  )
  assert_eq(cleanup_node_managed_run_admission(value), Err(Unknown))
  assert_true(
    value.prepared is Some(original) && physical_equal(original, prepared),
  )
  assert_eq(check_node_managed_run_preparation(value, prepared), Ok(()))
  assert_eq(cleanup_node_managed_run_admission(value), Err(Unknown))
  assert_eq(calls[0], 1)
}

///|
test "managed preparation lifetime already stopped cleanup drops original" {
  let prepared = [1]
  let child = preparation_lifetime_child()
  let value = prepare_node_managed_run_original(child, prepared, () => {
    Err(Unknown)
  })
  // Exercise the successful stop latch observed by cleanup, without claiming
  // that an unpublished abort or a new child initialization took place.
  child.stop_attempted = true
  child.stop_outcome = None
  assert_eq(cleanup_node_managed_run_admission(value), Ok(()))
  assert_true(value.prepared is None)
  assert_eq(
    check_node_managed_run_preparation(value, prepared),
    Err(AlreadyConsumed),
  )
}
