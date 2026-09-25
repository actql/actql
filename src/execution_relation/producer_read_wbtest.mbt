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
  let storage = prepare_producer_storage(
    completed_output(upstream, Step(0)).unwrap(),
    100,
    100,
  ).unwrap()
  let mapping = producer_storage_projection(storage, view, 100).unwrap()
  for column in 0..<2 {
    let name = @schema.field_at(producer_read_schema(view), column).unwrap().name
    if name == @schema.Unqualified("a") {
      assert_true(
        producer_storage_cell(storage, 0, mapping[column]) is Some(Number(1)),
      )
    } else {
      assert_true(
        producer_storage_cell(storage, 0, mapping[column]) is Some(Number(0)),
      )
    }
  }
  assert_true(producer_storage_projection(storage, view, 0) is Err(Limit))
  let again = evaluate_sequence_components(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["values_0"],
    run_limits(),
    { remaining: 10000, max_frames: 100, },
  ).unwrap()
  let other = prepare_producer_storage(
    completed_output(again, Step(0)).unwrap(),
    100,
    100,
  ).unwrap()
  assert_true(
    producer_storage_projection(other, view, 100) is Err(InvalidProjection),
  )
  let mut live = true
  let restricted = prepare_producer_storage(
    restrict_completed_output(completed_output(upstream, Step(0)).unwrap(), fn() {
      live
    }),
    100,
    100,
  ).unwrap()
  assert_true(producer_storage_projection(restricted, view, 100) is Ok(_))
  live = false
  assert_true(
    producer_storage_projection(restricted, view, 100)
    is Err(ProducerUnavailable),
  )
}

///|
test "producer read exposes admitted cells only from admitted storage" {
  let owner = row_owner("")
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["values_0"],
    100000,
    10000,
  ).unwrap()
  let active = start_bounded_values(
    @bounded.control(),
    generated,
    2,
    run_limits().input_values,
    run_limits().output_values,
    10000,
    0,
    100,
    10000,
  ).unwrap()
  let mut admitted : CompletedOutput? = None
  for _ in 0..<100 {
    if admitted is None {
      match advance_bounded_values(active, 1).unwrap() {
        BoundedValuesContinue(..) => ()
        BoundedValuesComplete(output, ..) => admitted = Some(output)
        _ => fail("bounded values did not produce admitted storage")
      }
    }
  }
  let output = admitted.unwrap()
  let receiver = producer_consumer(owner, Step(0))
  let read = prepare_producer_read(
    receiver,
    bind_completed_input(receiver, 0, owner, output).unwrap(),
    100,
    10000,
  ).unwrap()
  assert_true(
    producer_read_admitted_cell(read, 0, 0) is Some(@admitted.Number(1.0)),
  )
  assert_true(producer_read_admitted_cell(read, -1, 0) is None)
  assert_true(producer_read_admitted_cell(read, 0, -1) is None)
  let mut live = true
  let restricted = prepare_producer_read(
    receiver,
    bind_completed_input(
      receiver,
      0,
      owner,
      restrict_completed_output(output, fn() { live }),
    ).unwrap(),
    100,
    10000,
  ).unwrap()
  live = false
  assert_true(producer_read_admitted_cell(restricted, 0, 0) is None)
  assert_true(cleanup_bounded_values(active).unwrap())

  let ordinary = evaluate_sequence_components(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["values_0"],
    run_limits(),
    { remaining: 10000, max_frames: 100, },
  ).unwrap()
  let fallback = prepare_producer_read(
    receiver,
    bind_completed_input(
      receiver,
      0,
      owner,
      completed_output(ordinary, Step(0)).unwrap(),
    ).unwrap(),
    100,
    10000,
  ).unwrap()
  assert_true(producer_read_admitted_cell(fallback, 0, 0) is None)
}
