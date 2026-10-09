///|
fn qualify_group_collision_seed() -> String {
  (
    #|{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":1,"y":21},{"x":2,"y":10}]},"as":"t"}
  )
}

///|
fn qualify_group_collision_context() -> Context {
  let seed = @wire.admit(
    @source.parse_json(
      qualify_group_collision_seed(),
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
test "QUALIFY resolves a colliding aggregate alias to its evaluated result" {
  // Independent grouping and ranking: key 1 has COUNT 2 and rank 1;
  // key 2 has COUNT 1 and rank 2. QUALIFY must retain the first group.
  let expected = @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.pipe_slots\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[" +
    qualify_group_collision_seed() +
    (
      #|,{"from":"t","group":{"by":["x"],"aggregates":{"aql_select_aggregate_7":{"fn":"count"}}}},{"analytic":{"partition_by":[],"order_by":[{"field":"x","dir":"asc","nulls":"first"}],"functions":{"rn":{"fn":"row_number"}}}},{"filter":{"gt":[{"field":"aql_select_aggregate_7"},{"literal":1}]}},{"sort":[{"field":"x","dir":"asc","nulls":"first"}]},{"select":[{"original":"x"},{"x":"aql_select_aggregate_7"},"rn"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["original","x","rn"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("independent grouped analytic control must check")
  }
  let actual = compile(
    @query.parse_query(
      "SELECT t.x AS original, COUNT(*) AS x, ROW_NUMBER() OVER (ORDER BY t.x) AS rn FROM t GROUP BY t.x QUALIFY x > 1 ORDER BY original",
      syntax_limits(),
    ).unwrap(),
    qualify_group_collision_context(),
    construction_limits(),
  ).unwrap()
  assert_true(
    semantic(actual).contains(
      "\"filter\":{\"gt\":[{\"field\":\"aql_select_aggregate_7\"},{\"literal\":1}]}",
    ),
    msg="QUALIFY reads COUNT rather than the retained input key",
  )
  assert_eq(semantic(actual), semantic(expected))
}

///|
fn checked_group_clause_collision(source : String) -> String raise {
  let actual = compile(
    @query.parse_query(source, syntax_limits()).unwrap(),
    qualify_group_collision_context(),
    construction_limits(),
  ).unwrap()
  match @check.check_parsed(actual, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("grouped clause control must check: " + source)
  }
  semantic(actual)
}

///|
test "QUALIFY quoted aggregate aliases preserve the evaluated binding" {
  for reference in ["x", "X", "`x`", "`X`"] {
    let actual = checked_group_clause_collision(
      "SELECT t.x AS original, COUNT(*) AS `x`, ROW_NUMBER() OVER (ORDER BY t.x) AS rn FROM t GROUP BY t.x QUALIFY " +
      reference +
      " > 1 ORDER BY original",
    )
    assert_true(
      actual.contains(
        "\"filter\":{\"gt\":[{\"field\":\"aql_select_aggregate_7\"},{\"literal\":1}]}",
      ),
      msg=reference + "\n" + actual,
    )
  }
}

///|
test "QUALIFY qualified input keeps the grouping key and ordinary aggregate names" {
  let input = checked_group_clause_collision(
    "SELECT t.x AS original, COUNT(*) AS x, ROW_NUMBER() OVER (ORDER BY t.x) AS rn FROM t GROUP BY t.x QUALIFY t.x > 1 ORDER BY original",
  )
  assert_true(
    input.contains("\"filter\":{\"gt\":[{\"field\":\"x\"},{\"literal\":1}]}"),
  )
  let ordinary = checked_group_clause_collision(
    "SELECT t.x AS original, COUNT(*) AS total, ROW_NUMBER() OVER (ORDER BY t.x) AS rn FROM t GROUP BY t.x QUALIFY total > 1 ORDER BY original",
  )
  assert_true(
    ordinary.contains(
      "\"filter\":{\"gt\":[{\"field\":\"total\"},{\"literal\":1}]}",
    ),
  )
}

///|
test "ORDER windows use aggregate output slots rather than colliding grouped inputs" {
  // Descending COUNT places key 1 (two rows) before key 2 (one row).
  // Descending t.x deliberately requires the opposite order.
  let expected = @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.pipe_slots\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[" +
    qualify_group_collision_seed() +
    (
      #|,{"from":"t","group":{"by":["x"],"aggregates":{"aql_select_aggregate_6":{"fn":"count"}}}},{"analytic":{"partition_by":[],"order_by":[{"field":"aql_select_aggregate_6","dir":"desc","nulls":"last"}],"functions":{"aql_order_window_0":{"fn":"row_number"}}}},{"sort":[{"field":"aql_order_window_0","dir":"asc","nulls":"first"},{"field":"x","dir":"asc","nulls":"first"}]},{"select":[{"original":"x"},{"x":"aql_select_aggregate_6"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["original","x"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("independent aggregate ORDER control must check")
  }
  for reference in ["x", "`X`"] {
    let actual = checked_group_clause_collision(
      "SELECT t.x AS original, COUNT(*) AS x FROM t GROUP BY t.x ORDER BY ROW_NUMBER() OVER (ORDER BY " +
      reference +
      " DESC), original",
    )
    assert_eq(actual, semantic(expected), msg=reference)
  }
  let input = checked_group_clause_collision(
    "SELECT t.x AS original, COUNT(*) AS x FROM t GROUP BY t.x ORDER BY ROW_NUMBER() OVER (ORDER BY t.x DESC), original",
  )
  assert_true(
    input.contains(
      "\"order_by\":[{\"dir\":\"desc\",\"field\":\"x\",\"nulls\":\"last\"}]",
    ),
  )
}

///|
test "grouped later clauses do not restore discarded input columns" {
  for tail in ["QUALIFY t.y > 1", "ORDER BY ROW_NUMBER() OVER (ORDER BY t.y)"] {
    let actual = compile(
      @query.parse_query(
        "SELECT t.x AS original, COUNT(*) AS x, ROW_NUMBER() OVER (ORDER BY t.x) AS rn FROM t GROUP BY t.x " +
        tail,
        syntax_limits(),
      ).unwrap(),
      qualify_group_collision_context(),
      construction_limits(),
    )
    match actual {
      Err(error) =>
        if tail.has_prefix("QUALIFY") {
          assert_true(
            error is Expression({ issue: @expression.UnknownReference, .. }),
            msg=tail,
          )
        } else {
          assert_true(error is UnknownColumn, msg=tail)
        }
      _ => fail("discarded input must be rejected: " + tail)
    }
  }
}
