///|
fn lag_input_owner(
  offset : String,
  declarations? : @parameter.Declarations? = None,
  values? : @parameter.BoundValues? = None,
) -> @lower.BoundPrepared {
  let schema = @schema.from_fields(
    [
      (
        @schema.Unqualified("group"),
        @contract.primitive(StringType, nullable=true),
      ),
      (
        @schema.Unqualified("id"),
        @contract.primitive(NumberType, nullable=false),
      ),
      (
        @schema.Unqualified("amount"),
        @contract.primitive(NumberType, nullable=true),
      ),
    ],
    max_fields=3,
    max_name_bytes=13,
  ).unwrap()
  let carrier = @carrier.relation(@carrier.typed_rows(schema))
  let key = @evidence.declare_primary_key(input_cursor("[\"id\"]"), carrier, {
    max_fields: 1,
    max_name_bytes: 2,
  }).unwrap()
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"lag\":{\"partition_by\":[\"group\",\"group\"]," +
      "\"order_by\":[{\"amount\":\"desc\"}],\"field\":\"amount\"," +
      "\"output\":\"previous\",\"offset\":" +
      offset +
      "}}]",
    ),
    [("rows", @pipeline.KeyedInput(key))],
    declarations,
    Some(input_cursor("\"rows\"")),
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
    values,
    max_parameters=1,
    max_name_bytes=32,
  ).unwrap()
}

///|
fn lag_rows() -> Array[@decode.Cursor] {
  [
    input_cursor("{\"group\":\"a\",\"id\":3,\"amount\":30}"),
    input_cursor("{\"group\":null,\"id\":2,\"amount\":20}"),
    input_cursor("{\"group\":\"a\",\"id\":1,\"amount\":10}"),
    input_cursor("{\"group\":null,\"id\":4,\"amount\":null}"),
    input_cursor("{\"group\":\"a\",\"id\":5,\"amount\":30}"),
  ]
}

///|
fn execute_lag(
  owner : @lower.BoundPrepared,
  max_work? : Int = 100000,
) -> Result[CompletedSequence, SequenceRunIssue] raise {
  let sequence = prepared_sequence(owner)
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [],
    ["lag_0"],
    100000,
    10000,
  ).unwrap()
  let rows = lag_rows()
  let input = capture_input(
    owner,
    0,
    rows,
    max_rows=rows.length(),
    run_limits().input_values,
  ).unwrap()
  execute_generated_sequence(generated, [input], {
    rows: run_limits(),
    max_work,
    max_frames: 100,
  })
}

///|
test "lag uses complete partition order and preserves occurrence order" {
  let result = execute_lag(lag_input_owner("1")).unwrap()
  let table = test_row_output(completed_output(result, Step(0)).unwrap())
  assert_eq(table.names, ["amount", "group", "id", "previous"])
  assert_eq(table.rows.length(), 5)
  assert_true(table.rows[0][2] is Number(3) && table.rows[0][3] is Null)
  assert_true(table.rows[1][2] is Number(2) && table.rows[1][3] is Null)
  assert_true(table.rows[2][2] is Number(1) && table.rows[2][3] is Number(30))
  assert_true(table.rows[3][2] is Number(4) && table.rows[3][3] is Number(20))
  assert_true(table.rows[4][2] is Number(5) && table.rows[4][3] is Number(30))
}

///|
test "lag binds offset parameters and shares the exact execution budget" {
  let declarations = @parameter.read_declarations(
    Some(input_cursor("{\"offset\":{\"type\":\"number\",\"nullable\":false}}")),
    { max_parameters: 1, max_nodes: 10, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let values = match
    @parameter.bind(declarations, Some(input_cursor("{\"offset\":2}")), {
      max_nodes: 10,
      max_depth: 10,
      max_text_bytes: 1000,
    }).unwrap() {
    Ready(values) => values
    NeedsBindings(_) => abort("fixture is complete")
  }
  let owner = lag_input_owner(
    "{\"$param\":\"offset\"}",
    declarations=Some(declarations),
    values=Some(values),
  )
  let sequence = prepared_sequence(owner)
  let rows = lag_rows()
  let input = capture_input(
    owner,
    0,
    rows,
    max_rows=rows.length(),
    run_limits().input_values,
  ).unwrap()
  let control = { remaining: 100000, max_frames: 100, }
  let result = evaluate_sequence_components(
    registered_relation_contracts(),
    sequence,
    [input],
    ["lag_0"],
    run_limits(),
    control,
    fragments=Some([]),
  ).unwrap()
  let table = test_row_output(completed_output(result, Step(0)).unwrap())
  assert_true(table.rows[0][3] is Null)
  assert_true(table.rows[4][3] is Null)
  assert_true(table.rows[2][3] is Number(30))
  let used = 100000 - control.remaining
  assert_true(execute_lag(owner, max_work=used) is Ok(_))
  assert_true(execute_lag(owner, max_work=used - 1) is Err(_))
}

///|
test "empty lag reserves output schema before copying input names" {
  let owner = lag_input_owner("1")
  let input : Table = {
    owner,
    id: "source",
    names: ["amount", "group", "id"],
    rows: [],
  }
  // Checked lowering coalesces the repeated partition key: three input
  // names, one partition term, one order term, two complete sort terms,
  // and four output names coexist.
  for (limit, succeeds) in [(11, true), (10, false)] {
    let workspace = row_workspace(limit)
    let result = evaluate_lag_rows(
      row_kernel(owner, 0),
      input,
      "lagged",
      0,
      { remaining: 10000, max_frames: 100, },
      value_budget(run_limits().output_values).unwrap(),
      workspace,
    )
    assert_eq(result is Ok(_), succeeds)
    assert_eq(workspace.peak, if succeeds { 11 } else { 7 })
  }
}
