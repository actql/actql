///|
fn independent_group_having_implicit_program() -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"payload":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":true}}},"other":{"type":"object","nullable":false,"fields":{"score":{"type":"number","nullable":false}}}},"rows":[{"id":2,"payload":{"score":10},"other":{"score":100}},{"id":1,"payload":{"score":20},"other":{"score":200}},{"id":3,"payload":null,"other":{"score":300}},{"id":4,"payload":{"score":20},"other":{"score":400}},{"id":5,"payload":{"score":null},"other":{"score":500}}]},"as":"objects"},{"from":"objects","derive":{"aql_group_key_0":{"property":{"name":"score","value":{"field":"payload"}}}}},{"group":{"by":["aql_group_key_0"],"aggregates":{"n":{"fn":"count"}}}},{"filter":{"gt":[{"field":"aql_group_key_0"},{"literal":10}]}},{"select":[{"score":"aql_group_key_0"},"n"]},{"sort":[{"field":"score","dir":"asc","nulls":"first"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["score","n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "GROUP HAVING implicit aliases have an independent complete Program" {
  let expected = independent_group_having_implicit_program()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("ordinary grouping and filter read the evaluated nullable key")
  }
  let actual = match
    compile(
      @query.parse_query(
        "SELECT payload.score, COUNT(*) AS n FROM objects GROUP BY payload.score HAVING score > 10 ORDER BY score",
        syntax_limits(),
      ).unwrap(),
      group_property_context(),
      construction_limits(),
    ) {
    Ok(program) => program
    Err(Expression({ issue: @expression.UnknownReference, .. })) =>
      fail(
        "HAVING ignores the implicit score alias of the evaluated property key",
      )
    Err(_) => fail("unexpected source rejection")
  }
  assert_eq(semantic(actual), semantic(expected))
}

///|
test "GROUP HAVING implicit aliases resolve implicit grouping names" {
  let expected = independent_group_property_program()
  for path in ["payload.score", "objects.payload.score", "(payload).score"] {
    let actual = match
      compile(
        @query.parse_query(
          "SELECT " + path + ", COUNT(*) AS n FROM objects GROUP BY score",
          syntax_limits(),
        ).unwrap(),
        group_property_context(),
        construction_limits(),
      ) {
      Ok(program) => program
      Err(UnknownColumn) =>
        fail("GROUP BY ignores the implicit score alias: " + path)
      Err(_) => fail("unexpected source rejection")
    }
    assert_eq(semantic(actual), semantic(expected))
  }
}

