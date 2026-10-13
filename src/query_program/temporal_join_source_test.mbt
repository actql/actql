///|
fn temporal_join_source(call : String) -> String {
  "WITH l AS (SELECT 1 AS id, 10 AS `at`), r AS (SELECT 2 AS id, 5 AS begin, 15 AS finish), matched AS (FROM l AS left_rows |> " +
  call +
  ") SELECT id, value FROM matched ORDER BY id"
}

///|
fn temporal_join_control(operation : String, body : String) -> @program.Program {
  @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.temporal_join_source\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"at\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1,\"at\":10}]},\"as\":\"l\"},{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"begin\":{\"type\":\"number\",\"nullable\":false},\"finish\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":2,\"begin\":5,\"finish\":15}]},\"as\":\"r\"},{\"from\":\"l\",\"" +
    operation +
    "\":" +
    body +
    ",\"as\":\"matched\"},{\"from\":\"matched\",\"sort\":[{\"field\":\"id\",\"dir\":\"asc\",\"nulls\":\"first\"}]},{\"select\":[\"id\",\"value\"],\"as\":\"out\"}],\"results\":{\"rows\":{\"from\":\"out\",\"fields\":[\"id\",\"value\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "adopted temporal calls reach existing two-input Owners without argument substitutions" {
  let cases = [
    (
      "asof_join", "asof_join(with: r, kind: 'left', by: [], left_id: left_rows.id, left_time: left_rows.at, right_time: r.begin, direction: 'backward', tolerance: 10, select: {id: left.id, value: right.id})",
      "{\"with\":\"r\",\"kind\":\"left\",\"by\":[],\"left_id\":\"id\",\"left_time\":\"at\",\"right_time\":\"begin\",\"direction\":\"backward\",\"tolerance\":10,\"select\":{\"id\":\"left.id\",\"value\":\"right.id\"}}",
    ),
    (
      "interval_join", "interval_join(with: r, kind: 'left', mode: 'point_in_interval', on: [], left: {time: left_rows.at}, right: {start: r.begin, end: r.finish}, select: {id: left.id, value: right.id}, max_output_rows: 2)",
      "{\"with\":\"r\",\"kind\":\"left\",\"mode\":\"point_in_interval\",\"on\":[],\"left\":{\"time\":\"at\"},\"right\":{\"start\":\"begin\",\"end\":\"finish\"},\"select\":{\"id\":\"left.id\",\"value\":\"right.id\"},\"max_output_rows\":2}",
    ),
  ]
  for (operation, call, body) in cases {
    let control = temporal_join_control(operation, body)
    event_window_common_checked(control)
    let actual = @frontend.lower(
      temporal_join_source(call),
      Sql,
      Some({ ..pair_context(), inputs: [], }),
    ).unwrap().program.unwrap()
    event_window_common_checked(actual)
    let actual_body = with_carrier_argument(actual, operation)
    let physical = actual_body.split("\"with\":\"").collect()[1]
    .split("\"")
    .collect()[0].to_owned()
    assert_eq(
      actual_body.replace(old=physical, new="r"),
      with_carrier_argument(control, operation),
    )
  }
}

///|
fn temporal_join_checked(text : String) -> @program.Program raise {
  let actual = @frontend.lower(
    text,
    Sql,
    Some({ ..pair_context(), inputs: [], }),
  ).unwrap().program.unwrap()
  match
    @check.check_parsed(actual, graph_event_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(issue) => graph_rows_rejected(issue)
    NeedsInputs(_) => fail("closed temporal input has no acquisition")
  }
  actual
}

///|
test "temporal selectors retain repeated pairs, right ties and explicit bounds" {
  let actual = temporal_join_checked(
    temporal_join_source(
      "asof_join(with: r, kind: 'inner', by: [{left: left_rows.id, right: r.id}, {LEFT: left.id, RIGHT: right.id}], left_id: id, left_time: at, right_time: begin, direction: 'nearest', tolerance: 10, right_tie_break: [r.id, right.id], select: {id: left.id, value: RIGHT.id})",
    ),
  )
  let body = with_carrier_argument(actual, "asof_join")
  assert_true(
    body.contains(
      "\"by\":[{\"left\":\"id\",\"right\":\"id\"},{\"left\":\"id\",\"right\":\"id\"}]",
    ),
  )
  assert_true(body.contains("\"right_tie_break\":[\"id\",\"id\"]"))
  assert_true(body.contains("\"tolerance\":10"))
  let interval = temporal_join_checked(
    temporal_join_source(
      "interval_join(with: r, kind: 'left', mode: 'point_in_interval', on: [{left: id, right: r.id}, {left: id, right: right.id}], left: {TIME: at}, right: {START: begin, END: finish}, select: {id: left.id, value: right.id}, max_output_rows: 2)",
    ),
  )
  let body = with_carrier_argument(interval, "interval_join")
  assert_true(body.contains("\"max_output_rows\":2"))
  assert_true(
    body.contains(
      "\"on\":[{\"left\":\"id\",\"right\":\"id\"},{\"left\":\"id\",\"right\":\"id\"}]",
    ),
  )
}

