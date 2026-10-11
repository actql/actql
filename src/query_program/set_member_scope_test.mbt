///|
fn set_member_control(operation : String) -> @program.Program {
  // Hand-authored common JSON: complete rows are compared before projection.
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"payload":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":false}}}},"rows":[{"id":2,"payload":{"score":10}},{"id":1,"payload":{"score":20}},{"id":3,"payload":null}]},"as":"objects"},{"from":"objects","filter":{"not":{"eq":[{"field":"id"},{"literal":1}]}}},{"select":["id","payload"],"as":"right"},{"from":"objects","select":["id","payload"],"as":"left"},{"from":"left",
    ) +
    "\"" +
    operation +
    "\":" +
    (
      #|{"with":"right","duplicates":"distinct"}},{"derive":{"score":{"property":{"value":{"field":"payload"},"name":"score"}}}},{"select":["id","score"]},{"sort":[{"field":"id","dir":"asc","nulls":"first"}],"as":"ordered"}],"results":{"rows":{"from":"ordered","fields":["id","score"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "INTERSECT and EXCEPT object projections have independently checked controls" {
  for operation in ["intersect", "except"] {
    member_case_require_checked(
      set_member_control(operation),
      "independent " + operation,
    )
  }
}

///|
test "CTE set outputs keep declared object member spelling" {
  for operation in ["INTERSECT", "EXCEPT"] {
    let text = "WITH chosen AS (SELECT id, payload FROM objects " +
      operation +
      " DISTINCT SELECT id, payload FROM objects WHERE id <> 1) SELECT id, payload.SCORE AS score FROM chosen ORDER BY id"
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      analytic_property_context(),
      construction_limits(),
    ).unwrap()
    member_case_require_checked(actual, "retained " + operation + " member")
    assert_true(semantic(actual).contains("\"name\":\"score\""))
    assert_false(semantic(actual).contains("\"name\":\"SCORE\""))
  }
}

///|
test "WITH set outputs keep declared object member spelling" {
  for operation in ["INTERSECT", "EXCEPT"] {
    let text = "WITH chosen AS (FROM objects |> SELECT id, payload |> " +
      operation +
      " DISTINCT (FROM objects |> WHERE id <> 1 |> SELECT id, payload)) FROM chosen |> SELECT id, payload.SCORE AS score |> ORDER BY id"
    let actual = compile_query_script(
      @query.parse_query_script(text, syntax_limits()).unwrap(),
      analytic_property_context(),
      construction_limits(),
    ).unwrap()
    member_case_require_checked(actual, "WITH " + operation + " member")
    assert_true(semantic(actual).contains("\"name\":\"score\""))
    assert_false(semantic(actual).contains("\"name\":\"SCORE\""))
  }
}