///|
fn group_having_collision_context() -> Context {
  let seed = @wire.admit(
    @source.parse_json(
      (
        #|{"values":{"schema":{"id":{"type":"number","nullable":false},"score":{"type":"number","nullable":false},"payload":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":true}}}},"rows":[{"id":1,"score":100,"payload":{"score":10}},{"id":2,"score":0,"payload":{"score":20}}]},"as":"colliding"}
      ),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  {
    ..pair_context(),
    inputs: [
      {
        relation: [{ value: "colliding", quoted: false, }],
        name: "colliding",
        source: GeneratedValues(seed),
        visible_fields: ["id", "score", "payload"],
        graph_bindings: [],
      },
    ],
  }
}

///|
test "GROUP HAVING implicit aliases beat input collisions without changing qualified references" {
  for
    (condition, field) in [
      ("score > 10", "aql_group_key_0"),
      ("colliding.score > 10", "score"),
    ] {
    let expected = @program.parse(
      (
        #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"score":{"type":"number","nullable":false},"payload":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":true}}}},"rows":[{"id":1,"score":100,"payload":{"score":10}},{"id":2,"score":0,"payload":{"score":20}}]},"as":"colliding"},{"from":"colliding","derive":{"aql_group_key_0":{"property":{"name":"score","value":{"field":"payload"}}}}},{"group":{"by":["aql_group_key_0","score"],"aggregates":{"n":{"fn":"count"}}}},{"filter":{"gt":[{"field":
      ) +
      "\"" +
      field +
      "\"" +
      (
        #|},{"literal":10}]}},{"select":[{"score":"aql_group_key_0"},"n"]},{"sort":[{"field":"score","dir":"asc","nulls":"first"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["score","n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
      ),
      construction_limits().program,
      format=Json,
    ).unwrap()
    match
      @check.check_parsed(expected, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("qualified and alias predicates read different checked values")
    }
    let actual = compile(
      @query.parse_query(
        "SELECT payload.score, COUNT(*) AS n FROM colliding GROUP BY score, colliding.score HAVING " +
        condition +
        " ORDER BY score",
        syntax_limits(),
      ).unwrap(),
      group_having_collision_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected))
  }
}

///|
test "GROUP HAVING implicit aliases retain quoted names and hidden aggregate inputs" {
  for
    source in [
      "SELECT `objects`.`payload`.`score`, COUNT(*) AS n FROM objects GROUP BY `SCORE` HAVING `SCORE` > 10 ORDER BY `SCORE`",
      "SELECT `objects`.`payload`.`SCORE`, COUNT(*) AS n FROM objects GROUP BY objects.payload.score HAVING `SCORE` > 10 ORDER BY `SCORE`",
      "SELECT (payload).score, COUNT(*) AS n FROM objects GROUP BY score HAVING COUNT(score) > 1 ORDER BY score",
      "SELECT objects.payload.score, COUNT(*) AS n FROM objects GROUP BY score HAVING COUNT(score) > 1 AND n > 0 ORDER BY score",
      "SELECT payload.score, COUNT(*) AS n FROM objects WHERE FALSE GROUP BY score HAVING score > 10 ORDER BY score",
    ] {
    let actual = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      group_property_context(),
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(actual, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(_) => fail("checker rejects implicit alias source: " + source)
      _ =>
        fail(
          "implicit aliases retain the existing property and aggregate contracts",
        )
    }
    assert_eq(semantic(actual).split("\"property\":").length() - 1, 1)
  }
}

///|
test "GROUP HAVING implicit aliases retain CTE and qualified JOIN scopes" {
  for
    source in [
      "WITH summary AS (SELECT payload.score, COUNT(*) AS n FROM objects GROUP BY score HAVING score > 10) SELECT score, n FROM summary ORDER BY score",
      "SELECT l.payload.score, COUNT(*) AS n FROM objects AS l JOIN objects AS r ON l.id = r.id MAX_OUTPUT_ROWS 10 GROUP BY score HAVING score > 10 ORDER BY score",
    ] {
    let actual = compile_query_script(
      @query.parse_query_script(source, syntax_limits()).unwrap(),
      group_property_context(),
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(
        actual,
        check_environment(numeric=true),
        None,
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("scoped grouping passes only the qualified left property slot")
    }
    assert_eq(semantic(actual).split("\"property\":").length() - 1, 1)
  }
}

///|
test "GROUP HAVING implicit aliases reject ambiguity and ungrouped receivers" {
  for
    source in [
      "SELECT payload.score, other.score, COUNT(*) AS n FROM objects GROUP BY score",
      "SELECT payload.score, COUNT(*) AS score FROM objects GROUP BY score",
    ] {
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        group_property_context(),
        construction_limits(),
      )
      is Err(InvalidQuery),
      msg=source,
    )
  }
  for
    source in [
      "SELECT payload.score, other.score, COUNT(*) AS n FROM objects GROUP BY payload.score HAVING score > 10",
      "SELECT payload.score, COUNT(*) AS n FROM objects GROUP BY payload.score + 1 HAVING score > 10",
      "SELECT payload.score, COUNT(*) AS n FROM objects AS `current` GROUP BY score HAVING objects.payload.score > 10",
      "SELECT payload.score, COUNT(*) AS n FROM objects GROUP BY score HAVING other.score > 10",
    ] {
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        group_property_context(),
        construction_limits(),
      )
      is Err(Expression({ issue: @expression.UnknownReference, .. })),
      msg=source,
    )
  }
}

