///|
test "Source material keeps the same initialized aggregate Environment and debit across Request borrows" {
  // The actual typed publication is independently owned fixture material.
  // This explicit Resource model tests the borrowed body/lifetime connection,
  // not installation construction backing, an actual Host or physical stop.
  let (_, environment) = request_query_publication_fixture()
  let ledger = @resources.create_ledger({
    planning_work: 0,
    attempts: 0,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 4096L,
    execution_bytes: 4096L,
  }).unwrap()
  let input = [1]
  let source = ["same initialized Source aggregate"]
  let capacity : @resources.PreparationCapacity[
    Array[Int],
    (Array[String], @source_publication.PreparedPublishedQueryEnvironment),
  ] = @resources.reserve_preparation_capacity(
    ledger,
    input,
    256L,
    0L,
    max_borrowers=3,
  ).unwrap()
  @resources.complete_preparation_capacity(
    capacity,
    input,
    (source, environment),
    256L,
    0L,
  ).unwrap()
  let initial = @resources.borrow_preparation_body(capacity).unwrap()
  let first = @resources.borrow_preparation_body_sibling(initial).unwrap()
  let second = @resources.borrow_preparation_body_sibling(initial).unwrap()
  let usage = @resources.ledger_usage(ledger)
  assert_true(
    physical_equal(
      borrowed_installed_source_environment(first, source).unwrap(),
      environment,
    ),
  )
  assert_true(
    physical_equal(
      borrowed_installed_source_environment(second, source).unwrap(),
      environment,
    ),
  )
  assert_true(
    borrowed_installed_source_environment(first, source.copy())
    is Err(@resources.ForeignOriginal),
  )
  assert_eq(@resources.ledger_usage(ledger), usage)
  assert_false(@resources.retire_preparation_capacity(capacity).unwrap())
  assert_true(
    @resources.borrow_preparation_body_sibling(initial)
    is Err(@resources.Retired),
  )
  // Existing operations can still identify their original metadata while
  // retiring; that DATA getter never starts or authorizes another read.
  assert_true(
    physical_equal(
      borrowed_installed_source_environment(first, source).unwrap(),
      environment,
    ),
  )
  assert_false(@resources.return_preparation_body_borrow(first).unwrap())
  assert_true(
    borrowed_installed_source_environment(first, source)
    is Err(@resources.BorrowReturned),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 256L)
  assert_false(@resources.return_preparation_body_borrow(second).unwrap())
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 256L)
  assert_true(@resources.return_preparation_body_borrow(initial).unwrap())
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  assert_true(@resources.retire_preparation_capacity(capacity).unwrap())
}

///|
test "Host initial Source successor keeps its original Environment until Request borrows and children settle" {
  let (_, environment) = request_query_publication_fixture()
  let input = [73]
  let child_pending = Ref(false)
  let host = begin_host_initialization_preparation(
    request_parent_fixture(input, pending=() => child_pending.val),
    input,
    client_local_resource_policy(),
  ).unwrap()
  let (original, capacity) = take_host_initialization_preparation_capacity(
    host,
  ).unwrap()
  assert_true(physical_equal(original, input))
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, original).unwrap(),
    (0L, 0L),
  )
  let next : @resources.PreparationCapacity[
    Array[Int],
    (Array[String], @source_publication.PreparedPublishedQueryEnvironment),
  ] = @resources.continue_preparation_capacity(capacity, original).unwrap()
  // Explicit component body extent, not the normal Source constructor recipe.
  @resources.reserve_working_preparation_phase(next, original, 256L, 128L).unwrap()
  let source = ["same actual initialized Source aggregate"]
  @resources.complete_preparation_capacity(
    next, original, (source, environment), 256L, 0L,
  ).unwrap()
  let first = @resources.borrow_preparation_body(next).unwrap()
  let second = @resources.borrow_preparation_body_sibling(first).unwrap()
  assert_true(
    physical_equal(
      borrowed_installed_source_environment(first, source).unwrap(),
      environment,
    ),
  )
  assert_true(
    borrowed_installed_source_environment(second, source.copy())
    is Err(@resources.ForeignOriginal),
  )
  child_pending.val = true
  assert_true(close_host_initialization_preparation(host) is Err(WrongPhase))
  assert_false(@resources.retire_preparation_capacity(next).unwrap())
  assert_false(@resources.return_preparation_body_borrow(first).unwrap())
  assert_true(close_host_initialization_preparation(host) is Err(WrongPhase))
  assert_true(
    physical_equal(
      borrowed_installed_source_environment(second, source).unwrap(),
      environment,
    ),
  )
  assert_true(@resources.return_preparation_body_borrow(second).unwrap())
  assert_true(@resources.preparation_capacity_reservation_retired(capacity))
  // The Source owner must observe its original child settled before asking
  // B to close. An attempted physical stop is not a retryable Bool probe.
  child_pending.val = false
  close_host_initialization_preparation(host).unwrap()
}
