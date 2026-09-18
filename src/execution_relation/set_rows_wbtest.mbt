///|
fn set_test_sequence(
  operation : String,
  duplicates : String,
  left? : String = "[{\"k\":1,\"payload\":[1]},{\"k\":1,\"payload\":[1]},{\"k\":2,\"payload\":[2]},{\"k\":null,\"payload\":[]}]",
  right? : String = "[{\"payload\":[1],\"k\":1},{\"payload\":[3],\"k\":3}]",
) -> GeneratedSequence raise {
  let schema = "{\"k\":{\"type\":\"number\",\"nullable\":true},\"payload\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}}"
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":" +
    schema +
    ",\"rows\":" +
    left +
    "},\"as\":\"l\"},{\"values\":{\"schema\":{\"payload\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}},\"k\":{\"type\":\"number\",\"nullable\":true}},\"rows\":" +
    right +
    "},\"as\":\"r\"},{\"from\":\"l\",\"" +
    operation +
    "\":{\"with\":\"r\",\"duplicates\":\"" +
    duplicates +
    "\"},\"as\":\"out\"}]",
  )
  let sequence = prepared_sequence(owner)
  guard @lower.sequence_step(sequence, 2) is Some(@lower.SetStep(_)) else {
    abort("set step")
  }
  prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [],
    [operation + "_2"],
    100000,
    10000,
  ).unwrap()
}

///|
fn set_keys(output : CompletedOutput) -> Array[Value] {
  let values = []
  for row in 0..<completed_row_count(output) {
    values.push(completed_cell(output, row, 0).unwrap())
  }
  values
}

///|
fn set_key_values_match(actual : Array[Value], expected : Array[Value]) -> Bool {
  if actual.length() != expected.length() {
    return false
  }
  for index in 0..<actual.length() {
    match (actual[index], expected[index]) {
      (Null, Null) => ()
      (Number(left), Number(right)) if left == right => ()
      _ => return false
    }
  }
  true
}

///|
test "row set variants preserve complete-value multiplicity and left order" {
  let limits = { rows: run_limits(), max_work: 100000, max_frames: 100, }
  for
    (operation, duplicates, expected) in [
      ("except", "all", [Number(1), Number(2), Null]),
      ("intersect", "all", [Number(1)]),
      ("except", "distinct", [Number(2), Null]),
      ("intersect", "distinct", [Number(1)]),
    ] {
    let output = completed_output(
      execute_generated_sequence(
        set_test_sequence(operation, duplicates),
        [],
        limits,
      ).unwrap(),
      Step(2),
    ).unwrap()
    assert_true(set_key_values_match(set_keys(output), expected))
  }
}

///|
test "row set lowering emits registered operation and checked duplicate mode" {
  for
    (operation, machine) in [
      ("except", "REL.except_rows"),
      ("intersect", "REL.intersect_rows"),
    ] {
    let generated = set_test_sequence(operation, "all")
    let sequence = generated_sequence_owner(generated)
    let prepared = @lower.bound_preparation(sequence)
    assert_eq(@lower.operation(@lower.node_at(prepared, 2).unwrap()), machine)
    let steps = @lower.prepare_sequence(sequence, {
      max_steps: 10,
      max_rows: 100,
      max_cells: 1000,
      max_bindings: 100,
      max_name_bytes: 1000,
      expressions: {
        max_nodes: 100,
        max_work: 1000,
        max_depth: 20,
        max_literal_nodes: 100,
        max_literal_text_bytes: 1000,
      },
    }).unwrap()
    let writer = @encode.writer(100000, 10000, 100)
    @lower.emit_sequence_steps(steps, writer)
    let wire = @encode.finish(writer)
    assert_true(
      wire.contains(
        "\"id\":\"" +
        operation +
        "_2\",\"in\":[\"values_0\",\"values_1\"],\"op\":\"" +
        machine +
        "\",\"params\":{\"duplicates\":\"all\"}",
      ),
    )
  }
}

///|
test "row set output ceiling fails atomically" {
  let generated = set_test_sequence("except", "all")
  assert_true(
    execute_generated_sequence(generated, [], {
      rows: { ..run_limits(), max_rows: 3, },
      max_work: 100000,
      max_frames: 100,
    })
    is Err(_),
  )
}

///|
test "row set variants preserve their empty-side laws" {
  let limits = { rows: run_limits(), max_work: 100000, max_frames: 100, }
  for
    (operation, duplicates, left, right, expected) in [
      (
        "except",
        "all",
        "[{\"k\":1,\"payload\":[1]},{\"k\":1,\"payload\":[1]}]",
        "[]",
        [Number(1), Number(1)],
      ),
      (
        "except",
        "distinct",
        "[{\"k\":1,\"payload\":[1]},{\"k\":1,\"payload\":[1]}]",
        "[]",
        [Number(1)],
      ),
      ("intersect", "all", "[{\"k\":1,\"payload\":[1]}]", "[]", []),
      ("intersect", "distinct", "[]", "[{\"payload\":[1],\"k\":1}]", []),
    ] {
    let completed = execute_generated_sequence(
      set_test_sequence(operation, duplicates, left~, right~),
      [],
      limits,
    ).unwrap()
    let output = completed_output(completed, Step(2)).unwrap()
    assert_true(set_key_values_match(set_keys(output), expected))
  }
}

///|
test "row set execution accepts every pair of retained input layouts" {
  for operation in ["except", "intersect"] {
    let generated = set_test_sequence(operation, "all")
    let owner = generated_sequence_owner(generated)
    guard @lower.sequence_step(prepared_sequence(owner), 2)
      is Some(@lower.SetStep(kernel)) else {
      fail("set kernel was not prepared")
    }
    let left = capture_values(owner, 0, max_rows=4, run_limits().input_values).unwrap()
    let right = capture_values(owner, 1, max_rows=2, run_limits().input_values).unwrap()
    for left_layout in [RowLayout, ValueColumns, TypedColumns] {
      for right_layout in [RowLayout, ValueColumns, TypedColumns] {
        let result = evaluate_set_rows(
          kernel,
          layout_relation(left, left_layout),
          layout_relation(right, right_layout),
          4,
          { remaining: 100000, max_frames: 100, },
          value_budget(run_limits().output_values).unwrap(),
          { limit: 10000, live: 0, peak: 0, },
        ).unwrap()
        assert_eq(
          result.rows.length(),
          if operation == "except" {
            3
          } else {
            1
          },
        )
      }
    }
  }
}
