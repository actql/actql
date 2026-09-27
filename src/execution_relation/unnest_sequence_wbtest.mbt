///|
fn unnest_sequence_owner(body : String) -> @lower.BoundPrepared {
  let row = @schema.from_fields(
    [
      (
        @schema.Unqualified("id"),
        @contract.primitive(NumberType, nullable=false),
      ),
      (
        @schema.Unqualified("items"),
        @contract.array_contract(
          @contract.primitive(NumberType, nullable=true),
          nullable=true,
          max_items=Some(2L),
        ).unwrap(),
      ),
    ],
    max_fields=2,
    max_name_bytes=7,
  ).unwrap()
  let carrier = @carrier.relation(@carrier.typed_rows(row))
  let key = @evidence.declare_primary_key(input_cursor("[\"id\"]"), carrier, {
    max_fields: 1,
    max_name_bytes: 2,
  }).unwrap()
  sort_input_owner(@pipeline.KeyedInput(key), "[{\"unnest\":" + body + "}]")
}

///|
fn execute_unnest(
  owner : @lower.BoundPrepared,
  rows : Array[@decode.Cursor],
) -> Result[CompletedSequence, SequenceRunIssue] raise {
  let sequence = prepared_sequence(owner)
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [],
    [
      @lower.node_id(
        @lower.node_at(@lower.bound_preparation(owner), 0).unwrap(),
      ),
    ],
    100000,
    10000,
  ).unwrap()
  let input = capture_input(
    owner,
    0,
    rows,
    max_rows=rows.length(),
    run_limits().input_values,
  ).unwrap()
  execute_generated_sequence(generated, [input], {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  })
}

///|
test "unnest preserves parent and element order without synthesizing inner rows" {
  let owner = unnest_sequence_owner("{\"column\":\"items\",\"as\":\"item\"}")
  let result = execute_unnest(owner, [
    input_cursor("{\"id\":1,\"items\":[2,null]}"),
    input_cursor("{\"id\":2,\"items\":[]}"),
    input_cursor("{\"id\":3,\"items\":null}"),
  ]).unwrap()
  let table = test_row_output(completed_output(result, Step(0)).unwrap())
  assert_eq(table.names, ["id", "item", "items"])
  assert_eq(table.rows.length(), 2)
  assert_true(table.rows[0][0] is Number(1))
  assert_true(table.rows[0][1] is Number(2))
  assert_true(table.rows[1][0] is Number(1))
  assert_true(table.rows[1][1] is Null)
}

///|
test "outer unnest emits one nullable indexed row for empty and null arrays" {
  let owner = unnest_sequence_owner(
    "{\"column\":\"items\",\"as\":\"item\",\"with_index\":\"position\",\"outer\":true}",
  )
  let result = execute_unnest(owner, [
    input_cursor("{\"id\":1,\"items\":[2,null]}"),
    input_cursor("{\"id\":2,\"items\":[]}"),
    input_cursor("{\"id\":3,\"items\":null}"),
  ]).unwrap()
  let table = test_row_output(completed_output(result, Step(0)).unwrap())
  assert_eq(table.names, ["id", "item", "items", "position"])
  assert_eq(table.rows.length(), 4)
  assert_true(table.rows[0][1] is Number(2))
  assert_true(table.rows[0][3] is Number(0))
  assert_true(table.rows[1][1] is Null)
  assert_true(table.rows[1][3] is Number(1))
  assert_true(table.rows[2][0] is Number(2))
  assert_true(table.rows[2][1] is Null)
  assert_true(table.rows[2][3] is Null)
  assert_true(table.rows[3][0] is Number(3))
  assert_true(table.rows[3][1] is Null)
  assert_true(table.rows[3][3] is Null)
}

///|
test "unnest rejects an input array beyond its checked maximum before execution" {
  let owner = unnest_sequence_owner("{\"column\":\"items\",\"as\":\"item\"}")
  assert_true(
    capture_input(
      owner,
      0,
      [input_cursor("{\"id\":1,\"items\":[1,2,3]}")],
      max_rows=1,
      run_limits().input_values,
    )
    is Err(InputValue(0, _)),
  )
}

///|
test "unnest accepts exact shared work and rejects one-short execution" {
  let owner = unnest_sequence_owner(
    "{\"column\":\"items\",\"as\":\"item\",\"with_index\":true}",
  )
  let sequence = prepared_sequence(owner)
  let contracts = registered_relation_contracts()
  let generated = prepare_generated_sequence(
    contracts,
    sequence,
    [],
    ["unnest_0"],
    100000,
    10000,
  ).unwrap()
  let input = capture_input(
    owner,
    0,
    [input_cursor("{\"id\":1,\"items\":[2,null]}")],
    max_rows=1,
    run_limits().input_values,
  ).unwrap()
  let control = { remaining: 100000, max_frames: 100, }
  assert_true(
    evaluate_sequence_components(
      contracts,
      sequence,
      [input],
      ["unnest_0"],
      run_limits(),
      control,
      fragments=Some([]),
    )
    is Ok(_),
  )
  // Fixed expectation for this authored input and operation, not a budget
  // obtained from the implementation under test.
  let used = 116
  assert_eq(control.remaining, 100000 - used)
  let exact : SequenceExecutionLimits = {
    rows: run_limits(),
    max_work: used,
    max_frames: 100,
  }
  assert_true(execute_generated_sequence(generated, [input], exact) is Ok(_))
  assert_true(
    execute_generated_sequence(generated, [input], {
      ..exact,
      max_work: used - 1,
    })
    is Err(_),
  )
  assert_true(
    execute_generated_sequence(generated, [input], {
      ..exact,
      rows: { ..exact.rows, operation_entries: 0, },
    })
    is Err(_),
  )
}
