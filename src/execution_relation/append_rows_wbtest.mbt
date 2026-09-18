///|
test "checked append aligns columns and preserves left then right order" {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"tag\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[{\"id\":1,\"tag\":{\"literal\":\"left\"}}]},\"as\":\"left_rows\"},{\"values\":{\"schema\":{\"tag\":{\"type\":\"string\",\"nullable\":false},\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"tag\":{\"literal\":\"right\"},\"id\":2}]},\"as\":\"right_rows\"},{\"from\":\"left_rows\",\"append\":{\"with\":\"right_rows\"},\"as\":\"out\"}]",
  )
  let sequence = prepared_sequence(owner)
  assert_true(@lower.sequence_step(sequence, 2) is Some(@lower.AppendStep(_)))
  let writer = @encode.writer(100000, 10000, 100)
  @lower.emit_sequence_steps(sequence, writer)
  assert_eq(
    @encode.finish(writer),
    "[{\"id\":\"values_0\",\"in\":[],\"op\":\"REL.values\",\"params\":{\"rows\":[{\"id\":1,\"tag\":\"left\"}],\"schema\":{\"id\":{\"nullable\":false,\"type\":\"number\"},\"tag\":{\"nullable\":false,\"type\":\"string\"}}}},{\"id\":\"values_1\",\"in\":[],\"op\":\"REL.values\",\"params\":{\"rows\":[{\"id\":2,\"tag\":\"right\"}],\"schema\":{\"id\":{\"nullable\":false,\"type\":\"number\"},\"tag\":{\"nullable\":false,\"type\":\"string\"}}}},{\"id\":\"append_2\",\"in\":[\"values_0\",\"values_1\"],\"op\":\"REL.unionAll\",\"params\":{}}]",
  )
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [],
    ["append_2"],
    100000,
    10000,
  ).unwrap()
  let result = execute_generated_sequence(generated, [], {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }).unwrap()
  let table = test_row_output(completed_output(result, Step(2)).unwrap())
  assert_eq(table.names, ["id", "tag"])
  assert_eq(table.rows.length(), 2)
  assert_true(table.rows[0][0] is Number(1))
  assert_true(table.rows[0][1] is Text("left"))
  assert_true(table.rows[1][0] is Number(2))
  assert_true(table.rows[1][1] is Text("right"))
}

///|
test "append enforces the cumulative output row ceiling" {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1}]},\"as\":\"left_rows\"},{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":2}]},\"as\":\"right_rows\"},{\"from\":\"left_rows\",\"append\":{\"with\":\"right_rows\"}}]",
  )
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["append_2"],
    100000,
    10000,
  ).unwrap()
  assert_true(
    execute_generated_sequence(generated, [], {
      rows: { ..run_limits(), max_rows: 1, },
      max_work: 100000,
      max_frames: 100,
    })
    is Err(_),
  )
}

///|
fn append_contract(body : String) -> @contract.Contract {
  @contract.read_checked(input_cursor(body), {
    max_nodes: 100,
    max_depth: 10,
    max_text_bytes: 1000,
  }).unwrap()
}

