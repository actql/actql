///|
fn take_key_owner(tail : String) -> @lower.BoundPrepared {
  let seed = capture_values(
    capture_fixture(),
    0,
    max_rows=2,
    run_limits().input_values,
  ).unwrap()
  let carrier = @carrier.relation(@carrier.typed_rows(captured_schema(seed)))
  let key = @evidence.declare_primary_key(input_cursor("[\"n\"]"), carrier, {
    max_fields: 2,
    max_name_bytes: 100,
  }).unwrap()
  sort_input_owner(@pipeline.KeyedInput(key), tail)
}

///|
test "take emits its owned key completion before limit and applies offset after ordering" {
  let owner = take_key_owner("[{\"take\":{\"count\":1,\"offset\":1}}]")
  let sequence = prepared_sequence(owner)
  let writer = @encode.writer(10000, 1000, 100)
  @lower.emit_sequence_steps(sequence, writer)
  assert_eq(
    @encode.finish(writer),
    "[{\"id\":\"sort_0\",\"in\":[\"input_0\"],\"op\":\"REL.orderByStable\",\"params\":{\"by\":[{\"dir\":\"asc\",\"field\":\"n\",\"nulls\":\"last\"}]}},{\"id\":\"limit_0\",\"in\":[\"sort_0\"],\"op\":\"REL.limit\",\"params\":{\"count\":1,\"offset\":1}}]",
  )
  guard @lower.sequence_step(sequence, 0) is Some(@lower.RowStep(kernel)) else {
    fail("take")
  }
  assert_eq(@lower.kernel_sort_term_count(kernel), 1)
  assert_true(@lower.kernel_sort_term_at(kernel, -1) is None)
  assert_true(@lower.kernel_sort_term_at(kernel, 1) is None)
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [],
    ["limit_0"],
    100000,
    10000,
  ).unwrap()
  let limits : SequenceExecutionLimits = {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }
  for empty in [false, true] {
    let rows = if empty {
      []
    } else {
      [
        input_cursor("{\"n\":3,\"s\":\"third\"}"),
        input_cursor("{\"n\":1,\"s\":\"first\"}"),
        input_cursor("{\"n\":2,\"s\":\"second\"}"),
      ]
    }
    let input = capture_input(
      owner,
      0,
      rows,
      max_rows=3,
      run_limits().input_values,
    ).unwrap()
    for _i = 0; _i < 2; _i = _i + 1 {
      let done = execute_generated_sequence(generated, [input], limits).unwrap()
      let result = test_row_output(completed_output(done, Step(0)).unwrap())
      if empty {
        assert_eq(result.rows.length(), 0)
      } else {
        assert_eq(result.rows.length(), 1)
        assert_true(result.rows[0][0] is Number(2))
        assert_true(result.rows[0][1] is Text("second"))
        assert_true(input.rows[0][0] is Number(3))
      }
    }
  }
}

///|
test "take completion validates every input key even beyond the requested prefix" {
  let owner = take_key_owner("[{\"take\":1}]")
  let sequence = prepared_sequence(owner)
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [],
    ["limit_0"],
    100000,
    10000,
  ).unwrap()
  let input = capture_input(
    owner,
    0,
    [
      input_cursor("{\"n\":1,\"s\":\"first\"}"),
      input_cursor("{\"n\":9,\"s\":\"last\"}"),
      input_cursor("{\"n\":9,\"s\":\"duplicate outside take\"}"),
    ],
    max_rows=3,
    run_limits().input_values,
  ).unwrap()
  assert_true(
    execute_generated_sequence(generated, [input], {
      rows: run_limits(),
      max_work: 100000,
      max_frames: 100,
    })
    is Err(InputKey(0, _)),
  )
}

///|
test "take key completion reserves a real graph prefix and shares runtime budgets" {
  let owner = take_key_owner("[{\"take\":1}]")
  let p = @lower.pipeline(@lower.bound_preparation(owner))
  let prepared = @lower.prepare(p, {
    max_nodes: 3,
    max_references: 2,
    max_work: 1000,
    max_identifier_bytes: 1000,
  }).unwrap()
  assert_eq(@lower.usage(prepared).nodes, 3)
  assert_eq(@lower.usage(prepared).references, 2)
  assert_true(
    @lower.prepare(p, {
      max_nodes: 2,
      max_references: 2,
      max_work: 1000,
      max_identifier_bytes: 1000,
    })
    is Err(_),
  )
  assert_true(
    @lower.prepare(p, {
      max_nodes: 3,
      max_references: 1,
      max_work: 1000,
      max_identifier_bytes: 1000,
    })
    is Err(_),
  )
  let sequence = prepared_sequence(owner)
  let contracts = registered_relation_contracts()
  let generated = prepare_generated_sequence(
    contracts,
    sequence,
    [],
    ["limit_0"],
    100000,
    10000,
  ).unwrap()
  let input = capture_input(
    owner,
    0,
    [
      input_cursor("{\"n\":2,\"s\":\"b\"}"),
      input_cursor("{\"n\":1,\"s\":\"a\"}"),
    ],
    max_rows=2,
    run_limits().input_values,
  ).unwrap()
  let control = { remaining: 100000, max_frames: 100, }
  assert_true(
    evaluate_sequence_components(
      contracts,
      sequence,
      [input],
      ["limit_0"],
      run_limits(),
      control,
      fragments=Some([]),
    )
    is Ok(_),
  )
  let used = 100000 - control.remaining
  let limits : SequenceExecutionLimits = {
    rows: run_limits(),
    max_work: used,
    max_frames: 100,
  }
  assert_true(execute_generated_sequence(generated, [input], limits) is Ok(_))
  assert_true(
    execute_generated_sequence(generated, [input], {
      ..limits,
      max_work: used - 1,
    })
    is Err(_),
  )
  assert_true(execute_generated_sequence(generated, [input], limits) is Ok(_))
}
