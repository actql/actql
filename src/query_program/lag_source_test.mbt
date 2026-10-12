///|
fn lag_source_control(
  body : String,
  parameters? : Bool = false,
) -> @program.Program {
  @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.lag_source\"," +
    (if parameters { "\"params\":{\"p\":{\"type\":\"number\"}}," } else { "" }) +
    "\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[" +
    "{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"amount\":{\"type\":\"number\",\"nullable\":true}},\"rows\":[{\"id\":1,\"amount\":10},{\"id\":2,\"amount\":30},{\"id\":3,\"amount\":null}]},\"as\":\"rows\"}," +
    "{\"from\":\"rows\",\"assert_rows\":{\"unique_by\":[\"id\"]},\"as\":\"keyed\"}," +
    "{\"from\":\"keyed\",\"lag\":" +
    body +
    ",\"as\":\"lagged\"}," +
    "{\"from\":\"lagged\",\"sort\":[{\"field\":\"id\",\"dir\":\"asc\",\"nulls\":\"first\"}]}," +
    "{\"select\":[\"id\",\"amount\",\"previous\"],\"as\":\"out\"}]," +
    "\"results\":{\"rows\":{\"from\":\"out\",\"fields\":[\"id\",\"amount\",\"previous\"]}}}]," +
    "\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
fn lag_source_text(call : String) -> String {
  "WITH rows AS (SELECT 1 AS id, 10 AS amount UNION ALL SELECT 2, 30 UNION ALL SELECT 3, CAST(NULL AS FLOAT64)), " +
  "keyed AS (FROM rows |> ASSERT UNIQUE BY (id)), " +
  "lagged AS (FROM keyed AS r |> " +
  call +
  ") " +
  "SELECT id, amount, previous FROM lagged ORDER BY id"
}

///|
test "P2 Lag source keeps exact common invalid count order and collision refusals" {
  let prefix = "WITH rows AS (SELECT 1 AS id, 10 AS amount), keyed AS (FROM rows |> ASSERT UNIQUE BY (id)) FROM keyed |> "
  let cases : Array[(String, @pipeline.IssueKind)] = [
    (
      "lag(partition_by: [], order_by: [], field: amount, output: previous)",
      Operation(InvalidOrder),
    ),
    (
      "lag(partition_by: [], order_by: [{amount: 'asc'}], field: amount, output: previous, offset: 0)",
      Operation(InvalidCount),
    ),
    (
      "lag(partition_by: [], order_by: [{amount: 'asc'}], field: amount, output: previous, offset: -1)",
      Operation(InvalidCount),
    ),
    (
      "lag(partition_by: [], order_by: [{amount: 'asc'}], field: amount, output: previous, offset: 1.5)",
      Operation(InvalidCount),
    ),
    (
      "lag(partition_by: [], order_by: [{amount: 'asc'}], field: amount, output: amount)",
      Operation(InputCollision("amount")),
    ),
  ]
  for (call, expected) in cases {
    assert_eq(event_window_issue(prefix + call), expected)
  }
}

///|
test "P2 Lag source does not restore dropped columns or old range aliases" {
  let prefix = "WITH rows AS (SELECT 1 AS id, 10 AS amount), kept AS (FROM rows AS old |> SELECT id |> AS current) FROM kept AS r |> "
  for field in ["amount", "old.id", "current.id"] {
    assert_true(
      with_carrier_program(
        prefix +
        "lag(partition_by: [], order_by: [{id: 'asc'}], field: " +
        field +
        ", output: previous)",
        { ..pair_context(), inputs: [], },
      )
      is Err(UnknownColumn),
    )
  }
  assert_true(
    with_carrier_program(
      lag_source_text(
        "lag(partition_by: [], order_by: [{id: 'asc'}], field: amount, output: previous, max_output_rows: 10)",
      ),
      { ..pair_context(), inputs: [], },
    )
    is Err(InvalidQuery),
  )
}

///|
test "P2 independent Lag Program retains nullable navigation and candidate-key order" {
  for offset in ["", ",\"offset\":2", ",\"offset\":{\"$param\":\"p\"}"] {
    event_window_common_checked(
      lag_source_control(
        "{\"partition_by\":[],\"order_by\":[{\"field\":\"amount\",\"dir\":\"desc\",\"nulls\":\"last\"}],\"field\":\"amount\",\"output\":\"previous\"" +
        offset +
        "}",
        parameters=offset.contains("$param"),
      ),
    )
  }
}

///|
test "P2 Lag text preserves scoped fields output order and optional offset" {
  for (suffix, expected) in [("", ""), (", offset: 2", ",\"offset\":2")] {
    let actual = with_carrier_program(
      lag_source_text(
        "lag(partition_by: [], order_by: [{field: r.AMOUNT, dir: 'desc', nulls: 'last'}], field: r.amount, output: previous" +
        suffix +
        ")",
      ),
      { ..pair_context(), inputs: [], },
    )
    let actual = match actual {
      Ok(p) => p
      Err(BindingPreparation(LocalProgram(Pipeline(stage, issue)))) =>
        fail("Lag pipeline stage \{stage}: " + @debug.to_string(issue.kind))
      Err(BindingPreparation(LocalProgram(Order(stage, PipelineOrder(issue))))) =>
        fail("Lag order stage \{stage}: " + @debug.to_string(issue.kind))
      Err(UnknownColumn) => fail("Lag column resolution")
      Err(UnsupportedGraph) => fail("Lag Carrier routing")
      Err(UnsupportedProjection) => fail("Lag projection routing")
      Err(InvalidQuery) => fail("Lag signature lowering")
      Err(_) => fail("Lag unexpected preparation boundary")
    }
    let control = lag_source_control(
      "{\"partition_by\":[],\"order_by\":[{\"field\":\"amount\",\"dir\":\"desc\",\"nulls\":\"last\"}],\"field\":\"amount\",\"output\":\"previous\"" +
      expected +
      "}",
    )
    assert_eq(
      with_carrier_argument(actual, "lag"),
      with_carrier_argument(control, "lag"),
    )
    assert_eq(
      with_carrier_argument(actual, "assert_rows"),
      with_carrier_argument(control, "assert_rows"),
    )
    event_window_common_checked(actual)
  }
}

///|
test "P2 Lag text preserves shorthand order duplicates and whole offset Parameter" {
  let actual = with_carrier_program(
    lag_source_text(
      "lag(partition_by: [r.ID, id], order_by: [{r.amount: 'desc'}], field: amount, output: previous, offset: @p)",
    ),
    {
      ..pair_context(),
      inputs: [],
      parameter_declarations: Some(number_parameter_declarations()),
    },
  )
  let actual = match actual {
    Ok(p) => p
    Err(BindingPreparation(LocalProgram(Pipeline(stage, issue)))) =>
      fail("Lag pipeline stage \{stage}: " + @debug.to_string(issue.kind))
    Err(BindingPreparation(LocalProgram(Order(stage, PipelineOrder(issue))))) =>
      fail("Lag order stage \{stage}: " + @debug.to_string(issue.kind))
    Err(UnknownColumn) => fail("Lag column resolution")
    Err(UnsupportedGraph) => fail("Lag Carrier routing")
    Err(UnsupportedProjection) => fail("Lag projection routing")
    Err(InvalidQuery) => fail("Lag signature lowering")
    Err(_) => fail("Lag unexpected preparation boundary")
  }
  let control = lag_source_control(
    "{\"partition_by\":[\"id\",\"id\"],\"order_by\":[{\"amount\":\"desc\"}],\"field\":\"amount\",\"output\":\"previous\",\"offset\":{\"$param\":\"p\"}}",
    parameters=true,
  )
  assert_eq(
    with_carrier_argument(actual, "lag"),
    with_carrier_argument(control, "lag"),
  )
  event_window_common_checked(actual)
}
