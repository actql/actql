///|
test "checked group count runs through generated sequence without expression contexts" {
  let sequence = prepared_sequence(
    bound_pipeline(
      "[{\"values\":{\"schema\":{\"k\":{\"type\":\"number\",\"nullable\":true},\"v\":{\"type\":\"string\",\"nullable\":true}},\"rows\":[{\"k\":2,\"v\":null},{\"k\":null,\"v\":{\"literal\":\"x\"}},{\"k\":1,\"v\":null},{\"k\":2,\"v\":{\"literal\":\"x\"}},{\"k\":null,\"v\":null}]},\"as\":\"seed\"},{\"group\":{\"by\":[\"k\",\"k\"],\"aggregates\":{\"rows\":{\"fn\":\"count\"},\"present\":{\"fn\":\"count\",\"field\":\"v\"}}}}]",
    ),
  )
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [],
    ["group_1"],
    100000,
    10000,
  ).unwrap()
  let result = execute_generated_sequence(generated, [], {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }).unwrap()
  let table = test_row_output(completed_output(result, Step(1)).unwrap())
  assert_eq(table.names, ["k", "present", "rows"])
  assert_eq(table.rows.length(), 3)
  assert_true(table.rows[0][0] is Null)
  assert_true(table.rows[0][1] is Number(1))
  assert_true(table.rows[0][2] is Number(2))
  assert_true(table.rows[1][0] is Number(1))
  assert_true(table.rows[1][1] is Number(0))
  assert_true(table.rows[1][2] is Number(1))
  assert_true(table.rows[2][0] is Number(2))
  assert_true(table.rows[2][1] is Number(1))
  assert_true(table.rows[2][2] is Number(2))
}

///|
test "empty global count publishes zero and feeds an independently completed consumer" {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"k\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[]},\"as\":\"seed\"},{\"group\":{\"by\":[],\"aggregates\":{\"a\":{\"fn\":\"count\"}}}}]",
  )
  let sequence = prepared_sequence(owner)
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [],
    ["group_1"],
    100000,
    10000,
  ).unwrap()
  let result = execute_generated_sequence(generated, [], {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }).unwrap()
  let output = completed_output(result, Step(1)).unwrap()
  let table = test_row_output(output)
  assert_eq(table.names, ["a"])
  assert_eq(table.rows.length(), 1)
  assert_true(table.rows[0][0] is Number(0))
  let receiver = producer_consumer(owner, Step(1))
  let live = Ref(true)
  let binding = bind_live_completed_input(receiver, 0, owner, output, fn() {
    live.val
  }).unwrap()
  let downstream = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(receiver),
    [],
    ["select_0"],
    100000,
    10000,
  ).unwrap()
  let completed = execute_generated_sequence(
    downstream,
    [],
    { rows: run_limits(), max_work: 100000, max_frames: 100, },
    produced=[binding],
  ).unwrap()
  live.val = false
  assert_true(
    test_row_output(completed_output(completed, Step(0)).unwrap()).rows[0][0]
    is Number(0),
  )
  assert_true(
    execute_generated_sequence(
      downstream,
      [],
      { rows: run_limits(), max_work: 100000, max_frames: 100, },
      produced=[binding],
    )
    is Err(_),
  )
  // Zero input rows do not waive the independently enforced output limit.
  assert_true(
    execute_generated_sequence(generated, [], {
      rows: { ..run_limits(), max_rows: 0, },
      max_work: 100000,
      max_frames: 100,
    })
    is Err(Rows(1, RowLimit)),
  )
}

///|
test "group count enforces its cumulative result ceiling" {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"k\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"k\":1},{\"k\":2}]},\"as\":\"seed\"},{\"group\":{\"by\":[\"k\"],\"aggregates\":{\"n\":{\"fn\":\"count\"}}}}]",
  )
  assert_true(
    evaluate_rows(
      row_kernel(owner, 1),
      row_capture(owner),
      1,
      { remaining: 100000, max_frames: 100, },
      row_output(),
    )
    is Err(RowLimit),
  )
}

