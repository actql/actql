///|
fn seal_schema_borrow_shape(
  preparation : PublicationSealPreparation,
  wanted : Bool,
) -> ProtocolValidationCursor raise {
  for _ in 0..<10000 {
    if preparation.phase is Shape(cursor, complete) && complete == wanted {
      return cursor
    }
    let (done, work) = preparation.advance(1).unwrap()
    assert_false(done)
    assert_eq(work, 1)
  }
  fail("the bounded seal did not reach the selected shape phase")
}

///|
test "publication seal borrows the same immutable schema across independent cursors" {
  let first = start_publication_seal_preparation(
    "result_delivery_receipt",
    seal_preparation_test_body(),
    4096,
    32,
    4,
    1000,
  ).unwrap()
  let second = start_publication_seal_preparation(
    "result_delivery_receipt",
    seal_preparation_test_body(),
    4096,
    32,
    4,
    1000,
  ).unwrap()
  let first_shape = seal_schema_borrow_shape(first, false)
  let second_shape = seal_schema_borrow_shape(second, false)
  let same_first = physical_equal(first_shape.nodes, protocol_schema_nodes())
  let same_second = physical_equal(second_shape.nodes, protocol_schema_nodes())
  let length = protocol_schema_nodes().length()
  assert_false(physical_equal(first_shape, second_shape))
  assert_false(physical_equal(first_shape.pending, second_shape.pending))
  assert_false(physical_equal(first_shape.budget, second_shape.budget))
  let untouched = second_shape.budget.remaining
  first.cancel()
  assert_true(first_shape.closed && first_shape.pending.is_empty())
  assert_eq(first.live, 0)
  assert_eq(second_shape.budget.remaining, untouched)
  assert_eq(protocol_schema_nodes().length(), length)
  let (contract, _) = seal_preparation_test_finish(second, 1).unwrap()
  assert_eq(contract.wire, seal_preparation_test_complete())
  assert_eq(
    contract.identity,
    "sha256:1b672f923a8f34e603d8246a3541922ccb1eedb4be8d1691f9a290d14fe1e2ea",
  )
  assert_eq(second.live, 0)
  // Check sharing after both original children have retired their data, so a
  // failing historical implementation leaves no live child in this fixture.
  assert_true(same_first && same_second)
}

///|
test "publication seal reuses immutable schema for complete shape without transferring control" {
  let preparation = start_publication_seal_preparation(
    "result_delivery_receipt",
    seal_preparation_test_body(),
    4096,
    32,
    4,
    1000,
  ).unwrap()
  let initial = seal_schema_borrow_shape(preparation, false)
  let complete = seal_schema_borrow_shape(preparation, true)
  let shared = physical_equal(initial.nodes, complete.nodes) &&
    physical_equal(complete.nodes, protocol_schema_nodes())
  assert_false(physical_equal(initial, complete))
  assert_true(initial.closed && initial.pending.is_empty())
  assert_false(complete.closed)
  preparation.cancel()
  preparation.cancel()
  assert_true(complete.closed && complete.pending.is_empty())
  assert_eq(preparation.live, 0)
  assert_true(preparation.value is None && preparation.writer is None)
  assert_true(preparation.contract is None && preparation.identity is None)
  assert_true(preparation.finish() is Err(Encoding))
  assert_true(shared)
}
