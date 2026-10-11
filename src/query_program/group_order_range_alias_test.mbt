///|
fn group_order_range_alias_declarations() -> @parameters.Declarations {
  let cursor = @wire.admit(
    @source.parse_json(
      (
        #|{"low":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":true}}},"high":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":true}}},"nil":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":true}}}}
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
fn group_order_range_alias_values() -> @wire.Cursor {
  @wire.admit(
    @source.parse_json(
      (
        #|{"low":{"score":30},"high":{"score":5},"nil":null}
      ),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
}

///|
fn group_order_range_alias_context() -> Context {
  let seed = @wire.admit(
    @source.parse_json(
      (
        #|{"values":{"schema":{"score":{"type":"number","nullable":true}},"rows":[{"score":10},{"score":20},{"score":10},{"score":null}]},"as":"objects"}
      ),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  {
    ..pair_context(),
    parameter_declarations: Some(group_order_range_alias_declarations()),
    inputs: [
      {
        relation: [{ value: "objects", quoted: false, }],
        name: "objects",
        source: GeneratedValues(seed),
        visible_fields: ["score"],
        graph_bindings: [],
      },
    ],
  }
}

///|
fn group_order_range_alias_source(order : String) -> String {
  "SELECT score AS bucket, CASE WHEN score IS NULL THEN @nil WHEN score = 10 THEN @low ELSE @high END AS payload, COUNT(*) AS n FROM objects AS payload GROUP BY score ORDER BY " +
  order
}

///|
fn group_order_range_alias_expected() -> @program.Program {
  // Authored from evaluated alias slots and ordinary property/sort contracts.
  // The old range's score cannot supply this ORDER receiver.
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","params":{"low":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":true}}},"high":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":true}}},"nil":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":true}}}},"stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"score":{"type":"number","nullable":true}},"rows":[{"score":10},{"score":20},{"score":10},{"score":null}]},"as":"objects"},{"from":"objects","group":{"by":["score"],"aggregates":{"n":{"fn":"count"}}}},{"derive":{"aql_query_expr_1":{"case":{"when":[{"when":{"is_null":{"field":"score"}},"then":{"$param":"nil"}},{"when":{"eq":[{"field":"score"},{"literal":10}]},"then":{"$param":"low"}}],"else":{"$param":"high"}}}}},{"derive":{"aql_query_sort_5":{"property":{"name":"score","value":{"field":"aql_query_expr_1"}}}}},{"sort":[{"field":"aql_query_sort_5","dir":"asc","nulls":"last"}]},{"select":[{"bucket":"score"},{"payload":"aql_query_expr_1"},"n"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["bucket","payload","n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "GROUP ORDER alias receiver shadows a same-named range in a complete independent Program" {
  let expected = group_order_range_alias_expected()
  assert_true(
    @check.check_parsed(
      expected,
      check_environment(),
      Some(group_order_range_alias_values()),
      check_limits(),
    )
    is Checked(_),
  )
  for
    order in [
      "payload.score NULLS LAST", "(payload).score NULLS LAST", "`PAYLOAD`.`ScOrE` NULLS LAST",
    ] {
    let actual = compile(
      @query.parse_query(group_order_range_alias_source(order), syntax_limits()).unwrap(),
      group_order_range_alias_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected), msg=order)
    assert_true(
      @check.check_parsed(
        actual,
        check_environment(),
        Some(group_order_range_alias_values()),
        check_limits(),
      )
      is Checked(_),
      msg=order,
    )
  }
}

///|
test "GROUP ORDER preserves a nonshadowed range and rejects missing alias properties" {
  let source = group_order_range_alias_source("original.score NULLS LAST").replace(
    "objects AS payload",
    new="objects AS original",
  )
  let actual = compile(
    @query.parse_query(source, syntax_limits()).unwrap(),
    group_order_range_alias_context(),
    construction_limits(),
  ).unwrap()
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","params":{"low":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":true}}},"high":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":true}}},"nil":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":true}}}},"stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"score":{"type":"number","nullable":true}},"rows":[{"score":10},{"score":20},{"score":10},{"score":null}]},"as":"objects"},{"from":"objects","group":{"by":["score"],"aggregates":{"n":{"fn":"count"}}}},{"derive":{"aql_query_expr_1":{"case":{"when":[{"when":{"is_null":{"field":"score"}},"then":{"$param":"nil"}},{"when":{"eq":[{"field":"score"},{"literal":10}]},"then":{"$param":"low"}}],"else":{"$param":"high"}}}}},{"sort":[{"field":"score","dir":"asc","nulls":"last"}]},{"select":[{"bucket":"score"},{"payload":"aql_query_expr_1"},"n"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["bucket","payload","n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
  let missing = compile(
    @query.parse_query(
      group_order_range_alias_source("payload.missing NULLS LAST"),
      syntax_limits(),
    ).unwrap(),
    group_order_range_alias_context(),
    construction_limits(),
  ).unwrap()
  assert_true(
    @check.check_parsed(
      missing,
      check_environment(),
      Some(group_order_range_alias_values()),
      check_limits(),
    )
    is Rejected(_),
  )
}
