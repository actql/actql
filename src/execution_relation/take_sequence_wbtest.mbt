///|
test "take uses proven input order and safe offset without skipping upstream" {
  for (offset, expected) in [(0L, 2), (1L, 1), (2L, 0), (9007199254740991L, 0)] {
    let sequence = prepared_sequence(
      row_owner(
        ",{\"rename\":{\"a\":\"x\"}},{\"take\":{\"count\":9007199254740991,\"offset\":" +
        offset.to_string() +
        "}}",
      ),
    )
    let generated = prepare_generated_sequence(
      registered_relation_contracts(),
      sequence,
      [],
      ["limit_2"],
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
      let completed = execute_generated_sequence(generated, [], limits).unwrap()
      let table = test_row_output(completed_output(completed, Step(2)).unwrap())
      assert_eq(table.names, ["x", "b"])
      assert_eq(table.rows.length(), expected)
      if offset == 1L {
        assert_true(table.rows[0][0] is Number(0.0))
      }
    }
  }
  let sequence = prepared_sequence(
    row_owner(
      ",{\"derive\":{\"bad\":\"1 / b\"}},{\"take\":{\"count\":1,\"offset\":9007199254740991}}",
    ),
  )
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [sequence_fragment_context(sequence, 1, 2L)],
    ["limit_2"],
    100000,
    10000,
  ).unwrap()
  assert_true(
    execute_generated_sequence(generated, [], {
      rows: run_limits(),
      max_work: 100000,
      max_frames: 100,
    })
    is Err(Rows(1, Evaluation(_, _, _))),
  )
}

///|
test "take rejects missing order during preparation even for empty runtime input" {
  let schema = @schema.from_fields([], max_fields=0, max_name_bytes=0).unwrap()
  let checked = @pipeline.check(
    input_cursor("[{\"take\":1}]"),
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
  assert_true(
    @lower.prepare_kernel(owner, 0, max_bindings=100, max_name_bytes=100, {
      max_nodes: 100,
      max_work: 1000,
      max_depth: 100,
      max_literal_nodes: 100,
      max_literal_text_bytes: 1000,
    })
    is Err(@lower.PendingTakeOrder),
  )
}

///|
test "take physical budgets apply to full input and permit exact selected output" {
  let table = order_table([Number(2), Number(1), Number(0)])
  let control = { remaining: 10000, max_frames: 0, }
  let workspace = { limit: 1000, live: 0, peak: 0, }
  let result = evaluate_take_rows(
    table,
    "limited",
    1L,
    1L,
    3,
    control,
    row_output(),
    workspace,
  ).unwrap()
  assert_true(result.rows[0][0] is Number(1.0))
  let used = 10000 - control.remaining
  let peak = workspace.peak
  for
    (work, space, expected) in [
      (used, peak, true),
      (used - 1, peak, false),
      (used, peak - 1, false),
    ] {
    let result = evaluate_take_rows(
      table,
      "limited",
      1L,
      1L,
      3,
      { remaining: work, max_frames: 0, },
      row_output(),
      { limit: space, live: 0, peak: 0, },
    )
    if expected {
      assert_true(result is Ok(_))
    } else {
      assert_true(result is Err(RowLimit))
    }
  }
  assert_true(
    evaluate_take_rows(
      table,
      "limited",
      1L,
      9007199254740991L,
      2,
      { remaining: 1000, max_frames: 0, },
      row_output(),
      { limit: 1000, live: 0, peak: 0, },
    )
    is Err(RowLimit),
  )
}

///|
test "take retains independent selected branch outputs" {
  let sequence = prepared_sequence(
    row_owner(
      ",{\"take\":1,\"as\":\"first\"},{\"from\":\"seed\",\"take\":{\"count\":1,\"offset\":1}}",
    ),
  )
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [],
    ["limit_1", "limit_2"],
    100000,
    10000,
  ).unwrap()
  let completed = execute_generated_sequence(generated, [], {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }).unwrap()
  assert_true(
    test_row_output(completed_output(completed, Step(1)).unwrap()).rows[0][0]
    is Number(1.0),
  )
  assert_true(
    test_row_output(completed_output(completed, Step(2)).unwrap()).rows[0][0]
    is Number(0.0),
  )
}

///|
test "take preserves every relation value domain and NULL" {
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
    let contract = select_checked_contract(body)
    let live = Ref(true)
    let value = match kind {
      "resource" =>
        issued_resource_value(
          contract, "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
          live,
        ).value
      "artifact" => issued_artifact_value(contract, live).value
      _ =>
        @admitted.admit(contract, input_cursor(wire), {
          max_nodes: 100,
          max_depth: 10,
          max_text_bytes: 1000,
        }).unwrap().value
    }
    let table : Table = {
      owner: row_owner(""),
      id: "source",
      names: ["value"],
      rows: [[capture(value)], [Null]],
    }
    let result = evaluate_take_rows(
      table,
      "limited",
      2L,
      0L,
      2,
      { remaining: 10000, max_frames: 0, },
      row_output(),
      { limit: 1000, live: 0, peak: 0, },
    ).unwrap()
    assert_true(append_value_equal(result.rows[0][0], capture(value)))
    assert_true(result.rows[1][0] is Null)
    live.val = false
  }
}