///|
test "asof Events input retains its intrinsic identity and produces a Relation" {
  let text = "WITH l AS (SELECT 1 AS id, 10 AS `at`), r AS (SELECT 2 AS id, 5 AS begin), ev AS (FROM l |> to_events(id: id, time: at)), matched AS (FROM ev |> asof_join(with: r, kind: 'left', by: [], left_time: at, right_time: begin, direction: 'backward', tolerance: 10, select: {id: left.id, value: right.id})) SELECT id, value FROM matched ORDER BY id"
  let actual = temporal_join_checked(text)
  let body = with_carrier_argument(actual, "asof_join")
  assert_true(!body.contains("left_id"))
  assert_eq(semantic(actual).split("\"to_events\":").length(), 2)
}

///|
test "temporal peer shadowing does not select an outer same-name producer" {
  let text = "WITH r AS (SELECT 99 AS id, 100 AS begin), matched AS (WITH l AS (SELECT 1 AS id, 10 AS `at`), r AS (SELECT 2 AS id, 5 AS begin) FROM l |> asof_join(with: r, kind: 'left', by: [], left_id: id, left_time: at, right_time: r.begin, direction: 'backward', tolerance: 10, select: {id: left.id, value: right.id})) SELECT id, value FROM matched ORDER BY id"
  let actual = temporal_join_checked(text)
  let body = semantic(actual)
  assert_true(!body.contains("\"literal\":99"))
  assert_true(body.contains("\"literal\":2"))
  assert_eq(body.split("\"asof_join\":").length(), 2)
}

///|
test "temporal peer references share an original installed input once" {
  let text = "WITH l AS (SELECT x AS id, y AS `at` FROM pair), r AS (SELECT x AS id, y AS begin, y + 10 AS finish FROM pair), matched AS (FROM l |> interval_join(with: r, kind: 'left', mode: 'point_in_interval', on: [], left: {time: at}, right: {start: begin, end: finish}, select: {id: left.id, value: right.id}, max_output_rows: 2)) SELECT id, value FROM matched ORDER BY id"
  let actual = @frontend.lower(text, Sql, Some(pair_context())).unwrap().program.unwrap()
  event_window_common_checked(actual)
  assert_eq(semantic(actual).split("\"values\":").length(), 2)
}

///|
test "temporal operands reject wrong receivers instead of selecting equal named columns" {
  let valid = "asof_join(with: r, kind: 'left', by: [], left_id: left_rows.id, left_time: left_rows.at, right_time: r.begin, direction: 'backward', tolerance: 10, select: {id: left.id, value: right.id})"
  for
    (before, after) in [
      ("left_time: left_rows.at", "left_time: right.at"),
      ("right_time: r.begin", "right_time: left.begin"),
      ("right_time: r.begin", "right_time: missing.begin"),
    ] {
    let text = temporal_join_source(valid.replace(old=before, new=after))
    assert_true(
      @frontend.lower(text, Sql, Some({ ..pair_context(), inputs: [], }))
      is Err(QueryLowering(UnknownColumn)),
    )
  }
}

///|
test "temporal OutputNames use ordinary reserved-word and quotation rules" {
  let prefix = "WITH l AS (SELECT 1 AS id, 10 AS `at`), r AS (SELECT 2 AS id, 5 AS begin) FROM l |> asof_join(with: r, kind: 'left', by: [], left_id: id, left_time: at, right_time: begin, direction: 'backward', tolerance: 10, select: {"
  for name in ["SELECT", "NULL"] {
    assert_true(
      @frontend.lower(
        prefix + name + ": left.id})",
        Text,
        Some({ ..pair_context(), inputs: [], }),
      )
      is Err(QuerySyntax(_)),
    )
    let actual = temporal_join_checked(
      prefix + "`" + name + "`: left.id}) |> SELECT `" + name + "`",
    )
    assert_true(
      with_carrier_argument(actual, "asof_join").contains(
        "\"" + name + "\":\"left.id\"",
      ),
    )
  }
}

///|
test "temporal row alias wins over a same-name outer WITH producer" {
  let text = "WITH left_rows AS (SELECT 99 AS id, 100 AS `at`), l AS (SELECT 1 AS id, 10 AS `at`), r AS (SELECT 2 AS id, 5 AS begin), matched AS (FROM l AS left_rows |> asof_join(with: r, kind: 'left', by: [], left_id: left_rows.id, left_time: left_rows.at, right_time: r.begin, direction: 'backward', tolerance: 10, select: {id: left.id, value: right.id})) SELECT id, value FROM matched ORDER BY id"
  let actual = temporal_join_checked(text)
  assert_true(!semantic(actual).contains("\"literal\":99"))
  assert_true(
    with_carrier_argument(actual, "asof_join").contains("\"left_time\":\"at\""),
  )
}

