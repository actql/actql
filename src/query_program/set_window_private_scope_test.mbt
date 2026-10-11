///|
fn set_window_private_context(field : String) -> Context {
  let body = "{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"" +
    field +
    "\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":2,\"" +
    field +
    "\":90},{\"id\":1,\"" +
    field +
    "\":10}]},\"as\":\"records\"}"
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
fn set_window_private_control() -> @program.Program {
  // Independent append/window/sort/projection. The authored column is
  // deliberately ordered differently from id and must survive unchanged.
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.set_window_private","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"aql_order_window_0":{"type":"number","nullable":false}},"rows":[{"id":2,"aql_order_window_0":10},{"id":1,"aql_order_window_0":90}]},"as":"records"},{"from":"records","append":{"with":"records"},"as":"combined"},{"from":"combined","analytic":{"partition_by":[],"order_by":[{"field":"id","dir":"asc","nulls":"first"}],"functions":{"private_rank":{"fn":"row_number"}}}},{"sort":[{"field":"private_rank","dir":"desc","nulls":"last"}]},{"select":["id","aql_order_window_0"],"as":"out"}],"results":{"rows":{"from":"out","fields":["id","aql_order_window_0"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "set ORDER window has an independent checked append control" {
  match
    @check.check_parsed(
      set_window_private_control(),
      check_environment(),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the independently authored append control is closed")
  }
}

///|
test "set ORDER private window and authored OVER key remain separate" {
  let context = set_window_private_context("AQL_ORDER_WINDOW_0")
  for
    source in [
      "SELECT * FROM records UNION ALL SELECT * FROM records ORDER BY ROW_NUMBER() OVER (ORDER BY id) + 1 DESC",
      "SELECT * FROM records UNION ALL SELECT * FROM records ORDER BY ROW_NUMBER() OVER (ORDER BY AQL_ORDER_WINDOW_0) DESC",
      "SELECT * FROM records UNION ALL SELECT * FROM records ORDER BY ROW_NUMBER() OVER (ORDER BY id) DESC, AQL_ORDER_WINDOW_0",
    ] {
    let query = @query.parse_query(source, syntax_limits()).unwrap()
    for
      program in [
        compile(query, context, construction_limits()).unwrap(),
        compile_query_script(
          @query.single_query_script(query),
          context,
          construction_limits(),
        ).unwrap(),
      ] {
      match
        @check.check_parsed(program, check_environment(), None, check_limits()) {
        Checked(_) => ()
        Rejected(error) => raise @check.diagnostic_cause(error)
        _ => fail("all authored columns and private windows are closed")
      }
      assert_true(
        semantic(program).contains("\"fields\":[\"id\",\"AQL_ORDER_WINDOW_0\"]"),
      )
    }
  }
}

///|
test "set ORDER window does not expose an unbound private slot" {
  let query = @query.parse_query(
    "SELECT * FROM records UNION ALL SELECT * FROM records ORDER BY ROW_NUMBER() OVER (ORDER BY id) DESC, aql_set_window_2",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(
      query,
      set_window_private_context("aql_order_window_0"),
      construction_limits(),
    )
    is Err(Expression({ issue: @expression.UnknownReference, .. })),
  )
}

///|
test "set star parameter schema keeps private-name columns in script scope" {
  for field in ["aql_order_window_0", "AQL_ORDER_WINDOW_0"] {
    let declarations = @parameters.read_declarations(
      Some(
        unnest_value_cursor(
          "{\"items\":{\"type\":\"array\",\"nullable\":false,\"max_items\":3,\"items\":{\"type\":\"object\",\"nullable\":false,\"fields\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"" +
          field +
          "\":{\"type\":\"number\",\"nullable\":true}}}}}",
        ),
      ),
      {
        max_parameters: 10,
        max_nodes: 1000,
        max_depth: 100,
        max_text_bytes: 10000,
      },
    ).unwrap()
    let context = {
      ..fixture_context(),
      inputs: [],
      parameter_declarations: Some(declarations),
    }
    for
      source in [
        "SELECT * FROM UNNEST(@items) e UNION ALL SELECT * FROM UNNEST(@items) e ORDER BY ROW_NUMBER() OVER (ORDER BY id) DESC",
        "WITH combined AS (SELECT * FROM UNNEST(@items) e UNION ALL SELECT * FROM UNNEST(@items) e ORDER BY ROW_NUMBER() OVER (ORDER BY id) DESC) FROM combined |> SELECT * |> RESULT answer",
      ] {
      let program = compile_query_script(
        @query.parse_query_script(source, syntax_limits()).unwrap(),
        context,
        construction_limits(),
      ).unwrap()
      for
        values in [
          "[]",
          "[{\"id\":2,\"" + field + "\":10},{\"id\":1,\"" + field + "\":null}]",
        ] {
        match
          @check.check_parsed(
            program,
            check_environment(),
            Some(unnest_value_cursor("{\"items\":" + values + "}")),
            check_limits(),
          ) {
          Checked(_) => ()
          Rejected(error) => raise @check.diagnostic_cause(error)
          _ => fail("the typed parameter supplies the complete star schema")
        }
      }
    }
  }
}

///|
test "set ORDER window preserves star columns colliding with private names" {
  for field in ["aql_order_window_0", "AQL_ORDER_WINDOW_0"] {
    let query = @query.parse_query(
      "SELECT * FROM records UNION ALL SELECT * FROM records ORDER BY ROW_NUMBER() OVER (ORDER BY id) DESC",
      syntax_limits(),
    ).unwrap()
    let actual = match
      compile(query, set_window_private_context(field), construction_limits()) {
      Ok(program) => program
      Err(Expression(diagnostic)) =>
        fail("set window private scope: " + @debug.to_string(diagnostic.issue))
      Err(_) => fail("set window private scope rejected")
    }
    match
      @check.check_parsed(actual, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("independent star inputs are closed")
    }
    // Complete final Stage written from the shared set output contract.
    // The hidden physical window is distinct from the authored star column.
    let expected_final = "{\"id\":\"main\",\"inputs\":{\"set_rows\":{\"result\":{\"result\":\"aql_set_merge_0\",\"stage\":\"aql_set_merge_0\"}}},\"results\":{\"rows\":{\"fields\":[\"id\",\"" +
      field +
      "\"],\"from\":\"aql_set_final_1\"}},\"steps\":[{\"analytic\":{\"functions\":{\"aql_set_window_2\":{\"fn\":\"row_number\"}},\"order_by\":[{\"dir\":\"asc\",\"field\":\"id\",\"nulls\":\"first\"}],\"partition_by\":[]},\"as\":\"aql_set_final_0\",\"from\":\"set_rows\"},{\"as\":\"aql_set_ordered_1\",\"from\":\"aql_set_final_0\",\"sort\":[{\"dir\":\"desc\",\"field\":\"aql_set_window_2\",\"nulls\":\"last\"}]},{\"as\":\"aql_set_final_1\",\"from\":\"aql_set_ordered_1\",\"select\":[\"id\",\"" +
      field +
      "\"]}]}"
    assert_true(semantic(actual).contains(expected_final))
  }
}
