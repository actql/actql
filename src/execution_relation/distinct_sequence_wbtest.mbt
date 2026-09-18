///|
test "whole-row distinct preserves first occurrence and feeds take in the same driver" {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"k\":{\"type\":\"number\",\"nullable\":true}},\"rows\":[{\"k\":2},{\"k\":1},{\"k\":2},{\"k\":null},{\"k\":null}]},\"as\":\"seed\"},{\"rename\":{\"k\":\"x\"}},{\"distinct\":true},{\"take\":{\"count\":1,\"offset\":1}}]",
  )
  let sequence = prepared_sequence(owner)
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [],
    ["distinct_2", "limit_3"],
    100000,
    10000,
  ).unwrap()
  let limits : SequenceExecutionLimits = {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }
  assert_true(
    execute_generated_sequence(generated, [], { ..limits, max_work: 0, })
    is Err(_),
  )
  for _i = 0; _i < 2; _i = _i + 1 {
    let complete = execute_generated_sequence(generated, [], limits).unwrap()
    let distinct = test_row_output(completed_output(complete, Step(2)).unwrap())
    assert_eq(distinct.names, ["x"])
    assert_eq(distinct.rows.length(), 3)
    assert_true(distinct.rows[0][0] is Number(2.0))
    assert_true(distinct.rows[1][0] is Number(1.0))
    assert_true(distinct.rows[2][0] is Null)
    assert_true(
      test_row_output(completed_output(complete, Step(3)).unwrap()).rows[0][0]
      is Number(1.0),
    )
  }
}

///|
test "distinct comparison readiness depends on selected schema not row count" {
  for rows in ["[]", "[{\"k\":1,\"payload\":[1]}]"] {
    for projected in [false, true] {
      let sequence = prepared_sequence(
        bound_pipeline(
          "[{\"values\":{\"schema\":{\"k\":{\"type\":\"number\",\"nullable\":false},\"payload\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}},\"rows\":" +
          rows +
          "},\"as\":\"seed\"}" +
          (if projected { ",{\"select\":[\"k\"]}" } else { "" }) +
          ",{\"distinct\":true}]",
        ),
      )
      let step = if projected { 2 } else { 1 }
      let result = prepare_generated_sequence(
        registered_relation_contracts(),
        sequence,
        [],
        ["distinct_" + step.to_string()],
        100000,
        10000,
      )
      if projected {
        let complete = execute_generated_sequence(result.unwrap(), [], {
          rows: run_limits(),
          max_work: 100000,
          max_frames: 100,
        }).unwrap()
        assert_eq(
          test_row_output(completed_output(complete, Step(step)).unwrap()).names,
          ["k"],
        )
      } else {
        assert_true(result is Err(UnsupportedRowComparison(1, _)))
      }
    }
  }
}

///|
test "empty-schema distinct collapses identical empty tuples but preserves empty input" {
  let schema = @schema.from_fields([], max_fields=0, max_name_bytes=0).unwrap()
  let checked = @pipeline.check(
    input_cursor("[{\"distinct\":true}]"),
    [("seed", schema)],
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
      max_nodes: 100,
      max_references: 100,
      max_work: 10000,
      max_identifier_bytes: 10000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["distinct_0"],
    100000,
    10000,
  ).unwrap()
  for count in [0, 3] {
    let input = capture_input(
      owner,
      0,
      Array::makei(count, _ => input_cursor("{}")),
      max_rows=3,
      run_limits().input_values,
    ).unwrap()
    let complete = execute_generated_sequence(generated, [input], {
      rows: run_limits(),
      max_work: 100000,
      max_frames: 100,
    }).unwrap()
    let table = test_row_output(completed_output(complete, Step(0)).unwrap())
    assert_eq(table.names, [])
    assert_eq(table.rows.length(), if count == 0 { 0 } else { 1 })
  }
}

