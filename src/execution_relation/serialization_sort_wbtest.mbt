///|
test "serialization ORDER BY executes the shared sort rather than provider arrival order" {
  let owner = sort_seed(
    ",{\"serialize\":{\"format\":\"jsonl\",\"fields\":[\"id\",\"payload\"],\"order_by\":[{\"field\":\"k\",\"dir\":\"desc\",\"nulls\":\"first\"}],\"name\":\"out.jsonl\"}}",
  )
  let barrier = @lower.prepare_serialization(owner, 1, max_work=3).unwrap()
  let kernel = @lower.prepare_serialization_sort_kernel(
    barrier,
    max_bindings=1,
    max_name_bytes=1,
    max_work=1,
  ).unwrap()
  let input : Table = {
    owner,
    id: @lower.kernel_input(kernel),
    names: ["id", "k", "payload"],
    rows: [
      [Number(3), Number(1), Null],
      [Number(1), Number(1), Null],
      [Number(2), Null, Null],
    ],
  }
  let sorted = evaluate_rows(
    kernel,
    input,
    3,
    { remaining: 100000, max_frames: 100, },
    value_budget(run_limits().output_values).unwrap(),
  ).unwrap()
  assert_eq(sorted.names, input.names)
  for (index, expected) in [(0, 2), (1, 3), (2, 1)] {
    assert_true(
      sorted.rows[index][0] is Number(value) && value == expected.to_double(),
    )
  }
  // Ties retain the existing Values occurrence witness, not an arbitrary id
  // order. Sorting never mutates the borrowed original rows.
  assert_true(input.rows[0][0] is Number(3))
  assert_true(input.rows[1][0] is Number(1))
  assert_eq(@schema.field_count(@lower.kernel_output_schema(kernel)), 3)
  assert_true(
    evaluate_rows(
      kernel,
      input,
      3,
      { remaining: 0, max_frames: 100, },
      value_budget(run_limits().output_values).unwrap(),
    )
    is Err(_),
  )
}

