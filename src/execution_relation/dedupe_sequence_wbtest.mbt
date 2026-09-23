///|
fn dedupe_source(rows : String, by : String, tail : String) -> String {
  "[{\"values\":{\"schema\":{\"k\":{\"type\":\"number\",\"nullable\":true},\"rank\":{\"type\":\"number\",\"nullable\":false},\"payload\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}},\"rows\":" +
  rows +
  "},\"as\":\"seed\"},{\"dedupe_rows\":{\"by\":" +
  by +
  ",\"order_by\":[{\"rank\":\"desc\"}]}}" +
  tail +
  "]"
}

///|
fn dedupe_contract_owner(
  key : @contract.Contract,
  rank : @contract.Contract,
  payload : @contract.Contract,
) -> @lower.BoundPrepared {
  let schema = @schema.from_fields(
    [
      (@schema.Unqualified("key"), key),
      (@schema.Unqualified("rank"), rank),
      (@schema.Unqualified("payload"), payload),
    ],
    max_fields=3,
    max_name_bytes=100,
  ).unwrap()
  let carrier = @carrier.relation(@carrier.typed_rows(schema))
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"dedupe_rows\":{\"by\":[\"key\"]," +
      "\"order_by\":[{\"rank\":\"desc\"}]}}]",
    ),
    [("seed", @pipeline.CarrierInput(carrier))],
    None,
    Some(input_cursor("\"seed\"")),
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  @lower.bind_parameters(
    @lower.prepare(checked, {
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
fn run_dedupe_contract_rows(
  owner : @lower.BoundPrepared,
  rows : Array[Array[Value]],
) -> Result[Table, RowIssue] {
  let kernel = row_kernel(owner, 0)
  evaluate_rows(
    kernel,
    {
      owner,
      id: @lower.kernel_input(kernel),
      names: ["key", "rank", "payload"],
      rows,
    },
    rows.length(),
    { remaining: 100000, max_frames: 100, },
    value_budget(run_limits().output_values).unwrap(),
  )
}

///|
test "dedupe runs through the owned driver retaining payload and canonical group order" {
  let sequence = prepared_sequence(
    bound_pipeline(
      dedupe_source(
        "[{\"k\":2,\"rank\":1,\"payload\":[10]},{\"k\":1,\"rank\":2,\"payload\":[20]},{\"k\":2,\"rank\":3,\"payload\":[30]},{\"k\":1,\"rank\":4,\"payload\":[40]}]",
        "[\"k\"]", ",{\"select\":[\"rank\",\"payload\"]}",
      ),
    ),
  )
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [],
    ["dedupe_1", "select_2"],
    100000,
    10000,
  ).unwrap()
  let limits : SequenceExecutionLimits = {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }
  assert_true(
    execute_generated_sequence(generated, [], {
      ..limits,
      rows: { ..limits.rows, operation_entries: 1, },
    })
    is Err(_),
  )
  for _i in 0..<2 {
    let complete = execute_generated_sequence(generated, [], limits).unwrap()
    let table = test_row_output(completed_output(complete, Step(1)).unwrap())
    assert_eq(table.rows.length(), 2)
    // Typed numeric key order is independent of the input and CID order.
    assert_true(table.rows[0][0] is Number(1))
    assert_true(table.rows[1][0] is Number(2))
    let selected = test_row_output(completed_output(complete, Step(2)).unwrap())
    assert_eq(selected.names, ["rank", "payload"])
    assert_true(selected.rows[0][0] is Number(4))
    assert_true(selected.rows[1][0] is Number(3))
    assert_true(selected.rows[0][1] is Captured(@admitted.Array(_)))
  }
}

///|
test "global dedupe handles empty input and rejects only first-place ties" {
  for
    (rows, expected) in [
      ("[]", 0),
      (
        "[{\"k\":null,\"rank\":2,\"payload\":[]},{\"k\":1,\"rank\":1,\"payload\":[]},{\"k\":2,\"rank\":1,\"payload\":[]}]",
        1,
      ),
    ] {
    let generated = prepare_generated_sequence(
      registered_relation_contracts(),
      prepared_sequence(bound_pipeline(dedupe_source(rows, "[]", ""))),
      [],
      ["dedupe_1"],
      100000,
      10000,
    ).unwrap()
    let complete = execute_generated_sequence(generated, [], {
      rows: run_limits(),
      max_work: 100000,
      max_frames: 100,
    }).unwrap()
    assert_eq(
      test_row_output(completed_output(complete, Step(1)).unwrap()).rows.length(),
      expected,
    )
  }
}

///|
test "unselected dedupe top tie fails the sequence without publishing an earlier output" {
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(
      bound_pipeline(
        dedupe_source(
          "[{\"k\":null,\"rank\":2,\"payload\":[1]},{\"k\":null,\"rank\":2,\"payload\":[2]}]",
          "[\"k\",\"k\"]", "",
        ),
      ),
    ),
    [],
    ["values_0"],
    100000,
    10000,
  ).unwrap()
  for _i in 0..<2 {
    assert_true(
      execute_generated_sequence(generated, [], {
        rows: run_limits(),
        max_work: 100000,
        max_frames: 100,
      })
      is Err(Rows(1, DedupeTopTie(0, 1))),
    )
  }
}

///|
test "dedupe prepares owned reference equality before reading rows" {
  let contract = @contract.read_author(
    input_cursor(
      "{\"type\":\"object\",\"nullable\":false,\"fields\":{\"k\":{\"type\":\"resource_ref\",\"resource_kind\":\"file\",\"nullable\":true},\"rank\":{\"type\":\"number\",\"nullable\":false}}}",
    ),
    { max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let checked = @pipeline.check(
    input_cursor(
      "[{\"dedupe_rows\":{\"by\":[\"k\"],\"order_by\":[{\"rank\":\"desc\"}]}}]",
    ),
    [("seed", @schema.from_object(contract).unwrap())],
    None,
    Some(input_cursor("\"seed\"")),
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  let owner = @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 10,
      max_references: 10,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  let sequence = prepared_sequence(owner)
  for rows in [[], [input_cursor("{\"k\":null,\"rank\":1}")]] {
    assert_true(
      capture_input(owner, 0, rows, max_rows=1, run_limits().input_values)
      is Ok(_),
    )
    assert_true(
      prepare_generated_sequence(
        registered_relation_contracts(),
        sequence,
        [],
        ["dedupe_0"],
        100000,
        10000,
      )
      is Ok(_),
    )
  }
}

///|
test "dedupe shares sequence work and enforces the exact execution boundary" {
  let sequence = prepared_sequence(
    bound_pipeline(
      dedupe_source(
        "[{\"k\":2,\"rank\":1,\"payload\":[1]},{\"k\":1,\"rank\":3,\"payload\":[2]}]",
        "[\"k\"]", ",{\"drop\":[\"payload\"]}",
      ),
    ),
  )
  let contracts = registered_relation_contracts()
  let generated = prepare_generated_sequence(
    contracts,
    sequence,
    [],
    ["select_2"],
    100000,
    10000,
  ).unwrap()
  let control = { remaining: 100000, max_frames: 100, }
  assert_true(
    evaluate_sequence_components(
      contracts,
      sequence,
      [],
      ["select_2"],
      run_limits(),
      control,
      fragments=Some([]),
    )
    is Ok(_),
  )
  let used = 100000 - control.remaining
  assert_true(
    execute_generated_sequence(generated, [], {
      rows: run_limits(),
      max_work: used,
      max_frames: 100,
    })
    is Ok(_),
  )
  assert_true(
    execute_generated_sequence(generated, [], {
      rows: run_limits(),
      max_work: used - 1,
      max_frames: 100,
    })
    is Err(_),
  )
  assert_true(
    execute_generated_sequence(generated, [], {
      rows: run_limits(),
      max_work: used,
      max_frames: 100,
    })
    is Ok(_),
  )
}

///|
test "dedupe preserves every relation value payload domain" {
  let key = select_checked_contract("{\"type\":\"number\",\"nullable\":false}")
  let rank = key
  let cases = [
    ("{\"type\":\"string\",\"nullable\":true}", "\"é\"", "ordinary"),
    ("{\"type\":\"number\",\"nullable\":true}", "1", "ordinary"),
    (
      "{\"type\":\"decimal\",\"precision\":4,\"scale\":2,\"nullable\":true}", "\"1.20\"",
      "ordinary",
    ),
    ("{\"type\":\"boolean\",\"nullable\":true}", "true", "ordinary"),
    (
      "{\"type\":\"timestamp\",\"nullable\":true}", "\"2000-02-29T12:30:00.000Z\"",
      "ordinary",
    ),
    ("{\"type\":\"date\",\"nullable\":true}", "\"0000-02-29\"", "ordinary"),
    (
      "{\"type\":\"json\",\"nullable\":true}", "{\"z\":[1,null],\"a\":\"x\"}", "ordinary",
    ),
    (
      "{\"type\":\"object\",\"nullable\":true,\"additional_properties\":false,\"fields\":{\"x\":{\"type\":\"string\",\"nullable\":false}}}",
      "{\"x\":\"v\"}", "ordinary",
    ),
    (
      "{\"type\":\"array\",\"nullable\":true,\"items\":{\"type\":\"number\",\"nullable\":true},\"max_items\":2}",
      "[1,null]", "ordinary",
    ),
    (
      "{\"type\":\"vector\",\"nullable\":true,\"dimensions\":2,\"element_type\":\"f32\"}",
      "[1,2]", "ordinary",
    ),
    (
      "{\"type\":\"resource_ref\",\"nullable\":true,\"resource_kind\":\"mail/message\"}",
      "", "resource",
    ),
    (
      "{\"type\":\"artifact_ref\",\"nullable\":true,\"media_type\":\"application/json\"}",
      "", "artifact",
    ),
  ]
  for (body, wire, kind) in cases {
    let payload = select_checked_contract(body)
    let owner = dedupe_contract_owner(key, rank, payload)
    let live = Ref(true)
    let value = assertion_admitted_value(payload, wire, kind, live)
    let result = run_dedupe_contract_rows(owner, [[Number(1), Number(1), value]]).unwrap()
    assert_eq(result.rows.length(), 1)
    assert_true(append_value_equal(result.rows[0][2], value))
    live.val = false
  }
}

///|
test "dedupe compares every key domain including owned references" {
  let rank = select_checked_contract("{\"type\":\"number\",\"nullable\":false}")
  let payload = rank
  let cases = [
    ("{\"type\":\"string\",\"nullable\":false}", "\"é\"", "ordinary"),
    ("{\"type\":\"number\",\"nullable\":false}", "1", "ordinary"),
    (
      "{\"type\":\"decimal\",\"precision\":4,\"scale\":2,\"nullable\":false}", "\"1.20\"",
      "ordinary",
    ),
    ("{\"type\":\"boolean\",\"nullable\":false}", "true", "ordinary"),
    (
      "{\"type\":\"timestamp\",\"nullable\":false}", "\"2000-02-29T12:30:00.000Z\"",
      "ordinary",
    ),
    ("{\"type\":\"date\",\"nullable\":false}", "\"0000-02-29\"", "ordinary"),
    (
      "{\"type\":\"resource_ref\",\"nullable\":false,\"resource_kind\":\"mail/message\"}",
      "", "resource",
    ),
    (
      "{\"type\":\"artifact_ref\",\"nullable\":false,\"media_type\":\"application/json\"}",
      "", "artifact",
    ),
  ]
  for (body, wire, kind) in cases {
    let key = select_checked_contract(body)
    let owner = dedupe_contract_owner(key, rank, payload)
    let live = Ref(true)
    let value = assertion_admitted_value(key, wire, kind, live)
    let rows = [[value, Number(1), Number(10)], [value, Number(2), Number(20)]]
    let result = run_dedupe_contract_rows(owner, rows).unwrap()
    assert_eq(result.rows.length(), 1)
    assert_true(result.rows[0][2] is Number(20))
    live.val = false
    if kind != "ordinary" {
      assert_true(
        run_dedupe_contract_rows(owner, rows) is Err(Comparison(InvalidOperand)),
      )
    }
  }
}

///|
test "dedupe orders every author orderable domain" {
  let key = select_checked_contract("{\"type\":\"number\",\"nullable\":false}")
  let payload = key
  let cases = [
    ("{\"type\":\"string\",\"nullable\":false}", "\"a\"", "\"é\""),
    ("{\"type\":\"number\",\"nullable\":false}", "1", "2"),
    (
      "{\"type\":\"decimal\",\"precision\":4,\"scale\":2,\"nullable\":false}", "\"1.20\"",
      "\"2.30\"",
    ),
    ("{\"type\":\"boolean\",\"nullable\":false}", "false", "true"),
    (
      "{\"type\":\"timestamp\",\"nullable\":false}", "\"2000-02-29T12:30:00.000Z\"",
      "\"2000-03-01T12:30:00.000Z\"",
    ),
    (
      "{\"type\":\"date\",\"nullable\":false}", "\"0000-02-29\"", "\"2000-02-29\"",
    ),
  ]
  for (body, low_wire, high_wire) in cases {
    let rank = select_checked_contract(body)
    let live = Ref(true)
    let low = assertion_admitted_value(rank, low_wire, "ordinary", live)
    let high = assertion_admitted_value(rank, high_wire, "ordinary", live)
    let result = run_dedupe_contract_rows(
      dedupe_contract_owner(key, rank, payload),
      [[Number(1), low, Number(10)], [Number(1), high, Number(20)]],
    ).unwrap()
    assert_eq(result.rows.length(), 1)
    assert_true(result.rows[0][2] is Number(20))
  }
}
