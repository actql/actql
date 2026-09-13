///|
test "producer read keeps immutable ownership and resolves receiving columns once" {
  let owner = row_owner(",{\"select\":[\"b\",\"a\"]}")
  let completion = evaluate_sequence_components(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["select_1"],
    run_limits(),
    { remaining: 10000, max_frames: 100, },
  ).unwrap()
  let receiver = producer_consumer(owner, Step(1))
  let output = completed_output(completion, Step(1)).unwrap()
  let bound = bind_completed_input(receiver, 0, owner, output).unwrap()
  let view = prepare_producer_read(receiver, bound, 5, 5).unwrap()
  assert_true(physical_equal(producer_read_receiver(view), receiver))
  assert_eq(producer_read_row_count(view), 2)
  assert_eq(@schema.field_count(producer_read_schema(view)), 2)
  assert_true(producer_read_cell(view, 0, 0) is Some(Number(1)))
  assert_true(producer_read_cell(view, 0, 1) is Some(Number(0)))
  assert_true(producer_read_cell(view, -1, 0) is None)
  assert_true(producer_read_cell(view, 0, -1) is None)
  assert_true(producer_read_cell(view, 2, 0) is None)
  assert_true(producer_read_cell(view, 0, 2) is None)
  assert_true(prepare_producer_read(receiver, bound, 4, 5) is Err(Limit))
  assert_true(prepare_producer_read(receiver, bound, 5, 4) is Err(Limit))
  assert_true(
    prepare_producer_read(receiver, bound, -1, 5) is Err(InvalidLimits),
  )
  let foreign = producer_consumer(owner, Step(1))
  assert_true(
    prepare_producer_read(foreign, bound, 100, 100) is Err(ForeignReceiver),
  )
  // A rejected read preparation does not consume the successfully retained data.
  assert_true(producer_read_cell(view, 1, 0) is Some(Number(0)))
}

///|
test "producer read applies checked aliases without materializing projection rows" {
  let owner = row_owner("")
  let upstream = evaluate_sequence_components(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["values_0"],
    run_limits(),
    { remaining: 10000, max_frames: 100, },
  ).unwrap()
  let receiver = projected_consumer(
    owner, "[{\"renamed\":\"b\"},\"a\"]", "[{\"select\":[\"renamed\",\"a\"]}]",
  )
  let bound = bind_completed_input(
    receiver,
    0,
    owner,
    completed_output(upstream, Step(0)).unwrap(),
  ).unwrap()
  let view = prepare_producer_read(receiver, bound, 100, 100).unwrap()
  for column in 0..<2 {
    let name = @schema.field_at(producer_read_schema(view), column).unwrap().name
    match name {
      @schema.Unqualified("a") =>
        assert_true(producer_read_cell(view, 0, column) is Some(Number(1)))
      @schema.Unqualified("renamed") =>
        assert_true(producer_read_cell(view, 0, column) is Some(Number(0)))
      _ => fail("unexpected receiving field")
    }
  }
  assert_true(physical_equal(view.bound.output.completion, upstream))
}
