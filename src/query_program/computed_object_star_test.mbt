///|
fn computed_star_context() -> Context {
  let seed = unnest_value_cursor(
    (
      #|{"values":{"schema":{"id":{"type":"number","nullable":false},"payload":{"type":"object","nullable":true,"fields":{"alpha":{"type":"number","nullable":false},"beta":{"type":"string","nullable":false}}},"other":{"type":"object","nullable":false,"fields":{"alpha":{"type":"number","nullable":false},"beta":{"type":"string","nullable":false}}}},"rows":[{"id":2,"payload":{"alpha":10,"beta":"b"},"other":{"alpha":30,"beta":"y"}},{"id":1,"payload":{"alpha":20,"beta":"a"},"other":{"alpha":5,"beta":"x"}},{"id":3,"payload":null,"other":{"alpha":15,"beta":"z"}}]},"as":"objects"}
    ),
  )
  {
    ..analytic_property_context(),
    inputs: [
      {
        relation: [{ value: "objects", quoted: false, }],
        name: "objects",
        source: GeneratedValues(seed),
        visible_fields: ["id", "payload", "other"],
        graph_bindings: [],
      },
    ],
  }
}

///|
// This independently authored control evaluates the receiver once, then reads
// its two fields through ordinary nullable property expressions.
fn computed_star_control() -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"payload":{"type":"object","nullable":true,"fields":{"alpha":{"type":"number","nullable":false},"beta":{"type":"string","nullable":false}}},"other":{"type":"object","nullable":false,"fields":{"alpha":{"type":"number","nullable":false},"beta":{"type":"string","nullable":false}}}},"rows":[{"id":2,"payload":{"alpha":10,"beta":"b"},"other":{"alpha":30,"beta":"y"}},{"id":1,"payload":{"alpha":20,"beta":"a"},"other":{"alpha":5,"beta":"x"}},{"id":3,"payload":null,"other":{"alpha":15,"beta":"z"}}]},"as":"objects"},{"from":"objects","derive":{"aql_computed_star_0":{"case":{"when":[{"when":{"eq":[{"field":"id"},{"literal":2}]},"then":{"field":"other"}}],"else":{"field":"payload"}}}}},{"derive":{"aql_query_expr_1":{"property":{"value":{"field":"aql_computed_star_0"},"name":"alpha"}},"aql_query_expr_2":{"property":{"value":{"field":"aql_computed_star_0"},"name":"beta"}}}},{"select":["id",{"alpha":"aql_query_expr_1"},{"beta":"aql_query_expr_2"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["id","alpha","beta"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "computed object star control uses one common receiver and nullable fields" {
  assert_true(
    @check.check_parsed(
      computed_star_control(),
      check_environment(),
      None,
      check_limits(),
    )
    is Checked(_),
  )
}

///|
test "computed object star source matches an independent evaluated receiver Program" {
  let query = @query.parse_query(
    "SELECT id, (CASE WHEN id = 2 THEN other ELSE payload END).* FROM objects",
    syntax_limits(),
  ).unwrap()
  let actual = compile(query, computed_star_context(), construction_limits()).unwrap()
  assert_eq(semantic(actual), semantic(computed_star_control()))
}

///|
test "computed object star keeps Pipe scope grouped keys and evaluated ORDER slots" {
  for
    text in [
      "FROM objects |> SELECT id, (CASE WHEN id = 2 THEN other ELSE payload END).* |> ORDER BY id",
      "SELECT id, COALESCE(payload, other).* FROM objects ORDER BY alpha", "FROM objects old |> SET payload = other |> SELECT id, COALESCE(payload, old.payload).*",
      "SELECT DISTINCT (CASE WHEN id = 2 THEN other ELSE payload END).* FROM objects ORDER BY beta, alpha",
      "SELECT (CASE WHEN id = 2 THEN other ELSE payload END).*, COUNT(*) AS n FROM objects GROUP BY (CASE WHEN id = 2 THEN other ELSE payload END).alpha, (CASE WHEN id = 2 THEN other ELSE payload END).beta ORDER BY alpha",
      "SELECT id, (payload).* EXCEPT (beta) REPLACE (id + 1 AS alpha) FROM objects",
      "SELECT id, COALESCE(payload, other).* FROM objects ORDER BY COALESCE(payload, other).alpha",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      computed_star_context(),
      construction_limits(),
    ).unwrap()
    assert_true(
      @check.check_parsed(actual, check_environment(), None, check_limits())
      is Checked(_),
      msg=text,
    )
    assert_false(semantic(actual).contains("aql_object_star_probe_"))
  }
}

///|
test "computed object star retains scalar scope and replacement refusals" {
  assert_true(
    compile(
      @query.parse_query("SELECT (id).* FROM objects", syntax_limits()).unwrap(),
      computed_star_context(),
      construction_limits(),
    )
    is Err(UnsupportedProjection),
  )
  assert_true(
    compile(
      @query.parse_query(
        "SELECT (payload).* EXCEPT (missing) FROM objects",
        syntax_limits(),
      ).unwrap(),
      computed_star_context(),
      construction_limits(),
    )
    is Err(UnknownColumn),
  )
  assert_true(
    compile(
      @query.parse_query(
        "SELECT (payload).* REPLACE (1 AS alpha, 2 AS ALPHA) FROM objects",
        syntax_limits(),
      ).unwrap(),
      computed_star_context(),
      construction_limits(),
    )
    is Err(DuplicateOutput),
  )
  assert_true(
    compile(
      @query.parse_query(
        "FROM objects old |> AS current |> SELECT COALESCE(old.payload, other).*",
        syntax_limits(),
      ).unwrap(),
      computed_star_context(),
      construction_limits(),
    )
    is Err(Expression({ issue: @expression.UnknownReference, .. })),
  )
  let query = @query.parse_query(
    "SELECT COALESCE(payload, other).* FROM objects",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(query, computed_star_context(), {
      ..construction_limits(),
      max_expression_work: 2,
    })
    is Err(Expression({ issue: WorkLimit, .. })),
  )
}
