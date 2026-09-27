///|
fn join_test_sequence(
  left : String,
  right : String,
  options? : String = "",
  tail? : String = "",
  kind? : String = "inner",
  projection? : String = "{\"k\":\"left.id\",\"l\":\"left.v\",\"r\":\"right.v\"}",
) -> GeneratedSequence raise {
  let schema = "{\"id\":{\"type\":\"number\",\"nullable\":true},\"v\":{\"type\":\"number\",\"nullable\":false}}"
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":" +
    schema +
    ",\"rows\":" +
    left +
    "},\"as\":\"l\"}," +
    "{\"values\":{\"schema\":" +
    schema +
    ",\"rows\":" +
    right +
    "},\"as\":\"r\"}," +
    "{\"join\":{\"with\":\"r\",\"kind\":\"" +
    kind +
    "\",\"on\":[{\"left\":\"id\",\"right\":\"id\"}],\"select\":" +
    projection +
    options +
    "},\"from\":\"l\"}" +
    tail +
    "]",
  )
  let sequence = prepared_sequence(owner)
  prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [],
    [if tail == "" { "join_2" } else { "group_3" }],
    100000,
    10000,
  ).unwrap()
}

///|
test "equality join passes the common kernel budget sweep" {
  let generated = join_test_sequence(
    "[{\"id\":1,\"v\":10}]", "[{\"id\":1,\"v\":20}]",
  )
  guard @lower.sequence_step(generated.sequence, 2)
    is Some(@lower.JoinStep(kernel)) else {
    fail("join kernel")
  }
  let owner = @lower.join_kernel_owner(kernel)
  let left = table_from_capture(
    capture_values(owner, 0, max_rows=1, run_limits().input_values).unwrap(),
  )
  let right = table_from_capture(
    capture_values(owner, 1, max_rows=1, run_limits().input_values).unwrap(),
  )
  assert_kernel_budget_sweep("join", (control, workspace) => {
    evaluate_join_rows(
      kernel,
      left,
      right,
      1,
      control,
      value_budget(run_limits().output_values).unwrap(),
      workspace,
    )
  })
}

///|
test "empty equality join has an independently bounded resource path" {
  let generated = join_test_sequence("[]", "[]")
  guard @lower.sequence_step(generated.sequence, 2)
    is Some(@lower.JoinStep(kernel)) else {
    fail("join kernel")
  }
  let owner = @lower.join_kernel_owner(kernel)
  let left = table_from_capture(
    capture_values(owner, 0, max_rows=0, run_limits().input_values).unwrap(),
  )
  let right = table_from_capture(
    capture_values(owner, 1, max_rows=0, run_limits().input_values).unwrap(),
  )
  let run = (work_limit, workspace_limit) => {
    let control = { remaining: work_limit, max_frames: 100, }
    let workspace = row_workspace(workspace_limit)
    let result = evaluate_join_rows(
      kernel,
      left,
      right,
      0,
      control,
      value_budget(run_limits().output_values).unwrap(),
      workspace,
    )
    (result, workspace.peak, work_limit - control.remaining)
  }
  // Both input schemas, the equality key, three projected fields, and the
  // empty right index are still admitted when no pair can be emitted.
  let expected_work = 38
  let expected_peak = 17
  let (result, peak, used) = run(expected_work, expected_peak)
  assert_true(result is Ok(_))
  assert_eq((peak, used), (expected_peak, expected_work))
  assert_true(run(expected_work - 1, expected_peak).0 is Err(RowLimit))
  assert_true(run(expected_work, expected_peak - 1).0 is Err(RowLimit))
}

///|
fn join_numeric_rows_equal(
  actual : Array[Array[Value]],
  expected : Array[Array[Value]],
) -> Bool {
  if actual.length() != expected.length() {
    return false
  }
  for row in 0..<actual.length() {
    if actual[row].length() != expected[row].length() {
      return false
    }
    for column in 0..<actual[row].length() {
      match (actual[row][column], expected[row][column]) {
        (Null, Null) => ()
        (Number(left), Number(right)) if left == right => ()
        _ => return false
      }
    }
  }
  true
}