///|
test "complete direct aggregates preserve group order and exact values" {
  let owner = bound_pipeline(
    (
      #|[{"values":{"schema":{"k":{"type":"number","nullable":true},"flag":{"type":"boolean","nullable":true},"amount":{"type":"decimal","precision":4,"scale":2,"nullable":true},"label":{"type":"string","nullable":true}},"rows":[{"k":2,"flag":true,"amount":"1.25","label":{"literal":"b"}},{"k":null,"flag":true,"amount":"-0.25","label":{"literal":"a"}},{"k":1,"flag":null,"amount":null,"label":null},{"k":2,"flag":false,"amount":"2.00","label":{"literal":"a"}},{"k":null,"flag":false,"amount":"0.50","label":{"literal":"c"}}]},"as":"seed"},{"group":{"by":["k"],"aggregates":{"distinct_labels":{"fn":"count","field":"label","distinct":true},"hits":{"fn":"count_if","field":"flag"},"highest":{"fn":"max","field":"label"},"lowest":{"fn":"min","field":"label"},"total":{"fn":"sum","field":"amount"}}}}]
    ),
  )
  let sequence = prepared_sequence(owner)
  let group = @lower.kernel_group(row_kernel(owner, 1)).unwrap()
  assert_true(group_execution_supported(group))
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [],
    ["group_1"],
    100000,
    10000,
  ).unwrap()
  let completed = execute_generated_sequence(generated, [], {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }).unwrap()
  let table = test_row_output(completed_output(completed, Step(1)).unwrap())
  assert_eq(table.names, [
    "distinct_labels", "highest", "hits", "k", "lowest", "total",
  ])
  assert_eq(table.rows.length(), 3)
  assert_true(table.rows[0][0] is Number(2))
  assert_true(table.rows[0][1] is Text("c"))
  assert_true(table.rows[0][2] is Number(1))
  assert_true(table.rows[0][3] is Null)
  assert_true(table.rows[0][4] is Text("a"))
  guard table.rows[0][5] is Captured(@admitted.Decimal(null_total)) else {
    fail("decimal total expected")
  }
  assert_eq(
    (null_total.coefficient, null_total.precision, null_total.scale),
    ("25", 38, 2),
  )
  assert_true(table.rows[1][0] is Number(0))
  assert_true(table.rows[1][1] is Null)
  assert_true(table.rows[1][2] is Number(0))
  assert_true(table.rows[1][3] is Number(1))
  assert_true(table.rows[1][4] is Null)
  assert_true(table.rows[1][5] is Null)
  assert_true(table.rows[2][0] is Number(2))
  assert_true(table.rows[2][1] is Text("b"))
  assert_true(table.rows[2][2] is Number(1))
  assert_true(table.rows[2][3] is Number(2))
  assert_true(table.rows[2][4] is Text("a"))
  guard table.rows[2][5] is Captured(@admitted.Decimal(two_total)) else {
    fail("decimal total expected")
  }
  assert_eq(
    (two_total.coefficient, two_total.precision, two_total.scale),
    ("325", 38, 2),
  )
}

///|
test "empty direct aggregates retain the global group laws" {
  let owner = bound_pipeline(
    (
      #|[{"values":{"schema":{"flag":{"type":"boolean","nullable":true},"amount":{"type":"decimal","precision":4,"scale":2,"nullable":true},"label":{"type":"string","nullable":true}},"rows":[]},"as":"seed"},{"group":{"by":[],"aggregates":{"hits":{"fn":"count_if","field":"flag"},"highest":{"fn":"max","field":"label"},"lowest":{"fn":"min","field":"label"},"total":{"fn":"sum","field":"amount"}}}}]
    ),
  )
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["group_1"],
    100000,
    10000,
  ).unwrap()
  let completed = execute_generated_sequence(generated, [], {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }).unwrap()
  let table = test_row_output(completed_output(completed, Step(1)).unwrap())
  assert_eq(table.names, ["highest", "hits", "lowest", "total"])
  assert_eq(table.rows.length(), 1)
  assert_true(table.rows[0][0] is Null)
  assert_true(table.rows[0][1] is Number(0))
  assert_true(table.rows[0][2] is Null)
  assert_true(table.rows[0][3] is Null)
}

///|
test "direct decimal sum checks only its final public precision" {
  let maximum = "999999999999999999999999999999999999.99"
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"amount\":{\"type\":\"decimal\",\"precision\":38,\"scale\":2,\"nullable\":false}},\"rows\":[{\"amount\":\"" +
    maximum +
    "\"},{\"amount\":\"0.01\"},{\"amount\":\"-0.01\"}]},\"as\":\"seed\"},{\"group\":{\"by\":[],\"aggregates\":{\"total\":{\"fn\":\"sum\",\"field\":\"amount\"}}}}]",
  )
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["group_1"],
    100000,
    10000,
  ).unwrap()
  let limits = { rows: run_limits(), max_work: 100000, max_frames: 100, }
  let completed = execute_generated_sequence(generated, [], limits).unwrap()
  let table = test_row_output(completed_output(completed, Step(1)).unwrap())
  guard table.rows[0][0] is Captured(@admitted.Decimal(total)) else {
    fail("decimal total expected")
  }
  assert_eq(total.coefficient, "99999999999999999999999999999999999999")
  let overflow = bound_pipeline(
    "[{\"values\":{\"schema\":{\"amount\":{\"type\":\"decimal\",\"precision\":38,\"scale\":2,\"nullable\":false}},\"rows\":[{\"amount\":\"" +
    maximum +
    "\"},{\"amount\":\"0.01\"}]},\"as\":\"seed\"},{\"group\":{\"by\":[],\"aggregates\":{\"total\":{\"fn\":\"sum\",\"field\":\"amount\"}}}}]",
  )
  let overflow_generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(overflow),
    [],
    ["group_1"],
    100000,
    10000,
  ).unwrap()
  assert_true(
    execute_generated_sequence(overflow_generated, [], limits)
    is Err(Rows(1, Aggregation(ArithmeticFailure))),
  )
}