///|
test "temporal calls preserve whole Parameters and pending values" {
  let declarations = @parameters.read_declarations(
    Some(
      from_unpivot_public_cursor(
        "{\"tolerance\":{\"type\":\"number\",\"nullable\":false},\"ceiling\":{\"type\":\"number\",\"nullable\":false}}",
      ),
    ),
    { max_parameters: 10, max_nodes: 128, max_depth: 16, max_text_bytes: 4096, },
  ).unwrap()
  for
    (call, operation, key, param) in [
      (
        "asof_join(with: r, kind: 'left', by: [], left_id: id, left_time: at, right_time: begin, direction: 'backward', tolerance: @TOLERANCE, select: {id: left.id, value: right.id})",
        "asof_join", "tolerance", "tolerance",
      ),
      (
        "interval_join(with: r, kind: 'left', mode: 'point_in_interval', on: [], left: {time: at}, right: {start: begin, end: finish}, select: {id: left.id, value: right.id}, max_output_rows: @ceiling)",
        "interval_join", "max_output_rows", "ceiling",
      ),
    ] {
    let actual = @frontend.lower(
      temporal_join_source(call),
      Sql,
      Some({
        ..pair_context(),
        inputs: [],
        parameter_declarations: Some(declarations),
      }),
    ).unwrap().program.unwrap()
    assert_true(
      with_carrier_argument(actual, operation).contains(
        "\"" + key + "\":{\"$param\":\"" + param + "\"}",
      ),
    )
    assert_true(
      @check.check_parsed(
        actual,
        graph_event_environment(),
        None,
        check_limits(),
      )
      is NeedsInputs(_),
    )
  }
}

///|
test "temporal operand roles distinguish a row alias from a same-name right peer" {
  let text = "WITH l AS (SELECT 1 AS id, 10 AS `at`), r AS (SELECT 2 AS id, 5 AS begin), matched AS (FROM l AS r |> asof_join(with: r, kind: 'left', by: [], left_id: r.id, left_time: r.at, right_time: r.begin, direction: 'backward', tolerance: 10, select: {id: left.id, value: right.id})) SELECT id, value FROM matched ORDER BY id"
  let actual = temporal_join_checked(text)
  let body = with_carrier_argument(actual, "asof_join")
  assert_true(body.contains("\"left_time\":\"at\""))
  assert_true(body.contains("\"right_time\":\"begin\""))
}

///|
fn temporal_join_schema(
  program : @program.Program,
) -> Array[@schema.Field] raise {
  let checked = match
    @check.check_parsed(
      program,
      graph_event_environment(),
      None,
      check_limits(),
    ) {
    Checked(checked) => checked
    Rejected(issue) => {
      graph_rows_rejected(issue)
      fail("temporal schema")
    }
    NeedsInputs(_) => fail("closed schema")
  }
  let stage = @stage_results.stage_at(@check.checked_stage_results(checked), 0).unwrap()
  @schema.fields(
    @relation_results.output_schema(
      @relation_results.lookup(stage, "rows").unwrap(),
    ),
  )
}

///|
test "temporal empty output retains the full independent ordered nullable schema" {
  let call = "interval_join(with: r, kind: 'left', mode: 'point_in_interval', on: [], left: {time: at}, right: {start: begin, end: finish}, select: {id: left.id, value: right.id}, max_output_rows: 2)"
  let text = temporal_join_source(call).replace(
    old="SELECT 1 AS id, 10 AS `at`",
    new="WITH seed AS (SELECT 1 AS id, 10 AS `at`) SELECT id, at FROM seed WHERE FALSE",
  )
  let actual = temporal_join_checked(text)
  let control = temporal_join_control(
    "interval_join", "{\"with\":\"r\",\"kind\":\"left\",\"mode\":\"point_in_interval\",\"on\":[],\"left\":{\"time\":\"at\"},\"right\":{\"start\":\"begin\",\"end\":\"finish\"},\"select\":{\"id\":\"left.id\",\"value\":\"right.id\"},\"max_output_rows\":2}",
  )
  let expected = temporal_join_schema(control)
  let fields = temporal_join_schema(actual)
  assert_eq(fields.map(field => field.name), expected.map(field => field.name))
  for i in 0..<fields.length() {
    assert_eq(fields[i].presence, expected[i].presence)
    assert_true(
      @contract.type_equal(fields[i].contract, expected[i].contract, 10000),
    )
  }
}
