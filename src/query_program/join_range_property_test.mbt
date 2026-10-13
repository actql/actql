///|
fn staged_join_range_property_expected() -> @program.Program {
  // Complete expectation written from the shared JOIN and ordinary property
  // contracts: carry each input once, derive score from the left object, and
  // publish only score. This is never generated from compiler output.
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"aql_chain_source_0","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"payload":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":false}}}},"rows":[{"id":2,"payload":{"score":10}},{"id":1,"payload":{"score":20}},{"id":3,"payload":null}]},"as":"objects"}],"results":{"aql_chain_source_0":{"from":"objects","fields":["id","payload"]}}},{"id":"aql_chain_source_1","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"other":{"type":"object","nullable":false,"fields":{"score":{"type":"number","nullable":false}}}},"rows":[{"id":1,"other":{"score":5}},{"id":2,"other":{"score":30}},{"id":3,"other":{"score":15}}]},"as":"others"}],"results":{"aql_chain_source_1":{"from":"others","fields":["id","other"]}}},{"id":"main","inputs":{"aql_chain_input_0":{"result":{"stage":"aql_chain_source_0","result":"aql_chain_source_0"}},"aql_chain_input_1":{"result":{"stage":"aql_chain_source_1","result":"aql_chain_source_1"}}},"steps":[{"from":"aql_chain_input_0","join":{"with":"aql_chain_input_1","kind":"inner","on":[{"left":"id","right":"id"}],"max_output_rows":9,"select":{"aql_chain_column_2":"left.id","aql_chain_column_3":"left.payload","aql_chain_column_4":"right.id","aql_chain_column_5":"right.other"}},"as":"aql_chain_join_2"},{"from":"aql_chain_join_2","derive":{"aql_pipe_expr_4":{"property":{"value":{"field":"aql_chain_column_3"},"name":"score"}}}},{"select":[{"score":"aql_pipe_expr_4"}],"as":"aql_chain_result_3"}],"results":{"rows":{"from":"aql_chain_result_3","fields":["score"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
// Complete current topology from the original typed Values/property contracts.
// Receiver fields, nullable payloads, guards and public projection are unchanged.
fn join_range_property_expected() -> @program.Program raise {
  check_join_property(staged_join_range_property_expected())
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"payload":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":false}}}},"rows":[{"id":2,"payload":{"score":10}},{"id":1,"payload":{"score":20}},{"id":3,"payload":null}]},"as":"aql_script_seed_2"},{"values":{"schema":{"id":{"type":"number","nullable":false},"other":{"type":"object","nullable":false,"fields":{"score":{"type":"number","nullable":false}}}},"rows":[{"id":1,"other":{"score":5}},{"id":2,"other":{"score":30}},{"id":3,"other":{"score":15}}]},"as":"aql_script_seed_3"},{"from":"aql_script_seed_2","join":{"with":"aql_script_seed_3","kind":"inner","on":[{"left":"id","right":"id"}],"max_output_rows":9,"select":{"aql_chain_column_2":"left.id","aql_chain_column_3":"left.payload","aql_chain_column_4":"right.id","aql_chain_column_5":"right.other"}},"as":"aql_chain_join_4"},{"from":"aql_chain_join_4","derive":{"aql_pipe_expr_4":{"property":{"value":{"field":"aql_chain_column_3"},"name":"score"}}}},{"select":[{"score":"aql_pipe_expr_4"}],"as":"aql_chain_result_5"}],"results":{"rows":{"from":"aql_chain_result_5","fields":["score"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
fn checked_join_range_property(text : String) -> String raise {
  let query = @query.parse_query(text, syntax_limits()).unwrap()
  let program = compile(query, join_property_context(), construction_limits()).unwrap()
  check_join_property(program)
  let scripted = compile_query_script(
    @query.single_query_script(query),
    join_property_context(),
    construction_limits(),
  ).unwrap()
  check_join_property(scripted)
  semantic(program)
}

///|
test "JOIN range properties have an independently checked common control" {
  check_join_property(join_property_expected())
  check_join_property(join_range_property_expected())
  ignore(
    checked_join_range_property(
      "SELECT l.payload.score FROM objects AS l JOIN others AS r ON l.id = r.id",
    ),
  )
}

///|
test "JOIN SELECT binds parenthesized range properties through the existing row scope" {
  for
    text in [
      "SELECT ((l)).payload.score FROM objects AS l JOIN others AS r ON l.id = r.id MAX_OUTPUT_ROWS 9",
      "FROM objects AS l |> JOIN others AS r ON l.id = r.id MAX_OUTPUT_ROWS 9 |> SELECT ((l)).payload.score",
      "SELECT ((`L`)).`payload`.score FROM objects AS `l` JOIN others AS r ON `l`.id = r.id MAX_OUTPUT_ROWS 9",
    ] {
    let body = checked_join_range_property(text)
    assert_eq(body, semantic(join_range_property_expected()))
    assert_true(body.contains("\"name\":\"score\""))
    assert_true(body.contains("\"fields\":[\"score\"]"))
  }
}

///|
test "JOIN WHERE preserves parenthesized input range and nullable property" {
  let body = checked_join_range_property(
    "SELECT l.id, r.other AS payload FROM objects AS l JOIN others AS r ON l.id = r.id WHERE ((l)).payload.score > 15 ORDER BY payload.score",
  )
  assert_true(body.contains("\"filter\":{\"gt\""))
  assert_true(body.contains("\"fields\":[\"id\",\"payload\"]"))
}

///|
test "JOIN ORDER distinguishes parenthesized input range from the output receiver" {
  let body = checked_join_range_property(
    "SELECT l.id, l.payload.score AS original_score, r.other AS payload FROM objects AS l JOIN others AS r ON l.id = r.id ORDER BY ((l)).payload.score NULLS LAST",
  )
  assert_true(
    body.contains("\"fields\":[\"id\",\"original_score\",\"payload\"]"),
  )
}

///|
test "JOIN range-name collision retains range precedence through parentheses" {
  let scoped = pipe_range_property_context()
  let context = {
    ..join_property_context(),
    inputs: scoped.inputs + [join_property_context().inputs[1]],
  }
  let actual = compile(
    @query.parse_query(
      "SELECT (payload).score AS parenthesized_score, payload.score AS range_score FROM objects AS payload JOIN others AS r ON payload.id = r.id",
      syntax_limits(),
    ).unwrap(),
    context,
    construction_limits(),
  ).unwrap()
  check_join_property(actual)
  let body = semantic(actual)
  assert_false(body.contains("\"property\":{\"name\":\"score\""))
  assert_true(
    body.contains("\"fields\":[\"parenthesized_score\",\"range_score\"]"),
  )
}

///|
test "JOIN range properties retain precise unknown-range and work refusals" {
  let removed = @query.parse_query(
    "SELECT DISTINCT l.id FROM objects AS l JOIN others AS r ON l.id = r.id MAX_OUTPUT_ROWS 12 ORDER BY payload.score",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(removed, join_property_context(), construction_limits())
    is Err(InvalidQuery),
  )
  assert_true(
    compile_query_script(
      @query.single_query_script(removed),
      join_property_context(),
      construction_limits(),
    )
    is Err(InvalidQuery),
  )
  let query = @query.parse_query(
    "SELECT ((l)).missing AS value FROM objects AS l JOIN others AS r ON l.id = r.id",
    syntax_limits(),
  ).unwrap()
  // The ordinary row receiver exists. Its missing property is a common
  // closed-object typing failure, not an unresolved range name.
  for
    p in [
      compile(query, join_property_context(), construction_limits()).unwrap(),
      compile_query_script(
        @query.single_query_script(query),
        join_property_context(),
        construction_limits(),
      ).unwrap(),
    ] {
    guard @check.check_parsed(p, check_environment(), None, check_limits())
      is Rejected(issue) else {
      fail("unknown joined row property accepted")
    }
    assert_true(
      @check.diagnostic_cause(issue)
      is Source(
        SourceView(
          Program(
            Program(
              Pipeline(
                _,
                { kind: Operation(Expression(UnknownField("missing"))), .. }
              )
            )
          )
        )
      ),
    )
  }
  let bounded = @query.parse_query(
    "SELECT ((l)).payload.score FROM objects AS l JOIN others AS r ON l.id = r.id",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(bounded, join_property_context(), {
      ..construction_limits(),
      max_expression_work: 1,
    })
    is Err(Expression({ issue: WorkLimit, origin: Some(_), })),
  )
}

///|
test "JOIN scoped ORDER binds a parenthesized current range without reviving an old range" {
  ignore(
    checked_join_range_property(
      "FROM objects AS l |> JOIN others AS r ON l.id = r.id |> SELECT l.id, l.payload |> AS `current` |> ORDER BY ((current)).payload.score NULLS LAST",
    ),
  )
  let query = @query.parse_query(
    "FROM objects AS l |> JOIN others AS r ON l.id = r.id |> SELECT l.id, l.payload |> AS `current` |> ORDER BY ((l)).payload.score NULLS LAST",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(query, join_property_context(), construction_limits())
    is Err(Expression({ issue: UnknownReference, origin: Some(_), })),
  )
}

///|
test "ordinary scoped ORDER uses the same existing range-property binder" {
  let actual = compile(
    @query.parse_query(
      "FROM pair |> AS `current` |> ORDER BY ((current)).x + 1 |> SELECT current.x",
      syntax_limits(),
    ).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
  check_join_property(actual)
  assert_true(
    semantic(actual).contains("\"add\":[{\"field\":\"x\"},{\"literal\":1}]"),
  )
  assert_true(semantic(actual).contains("\"fields\":[\"x\"]"))
}

///|
test "CTE current-range property ORDER retains ordinary Relation scope" {
  let declarations = @parameters.read_declarations(
    Some(
      @wire.admit(
        @source.parse_json(
          (
            #|{"a":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":false}}},"b":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":false}}},"c":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":false}}},"oa":{"type":"object","nullable":false,"fields":{"score":{"type":"number","nullable":false}}},"ob":{"type":"object","nullable":false,"fields":{"score":{"type":"number","nullable":false}}},"oc":{"type":"object","nullable":false,"fields":{"score":{"type":"number","nullable":false}}},"od":{"type":"object","nullable":false,"fields":{"score":{"type":"number","nullable":false}}}}
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
  let query = @query.parse_query(
    "WITH seed AS (SELECT 1 AS unit), objects AS (SELECT 2 AS id, @a AS payload FROM seed UNION ALL SELECT 1 AS id, @b AS payload FROM seed UNION ALL SELECT 3 AS id, @c AS payload FROM seed), others AS (SELECT 1 AS id, @oa AS other FROM seed UNION ALL SELECT 2 AS id, @ob AS other FROM seed UNION ALL SELECT 3 AS id, @oc AS other FROM seed UNION ALL SELECT 2 AS id, @od AS other FROM seed) FROM objects |> AS `current` |> ORDER BY ((current)).payload.score NULLS LAST |> SELECT current.id AS id, current.payload.score AS score",
    syntax_limits(),
  ).unwrap()
  let context = {
    ..join_property_context(),
    parameter_declarations: Some(declarations),
  }
  // Static-check the unused peer but keep it out of execution demand. Its
  // object parameters must not leak into the evaluated current-range ORDER.
  let with_unused = compile(query, context, construction_limits()).unwrap()
  let body = semantic(with_unused)
  assert_true(body.contains("\"fields\":[\"id\",\"score\"]"))
  for parameter in ["oa", "ob", "oc", "od"] {
    assert_false(body.contains("\"parameter\":\"" + parameter + "\""))
  }
  match
    @check.check_parsed(with_unused, check_environment(), None, check_limits()) {
    NeedsInputs(_) => ()
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    _ => fail("the original object parameters remain required")
  }
  let used = @query.parse_query(
    "WITH seed AS (SELECT 1 AS unit), objects AS (SELECT 2 AS id, @a AS payload FROM seed UNION ALL SELECT 1 AS id, @b AS payload FROM seed UNION ALL SELECT 3 AS id, @c AS payload FROM seed) FROM objects |> AS `current` |> ORDER BY ((current)).payload.score NULLS LAST |> SELECT current.id AS id, current.payload.score AS score",
    syntax_limits(),
  ).unwrap()
  match compile(used, context, construction_limits()) {
    Ok(program) =>
      assert_true(semantic(program).contains("\"fields\":[\"id\",\"score\"]"))
    Err(UnsupportedOrdering) =>
      fail("CTE current-range ORDER: UnsupportedOrdering")
    Err(UnsupportedProjection) =>
      fail("CTE current-range ORDER: UnsupportedProjection")
    Err(UnsupportedCte) => fail("CTE current-range ORDER: UnsupportedCte")
    Err(Expression(_)) => fail("CTE current-range ORDER: Expression")
    Err(ExpressionTyping(_)) =>
      fail("CTE current-range ORDER: ExpressionTyping")
    Err(_) => fail("CTE current-range ORDER: other issue")
  }
}
