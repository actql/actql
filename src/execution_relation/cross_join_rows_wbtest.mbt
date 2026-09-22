///|
fn cross_join_generated(
  left : String,
  right : String,
  options? : String = "",
) -> GeneratedSequence raise {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":" +
    left +
    "},\"as\":\"left_rows\"},{\"values\":{\"schema\":{\"tag\":{\"type\":\"string\",\"nullable\":false}},\"rows\":" +
    right +
    "},\"as\":\"right_rows\"},{\"from\":\"left_rows\",\"cross_join\":{\"with\":\"right_rows\",\"select\":{\"id\":\"left.id\",\"tag\":\"right.tag\"}" +
    options +
    "},\"as\":\"out\"}]",
  )
  prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["cross_join_2"],
    100000,
    10000,
  ).unwrap()
}

///|
fn cross_join_input_owner(
  contract : @contract.Contract,
) -> @lower.BoundPrepared {
  let schema = @schema.from_fields(
    [(@schema.Unqualified("value"), contract)],
    max_fields=1,
    max_name_bytes=100,
  ).unwrap()
  let carrier = @carrier.relation(@carrier.typed_rows(schema))
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"from\":\"l\",\"cross_join\":{\"with\":\"r\",\"select\":{" +
      "\"left_value\":\"left.value\",\"right_value\":\"right.value\"}}}]",
    ),
    [
      ("l", @pipeline.CarrierInput(carrier)),
      ("r", @pipeline.CarrierInput(carrier)),
    ],
    None,
    None,
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
test "cross join preserves every relation value domain and NULL" {
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
    let owner = cross_join_input_owner(contract)
    guard @lower.sequence_step(prepared_sequence(owner), 0)
      is Some(@lower.CrossJoinStep(kernel)) else {
      fail("cross join kernel")
    }
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
    let null = @admitted.admit(contract, input_cursor("null"), {
        max_nodes: 1,
        max_depth: 0,
        max_text_bytes: 0,
      }).unwrap().value
    let result = evaluate_cross_join_rows(
      kernel,
      AdmittedTable({
        owner,
        id: @lower.cross_join_kernel_input(kernel, true),
        names: ["value"],
        rows: [[value]],
      }),
      AdmittedTable({
        owner,
        id: @lower.cross_join_kernel_input(kernel, false),
        names: ["value"],
        rows: [[null]],
      }),
      1,
      { remaining: 100000, max_frames: 100, },
      value_budget(run_limits().output_values).unwrap(),
      { limit: 10000, live: 0, peak: 0, },
    ).unwrap()
    assert_eq(result.names, ["left_value", "right_value"])
    assert_eq(result.rows.length(), 1)
    assert_true(append_value_equal(result.rows[0][0], capture(value)))
    assert_true(result.rows[0][1] is Null)
    live.val = false
  }
}

///|
test "cross join emits the left-major product and empty-side results" {
  let generated = cross_join_generated(
    "[{\"id\":1},{\"id\":2}]", "[{\"tag\":{\"literal\":\"a\"}},{\"tag\":{\"literal\":\"b\"}}]",
  )
  let completed = execute_generated_sequence(generated, [], {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }).unwrap()
  let table = test_row_output(completed_output(completed, Step(2)).unwrap())
  assert_eq(table.names, ["id", "tag"])
  assert_eq(table.rows.length(), 4)
  for
    (index, id, tag) in [
      (0, 1.0, "a"),
      (1, 1.0, "b"),
      (2, 2.0, "a"),
      (3, 2.0, "b"),
    ] {
    assert_true(table.rows[index][0] is Number(value) && value == id)
    assert_true(table.rows[index][1] is Text(value) && value == tag)
  }
  for
    (left, right) in [
      ("[]", "[{\"tag\":{\"literal\":\"a\"}}]"),
      ("[{\"id\":1}]", "[]"),
    ] {
    let result = execute_generated_sequence(
      cross_join_generated(left, right),
      [],
      { rows: run_limits(), max_work: 100000, max_frames: 100, },
    ).unwrap()
    assert_eq(
      test_row_output(completed_output(result, Step(2)).unwrap()).rows.length(),
      0,
    )
  }
}

