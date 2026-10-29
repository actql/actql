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
