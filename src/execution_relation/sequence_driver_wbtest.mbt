///|
fn run_limits() -> SequenceRunLimits {
  {
    max_rows: 100,
    metadata_entries: 10000,
    retained_entries: 10000,
    operation_entries: 10000,
    input_values: {
      max_nodes: 10000,
      max_text_bytes: 10000,
      max_depth: 100,
      max_work: 100000,
    },
    output_values: {
      max_nodes: 10000,
      max_text_bytes: 10000,
      max_depth: 100,
      max_work: 100000,
    },
  }
}

///|
fn prepared_sequence(owner : @lower.BoundPrepared) -> @lower.PreparedSequence {
  @lower.prepare_sequence(owner, {
    max_steps: 100,
    max_rows: 100,
    max_cells: 10000,
    max_bindings: 100,
    max_name_bytes: 10000,
    expressions: {
      max_nodes: 10000,
      max_work: 100000,
      max_depth: 100,
      max_literal_nodes: 10000,
      max_literal_text_bytes: 10000,
    },
  }).unwrap()
}

///|
test "ordered preparation cannot execute without logical row resource accounting" {
  let result = evaluate_sequence_components(
    registered_relation_contracts(),
    prepared_sequence(row_owner(",{\"derive\":[{\"a\":\"b\"}]}")),
    [],
    ["derive_1"],
    run_limits(),
    { remaining: 10000, max_frames: 100, },
  )
  assert_true(result is Err(Rows(1, MissingOrderedResourceContext)))
}

///|
test "sequence driver executes all four operators and follows branch retention automatically" {
  let owner = row_owner(
    ",{\"derive\":{\"c\":\"a + 10\"},\"as\":\"augmented\"},{\"filter\":\"c > 10\"},{\"from\":\"augmented\",\"select\":[\"c\",\"b\"]}",
  )
  let result = evaluate_sequence_components(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["select_3"],
    run_limits(),
    { remaining: 10000, max_frames: 100, },
  ).unwrap()
  assert_eq(result.store.next, 4)
  assert_true(result.store.tables[0] is None)
  assert_true(result.store.tables[1] is None)
  assert_true(result.store.tables[2] is None)
  let table = result.store.tables[3].unwrap().table
  assert_eq(table.names, ["c", "b"])
  assert_eq(table.rows.length(), 2)
  assert_true(table.rows[0][0] is Number(11.0))
  assert_true(table.rows[1][0] is Number(10.0))
  assert_true(table.rows[1][1] is Number(1.0))
}

///|
test "sequence driver does not prune an unused failing derive and returns no partial store" {
  let owner = row_owner(
    ",{\"derive\":{\"unused\":\"1 / b\"}},{\"from\":\"seed\",\"select\":[\"a\"]}",
  )
  let result = evaluate_sequence_components(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["select_2"],
    run_limits(),
    { remaining: 10000, max_frames: 100, },
  )
  assert_true(result is Err(Rows(1, Evaluation(0, 0, { kind: Scalar(_), .. }))))
}

///|
test "sequence driver supplied input uses the same path and rejects foreign captures" {
  let owner = input_owner()
  let capture = capture_input(
    owner,
    0,
    [input_cursor("{\"s\":\"ok\",\"n\":7}")],
    max_rows=1,
    run_limits().input_values,
  ).unwrap()
  let sequence = prepared_sequence(owner)
  let result = evaluate_sequence_components(
    registered_relation_contracts(),
    sequence,
    [capture],
    ["select_0"],
    run_limits(),
    { remaining: 10000, max_frames: 100, },
  ).unwrap()
  assert_eq(result.store.tables[1].unwrap().table.names, ["s", "n"])
  assert_true(result.store.tables[0] is None)
  assert_true(
    evaluate_sequence_components(
      registered_relation_contracts(),
      prepared_sequence(input_owner()),
      [capture],
      ["select_0"],
      run_limits(),
      { remaining: 10000, max_frames: 100, },
    )
    is Err(InputOwnership),
  )
  assert_true(
    evaluate_sequence_components(
      registered_relation_contracts(),
      sequence,
      [],
      ["select_0"],
      run_limits(),
      { remaining: 10000, max_frames: 100, },
    )
    is Err(InputSet),
  )
}

///|
test "sequence driver carries bound parameters and cumulative output limits through every stage" {
  let (prepared, declarations) = parameter_preparation()
  for (n, expected) in [(3, 6.0), (7, 14.0)] {
    let owner = bind_number(prepared, declarations, n)
    let exact = {
      ..run_limits(),
      input_values: {
        max_nodes: 2,
        max_text_bytes: 2,
        max_depth: 2,
        max_work: 4,
      },
      output_values: {
        max_nodes: 9,
        max_text_bytes: 9,
        max_depth: 2,
        max_work: 18,
      },
    }
    let result = evaluate_sequence_components(
      registered_relation_contracts(),
      prepared_sequence(owner),
      [],
      ["select_3"],
      exact,
      { remaining: 10000, max_frames: 100, },
    ).unwrap()
    let table = result.store.tables[3].unwrap().table
    assert_eq(table.names, ["v", "id"])
    assert_eq(table.rows.length(), 1)
    assert_true(table.rows[0][0] is Number(v) && v == expected)
    let short = {
      ..exact,
      output_values: { ..exact.output_values, max_nodes: 8, },
    }
    assert_true(
      evaluate_sequence_components(
        registered_relation_contracts(),
        prepared_sequence(owner),
        [],
        ["select_3"],
        short,
        { remaining: 10000, max_frames: 100, },
      )
      is Err(Rows(3, RowLimit)),
    )
  }
}

///|
test "sequence driver input ceiling includes all values nodes even when earlier output is discarded" {
  let owner = row_owner(
    ",{\"values\":{\"schema\":{\"x\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"x\":3}]},\"as\":\"other\"}",
  )
  let sequence = prepared_sequence(owner)
  let result = evaluate_sequence_components(
    registered_relation_contracts(),
    sequence,
    [],
    ["values_1"],
    { ..run_limits(), max_rows: 3, },
    { remaining: 10000, max_frames: 100, },
  ).unwrap()
  assert_true(result.store.tables[0] is None)
  assert_true(result.store.tables[1].unwrap().table.rows[0][0] is Number(3.0))
  assert_true(
    evaluate_sequence_components(
      registered_relation_contracts(),
      sequence,
      [],
      ["values_1"],
      { ..run_limits(), max_rows: 2, },
      { remaining: 10000, max_frames: 100, },
    )
    is Err(Capture(1, CaptureLimit)),
  )
}