///|
fn distinct_input_owner(
  key : @contract.Contract,
  payload : @contract.Contract,
  whole : Bool,
) -> @lower.BoundPrepared {
  let schema = @schema.from_fields(
    [
      (@schema.Unqualified("key"), key),
      (@schema.Unqualified("payload"), payload),
    ],
    max_fields=2,
    max_name_bytes=100,
  ).unwrap()
  let carrier = @carrier.relation(@carrier.typed_rows(schema))
  let checked = @pipeline.check_with_evidence(
    input_cursor(if whole { "[{\"distinct\":true}]" } else { "[{\"distinct\":[\"key\"]}]" }),
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
test "whole-row distinct compares every key domain including owned references" {
  let payload = select_checked_contract("{\"type\":\"number\",\"nullable\":false}")
  let cases = [
    ("{\"type\":\"string\",\"nullable\":false}", "\"é\"", "ordinary"),
    ("{\"type\":\"number\",\"nullable\":false}", "1", "ordinary"),
    (
      "{\"type\":\"decimal\",\"precision\":4,\"scale\":2,\"nullable\":false}",
      "\"1.20\"", "ordinary",
    ),
    ("{\"type\":\"boolean\",\"nullable\":false}", "true", "ordinary"),
    (
      "{\"type\":\"timestamp\",\"nullable\":false}",
      "\"2000-02-29T12:30:00.000Z\"", "ordinary",
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
    let owner = distinct_input_owner(key, payload, true)
    let sequence = prepared_sequence(owner)
    prepare_generated_sequence(
      registered_relation_contracts(),
      sequence,
      [],
      ["distinct_0"],
      100000,
      10000,
    ).unwrap() |> ignore
    let live = Ref(true)
    let value = assertion_admitted_value(key, wire, kind, live)
    let kernel = row_kernel(owner, 0)
    let result = evaluate_rows(
      kernel,
      {
        owner,
        id: @lower.kernel_input(kernel),
        names: ["key", "payload"],
        rows: [[value, Number(7)], [value, Number(7)]],
      },
      2,
      { remaining: 100000, max_frames: 100, },
      value_budget(run_limits().output_values).unwrap(),
    ).unwrap()
    assert_eq(result.rows.length(), 1)
    assert_true(append_value_equal(result.rows[0][0], value))
    live.val = false
  }
}

///|
test "keyed distinct accepts every relation value payload domain" {
  let key = select_checked_contract("{\"type\":\"number\",\"nullable\":false}")
  let cases = [
    ("{\"type\":\"string\",\"nullable\":true}", "\"é\"", "ordinary"),
    ("{\"type\":\"number\",\"nullable\":true}", "1", "ordinary"),
    (
      "{\"type\":\"decimal\",\"precision\":4,\"scale\":2,\"nullable\":true}",
      "\"1.20\"", "ordinary",
    ),
    ("{\"type\":\"boolean\",\"nullable\":true}", "true", "ordinary"),
    (
      "{\"type\":\"timestamp\",\"nullable\":true}",
      "\"2000-02-29T12:30:00.000Z\"", "ordinary",
    ),
    ("{\"type\":\"date\",\"nullable\":true}", "\"0000-02-29\"", "ordinary"),
    (
      "{\"type\":\"json\",\"nullable\":true}",
      "{\"z\":[1,null],\"a\":\"x\"}", "ordinary",
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
    let owner = distinct_input_owner(key, payload, false)
    let live = Ref(true)
    let value = assertion_admitted_value(payload, wire, kind, live)
    let kernel = row_kernel(owner, 0)
    let result = evaluate_rows(
      kernel,
      {
        owner,
        id: @lower.kernel_input(kernel),
        names: ["key", "payload"],
        rows: [[Number(1), value], [Number(1), Null]],
      },
      2,
      { remaining: 100000, max_frames: 100, },
      value_budget(run_limits().output_values).unwrap(),
    ).unwrap()
    assert_eq(result.names, ["key"])
    assert_eq(result.rows.length(), 1)
    assert_true(result.rows[0][0] is Number(1))
    live.val = false
  }
}