///|
test "serialization sort runs inside the existing generated sequence" {
  let owner = sort_seed(
    ",{\"serialize\":{\"format\":\"jsonl\",\"fields\":[\"id\"],\"order_by\":[{\"id\":\"asc\"}],\"name\":\"out.jsonl\"}}",
  )
  let barrier = @lower.prepare_serialization(owner, 1, max_work=3).unwrap()
  let limits : @lower.SequenceLimits = {
    max_steps: 10,
    max_rows: 10,
    max_cells: 100,
    max_bindings: 100,
    max_name_bytes: 1000,
    expressions: {
      max_nodes: 1000,
      max_work: 10000,
      max_depth: 100,
      max_literal_nodes: 1000,
      max_literal_text_bytes: 10000,
    },
  }
  let sequence = @lower.prepare_serialization_input_sequence(barrier, limits).unwrap()
  let output_id = @lower.node_id(
    @lower.node_at(@lower.bound_preparation(owner), 1).unwrap(),
  )
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [],
    [output_id, "values_0"],
    100000,
    10000,
  ).unwrap()
  let result = execute_generated_sequence(generated, [], {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }).unwrap()
  let output = completed_output(result, Step(1)).unwrap()
  assert_true(completed_output_matches_serialization_sort(output, barrier))
  let foreign = sort_seed(
    ",{\"serialize\":{\"format\":\"jsonl\",\"fields\":[\"id\"],\"order_by\":[{\"id\":\"asc\"}],\"name\":\"out.jsonl\"}}",
  )
  let foreign_barrier = @lower.prepare_serialization(foreign, 1, max_work=3).unwrap()
  assert_false(
    completed_output_matches_serialization_sort(output, foreign_barrier),
  )
  assert_true(prepare_serialization_completion(output, foreign_barrier) is None)
  assert_false(completed_output_matches_port(output, owner, Step(1)))
  assert_false(completed_output_matches_port(output, owner, Step(0)))
  let exported = completed_output_export_rows(output)
  assert_eq(@schema.field_count(exported.schema), 3)
  // Producer metadata demand follows the physical relation projection, not
  // the authored serialization target's five-field artifact schema.
  let demand = producer_read_schema_demand(
    exported.schema,
    completed_output_relation_schema(output),
    0,
  ).unwrap()
  assert_eq(producer_read_demand_columns(demand), 3)
  assert_eq(producer_read_demand_entries(demand), 12)
  assert_eq(producer_read_demand_name_bytes(demand), 40)
  assert_true(@schema.lookup_reference(exported.schema, "content") is None)
  let rows = test_row_output(output)
  assert_eq(rows.names, ["id", "k", "payload"])
  for index in 0..<3 {
    assert_true(
      rows.rows[index][0] is Number(value) && value == (index + 1).to_double(),
    )
  }
  let original = completed_output(result, Step(0)).unwrap()
  assert_false(completed_output_matches_serialization_sort(original, barrier))
  assert_true(test_row_output(original).rows[0][0] is Number(3))
  assert_true(prepare_serialization_completion(original, barrier) is None)
  let completion = prepare_serialization_completion(output, barrier).unwrap()
  let metadata = completion_preparation_schema(completion, Step(1)).unwrap()
  assert_eq(@schema.field_count(metadata), 5)
  assert_true(@schema.lookup_reference(metadata, "content") is Some(_))

  // Re-enter only the selected common sort with the exact original input
  // borrow. Quantum affects scheduling, not rows or cumulative logical work.
  let selected = select_generated_sequence_step(generated, 1).unwrap()
  let input = prepare_producer_read(
    owner,
    bind_completed_operation_input(owner, 1, 0, owner, original).unwrap(),
    100,
    10000,
  ).unwrap()
  let mut expected_work : Int64? = None
  for quantum in [1, 7, 32] {
    let execution = start_bounded_binding_rows(
      @bounded.control(),
      selected,
      input,
      3,
      run_limits().input_values,
      run_limits().output_values,
      100000,
      100,
      10000,
      10000,
    ).unwrap()
    let mut work = 0L
    let mut completed = false
    for _ in 0..<10000 {
      match advance_bounded_binding_rows(execution, quantum).unwrap() {
        BoundedBindingRowsContinue(work=cumulative, ..) => {
          assert_true(cumulative >= work)
          work = cumulative
        }
        BoundedBindingRowsComplete(sorted, work=used, ..) => {
          assert_true(used >= work)
          work = used
          assert_true(
            completed_output_matches_serialization_sort(sorted, barrier),
          )
          assert_false(completed_output_matches_port(sorted, owner, Step(1)))
          for index in 0..<3 {
            assert_true(
              completed_cell(sorted, index, 0) is Some(Number(value)) &&
              value == (index + 1).to_double(),
            )
          }
          completed = true
          break
        }
        _ => fail("bounded serialization sort did not complete")
      }
    }
    assert_true(completed)
    assert_true(work > 0L)
    match expected_work {
      Some(expected) => assert_eq(work, expected)
      None => expected_work = Some(work)
    }
    assert_true(cleanup_bounded_binding_rows(execution).unwrap())
    assert_true(producer_read_available(input))
  }
}

///|
test "serialization metadata row proof does not shrink its original hundred-row sort" {
  let rows = Array::makei(100, index => "{\"id\":" + index.to_string() + "}").join(
    ",",
  )
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[" +
    rows +
    "]},\"as\":\"seed\"},{\"serialize\":{\"format\":\"jsonl\",\"fields\":[\"id\"],\"order_by\":[{\"id\":\"desc\"}],\"name\":\"out.jsonl\"}}]",
  )
  let prepared = @lower.bound_preparation(owner)
  assert_eq(
    @lower.node_row_count_bound(@lower.node_at(prepared, 1).unwrap(), [100]),
    Some(1),
  )
  assert_eq(@lower.prepared_closed_row_bound(prepared, 10000).unwrap().0, 100)
  let barrier = @lower.prepare_serialization(owner, 1, max_work=3).unwrap()
  let kernel = @lower.prepare_serialization_sort_kernel(
    barrier,
    max_bindings=1,
    max_name_bytes=2,
    max_work=1,
  ).unwrap()
  let input : Table = {
    owner,
    id: @lower.kernel_input(kernel),
    names: ["id"],
    rows: Array::makei(100, index => [Number(index.to_double())]),
  }
  let sorted = evaluate_rows(
    kernel,
    input,
    100,
    { remaining: 100000, max_frames: 100, },
    value_budget(run_limits().output_values).unwrap(),
  ).unwrap()
  assert_eq(sorted.rows.length(), 100)
  assert_eq(@schema.field_count(@lower.kernel_output_schema(kernel)), 1)
  for index in 0..<100 {
    assert_true(
      sorted.rows[index][0] is Number(value) &&
      value == (99 - index).to_double(),
    )
  }
}
