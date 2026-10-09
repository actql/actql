///|
// The authored field is legitimate input, never an internal-slot declaration.
fn group_key_collision_seed(field : String) -> String {
  "{\"values\":{\"schema\":{\"x\":{\"type\":\"number\",\"nullable\":true},\"" +
  field +
  "\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"x\":2,\"" +
  field +
  "\":200},{\"x\":1,\"" +
  field +
  "\":100},{\"x\":2,\"" +
  field +
  "\":201},{\"x\":null,\"" +
  field +
  "\":50}]},\"as\":\"t\"}"
}

///|
fn group_key_collision_context(field : String) -> Context {
  let seed = @wire.admit(
    @source.parse_json(
      group_key_collision_seed(field),
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
        visible_fields: ["x", field],
        graph_bindings: [],
      },
    ],
  }
}

///|
fn group_key_collision_expected(
  field : String,
  count_name? : String = "n",
) -> @program.Program {
  @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.pipe_slots\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[" +
    group_key_collision_seed(field) +
    (
      #|,{"from":"t","derive":{"aql_group_key_1":{"add":[{"field":"x"},{"literal":1}]}}},{"group":{"by":["aql_group_key_1"],"aggregates":{"n":{"fn":"count"}}}},{"select":[{"bucket":"aql_group_key_1"},"n"]},{"sort":[{"field":"bucket","dir":"asc","nulls":"first"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["bucket","n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ).replace_all(old="\"n\"", new="\"" + count_name + "\""),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "computed GROUP keys avoid legitimate input and output names" {
  for
    (field, count_name) in [
      ("aql_group_key_0", "n"),
      ("AQL_GROUP_KEY_0", "n"),
      ("authored", "aql_group_key_0"),
    ] {
    let expected = group_key_collision_expected(field, count_name~)
    match
      @check.check_parsed(expected, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("the independent grouping Program must check")
    }
    let actual = match
      compile(
        @query.parse_query(
          "SELECT x + 1 AS bucket, COUNT(*) AS " +
          count_name +
          " FROM t GROUP BY x + 1 ORDER BY bucket",
          syntax_limits(),
        ).unwrap(),
        group_key_collision_context(field),
        construction_limits(),
      ) {
      Ok(program) => program
      Err(UnsupportedGrouping) =>
        fail("legitimate input name caused UnsupportedGrouping")
      Err(_) => fail("another compilation failure")
    }
    assert_eq(semantic(actual), semantic(expected))
  }
}

///|
test "computed GROUP collisions retain later private keys and scoped consumers" {
  for
    source in [
      "SELECT x + 1 AS bucket, COUNT(*) AS n FROM t GROUP BY ALL ORDER BY bucket",
      "FROM t AS original |> AGGREGATE COUNT(*) AS n GROUP BY x + 1 AS bucket |> ORDER BY bucket",
      "FROM t AS original |> SET x = original.x |> AGGREGATE COUNT(*) AS n GROUP BY x + 1 AS bucket |> ORDER BY bucket",
      "SELECT x + 1 AS bucket, x + 2 AS next, COUNT(*) AS n FROM t GROUP BY x + 1, x + 2 ORDER BY bucket",
    ] {
    let actual = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      group_key_collision_context("aql_group_key_0"),
      construction_limits(),
    ).unwrap()
    assert_true(
      @check.check_parsed(actual, check_environment(), None, check_limits())
      is Checked(_),
      msg=source,
    )
    if source.contains("x + 2") {
      assert_true(
        semantic(actual).contains(
          "\"by\":[\"aql_group_key_1\",\"aql_group_key_2\"]",
        ),
      )
    }
  }
}

///|
test "private GROUP collision handling does not expose an ungrouped authored input" {
  let source = "SELECT x + 1 AS bucket, COUNT(*) AS n FROM t GROUP BY x + 1 HAVING t.aql_group_key_0 > 0"
  assert_true(
    compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      group_key_collision_context("aql_group_key_0"),
      construction_limits(),
    )
    is Err(Expression({ issue: @expression.UnknownReference, .. })),
  )
}

///|
test "existing DISTINCT refusal retains the unsupported ordering cause" {
  assert_true(
    compile(
      @query.parse_query(
        "SELECT DISTINCT x + 1.0 AS next FROM t ORDER BY x + 2e0",
        syntax_limits(),
      ).unwrap(),
      group_key_collision_context("aql_group_key_0"),
      construction_limits(),
    )
    is Err(UnsupportedOrdering),
  )
}
