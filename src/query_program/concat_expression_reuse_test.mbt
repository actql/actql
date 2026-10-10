///|
fn concat_reuse_context() -> Context {
  let seed = @wire.admit(
    @source.parse_json(
      (
        #|{"values":{"schema":{"x":{"type":"string","nullable":false},"y":{"type":"string","nullable":true}},"rows":[{"x":"a","y":"b"},{"x":"a","y":null},{"x":"a","y":"b"}]},"as":"t"}
      ),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  {
    ..join_order_context(),
    inputs: [
      {
        relation: [{ value: "t", quoted: false, }],
        name: "t",
        source: GeneratedValues(seed),
        visible_fields: ["x", "y"],
        graph_bindings: [],
      },
    ],
  }
}

///|
fn concat_reuse_expected(
  tail : String,
  fields? : String = "[\"value\",\"n\"]",
) -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"string","nullable":false},"y":{"type":"string","nullable":true}},"rows":[{"x":"a","y":"b"},{"x":"a","y":null},{"x":"a","y":"b"}]},"as":"t"},
    ) +
    tail +
    (
      #|],"results":{"rows":{"from":"aql_gen_0","fields":
    ) +
    fields +
    (
      #|}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "grouped binary strict CONCAT spellings reuse one checked value" {
  let expected = concat_reuse_expected(
    (
      #|{"from":"t","derive":{"aql_group_key_0":{"concat_strict":[{"field":"x"},{"field":"y"}]}}},{"group":{"by":["aql_group_key_0"],"aggregates":{"n":{"fn":"count"}}}},{"select":[{"value":"aql_group_key_0"},"n"],"as":"aql_gen_0"}
    ),
  )
  assert_true(
    @check.check_parsed(expected, check_environment(), None, check_limits())
    is Checked(_),
  )
  for
    (selected, grouped) in [
      ("x || y", "CONCAT(x, y)"),
      ("CONCAT(x, y)", "x || y"),
      ("(x) || (t.y)", "`concat`(t.x, y)"),
    ] {
    let actual = compile(
      @query.parse_query(
        "SELECT " +
        selected +
        " AS value, COUNT(*) AS n FROM t GROUP BY " +
        grouped,
        syntax_limits(),
      ).unwrap(),
      concat_reuse_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected))
    assert_true(
      @check.check_parsed(actual, check_environment(), None, check_limits())
      is Checked(_),
    )
  }
}

///|
test "DISTINCT ORDER recognizes binary strict CONCAT without restoring input" {
  let expected = concat_reuse_expected(
    (
      #|{"from":"t","derive":{"aql_query_expr_0":{"concat_strict":[{"field":"x"},{"field":"y"}]}}},{"select":[{"value":"aql_query_expr_0"}]},{"distinct":["value"]},{"sort":[{"field":"value","dir":"asc","nulls":"last"}],"as":"aql_gen_0"}
    ),
    fields="[\"value\"]",
  )
  for
    (selected, ordered) in [
      ("x || y", "CONCAT(x, y)"),
      ("CONCAT(x, y)", "x || y"),
    ] {
    let actual = compile(
      @query.parse_query(
        "SELECT DISTINCT " +
        selected +
        " AS value FROM t ORDER BY " +
        ordered +
        " NULLS LAST",
        syntax_limits(),
      ).unwrap(),
      concat_reuse_context(),
      construction_limits(),
    ).unwrap()
    let body = semantic(actual)
    assert_eq(body, semantic(expected))
    assert_eq(body.split("\"concat_strict\":").length(), 2)
    assert_true(body.contains("\"field\":\"value\",\"nulls\":\"last\""))
    assert_false(body.contains("aql_pipe_sort_"))
    assert_true(
      @check.check_parsed(actual, check_environment(), None, check_limits())
      is Checked(_),
    )
  }
}

///|
test "strict CONCAT reuse preserves argument order arity and clause receivers" {
  for
    source in [
      "SELECT DISTINCT CONCAT(x,y) AS value FROM t ORDER BY y || x", "SELECT DISTINCT x || y AS value FROM t ORDER BY ACTQL.CONCAT(x,y)",
      "SELECT DISTINCT CONCAT(x,y,'') AS value FROM t ORDER BY x || y", "SELECT DISTINCT CONCAT(x,y) AS x FROM t ORDER BY x || y",
    ] {
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        concat_reuse_context(),
        construction_limits(),
      )
      is Err(UnsupportedOrdering),
      msg=source,
    )
  }
  for (ordered, count) in [("x || y", 3), ("t.x || y", 2)] {
    let actual = compile(
      @query.parse_query(
        "SELECT CONCAT(x,y) AS original, y AS x FROM t ORDER BY " + ordered,
        syntax_limits(),
      ).unwrap(),
      concat_reuse_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual).split("\"concat_strict\":").length(), count)
    assert_true(
      @check.check_parsed(actual, check_environment(), None, check_limits())
      is Checked(_),
    )
  }
}

///|
test "Pipe selected strict CONCAT reuses the evaluated slot in ORDER" {
  for
    (selected, ordered) in [
      ("CONCAT(x,y)", "x || y"),
      ("x || y", "`concat`(t.x, y)"),
    ] {
    let actual = compile(
      @query.parse_query(
        "FROM t |> SELECT DISTINCT " +
        selected +
        " AS value |> ORDER BY " +
        ordered +
        " NULLS LAST",
        syntax_limits(),
      ).unwrap(),
      concat_reuse_context(),
      construction_limits(),
    ).unwrap()
    let body = semantic(actual)
    assert_eq(body.split("\"concat_strict\":").length(), 2)
    assert_true(body.contains("\"field\":\"value\",\"nulls\":\"last\""))
    assert_true(
      @check.check_parsed(actual, check_environment(), None, check_limits())
      is Checked(_),
    )
  }
}