///|
fn join_value_owner(contract : @contract.Contract) -> @lower.BoundPrepared {
  let schema = @schema.from_fields(
    [
      (
        @schema.Unqualified("id"),
        @contract.primitive(NumberType, nullable=false),
      ),
      (@schema.Unqualified("value"), contract),
    ],
    max_fields=2,
    max_name_bytes=100,
  ).unwrap()
  let carrier = @carrier.relation(@carrier.typed_rows(schema))
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"from\":\"l\",\"join\":{\"with\":\"r\",\"kind\":\"inner\",\"on\":\"id\",\"select\":{" +
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
test "join projection preserves every relation value domain and NULL" {
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
    let owner = join_value_owner(contract)
    guard @lower.sequence_step(prepared_sequence(owner), 0)
      is Some(@lower.JoinStep(kernel)) else {
      fail("join kernel")
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
    let result = evaluate_join_rows(
      kernel,
      RowTable({
        owner,
        id: @lower.join_kernel_input(kernel, true),
        names: ["id", "value"],
        rows: [[Number(1), capture(value)]],
      }),
      RowTable({
        owner,
        id: @lower.join_kernel_input(kernel, false),
        names: ["id", "value"],
        rows: [[Number(1), capture(null)]],
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
test "equality join kinds preserve unmatched and single-left row order" {
  let left = "[{\"id\":1,\"v\":10},{\"id\":2,\"v\":11},{\"id\":null,\"v\":12}]"
  let right = "[{\"id\":1,\"v\":20},{\"id\":1,\"v\":21},{\"id\":3,\"v\":22},{\"id\":null,\"v\":23}]"
  let limits = { rows: run_limits(), max_work: 100000, max_frames: 100, }
  for
    (kind, expected) in [
      (
        "left",
        [
          [Number(1), Number(10), Number(20)],
          [Number(1), Number(10), Number(21)],
          [Number(2), Number(11), Null],
          [Null, Number(12), Null],
        ],
      ),
      (
        "full",
        [
          [Number(1), Number(10), Number(20)],
          [Number(1), Number(10), Number(21)],
          [Number(2), Number(11), Null],
          [Null, Number(12), Null],
          [Null, Null, Number(22)],
          [Null, Null, Number(23)],
        ],
      ),
    ] {
    let generated = join_test_sequence(left, right, kind~)
    let table = test_row_output(
      completed_output(
        execute_generated_sequence(generated, [], limits).unwrap(),
        Step(2),
      ).unwrap(),
    )
    assert_true(join_numeric_rows_equal(table.rows, expected))
  }
  for
    (kind, expected) in [
      ("semi", [[Number(1), Number(10)]]),
      ("anti", [[Number(2), Number(11)], [Null, Number(12)]]),
    ] {
    let generated = join_test_sequence(
      left,
      right,
      kind~,
      projection="{\"k\":\"left.id\",\"l\":\"left.v\"}",
    )
    let table = test_row_output(
      completed_output(
        execute_generated_sequence(generated, [], limits).unwrap(),
        Step(2),
      ).unwrap(),
    )
    assert_true(join_numeric_rows_equal(table.rows, expected))
  }
}

///|
test "semi join does not charge right multiplicity as output rows" {
  let left = "[{\"id\":1,\"v\":10}]"
  let right = "[{\"id\":1,\"v\":20},{\"id\":1,\"v\":21},{\"id\":1,\"v\":22}]"
  let generated = join_test_sequence(
    left,
    right,
    kind="semi",
    projection="{\"k\":\"left.id\",\"l\":\"left.v\"}",
    options=",\"max_output_rows\":1",
  )
  let output = completed_output(
    execute_generated_sequence(generated, [], {
      rows: run_limits(),
      max_work: 100000,
      max_frames: 100,
    }).unwrap(),
    Step(2),
  ).unwrap()
  assert_eq(completed_row_count(output), 1)
  assert_true(completed_cell(output, 0, 0) is Some(Number(1)))
  assert_true(completed_cell(output, 0, 1) is Some(Number(10)))
}

///|
test "outer unmatched rows obey the checked output ceiling" {
  let generated = join_test_sequence(
    "[{\"id\":1,\"v\":10},{\"id\":2,\"v\":11}]",
    "[]",
    kind="left",
    options=",\"max_output_rows\":1",
  )
  assert_true(
    execute_generated_sequence(generated, [], {
      rows: run_limits(),
      max_work: 100000,
      max_frames: 100,
    })
    is Err(Rows(2, RowLimit)),
  )
}

///|
test "owned generated inner join executes both inputs and keeps duplicate pair order" {
  let generated = join_test_sequence(
    "[{\"id\":1,\"v\":10},{\"id\":1,\"v\":11},{\"id\":null,\"v\":12}]", "[{\"id\":1,\"v\":20},{\"id\":1,\"v\":21},{\"id\":null,\"v\":22}]",
  )
  let result = execute_generated_sequence(generated, [], {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }).unwrap()
  let table = test_row_output(completed_output(result, Step(2)).unwrap())
  assert_eq(table.names, ["k", "l", "r"])
  assert_eq(table.rows.length(), 4)
  for
    (index, l, r) in [
      (0, 10.0, 20.0),
      (1, 10.0, 21.0),
      (2, 11.0, 20.0),
      (3, 11.0, 21.0),
    ] {
    assert_true(table.rows[index][0] is Number(1))
    assert_true(table.rows[index][1] is Number(v) && v == l)
    assert_true(table.rows[index][2] is Number(v) && v == r)
  }
  assert_true(completed_output(result, Step(0)) is None)
  assert_true(completed_output(result, Step(1)) is None)
}

///|
test "join cardinality and null obligations run even when no pair can be emitted" {
  let limits = { rows: run_limits(), max_work: 100000, max_frames: 100, }
  let duplicate = join_test_sequence(
    "[]",
    "[{\"id\":1,\"v\":1},{\"id\":1,\"v\":2}]",
    options=",\"cardinality\":\"many_to_one\"",
  )
  assert_true(
    execute_generated_sequence(duplicate, [], limits)
    is Err(Rows(2, JoinDuplicateKey(false, 1, 0))),
  )
  let nulls = "[{\"id\":null,\"v\":1},{\"id\":null,\"v\":2}]"
  let allowed = join_test_sequence(
    "[]",
    nulls,
    options=",\"cardinality\":\"many_to_one\"",
  )
  let result = execute_generated_sequence(allowed, [], limits).unwrap()
  assert_eq(completed_row_count(completed_output(result, Step(2)).unwrap()), 0)
  let rejected = join_test_sequence(
    "[]",
    nulls,
    options=",\"null_key\":\"fail\"",
  )
  assert_true(
    execute_generated_sequence(rejected, [], limits)
    is Err(Rows(2, JoinNullKey(false, 0, 0))),
  )
}

///|
test "join intermediate output guard cannot be hidden by a one row count result" {
  let rows = "[{\"id\":1,\"v\":1},{\"id\":1,\"v\":2}]"
  let tail = ",{\"group\":{\"by\":[],\"aggregates\":{\"n\":{\"fn\":\"count\"}}}}"
  let limits = { rows: run_limits(), max_work: 100000, max_frames: 100, }
  let rejected = join_test_sequence(
    rows,
    rows,
    options=",\"max_output_rows\":3",
    tail~,
  )
  assert_true(
    execute_generated_sequence(rejected, [], limits) is Err(Rows(2, RowLimit)),
  )
  let accepted = join_test_sequence(
    rows,
    rows,
    options=",\"max_output_rows\":4",
    tail~,
  )
  let output = completed_output(
    execute_generated_sequence(accepted, [], limits).unwrap(),
    Step(3),
  ).unwrap()
  assert_eq(completed_row_count(output), 1)
  assert_true(completed_cell(output, 0, 0) is Some(Number(4)))
}

///|
test "compound nullable join keys match only complete equal tuples" {
  let schema = "{\"a\":{\"type\":\"number\",\"nullable\":true},\"b\":{\"type\":\"string\",\"nullable\":true},\"v\":{\"type\":\"number\",\"nullable\":false}}"
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":" +
    schema +
    ",\"rows\":[{\"a\":1,\"b\":\"x\",\"v\":10},{\"a\":1,\"b\":null,\"v\":11},{\"a\":null,\"b\":\"x\",\"v\":12},{\"a\":2,\"b\":\"y\",\"v\":13}]},\"as\":\"l\"},{\"values\":{\"schema\":" +
    schema +
    ",\"rows\":[{\"a\":1,\"b\":\"x\",\"v\":20},{\"a\":1,\"b\":null,\"v\":21},{\"a\":null,\"b\":\"x\",\"v\":22},{\"a\":3,\"b\":\"z\",\"v\":23}]},\"as\":\"r\"},{\"from\":\"l\",\"join\":{\"with\":\"r\",\"kind\":\"left\",\"on\":[{\"left\":\"a\",\"right\":\"a\"},{\"left\":\"b\",\"right\":\"b\"}],\"select\":{\"a\":\"left.a\",\"b\":\"left.b\",\"l\":\"left.v\",\"r\":\"right.v\"}}}]",
  )
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["join_2"],
    100000,
    10000,
  ).unwrap()
  let completed = execute_generated_sequence(generated, [], {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }).unwrap()
  let table = test_row_output(completed_output(completed, Step(2)).unwrap())
  assert_eq(table.names, ["a", "b", "l", "r"])
  assert_eq(table.rows.length(), 4)
  assert_true(table.rows[0][0] is Number(1))
  assert_true(table.rows[0][1] is Text("x"))
  assert_true(table.rows[0][2] is Number(10))
  assert_true(table.rows[0][3] is Number(20))
  assert_true(table.rows[1][1] is Null)
  assert_true(table.rows[1][3] is Null)
  assert_true(table.rows[2][0] is Null)
  assert_true(table.rows[2][3] is Null)
  assert_true(table.rows[3][0] is Number(2))
  assert_true(table.rows[3][3] is Null)
}

///|
test "self join retains both checked operand occurrences" {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"v\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1,\"v\":10},{\"id\":1,\"v\":11},{\"id\":2,\"v\":20}]},\"as\":\"rows\"},{\"from\":\"rows\",\"join\":{\"with\":\"rows\",\"kind\":\"inner\",\"on\":[{\"left\":\"id\",\"right\":\"id\"}],\"select\":{\"id\":\"left.id\",\"l\":\"left.v\",\"r\":\"right.v\"}}}]",
  )
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["join_1"],
    100000,
    10000,
  ).unwrap()
  let completed = execute_generated_sequence(generated, [], {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }).unwrap()
  let table = test_row_output(completed_output(completed, Step(1)).unwrap())
  assert_eq(table.names, ["id", "l", "r"])
  assert_true(
    join_numeric_rows_equal(table.rows, [
      [Number(1), Number(10), Number(10)],
      [Number(1), Number(10), Number(11)],
      [Number(1), Number(11), Number(10)],
      [Number(1), Number(11), Number(11)],
      [Number(2), Number(20), Number(20)],
    ]),
  )
}
