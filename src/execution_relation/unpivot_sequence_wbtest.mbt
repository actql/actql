///|
fn unpivot_sequence_owner() -> @lower.BoundPrepared {
  let row = @schema.from_fields(
    [
      (
        @schema.Unqualified("id"),
        @contract.primitive(NumberType, nullable=false),
      ),
      (
        @schema.Unqualified("jan"),
        @contract.primitive(NumberType, nullable=true),
      ),
      (
        @schema.Unqualified("feb"),
        @contract.primitive(NumberType, nullable=true),
      ),
    ],
    max_fields=3,
    max_name_bytes=8,
  ).unwrap()
  let carrier = @carrier.relation(@carrier.typed_rows(row))
  let key = @evidence.declare_primary_key(input_cursor("[\"id\"]"), carrier, {
    max_fields: 1,
    max_name_bytes: 2,
  }).unwrap()
  sort_input_owner(
    @pipeline.KeyedInput(key),
    "[{\"unpivot\":{\"columns\":[\"jan\",\"feb\",\"jan\"],\"keep\":[\"id\",\"jan\"],\"name_column\":\"metric\",\"value_column\":\"amount\"}}]",
  )
}

///|
fn unpivot_generated(owner : @lower.BoundPrepared) -> GeneratedSequence raise {
  prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["unpivot_0"],
    100000,
    10000,
  ).unwrap()
}

///|
test "unpivot expands repeated authored occurrences and retains NULL values" {
  let owner = unpivot_sequence_owner()
  let input = capture_input(
    owner,
    0,
    [
      input_cursor("{\"id\":1,\"jan\":10,\"feb\":null}"),
      input_cursor("{\"id\":2,\"jan\":null,\"feb\":20}"),
    ],
    max_rows=2,
    run_limits().input_values,
  ).unwrap()
  let completed = execute_generated_sequence(
    unpivot_generated(owner),
    [input],
    { rows: run_limits(), max_work: 100000, max_frames: 100, },
  ).unwrap()
  let table = test_row_output(completed_output(completed, Step(0)).unwrap())
  assert_eq(table.names, ["amount", "id", "jan", "metric"])
  assert_eq(table.rows.length(), 6)
  assert_true(table.rows[0][0] is Number(10))
  assert_true(table.rows[0][1] is Number(1))
  assert_true(table.rows[0][2] is Number(10))
  assert_true(table.rows[0][3] is Text("jan"))
  assert_true(table.rows[1][0] is Null)
  assert_true(table.rows[1][3] is Text("feb"))
  assert_true(table.rows[2][0] is Number(10))
  assert_true(table.rows[2][3] is Text("jan"))
  assert_true(table.rows[3][0] is Null)
  assert_true(table.rows[3][1] is Number(2))
  assert_true(table.rows[4][0] is Number(20))
  assert_true(table.rows[5][0] is Null)
}

///|
test "unpivot keeps an empty typed input empty" {
  let owner = unpivot_sequence_owner()
  let input = capture_input(owner, 0, [], max_rows=0, run_limits().input_values).unwrap()
  let completed = execute_generated_sequence(
    unpivot_generated(owner),
    [input],
    { rows: run_limits(), max_work: 100000, max_frames: 100, },
  ).unwrap()
  let table = test_row_output(completed_output(completed, Step(0)).unwrap())
  assert_eq(table.names, ["amount", "id", "jan", "metric"])
  assert_eq(table.rows.length(), 0)
}

///|
test "unpivot accepts exact shared work and rejects one-short execution" {
  let owner = unpivot_sequence_owner()
  let sequence = prepared_sequence(owner)
  let contracts = registered_relation_contracts()
  let generated = unpivot_generated(owner)
  let input = capture_input(
    owner,
    0,
    [input_cursor("{\"id\":1,\"jan\":10,\"feb\":null}")],
    max_rows=1,
    run_limits().input_values,
  ).unwrap()
  let control = { remaining: 100000, max_frames: 100, }
  assert_true(
    evaluate_sequence_components(
      contracts,
      sequence,
      [input],
      ["unpivot_0"],
      run_limits(),
      control,
      fragments=Some([]),
    )
    is Ok(_),
  )
  let used = 100000 - control.remaining
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
}
