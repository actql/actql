///|
fn computed_view_fixture() -> (ManagedViewPlan[Int], @lower.BoundPrepared) raise {
  let owner = capture_fixture()
  let source = managed_read_fixture(owner, Ref(true), index_cells=4)
  let receiver = typed_receiver(
    owner, "[{\"select\":[\"n\",\"s\"]},{\"filter\":\"n > 0\"},{\"derive\":{\"copy\":\"s\",\"new\":\"n + 1\"}},{\"sort\":[]},{\"take\":2}]",
  )
  let input = prepare_managed_producer_read(
    receiver, 0, owner, source, 1000, 10000,
  ).unwrap()
  (
    prepare_managed_view_plan(
      input,
      Array::makei(5, i => row_kernel(receiver, i)),
      1000,
      10000,
      100,
    ).unwrap(),
    receiver,
  )
}

///|
fn computed_view_value(
  schema : @schema.Schema,
  number : Int,
) -> @admitted.CheckedValue {
  @admitted.admit(
    @schema.field_at(schema, 2).unwrap().contract,
    input_cursor(number.to_string()),
    { max_nodes: 10, max_text_bytes: 100, max_depth: 10, },
  ).unwrap()
}

///|
test "managed derive validates only computed columns and merges a reusable index" {
  let (plan, owner) = computed_view_fixture()
  let computed = prepare_managed_computed_view(
    plan,
    [0, 1],
    8,
    1000,
    stream_value_limits(),
    100,
    managed_test_measure_limits(),
  ).unwrap()
  let schema = managed_computed_view_schema(computed)
  let calls = []
  for row in 0..<2 {
    let cell = computed_view_value(schema, row + 2)
    append_managed_computed_view(computed, column => {
      calls.push(column)
      Some(cell)
    }).unwrap()
  }
  assert_eq(calls, [2, 2])
  let selection = finish_managed_computed_view(computed).unwrap()
  assert_eq(selection.index.count, 8)
  assert_eq(selection.facts.columns.map(c => c.bytes), [10, 2, 2, 10])
  assert_true(finish_managed_computed_view(computed) is Err(Closed))
  let values = prepare_managed_output_values(
    owner,
    Step(4),
    2,
    stream_value_limits(),
    100,
    managed_test_measure_limits(),
  ).unwrap()
  let port = prepare_managed_selected_view_output_port(selection, values, (
    _ : Unit,
  ) => true).unwrap()
  let receipt = finish_managed_view_output(port, ()).unwrap()
  assert_eq(managed_output_value_measurement(receipt), (10, 24, 8))
  assert_eq(managed_output_value_usage(receipt), {
    work: 10,
    nodes: 4,
    text_bytes: 6,
  })
  assert_eq(managed_output_measurement_index_cells(receipt), Some(8))
}

///|
test "managed computed columns cannot seal missing foreign or oversized values" {
  for mode in 0..<4 {
    let (plan, _) = computed_view_fixture()
    let computed = prepare_managed_computed_view(
      plan,
      [0, 1],
      8,
      1000,
      stream_value_limits(),
      if mode == 2 {
        6
      } else {
        100
      },
      managed_test_measure_limits(),
    ).unwrap()
    let schema = managed_computed_view_schema(computed)
    let cell = computed_view_value(schema, if mode == 2 { 1234567 } else { 2 })
    if mode == 0 {
      assert_true(finish_managed_computed_view(computed) is Err(RowCount))
    } else if mode == 1 {
      let (foreign, _) = computed_view_fixture()
      let foreign_schema = @lower.preparation_schema_at(
        @lower.bound_preparation(foreign.input.receiver),
        foreign.target,
      ).unwrap()
      let other = computed_view_value(foreign_schema, 2)
      assert_true(
        append_managed_computed_view(computed, _ => Some(other))
        is Err(Values(Admission(ForeignCheckedValue(0, 2)))),
      )
    } else if mode == 2 {
      for _ in 0..<2 {
        append_managed_computed_view(computed, _ => Some(cell)).unwrap()
      }
      assert_true(
        finish_managed_computed_view(computed)
        is Err(NeedsOrderedMeasurement(ValueBytes(Output, 0, 2))),
      )
    } else {
      assert_true(
        append_managed_computed_view(computed, _ => {
          cancel_managed_computed_view(computed) |> ignore
          Some(cell)
        })
        is Err(Closed),
      )
    }
    assert_true(finish_managed_computed_view(computed) is Err(Closed))
    assert_eq(computed.selection.index.count, 0)
  }
}

///|
test "managed copied-column failure participates in canonical diagnostic order" {
  let (plan, _) = computed_view_fixture()
  let computed = prepare_managed_computed_view(
    plan,
    [0, 1],
    8,
    1000,
    stream_value_limits(),
    0,
    managed_test_measure_limits(),
  ).unwrap()
  let cell = computed_view_value(managed_computed_view_schema(computed), 2)
  let calls = Ref(0)
  for _ in 0..<2 {
    append_managed_computed_view(computed, _ => {
      calls.val += 1
      Some(cell)
    }).unwrap()
  }
  assert_eq(calls.val, 2)
  assert_true(
    finish_managed_computed_view(computed)
    is Err(NeedsOrderedMeasurement(ValueBytes(Output, 0, 0))),
  )
}

///|
test "managed computed view rejects missing cells and reentrant finish without publishing" {
  for missing in [false, true] {
    let (plan, _) = computed_view_fixture()
    let computed = prepare_managed_computed_view(
      plan,
      [0, 1],
      8,
      1000,
      stream_value_limits(),
      100,
      managed_test_measure_limits(),
    ).unwrap()
    let cell = computed_view_value(managed_computed_view_schema(computed), 2)
    let rejected = Ref(false)
    let result = append_managed_computed_view(computed, _ => {
      rejected.val = finish_managed_computed_view(computed) is Err(Closed)
      if missing {
        None
      } else {
        Some(cell)
      }
    })
    assert_true(rejected.val)
    if missing {
      assert_true(result is Err(Values(Admission(InvalidCheckedRow))))
      assert_eq(computed.selection.index.count, 0)
    } else {
      result.unwrap()
      append_managed_computed_view(computed, _ => Some(cell)).unwrap()
      assert_eq(finish_managed_computed_view(computed).unwrap().index.count, 8)
    }
  }
}
