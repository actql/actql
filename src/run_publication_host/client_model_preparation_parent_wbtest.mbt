///|
test "checked Model Scope borrows the first preparation reservation instead of settling its compiled parent" {
  // Logical ownership fixture only. These independent byte vectors do not
  // establish physical compiler/Model coefficients or an installed admission.
  let ledger = @resources.create_ledger({
    planning_work: 3,
    attempts: 2,
    holdings: 3,
    transfer_bytes: 11L,
    retained_bytes: 100L,
    execution_bytes: 100L,
  }).unwrap()
  let input = [1]
  let parent : @resources.PreparationCapacity[Array[Int], ClientCompiledRun] = @resources.reserve_preparation_capacity(
    ledger,
    input,
    40L,
    30L,
    max_borrowers=2,
  ).unwrap()
  let identity = @resources.begin_preparation_capacity_inventory(
    parent, input, 1, 0, 0,
  ).unwrap()
  let (compiled, definition, plan) = client_model_read_test_run("same-parent")
  let (_, _, foreign_plan) = client_model_read_test_run("foreign-parent")
  assert_true(
    bind_client_model_read_scope(
      compiled, definition, foreign_plan, ledger, identity,
    )
    is Err(ForeignRun),
  )
  let scope = bind_client_model_read_scope(
    compiled, definition, plan, ledger, identity,
  ).unwrap()
  @resources.complete_preparation_capacity(parent, input, compiled, 40L, 30L).unwrap()
  let borrower = @resources.borrow_preparation_body(parent).unwrap()
  let read = prepare_client_model_read(scope, 20L, 20L).unwrap()
  assert_true(
    physical_equal(
      handoff_client_model_read(read, compiled, definition, plan).unwrap(),
      ledger,
    ),
  )
  assert_false(
    finish_client_model_read_scope(scope, compiled, definition, plan, true).unwrap(),
  )
  assert_true(
    settle_client_model_read(read, false)
    is Err(Resource(@resources.CleanupPending)),
  )
  settle_client_model_read(read, true).unwrap()
  assert_true(
    finish_client_model_read_scope(scope, compiled, definition, plan, true).unwrap(),
  )
  assert_false(client_model_read_scope_live(scope, compiled, definition, plan))
  assert_true(
    @resources.preparation_body_borrow_value(borrower) is Some(original) &&
    physical_equal(original, compiled),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 40L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 30L)
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 1)
  assert_false(@resources.retire_preparation_capacity(parent).unwrap())
  assert_true(@resources.return_preparation_body_borrow(borrower).unwrap())
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
}

///|
test "checked Content Model prefix borrows the same compiler after original preparation input IO" {
  let (prepared, compiled, definition, plan) = original_serialization_test_run()
  // Independent logical ownership vectors, not full physical domain funding.
  let ledger = @resources.create_ledger({
    planning_work: 3,
    attempts: 4,
    holdings: 1,
    transfer_bytes: 11L,
    retained_bytes: 1000L,
    execution_bytes: 1000L,
  }).unwrap()
  let input = [1]
  let parent : @resources.PreparationCapacity[Array[Int], PreparedClientProgram] = @resources.reserve_preparation_capacity_inventory(
    ledger,
    input,
    800L,
    20L,
    max_borrowers=2,
  ).unwrap()
  let identity = @resources.preparation_capacity_inventory_original(
    parent, input,
  ).unwrap()
  let operation = @resources.begin_preparation_io(parent, input, 3L).unwrap()
  @resources.charge_preparation_io(operation, 2L).unwrap()
  @resources.finish_preparation_io_after_cleanup(operation).unwrap()
  @resources.charge_planning(ledger, 2).unwrap()
  let scope = bind_client_model_read_scope(
    compiled, definition, plan, ledger, identity,
  ).unwrap()
  @resources.complete_preparation_capacity(parent, input, prepared, 800L, 20L).unwrap()
  let held = @resources.borrow_preparation_body(parent).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    physical_equal(
      borrow_client_original_serialization_ledger(
        scope, compiled, definition, plan, prepared, 0, 1,
      ).unwrap(),
      ledger,
    ),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  let prefix = @resources.reserve_attempt(ledger, 0L, 1L, 1L).unwrap()
  @resources.settle_reservation(ledger, prefix).unwrap()
  assert_true(
    borrow_client_original_serialization_ledger(
      scope, compiled, definition, plan, prepared, 0, 1,
    )
    is Err(Resource(@resources.ChangedOriginalState)),
  )
  assert_true(
    finish_client_model_read_scope(scope, compiled, definition, plan, true).unwrap(),
  )
  assert_false(@resources.retire_preparation_capacity(parent).unwrap())
  assert_true(
    @resources.preparation_body_borrow_value(held) is Some(original) &&
    physical_equal(original, prepared),
  )
  assert_true(@resources.return_preparation_body_borrow(held).unwrap())
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
  assert_eq(@resources.ledger_usage(ledger).attempts, 1)
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 2L)
  assert_eq(@resources.ledger_usage(ledger).planning_work, 2)
}