///|
test "cross join validates singleton and output ceilings atomically" {
  let singleton = cross_join_generated(
    "[{\"id\":1}]",
    "[{\"tag\":{\"literal\":\"a\"}},{\"tag\":{\"literal\":\"b\"}}]",
    options=",\"right_rows\":\"one\"",
  )
  assert_true(
    execute_generated_sequence(singleton, [], {
      rows: run_limits(),
      max_work: 100000,
      max_frames: 100,
    })
    is Err(Rows(2, InvalidRows)),
  )
  let limited = cross_join_generated(
    "[{\"id\":1},{\"id\":2}]",
    "[{\"tag\":{\"literal\":\"a\"}},{\"tag\":{\"literal\":\"b\"}}]",
    options=",\"max_output_rows\":3",
  )
  assert_true(
    execute_generated_sequence(limited, [], {
      rows: run_limits(),
      max_work: 100000,
      max_frames: 100,
    })
    is Err(Rows(2, RowLimit)),
  )
}

///|
test "cross join releases unpublished workspace after a bounded failure" {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1},{\"id\":2}]},\"as\":\"left_rows\"},{\"values\":{\"schema\":{\"tag\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[{\"tag\":{\"literal\":\"a\"}},{\"tag\":{\"literal\":\"b\"}}]},\"as\":\"right_rows\"},{\"from\":\"left_rows\",\"cross_join\":{\"with\":\"right_rows\",\"select\":{\"id\":\"left.id\",\"tag\":\"right.tag\"}},\"as\":\"out\"}]",
  )
  guard @lower.sequence_step(prepared_sequence(owner), 2)
    is Some(@lower.CrossJoinStep(kernel)) else {
    abort("cross join step")
  }
  let left = table_from_capture(
    capture_values(owner, 0, max_rows=2, run_limits().input_values).unwrap(),
  )
  let right = table_from_capture(
    capture_values(owner, 1, max_rows=2, run_limits().input_values).unwrap(),
  )
  let workspace = { limit: 8, live: 0, peak: 0, }
  let output = value_budget(run_limits().output_values).unwrap()
  assert_true(
    evaluate_cross_join_rows(
      kernel,
      left,
      right,
      4,
      { remaining: 10000, max_frames: 100, },
      output,
      workspace,
    )
    is Err(RowLimit),
  )
  assert_eq(workspace.live, 0)
  assert_true(workspace.peak > 0)
  assert_kernel_budget_sweep("cross_join", (control, swept_workspace) => {
    evaluate_cross_join_rows(
      kernel,
      left,
      right,
      4,
      control,
      value_budget(run_limits().output_values).unwrap(),
      swept_workspace,
    )
  })
}

///|
test "cross join accepts every pair of retained input layouts" {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1},{\"id\":2}]},\"as\":\"left_rows\"},{\"values\":{\"schema\":{\"tag\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[{\"tag\":{\"literal\":\"a\"}},{\"tag\":{\"literal\":\"b\"}}]},\"as\":\"right_rows\"},{\"from\":\"left_rows\",\"cross_join\":{\"with\":\"right_rows\",\"select\":{\"id\":\"left.id\",\"tag\":\"right.tag\"}},\"as\":\"out\"}]",
  )
  guard @lower.sequence_step(prepared_sequence(owner), 2)
    is Some(@lower.CrossJoinStep(kernel)) else {
    fail("cross join kernel was not prepared")
  }
  let left = capture_values(owner, 0, max_rows=2, run_limits().input_values).unwrap()
  let right = capture_values(owner, 1, max_rows=2, run_limits().input_values).unwrap()
  for left_layout in [RowLayout, ValueColumns, TypedColumns] {
    for right_layout in [RowLayout, ValueColumns, TypedColumns] {
      let result = evaluate_cross_join_rows(
        kernel,
        layout_relation(left, left_layout),
        layout_relation(right, right_layout),
        4,
        { remaining: 100000, max_frames: 100, },
        value_budget(run_limits().output_values).unwrap(),
        { limit: 10000, live: 0, peak: 0, },
      ).unwrap()
      assert_eq(result.rows.length(), 4)
      assert_true(result.rows[0][0] is Number(1))
      assert_true(result.rows[0][1] is Text("a"))
      assert_true(result.rows[3][0] is Number(2))
      assert_true(result.rows[3][1] is Text("b"))
    }
  }
}
