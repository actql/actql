///|
fn sort_seed(tail : String) -> @lower.BoundPrepared {
  bound_pipeline(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"k\":{\"type\":\"number\",\"nullable\":true},\"payload\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}},\"rows\":[{\"id\":3,\"k\":1,\"payload\":[30]},{\"id\":1,\"k\":1,\"payload\":[10]},{\"id\":2,\"k\":null,\"payload\":[20]}]},\"as\":\"seed\"}" +
    tail +
    "]",
  )
}

///|
test "sort retains hidden prior order across projection and exposes no CID tie break" {
  let sequence = prepared_sequence(
    sort_seed(
      ",{\"sort\":[{\"id\":\"asc\"}]},{\"select\":[\"k\",\"payload\"]},{\"sort\":[{\"k\":\"asc\"}]},{\"take\":1}",
    ),
  )
  let pipeline = @lower.pipeline(
    @lower.bound_preparation(@lower.sequence_owner(sequence)),
  )
  assert_true(
    @pipeline.sort_order_strategy(@pipeline.sort_order(pipeline, 3).unwrap())
    is ExistingTotal(_),
  )
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [],
    ["sort_3", "limit_4"],
    100000,
    10000,
  ).unwrap()
  let limits : SequenceExecutionLimits = {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }
  for _i in 0..<2 {
    let complete = execute_generated_sequence(generated, [], limits).unwrap()
    let table = test_row_output(completed_output(complete, Step(3)).unwrap())
    assert_eq(table.names, ["k", "payload"])
    assert_true(table.rows[0][0] is Number(1))
    assert_true(table.rows[2][0] is Null)
    guard table.rows[0][1] is Captured(@admitted.Array(values)) else {
      fail("payload")
    }
    assert_true(@admitted.element_at(values, 0) is Some(@admitted.Number(10)))
    guard test_row_output(completed_output(complete, Step(4)).unwrap()).rows[0][1]
      is Captured(@admitted.Array(chosen)) else {
      fail("chosen")
    }
    assert_true(@admitted.element_at(chosen, 0) is Some(@admitted.Number(10)))
  }
}

///|
test "sort obeys explicit null placement independently of direction and retains empty identity" {
  for
    (body, expected) in [
      ("[]", [3, 1, 2]),
      ("[{\"k\":\"desc\"}]", [3, 1, 2]),
      ("[{\"field\":\"k\",\"dir\":\"desc\",\"nulls\":\"first\"}]", [2, 3, 1]),
    ] {
    let sequence = prepared_sequence(sort_seed(",{\"sort\":" + body + "}"))
    let generated = prepare_generated_sequence(
      registered_relation_contracts(),
      sequence,
      [],
      ["sort_1"],
      100000,
      10000,
    ).unwrap()
    let result = execute_generated_sequence(generated, [], {
      rows: run_limits(),
      max_work: 100000,
      max_frames: 100,
    }).unwrap()
    let table = test_row_output(completed_output(result, Step(1)).unwrap())
    for i in 0..<3 {
      assert_true(table.rows[i][0] is Number(n) && n == expected[i].to_double())
    }
  }
}

