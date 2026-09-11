///|
fn keyed_owner(fields : String) -> @lower.BoundPrepared {
  let seed = capture_values(
    capture_fixture(),
    0,
    max_rows=2,
    run_limits().input_values,
  ).unwrap()
  let key = @evidence.declare_primary_key(
    input_cursor(fields),
    @carrier.relation(@carrier.typed_rows(captured_schema(seed))),
    { max_fields: 2, max_name_bytes: 100, },
  ).unwrap()
  let p = @pipeline.check_with_evidence(
    input_cursor("[{\"select\":[\"s\",\"n\"]}]"),
    [("rows", @pipeline.KeyedInput(key))],
    None,
    Some(input_cursor("\"rows\"")),
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
test "input key validation rejects duplicates before row evaluation" {
  let owner = keyed_owner("[\"n\"]")
  let rows = capture_input(
    owner,
    0,
    [
      input_cursor("{\"n\":1,\"s\":\"a\"}"),
      input_cursor("{\"n\":1,\"s\":\"b\"}"),
    ],
    max_rows=2,
    run_limits().input_values,
  ).unwrap()
  assert_true(
    evaluate_sequence_components(
      registered_relation_contracts(),
      prepared_sequence(owner),
      [rows],
      ["select_0"],
      run_limits(),
      { remaining: 10000, max_frames: 100, },
    )
    is Err(InputKey(0, DuplicateKey(0, 1))),
  )
}

///|
test "compound key preserves duplicates of individual fields and supplied order" {
  let owner = keyed_owner("[\"n\",\"s\"]")
  let rows = capture_input(
    owner,
    0,
    [
      input_cursor("{\"n\":1,\"s\":\"a\"}"),
      input_cursor("{\"n\":1,\"s\":\"b\"}"),
      input_cursor("{\"n\":2,\"s\":\"a\"}"),
    ],
    max_rows=3,
    run_limits().input_values,
  ).unwrap()
  let result = evaluate_sequence_components(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [rows],
    ["select_0"],
    run_limits(),
    { remaining: 10000, max_frames: 100, },
  ).unwrap()
  let table = result.store.tables[1].unwrap().table
  assert_eq(table.rows.length(), 3)
  assert_true(table.rows[0][1] is Number(1.0))
  assert_true(table.rows[2][1] is Number(2.0))
}

///|
test "key validation has bounded workspace and cumulative control" {
  let owner = keyed_owner("[\"s\"]")
  let rows = capture_input(
    owner,
    0,
    [
      input_cursor("{\"n\":1,\"s\":\"é\"}"),
      input_cursor("{\"n\":2,\"s\":\"hello\"}"),
    ],
    max_rows=2,
    run_limits().input_values,
  ).unwrap()
  let work = { remaining: 10000, max_frames: 100, }
  let space = { limit: 5, live: 0, peak: 0, }
  assert_true(validate_captured_keys(rows, work, space) is Ok(_))
  assert_eq(space.live, 0)
  assert_eq(space.peak, 5)
  let used = 10000 - work.remaining
  assert_true(
    validate_captured_keys(rows, { remaining: used, max_frames: 100, }, {
      limit: 5,
      live: 0,
      peak: 0,
    })
    is Ok(_),
  )
  assert_true(
    validate_captured_keys(rows, { remaining: used - 1, max_frames: 100, }, {
      limit: 5,
      live: 0,
      peak: 0,
    })
    is Err(Limit),
  )
  assert_true(
    validate_captured_keys(rows, { remaining: 10000, max_frames: 100, }, {
      limit: 4,
      live: 0,
      peak: 0,
    })
    is Err(Limit),
  )
}

///|
test "empty keyed input succeeds and invalid key budgets do not" {
  let owner = keyed_owner("[\"n\"]")
  let rows = capture_input(owner, 0, [], max_rows=0, run_limits().input_values).unwrap()
  assert_true(
    validate_captured_keys(rows, { remaining: 100, max_frames: 100, }, {
      limit: 1,
      live: 0,
      peak: 0,
    })
    is Ok(_),
  )
  assert_true(
    validate_captured_keys(rows, { remaining: 100, max_frames: 100, }, {
      limit: -1,
      live: 0,
      peak: 0,
    })
    is Err(InvalidLimits),
  )
}