///|
test "direct group capability rejects work owned by other contracts" {
  for
    aggregate in [
      "{\"n\":{\"fn\":\"sum\",\"field\":\"amount\"}}", "{\"n\":{\"fn\":\"avg\",\"field\":\"amount\"}}",
      "{\"n\":{\"fn\":\"count\",\"filter\":\"flag\"}}", "{\"n\":{\"fn\":\"max\",\"expr\":\"amount\"}}",
    ] {
    let owner = bound_pipeline(
      "[{\"values\":{\"schema\":{\"amount\":{\"type\":\"number\",\"nullable\":true},\"flag\":{\"type\":\"boolean\",\"nullable\":true}},\"rows\":[]},\"as\":\"seed\"},{\"group\":{\"by\":[],\"aggregates\":" +
      aggregate +
      "}}]",
    )
    let group = @lower.kernel_group(row_kernel(owner, 1)).unwrap()
    assert_false(group_execution_supported(group))
  }
}

///|
test "direct group accepts exact shared work and rejects one-short execution" {
  let owner = bound_pipeline(
    (
      #|[{"values":{"schema":{"k":{"type":"number","nullable":true},"amount":{"type":"decimal","precision":4,"scale":2,"nullable":true},"label":{"type":"string","nullable":true}},"rows":[{"k":1,"amount":"1.25","label":{"literal":"a"}},{"k":1,"amount":"2.00","label":{"literal":"b"}}]},"as":"seed"},{"group":{"by":["k"],"aggregates":{"labels":{"fn":"count","field":"label","distinct":true},"total":{"fn":"sum","field":"amount"}}}}]
    ),
  )
  let sequence = prepared_sequence(owner)
  let contracts = registered_relation_contracts()
  let generated = prepare_generated_sequence(
    contracts,
    sequence,
    [],
    ["group_1"],
    100000,
    10000,
  ).unwrap()
  let control = { remaining: 100000, max_frames: 100, }
  assert_true(
    evaluate_sequence_components(
      contracts,
      sequence,
      [],
      ["group_1"],
      run_limits(),
      control,
      fragments=Some([]),
    )
    is Ok(_),
  )
  let used = 100000 - control.remaining
  let exact : SequenceExecutionLimits = {
    rows: run_limits(),
    max_work: used,
    max_frames: 100,
  }
  let completed = execute_generated_sequence(generated, [], exact).unwrap()
  let table = test_row_output(completed_output(completed, Step(1)).unwrap())
  assert_eq(table.names, ["k", "labels", "total"])
  assert_eq(table.rows.length(), 1)
  assert_true(table.rows[0][1] is Number(2))
  assert_true(
    execute_generated_sequence(generated, [], { ..exact, max_work: used - 1, })
    is Err(_),
  )
  assert_true(execute_generated_sequence(generated, [], exact) is Ok(_))
}

///|
fn direct_group_scale_sample(count : Int) -> (Int, Int) raise {
  let owner = bound_pipeline(
    (
      #|[{"values":{"schema":{"k":{"type":"number","nullable":false},"label":{"type":"string","nullable":false}},"rows":[{"k":0,"label":{"literal":"v0"}}]},"as":"seed"},{"group":{"by":["k"],"aggregates":{"labels":{"fn":"count","field":"label","distinct":true},"lowest":{"fn":"min","field":"label"},"highest":{"fn":"max","field":"label"}}}}]
    ),
  )
  let template = row_capture(owner)
  let input = {
    ..template,
    rows: Array::makei(count, index => {
      [Number((index % 64).to_double()), Text("v" + (index % 32).to_string())]
    }),
  }
  let maximum = 100000000
  let control = { remaining: maximum, max_frames: 100, }
  let workspace = { limit: count * 12 + 1000, live: 0, peak: 0, }
  let output = value_budget({
    max_nodes: maximum,
    max_text_bytes: maximum,
    max_depth: 10,
    max_work: maximum,
  }).unwrap()
  let table = evaluate_rows_with_workspace(
    row_kernel(owner, 1),
    input,
    count,
    control,
    output,
    workspace,
  ).unwrap()
  assert_eq(table.rows.length(), Int::min(count, 64))
  (maximum - control.remaining, workspace.peak)
}

///|
test "direct group stays within indexed aggregation scaling floors" {
  for count in [128, 1024, 8192] {
    let (work, peak) = direct_group_scale_sample(count)
    let mut levels = 0
    let mut width = 1
    while width < count {
      width *= 2
      levels += 1
    }
    assert_true(work < count * (levels * 20 + 250))
    assert_true(peak < count * 12 + 1000)
  }
}
