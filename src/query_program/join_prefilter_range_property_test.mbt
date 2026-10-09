///|
test "CTE JOIN prefilter retains ordinary dotted property control" {
  let text = "WITH lefts AS (SELECT id, payload FROM objects), rights AS (SELECT id, other FROM others) FROM lefts AS l |> WHERE l.payload.score > 15 |> JOIN rights AS r ON l.id = r.id MAX_OUTPUT_ROWS 12 |> SELECT l.id, r.other.score |> ORDER BY id"
  let query = @query.parse_query(text, syntax_limits()).unwrap()
  for
    program in [
      compile(query, join_property_context(), construction_limits()).unwrap(),
      compile_query_script(
        @query.single_query_script(query),
        join_property_context(),
        construction_limits(),
      ).unwrap(),
    ] {
    check_join_property(program)
    assert_true(semantic(program).contains("\"max_output_rows\":12"))
    assert_true(semantic(program).contains("\"filter\":{\"gt\""))
  }
}

///|
test "CTE JOIN prefilter connects parenthesized range properties" {
  let text = "WITH lefts AS (SELECT id, payload FROM objects), rights AS (SELECT id, other FROM others) FROM lefts AS l |> WHERE ((l)).payload.score > 15 |> JOIN rights AS r ON l.id = r.id MAX_OUTPUT_ROWS 12 |> SELECT l.id, r.other.score |> ORDER BY id"
  let query = @query.parse_query(text, syntax_limits()).unwrap()
  for
    program in [
      compile(query, join_property_context(), construction_limits()).unwrap(),
      compile_query_script(
        @query.single_query_script(query),
        join_property_context(),
        construction_limits(),
      ).unwrap(),
    ] {
    check_join_property(program)
    assert_true(semantic(program).contains("\"max_output_rows\":12"))
    assert_true(semantic(program).contains("\"filter\":{\"gt\""))
    assert_true(
      semantic(program).contains(
        "\"filter\":{\"gt\":[{\"property\":{\"name\":\"score\",\"value\":{\"field\":\"payload\"}}},{\"literal\":15}]}",
      ),
    )
    assert_true(
      semantic(program).contains("\"on\":[{\"left\":\"id\",\"right\":\"id\"}]"),
    )
  }
}

///|
test "prefilter has an independently checked ordinary JSON control" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.prefilter_property","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"payload":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":false}}}},"rows":[{"id":2,"payload":{"score":10}},{"id":1,"payload":{"score":20}},{"id":3,"payload":null}]},"as":"objects"},{"values":{"schema":{"id":{"type":"number","nullable":false},"other":{"type":"object","nullable":false,"fields":{"score":{"type":"number","nullable":false}}}},"rows":[{"id":1,"other":{"score":5}},{"id":2,"other":{"score":30}},{"id":3,"other":{"score":15}}]},"as":"others"},{"from":"objects","filter":{"gt":[{"property":{"value":{"field":"payload"},"name":"score"}},{"literal":15}]},"as":"filtered"},{"from":"filtered","join":{"with":"others","kind":"inner","on":[{"left":"id","right":"id"}],"max_output_rows":1,"select":{"id":"left.id","other":"right.other"}},"as":"matched"},{"from":"matched","derive":{"score":{"property":{"value":{"field":"other"},"name":"score"}}}},{"select":["id","score"]},{"sort":[{"field":"id","dir":"asc","nulls":"first"}],"as":"ordered"}],"results":{"rows":{"from":"ordered","fields":["id","score"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  check_join_property(expected)
}

///|
test "prefilter quoted range parameter and authored JOIN ceiling are retained" {
  let query = @query.parse_query(
    "WITH lefts AS (SELECT id, payload FROM objects), rights AS (SELECT id, other FROM others) FROM lefts AS l |> WHERE ((`L`)).`payload`.score > @p |> JOIN rights AS r ON l.id = r.id MAX_OUTPUT_ROWS 1 |> SELECT l.id, r.other.score",
    syntax_limits(),
  ).unwrap()
  let context = {
    ..join_property_context(),
    parameter_declarations: Some(number_parameter_declarations()),
  }
  let actual = compile(query, context, construction_limits()).unwrap()
  let supplied = @wire.admit(
    @source.parse_json("{\"p\":15}", construction_limits().source.source).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  assert_true(
    @check.check_parsed(
      actual,
      check_environment(),
      Some(supplied),
      check_limits(),
    )
    is Checked(_),
  )
  let body = semantic(actual)
  assert_true(body.contains("\"$param\":\"p\""))
  assert_true(body.contains("\"max_output_rows\":1"))
}

///|
test "prefilter value receiver wins its same-named range without inventing a peer" {
  let text = "WITH lefts AS (SELECT id, payload, 90 AS score FROM objects), rights AS (SELECT id, other FROM others) FROM lefts AS payload |> WHERE (payload).score > 15 |> JOIN rights AS r ON payload.id = r.id MAX_OUTPUT_ROWS 12 |> SELECT payload.id, r.other.score"
  let actual = compile(
    @query.parse_query(text, syntax_limits()).unwrap(),
    join_property_context(),
    construction_limits(),
  ).unwrap()
  check_join_property(actual)
  assert_true(semantic(actual).contains("\"value\":{\"field\":\"payload\"}"))
  let future = @query.parse_query(
    "WITH lefts AS (SELECT id, payload FROM objects), rights AS (SELECT id, other FROM others) FROM lefts AS l |> WHERE ((r)).other.score > 0 |> JOIN rights AS r ON l.id = r.id MAX_OUTPUT_ROWS 12 |> SELECT l.id",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(future, join_property_context(), construction_limits())
    is Err(Expression({ issue: UnknownReference, origin: Some(_), })),
  )
}