///|
fn append_input_owner(contract : @contract.Contract) -> @lower.BoundPrepared {
  let schema = @schema.from_fields(
    [(@schema.Unqualified("value"), contract)],
    max_fields=1,
    max_name_bytes=100,
  ).unwrap()
  let carrier = @carrier.relation(@carrier.typed_rows(schema))
  let checked = @pipeline.check_with_evidence(
    input_cursor("[{\"from\":\"l\",\"append\":{\"with\":\"r\"}}]"),
    [
      ("l", @pipeline.CarrierInput(carrier)),
      ("r", @pipeline.CarrierInput(carrier)),
    ],
    None,
    None,
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
fn append_value_equal(left : Value, right : Value) -> Bool {
  match (left, right) {
    (Null, Null) => true
    (Number(a), Number(b)) => a == b
    (Boolean(a), Boolean(b)) => a == b
    (Text(a), Text(b)) => a == b
    (Captured(a), Captured(b)) => physical_equal(a, b)
    _ => false
  }
}

///|
test "append lowers every normative relation value contract" {
  let contracts = [
    "{\"type\":\"string\",\"nullable\":true}", "{\"type\":\"number\",\"nullable\":true}",
    "{\"type\":\"decimal\",\"precision\":4,\"scale\":2,\"nullable\":true}", "{\"type\":\"boolean\",\"nullable\":true}",
    "{\"type\":\"timestamp\",\"nullable\":true}", "{\"type\":\"date\",\"nullable\":true}",
    "{\"type\":\"json\",\"nullable\":true}", "{\"type\":\"object\",\"nullable\":true,\"additional_properties\":false,\"fields\":{\"x\":{\"type\":\"string\",\"nullable\":false}}}",
    "{\"type\":\"array\",\"nullable\":true,\"items\":{\"type\":\"number\",\"nullable\":true},\"max_items\":2}",
    "{\"type\":\"vector\",\"nullable\":true,\"dimensions\":2,\"element_type\":\"f32\"}",
    "{\"type\":\"resource_ref\",\"nullable\":true,\"resource_kind\":\"file\"}", "{\"type\":\"artifact_ref\",\"nullable\":true,\"media_type\":\"application/json\"}",
  ]
  for body in contracts {
    let owner = append_input_owner(append_contract(body))
    let sequence = prepared_sequence(owner)
    assert_true(@lower.sequence_step(sequence, 0) is Some(@lower.AppendStep(_)))
  }
}

///|
test "append preserves every relation value domain and NULL" {
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
  for (contract_body, wire, kind) in cases {
    let contract = append_contract(contract_body)
    let owner = append_input_owner(contract)
    let sequence = prepared_sequence(owner)
    guard @lower.sequence_step(sequence, 0) is Some(@lower.AppendStep(kernel)) else {
      fail("append kernel was not prepared")
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
    let result = evaluate_append_rows(
      kernel,
      AdmittedTable({ owner, id: "input_0", names: ["value"], rows: [[value]], }),
      AdmittedTable({ owner, id: "input_1", names: ["value"], rows: [[null]], }),
      2,
      { remaining: 100000, max_frames: 100, },
      value_budget({
        max_nodes: 1000,
        max_text_bytes: 10000,
        max_depth: 10,
        max_work: 100000,
      }).unwrap(),
      { limit: 10000, live: 0, peak: 0, },
    ).unwrap()
    assert_eq(result.rows.length(), 2)
    assert_true(append_value_equal(result.rows[0][0], capture(value)))
    assert_true(append_value_equal(result.rows[1][0], capture(null)))
    live.val = false
  }
}

///|
fn append_scale_sample(
  left_count : Int,
  right_count : Int,
  width : Int,
) -> (Int, Int, Int) raise {
  let fields = Array::makei(width, index => {
    "\"f" + index.to_string() + "\":{\"type\":\"number\",\"nullable\":false}"
  })
  let row_fields = Array::makei(width, index => {
    "\"f" + index.to_string() + "\":" + index.to_string()
  })
  let row = "{" + row_fields.join(",") + "}"
  let schema = "{" + fields.join(",") + "}"
  let left = Array::make(left_count, row).join(",")
  let right = Array::make(right_count, row).join(",")
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":" +
    schema +
    ",\"rows\":[" +
    left +
    "]},\"as\":\"left_rows\"},{\"values\":{\"schema\":" +
    schema +
    ",\"rows\":[" +
    right +
    "]},\"as\":\"right_rows\"},{\"from\":\"left_rows\",\"append\":{\"with\":\"right_rows\"}}]",
  )
  let sequence = prepared_sequence(owner)
  guard @lower.sequence_step(sequence, 2) is Some(@lower.AppendStep(kernel)) else {
    fail("append kernel was not prepared")
  }
  let control_max = 100000000
  let control = { remaining: control_max, max_frames: 100, }
  let workspace : RowWorkspace = { limit: 100000000, live: 0, peak: 0, }
  let output = value_budget({
    max_nodes: 10000000,
    max_text_bytes: 10000000,
    max_depth: 10,
    max_work: 100000000,
  }).unwrap()
  let result = evaluate_append_rows(
    kernel,
    table_from_capture(
      capture_values(owner, 0, max_rows=left_count, {
        max_nodes: 10000000,
        max_text_bytes: 10000000,
        max_depth: 10,
        max_work: 100000000,
      }).unwrap(),
    ),
    table_from_capture(
      capture_values(owner, 1, max_rows=right_count, {
        max_nodes: 10000000,
        max_text_bytes: 10000000,
        max_depth: 10,
        max_work: 100000000,
      }).unwrap(),
    ),
    left_count + right_count,
    control,
    output,
    workspace,
  ).unwrap()
  assert_eq(result.rows.length(), left_count + right_count)
  (control_max - control.remaining, workspace.peak, output.work)
}

///|
test "append work and retained slots scale with rows and value width" {
  for (left, right, width) in [(4, 4, 4), (32, 32, 4), (4, 4, 32)] {
    let (work, peak, output_work) = append_scale_sample(left, right, width)
    let rows = left + right
    let mut name_bytes = 0
    for index in 0..<width {
      name_bytes += ("f" + index.to_string()).length()
    }
    // One alignment walk plus one left-to-right pass over each output cell.
    assert_eq(work, width + name_bytes + rows * (1 + width))
    // Two row-index arrays, three width arrays, and two value arrays per row.
    assert_eq(peak, 2 * rows + 3 * width + 2 * rows * width)
    // Every retained row, field name, and scalar value is charged exactly once.
    assert_eq(output_work, rows * (1 + name_bytes + width))
  }
}
