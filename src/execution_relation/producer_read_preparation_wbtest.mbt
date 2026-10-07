///|
fn long_read_preparation_fixture(
  name : String,
) -> (ProducerReadPreparation, BoundProducerInput, @lower.BoundPrepared) raise {
  let owner = row_owner(",{\"select\":[{\"" + name + "\":\"a\"}]}")
  let completion = evaluate_sequence_components(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["select_1"],
    run_limits(),
    { remaining: 10000, max_frames: 100, },
  ).unwrap()
  let receiver = producer_consumer(owner, Step(1), selected=name)
  let bound = bind_completed_input(
    receiver,
    0,
    owner,
    completed_output(completion, Step(1)).unwrap(),
  ).unwrap()
  (
    start_prepare_producer_read(receiver, bound, 2, 10000).unwrap(),
    bound,
    receiver,
  )
}

///|
test "producer metadata yields inside long names with exact visit budgets" {
  let (cursor, bound, receiver) = long_read_preparation_fixture("x".repeat(256))
  assert_false(producer_read_preparation_is_small(cursor))
  let exact = start_prepare_producer_read(receiver, bound, 2, 512).unwrap()
  // Field + four receiver chunks + column + four producer chunks + four
  // exact-spelling chunks + terminal = fifteen polls, with two entry visits.
  for _ in 0..<14 {
    assert_true(advance_prepare_producer_read(exact) is Ok(None))
  }
  let read = advance_prepare_producer_read(exact).unwrap().unwrap()
  assert_eq(exact.bytes, 0)
  assert_eq(exact.entries, 0)
  assert_true(producer_read_cell(read, 0, 0) is Some(Number(1)))
  cancel_prepare_producer_read(exact)
  assert_true(producer_read_cell(read, 0, 0) is Some(Number(1)))
  for (entries, bytes) in [(1, 512), (2, 511)] {
    let active = start_prepare_producer_read(receiver, bound, entries, bytes).unwrap()
    let mut failed = false
    for _ in 0..<15 {
      if !failed {
        match advance_prepare_producer_read(active) {
          Ok(None) => ()
          Err(Limit) => failed = true
          _ => fail("metadata one-short did not yield the exact limit issue")
        }
      }
    }
    assert_true(failed)
    assert_true(active.columns.is_empty())
  }
  let stopping = start_prepare_producer_read(receiver, bound, 2, 512).unwrap()
  for _ in 0..<2 {
    assert_true(advance_prepare_producer_read(stopping) is Ok(None))
  }
  assert_eq(stopping.offset, 64)
  assert_eq(stopping.bytes, 448)
  cancel_prepare_producer_read(stopping)
  cancel_prepare_producer_read(stopping)
  assert_true(stopping.columns.is_empty())
  assert_true(advance_prepare_producer_read(stopping) is Err(InvalidLimits))
  assert_true(producer_read_available(read))
}

///|
test "producer metadata preserves scalar byte boundaries and current availability" {
  let name = "x".repeat(63) + "😀" + "é".repeat(65)
  let (_, bound, receiver) = long_read_preparation_fixture(name)
  let active = start_prepare_producer_read(receiver, bound, 2, 394).unwrap()
  for _ in 0..<2 {
    assert_true(advance_prepare_producer_read(active) is Ok(None))
  }
  assert_eq(active.offset, 65)
  assert_eq(active.bytes, 327)
  for _ in 0..<9 {
    assert_true(advance_prepare_producer_read(active) is Ok(None))
  }
  let read = advance_prepare_producer_read(active).unwrap().unwrap()
  assert_eq(active.bytes, 0)
  assert_true(producer_read_cell(read, 0, 0) is Some(Number(1)))
  let live = Ref(true)
  let restricted = {
    ..bound,
    output: restrict_completed_output(bound.output, fn() { live.val }),
  }
  let stopped = start_prepare_producer_read(receiver, restricted, 2, 394).unwrap()
  assert_true(advance_prepare_producer_read(stopped) is Ok(None))
  live.val = false
  assert_true(
    advance_prepare_producer_read(stopped) is Err(ProducerUnavailable),
  )
  assert_true(stopped.columns.is_empty())
  assert_true(producer_read_available(read))
}