///|
test "GROUP HAVING implicit aliases compare implicit object receivers in their own clause scope" {
  let declarations = @parameters.read_declarations(
    Some(
      @wire.admit(
        @source.parse_json(
          (
            #|{"wrapper":{"type":"object","nullable":false,"fields":{"payload":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":true}}}}}}
          ),
          construction_limits().source.source,
        ).unwrap(),
        construction_limits().source.tree,
      ).unwrap(),
    ),
    {
      max_parameters: 10,
      max_nodes: 1000,
      max_depth: 100,
      max_text_bytes: 10000,
    },
  ).unwrap()
  let values = @wire.admit(
    @source.parse_json(
      (
        #|{"wrapper":{"payload":{"score":20}}}
      ),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  for
    (condition, property_count) in [
      ("payload.score + 1 > 12", 3),
      ("objects.payload.score + 1 > 12", 2),
    ] {
    let actual = compile(
      @query.parse_query(
        "SELECT payload.score + 1 AS bucket, (@wrapper).payload, COUNT(*) AS n FROM objects GROUP BY objects.payload.score + 1 HAVING " +
        condition +
        " ORDER BY bucket",
        syntax_limits(),
      ).unwrap(),
      {
        ..group_property_context(),
        parameter_declarations: Some(declarations),
      },
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(
        actual,
        check_environment(),
        Some(values),
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ =>
        fail(
          "the implicit payload alias has a different receiver from the input key",
        )
    }
    let body = semantic(actual)
    assert_eq(body.split("\"property\":").length() - 1, property_count)
    assert_eq(body.split("\"$param\":").length() - 1, 1)
  }
}

///|
fn group_having_collision_bound_cte(
  used_only : Bool,
  qualified : Bool,
) -> (@program.Program, @wire.Cursor) {
  let admitted = text => {
    @wire.admit(
      @source.parse_json(text, construction_limits().source.source).unwrap(),
      construction_limits().source.tree,
    ).unwrap()
  }
  // Preserve the original failed packed input, including its unused fields,
  // independently of the corrected fixture's two used Parameters.
  let declarations = @parameters.read_declarations(
    Some(
      admitted(
        if used_only {
          "{\"a\":{\"type\":\"object\",\"nullable\":true,\"fields\":{\"score\":{\"type\":\"number\",\"nullable\":true}}},\"b\":{\"type\":\"object\",\"nullable\":true,\"fields\":{\"score\":{\"type\":\"number\",\"nullable\":true}}}}"
        } else {
          "{\"a\":{\"type\":\"object\",\"nullable\":true,\"fields\":{\"score\":{\"type\":\"number\",\"nullable\":true}}},\"b\":{\"type\":\"object\",\"nullable\":true,\"fields\":{\"score\":{\"type\":\"number\",\"nullable\":true}}},\"c\":{\"type\":\"object\",\"nullable\":true,\"fields\":{\"score\":{\"type\":\"number\",\"nullable\":true}}},\"d\":{\"type\":\"object\",\"nullable\":true,\"fields\":{\"score\":{\"type\":\"number\",\"nullable\":true}}},\"e\":{\"type\":\"object\",\"nullable\":true,\"fields\":{\"score\":{\"type\":\"number\",\"nullable\":true}}},\"oa\":{\"type\":\"object\",\"nullable\":false,\"fields\":{\"score\":{\"type\":\"number\",\"nullable\":false}}},\"ob\":{\"type\":\"object\",\"nullable\":false,\"fields\":{\"score\":{\"type\":\"number\",\"nullable\":false}}},\"oc\":{\"type\":\"object\",\"nullable\":false,\"fields\":{\"score\":{\"type\":\"number\",\"nullable\":false}}},\"od\":{\"type\":\"object\",\"nullable\":false,\"fields\":{\"score\":{\"type\":\"number\",\"nullable\":false}}},\"oe\":{\"type\":\"object\",\"nullable\":false,\"fields\":{\"score\":{\"type\":\"number\",\"nullable\":false}}}}"
        },
      ),
    ),
    {
      max_parameters: 10,
      max_nodes: 1000,
      max_depth: 100,
      max_text_bytes: 10000,
    },
  ).unwrap()
  let values = admitted(
    if used_only {
      "{\"a\":{\"score\":10},\"b\":{\"score\":20}}"
    } else {
      "{\"a\":{\"score\":10},\"b\":{\"score\":20},\"c\":null,\"d\":{\"score\":20},\"e\":{\"score\":null},\"oa\":{\"score\":100},\"ob\":{\"score\":200},\"oc\":{\"score\":300},\"od\":{\"score\":400},\"oe\":{\"score\":500}}"
    },
  )
  let condition = if qualified { "colliding.score > 10" } else { "score > 10" }
  let program = compile_query_script(
    @query.parse_query_script(
      "WITH colliding AS (SELECT 1 AS id, 100 AS score, @a AS payload UNION ALL SELECT 2 AS id, 0 AS score, @b AS payload) SELECT payload.score, COUNT(*) AS n FROM colliding GROUP BY score, colliding.score HAVING " +
      condition +
      " ORDER BY score",
      syntax_limits(),
    ).unwrap(),
    {
      ..pair_context(),
      inputs: [],
      parameter_declarations: Some(declarations),
    },
    construction_limits(),
  ).unwrap()
  (program, values)
}

///|
test "CTE collision keeps the original unused declaration refusal" {
  let (program, values) = group_having_collision_bound_cte(false, false)
  match
    @check.check_parsed(
      program,
      check_environment(),
      Some(values),
      check_limits(),
    ) {
    Rejected(error) =>
      match @check.diagnostic_cause(error) {
        Source(Identity(References(Usage(UnusedParameter(declaration))))) =>
          assert_eq(declaration.name, "c")
        cause => raise cause
      }
    _ => fail("unused declarations remain invalid across the complete CTE")
  }
}

///|
test "CTE parameter GROUP HAVING checks only its used collision declarations" {
  for qualified in [false, true] {
    let (program, values) = group_having_collision_bound_cte(true, qualified)
    match
      @check.check_parsed(
        program,
        check_environment(),
        Some(values),
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(error) => graph_rows_rejected(error)
      _ =>
        fail("the complete CTE retains its grouped alias and qualified input")
    }
  }
}
