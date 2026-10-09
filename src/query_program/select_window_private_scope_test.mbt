///|
fn select_window_private_context(field : String) -> Context {
  let body = "{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"" +
    field +
    "\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":2,\"" +
    field +
    "\":10},{\"id\":1,\"" +
    field +
    "\":90}]},\"as\":\"records\"}"
  let seed = @wire.admit(
    @source.parse_json(body, construction_limits().source.source).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  {
    ..pair_context(),
    inputs: [
      {
        relation: [{ value: "records", quoted: false, }],
        name: "records",
        source: GeneratedValues(seed),
        visible_fields: ["id", field],
        graph_bindings: [],
      },
    ],
  }
}

///|
test "SELECT embedded window keeps schema names distinct from private references" {
  for field in ["aql_select_window_0", "AQL_SELECT_WINDOW_0"] {
    for
      text in [
        "SELECT *, ROW_NUMBER() OVER (ORDER BY id) + 1 AS pos FROM records ORDER BY id DESC",
        "FROM records |> AS r |> SELECT *, ROW_NUMBER() OVER (ORDER BY id) + 1 AS pos |> ORDER BY id DESC",
        "SELECT *, ROW_NUMBER() OVER (ORDER BY id) + 1 AS pos FROM records GROUP BY ALL ORDER BY id DESC",
      ] {
      let actual = match
        compile(
          @query.parse_query(text, syntax_limits()).unwrap(),
          select_window_private_context(field),
          construction_limits(),
        ) {
        Ok(program) => program
        Err(Expression(diagnostic)) =>
          fail(text + ": " + @debug.to_string(diagnostic.issue))
        Err(UnsupportedGrouping) => fail(text + ": UnsupportedGrouping")
        Err(UnsupportedProjection) => fail(text + ": UnsupportedProjection")
        Err(UnsupportedAnalytic) => fail(text + ": UnsupportedAnalytic")
        Err(AmbiguousColumn) => fail(text + ": AmbiguousColumn")
        Err(DuplicateOutput) => fail(text + ": DuplicateOutput")
        Err(_) => fail(text + ": unexpected lowering refusal")
      }
      match
        @check.check_parsed(actual, check_environment(), None, check_limits()) {
        Checked(_) => ()
        Rejected(error) => raise @check.diagnostic_cause(error)
        _ => fail("the independent star schema is closed")
      }
      assert_true(
        semantic(actual).contains(
          "\"fields\":[\"id\",\"" + field + "\",\"pos\"]",
        ),
      )
      // Two input fields plus the reserved SELECT alias pos give slot 3.
      assert_true(
        semantic(actual).contains(
          "\"add\":[{\"field\":\"aql_analytic_output_3\"},{\"literal\":1}]",
        ),
        msg=text + "\n" + semantic(actual),
      )
    }
  }
}

///|
test "SELECT window has an independently checked public-column control" {
  let control = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.select_private_window","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"aql_select_window_0":{"type":"number","nullable":false}},"rows":[{"id":2,"aql_select_window_0":10},{"id":1,"aql_select_window_0":90}]},"as":"records"},{"from":"records","analytic":{"partition_by":[],"order_by":[{"field":"id","dir":"asc","nulls":"first"}],"functions":{"private_rank":{"fn":"row_number"}}}},{"derive":{"pos":{"add":[{"field":"private_rank"},{"literal":1}]}}},{"select":["id","aql_select_window_0","pos"]},{"sort":[{"field":"id","dir":"desc","nulls":"last"}],"as":"out"}],"results":{"rows":{"from":"out","fields":["id","aql_select_window_0","pos"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(control, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the hand-authored window control is closed")
  }
}

///|
test "SELECT private scope keeps qualified and explicitly authored user keys" {
  for
    text in [
      "FROM records |> AS r |> SELECT *, ROW_NUMBER() OVER (ORDER BY r.id) + 1 AS pos |> ORDER BY id DESC",
      "FROM records |> AS r |> SELECT *, ROW_NUMBER() OVER (ORDER BY aql_select_window_0) + 1 AS pos |> ORDER BY id DESC",
      "FROM records |> AS r |> SELECT *, ROW_NUMBER() OVER (ORDER BY id) + r.aql_select_window_0 AS pos |> ORDER BY id DESC",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      select_window_private_context("aql_select_window_0"),
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(actual, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("the authored input key is closed")
    }
    assert_true(
      semantic(actual).contains(
        "\"fields\":[\"id\",\"aql_select_window_0\",\"pos\"]",
      ),
    )
  }
}

///|
test "SELECT embedded window cannot expose a private physical slot" {
  let text = "FROM records |> AS r |> SELECT *, ROW_NUMBER() OVER (ORDER BY id) + 1 AS pos |> SELECT id, aql_analytic_output_3 AS leaked"
  assert_true(
    compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      select_window_private_context("aql_select_window_0"),
      construction_limits(),
    )
    is Err(Expression({ issue: @expression.UnknownReference, .. })),
  )
}