///|
fn sort_input_owner(
  contract : @pipeline.InputContract,
  tail : String,
) -> @lower.BoundPrepared {
  let p = @pipeline.check_with_evidence(
    input_cursor(tail),
    [("seed", contract)],
    None,
    Some(input_cursor("\"seed\"")),
    {
      max_steps: 100,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  @lower.bind_parameters(
    @lower.prepare(p, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
test "sort keeps an imported total witness only from its actual completed producer" {
  let owner = sort_seed(",{\"sort\":[{\"id\":\"desc\"}]}")
  let upstream = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["sort_1"],
    100000,
    10000,
  ).unwrap()
  let limits : SequenceExecutionLimits = {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }
  let complete = execute_generated_sequence(upstream, [], limits).unwrap()
  let output = completed_output(complete, Step(1)).unwrap()
  let producer = @pipeline.produced_input(
    @lower.pipeline(@lower.bound_preparation(owner)),
    Step(1),
  ).unwrap()
  let receiver = sort_input_owner(
    @pipeline.ProducedInput(producer),
    "[{\"sort\":[{\"k\":\"asc\"}]},{\"take\":1}]",
  )
  let sequence = prepared_sequence(receiver)
  let p = @lower.pipeline(@lower.bound_preparation(receiver))
  guard @pipeline.sort_order_strategy(@pipeline.sort_order(p, 0).unwrap())
    is ExistingTotal(prior) else {
    fail("retained producer")
  }
  assert_true(
    physical_equal(@pipeline.order_input_producer(prior).unwrap(), producer),
  )
  let received = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [],
    ["limit_1"],
    100000,
    10000,
  ).unwrap()
  let binding = bind_completed_input(receiver, 0, owner, output).unwrap()
  let result = execute_generated_sequence(received, [], limits, produced=[
    binding,
  ]).unwrap()
  assert_true(
    test_row_output(completed_output(result, Step(1)).unwrap()).rows[0][0]
    is Number(3),
  )
  let raw = capture_input(
    receiver,
    0,
    [],
    max_rows=3,
    run_limits().input_values,
  ).unwrap()
  assert_true(
    execute_generated_sequence(received, [raw], limits)
    is Err(InputExecutionEvidencePending(0)),
  )
}

///|
test "sort executes each supported scalar domain using the shared comparator" {
  for
    (contract, left, right) in [
      ("{\"type\":\"number\",\"nullable\":false}", "2", "1"),
      ("{\"type\":\"boolean\",\"nullable\":false}", "true", "false"),
      ("{\"type\":\"string\",\"nullable\":false}", "\"z\"", "\"a\""),
      (
        "{\"type\":\"date\",\"nullable\":false}", "\"2026-01-02\"", "\"2026-01-01\"",
      ),
      (
        "{\"type\":\"timestamp\",\"nullable\":false}", "\"2026-01-01T00:00:00.002Z\"",
        "\"2026-01-01T00:00:00.001Z\"",
      ),
      (
        "{\"type\":\"decimal\",\"nullable\":false,\"precision\":38,\"scale\":2}",
        "\"12345678901234567890123456789012345.02\"", "\"12345678901234567890123456789012345.01\"",
      ),
    ] {
    let owner = bound_pipeline(
      "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"k\":" +
      contract +
      "},\"rows\":[{\"id\":2,\"k\":" +
      left +
      "},{\"id\":1,\"k\":" +
      right +
      "}]},\"as\":\"seed\"},{\"sort\":[{\"k\":\"asc\"}]}]",
    )
    let generated = prepare_generated_sequence(
      registered_relation_contracts(),
      prepared_sequence(owner),
      [],
      ["sort_1"],
      100000,
      10000,
    ).unwrap()
    let complete = execute_generated_sequence(generated, [], {
      rows: run_limits(),
      max_work: 100000,
      max_frames: 100,
    }).unwrap()
    assert_true(
      test_row_output(completed_output(complete, Step(1)).unwrap()).rows[0][0]
      is Number(1),
    )
  }
}

///|
test "sort charges shared work across distinct and take and can retry with fresh limits" {
  let sequence = prepared_sequence(
    sort_seed(
      ",{\"sort\":[{\"id\":\"asc\"}]},{\"select\":[\"id\"]},{\"distinct\":true},{\"take\":1}",
    ),
  )
  let contracts = registered_relation_contracts()
  let generated = prepare_generated_sequence(
    contracts,
    sequence,
    [],
    ["limit_4"],
    100000,
    10000,
  ).unwrap()
  let control = { remaining: 100000, max_frames: 100, }
  assert_true(
    evaluate_sequence_components(
      contracts,
      sequence,
      [],
      ["limit_4"],
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
  assert_true(execute_generated_sequence(generated, [], limits) is Ok(_))
  assert_true(
    execute_generated_sequence(generated, [], { ..limits, max_work: used - 1, })
    is Err(_),
  )
  assert_true(
    execute_generated_sequence(generated, [], {
      ..limits,
      rows: { ..limits.rows, operation_entries: 1, },
    })
    is Err(_),
  )
  assert_true(execute_generated_sequence(generated, [], limits) is Ok(_))
}

///|
test "sort candidate completion uses checked keys and validates actual uniqueness" {
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
  let owner = sort_input_owner(
    @pipeline.KeyedInput(key),
    "[{\"sort\":[{\"s\":\"desc\"}]},{\"take\":1}]",
  )
  let sequence = prepared_sequence(owner)
  guard @lower.sequence_step(sequence, 0) is Some(@lower.RowStep(kernel)) else {
    fail("sort")
  }
  assert_eq(@lower.kernel_sort_term_count(kernel), 2)
  assert_eq(
    @lower.kernel_sort_term_at(kernel, 1),
    Some((@schema.Unqualified("n"), false, false)),
  )
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [],
    ["sort_0", "limit_1"],
    100000,
    10000,
  ).unwrap()
  for duplicate in [false, true] {
    let rows = [
      input_cursor("{\"n\":2,\"s\":\"tie\"}"),
      input_cursor(
        if duplicate {
          "{\"n\":2,\"s\":\"tie\"}"
        } else {
          "{\"n\":1,\"s\":\"tie\"}"
        },
      ),
    ]
    let captured = capture_input(
      owner,
      0,
      rows,
      max_rows=2,
      run_limits().input_values,
    ).unwrap()
    let result = execute_generated_sequence(generated, [captured], {
      rows: run_limits(),
      max_work: 100000,
      max_frames: 100,
    })
    if duplicate {
      assert_true(result is Err(InputKey(0, _)))
    } else {
      assert_true(
        test_row_output(completed_output(result.unwrap(), Step(1)).unwrap()).rows[0][0]
        is Number(1),
      )
    }
  }
  let unresolved = sort_input_owner(
    @pipeline.CarrierInput(carrier),
    "[{\"sort\":[{\"s\":\"asc\"}]}]",
  )
  assert_true(
    @lower.prepare_kernel(
      unresolved,
      0,
      max_bindings=100,
      max_name_bytes=1000,
      {
        max_nodes: 1000,
        max_work: 10000,
        max_depth: 100,
        max_literal_nodes: 1000,
        max_literal_text_bytes: 10000,
      },
    )
    is Err(@lower.PendingSortOrder),
  )
}
