///|
fn having_object_declarations() -> @parameters.Declarations {
  let cursor = @wire.admit(
    @source.parse_json(
      (
        #|{"assessment":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":true}}}}
      ),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  @parameters.read_declarations(Some(cursor), {
    max_parameters: 10,
    max_nodes: 1000,
    max_depth: 100,
    max_text_bytes: 10000,
  }).unwrap()
}

///|
fn having_object_values() -> @wire.Cursor {
  @wire.admit(
    @source.parse_json(
      (
        #|{"assessment":{"score":20}}
      ),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
}

///|
test "HAVING object properties match an independent checked Program" {
  // Authored before the source probe: Group, one evaluated object projection,
  // common nullable property and filter, then the public SELECT and sort.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","params":{"assessment":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":true}}}},"stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"},{"from":"t","group":{"by":["x"],"aggregates":{"n":{"fn":"count"}}}},{"derive":{"aql_having_expr_4":{"$param":"assessment"}}},{"filter":{"gt":[{"property":{"value":{"field":"aql_having_expr_4"},"name":"score"}},{"literal":10}]}},{"select":["x",{"assessment":"aql_having_expr_4"},"n"]},{"sort":[{"field":"x","dir":"asc","nulls":"first"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["x","assessment","n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(
      expected,
      check_environment(),
      Some(having_object_values()),
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ =>
      fail(
        "the independent ordinary Program must be closed before probing source",
      )
  }
  let program = compile(
    @query.parse_query(
      "SELECT x, @assessment AS assessment, COUNT(*) AS n FROM t GROUP BY x HAVING assessment.score > 10 ORDER BY x",
      syntax_limits(),
    ).unwrap(),
    {
      ..join_order_context(),
      parameter_declarations: Some(having_object_declarations()),
    },
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(program), semantic(expected))
}

///|
fn checked_having_object(text : String) -> @program.Program raise {
  let program = compile(
    @query.parse_query(text, syntax_limits()).unwrap(),
    {
      ..join_order_context(),
      parameter_declarations: Some(having_object_declarations()),
    },
    construction_limits(),
  ).unwrap()
  match
    @check.check_parsed(
      program,
      check_environment(),
      Some(having_object_values()),
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("HAVING uses the existing closed-object contract")
  }
  program
}

///|
test "HAVING object properties retain alias and qualified input meanings" {
  let program = checked_having_object(
    "SELECT t.x AS original, @assessment AS x, COUNT(*) AS n FROM t GROUP BY t.x HAVING x.score > t.x ORDER BY original",
  )
  let body = semantic(program)
  assert_true(
    body.contains(
      "\"property\":{\"name\":\"score\",\"value\":{\"field\":\"aql_having_expr_5\"}}",
    ),
  )
  assert_true(body.contains("\"gt\":[{\"property\":"))
  assert_true(body.contains("{\"field\":\"x\"}]"))
}

///|
test "HAVING object properties reuse one evaluated alias for predicate and SELECT" {
  let program = checked_having_object(
    "SELECT x, @assessment AS first, @assessment AS second, COUNT(*) AS n FROM t GROUP BY x HAVING first.score > 10 AND second.score < 30 ORDER BY x",
  )
  let body = semantic(program)
  assert_eq(
    body.split("\"$param\":").length(),
    2,
    msg="the selected object is evaluated once, not expanded per property",
  )
  assert_eq(body.split("\"property\":").length(), 3)
  assert_true(body.contains("{\"first\":\"aql_having_expr_5\"}"))
  assert_true(body.contains("{\"second\":\"aql_having_expr_5\"}"))
}

///|
test "HAVING object properties retain grouping scope and typed refusals" {
  for
    text in [
      "SELECT x, @assessment AS assessment, COUNT(*) AS n FROM t GROUP BY x HAVING t.assessment.score > 0",
      "SELECT x, @assessment AS assessment, COUNT(*) AS n FROM t GROUP BY x HAVING y.score > 0",
      "SELECT x, @assessment AS assessment, COUNT(*) AS n FROM t GROUP BY x HAVING missing.score > 0",
      "SELECT x, @assessment AS assessment, COUNT(*) AS n FROM t GROUP BY x HAVING assessment.score > 0 |> SELECT old.score",
    ] {
    assert_true(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        {
          ..join_order_context(),
          parameter_declarations: Some(having_object_declarations()),
        },
        construction_limits(),
      )
      is Err(Expression({ issue: @expression.UnknownReference, .. })),
      msg=text,
    )
  }
  for path in ["assessment.missing", "x.score"] {
    let program = compile(
      @query.parse_query(
        "SELECT x, @assessment AS assessment, COUNT(*) AS n FROM t GROUP BY x HAVING " +
        path +
        " > 0",
        syntax_limits(),
      ).unwrap(),
      {
        ..join_order_context(),
        parameter_declarations: Some(having_object_declarations()),
      },
      construction_limits(),
    ).unwrap()
    assert_true(
      @check.check_parsed(
        program,
        check_environment(),
        Some(having_object_values()),
        check_limits(),
      )
      is Rejected(_),
      msg="field/type validity remains the common checker's responsibility",
    )
  }
}

///|
test "HAVING object properties retain source origins and work bounds" {
  let text = "SELECT x, @assessment AS assessment, COUNT(*) AS n FROM t GROUP BY x HAVING missing.score > 0"
  guard compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      {
        ..join_order_context(),
        parameter_declarations: Some(having_object_declarations()),
      },
      construction_limits(),
    )
    is Err(
      Expression({ issue: @expression.UnknownReference, origin: Some(origin), })
    ) else {
    fail("unknown HAVING receiver must retain its original source diagnostic")
  }
  assert_eq(@origin.start(origin).utf16_offset, 76)
  assert_eq(@origin.end(origin).utf16_offset, 89)
  assert_true(
    compile(
      @query.parse_query(
        "SELECT x, @assessment AS assessment, COUNT(*) AS n FROM t GROUP BY x HAVING assessment.score > 0",
        syntax_limits(),
      ).unwrap(),
      {
        ..join_order_context(),
        parameter_declarations: Some(having_object_declarations()),
      },
      { ..construction_limits(), max_expression_work: 3, },
    )
    is Err(Expression({ issue: @expression.WorkLimit, .. })),
  )
}
