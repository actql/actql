///|
// Text sources and parameter values come from the independently authored
// public fixture. Its external-Source JSON controls run in the real packed Host;
// this local Values context checks the exact source text and parameter handoff.
fn set_member_public_cursor(text : String) -> @wire.Cursor {
  @wire.admit(
    @source.parse_json(text, construction_limits().source.source).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
}

///|
test "public set member text sources keep declared parameters" {
  let declarations = @parameters.read_declarations(
    Some(
      set_member_public_cursor(
        "{\"p1\":{\"type\":\"object\",\"nullable\":true,\"fields\":{\"score\":{\"type\":\"number\",\"nullable\":true},\"nested\":{\"type\":\"object\",\"nullable\":true,\"fields\":{\"score\":{\"type\":\"number\",\"nullable\":true}}}}},\"p2\":{\"type\":\"object\",\"nullable\":true,\"fields\":{\"score\":{\"type\":\"number\",\"nullable\":true},\"nested\":{\"type\":\"object\",\"nullable\":true,\"fields\":{\"score\":{\"type\":\"number\",\"nullable\":true}}}}},\"p3\":{\"type\":\"object\",\"nullable\":true,\"fields\":{\"score\":{\"type\":\"number\",\"nullable\":true},\"nested\":{\"type\":\"object\",\"nullable\":true,\"fields\":{\"score\":{\"type\":\"number\",\"nullable\":true}}}}},\"p4\":{\"type\":\"object\",\"nullable\":true,\"fields\":{\"score\":{\"type\":\"number\",\"nullable\":true},\"nested\":{\"type\":\"object\",\"nullable\":true,\"fields\":{\"score\":{\"type\":\"number\",\"nullable\":true}}}}},\"o1\":{\"type\":\"object\",\"nullable\":false,\"fields\":{\"score\":{\"type\":\"number\",\"nullable\":true},\"nested\":{\"type\":\"object\",\"nullable\":true,\"fields\":{\"score\":{\"type\":\"number\",\"nullable\":true}}}}},\"o2\":{\"type\":\"object\",\"nullable\":false,\"fields\":{\"score\":{\"type\":\"number\",\"nullable\":true},\"nested\":{\"type\":\"object\",\"nullable\":true,\"fields\":{\"score\":{\"type\":\"number\",\"nullable\":true}}}}},\"o3\":{\"type\":\"object\",\"nullable\":false,\"fields\":{\"score\":{\"type\":\"number\",\"nullable\":true},\"nested\":{\"type\":\"object\",\"nullable\":true,\"fields\":{\"score\":{\"type\":\"number\",\"nullable\":true}}}}},\"o4\":{\"type\":\"object\",\"nullable\":false,\"fields\":{\"score\":{\"type\":\"number\",\"nullable\":true},\"nested\":{\"type\":\"object\",\"nullable\":true,\"fields\":{\"score\":{\"type\":\"number\",\"nullable\":true}}}}}}",
      ),
    ),
    {
      max_parameters: 20,
      max_nodes: 1000,
      max_depth: 100,
      max_text_bytes: 10000,
    },
  ).unwrap()
  let values = set_member_public_cursor(
    "{\"p1\":{\"score\":20,\"nested\":{\"score\":11}},\"p2\":{\"score\":10,\"nested\":null},\"p3\":null,\"p4\":{\"score\":null,\"nested\":{\"score\":null}},\"o1\":{\"score\":5,\"nested\":null},\"o2\":{\"score\":30,\"nested\":{\"score\":22}},\"o3\":{\"score\":15,\"nested\":{\"score\":33}},\"o4\":{\"score\":25,\"nested\":null}}",
  )
  let context = {
    ..pair_context(),
    parameter_declarations: Some(declarations),
    inputs: [
      {
        relation: [{ value: "records", quoted: false, }],
        name: "records",
        source: GeneratedValues(
          set_member_public_cursor(
            "{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"amount\":{\"type\":\"number\",\"nullable\":true}},\"rows\":[{\"id\":2,\"amount\":10},{\"id\":1,\"amount\":20},{\"id\":3,\"amount\":null},{\"id\":4,\"amount\":40},{\"id\":2,\"amount\":10},{\"id\":0,\"amount\":99}]},\"as\":\"records\"}",
          ),
        ),
        visible_fields: ["id", "amount"],
        graph_bindings: [],
      },
    ],
  }
  let actual = compile_query_script(
    @query.parse_query_script(
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0), chosen AS (SELECT id, payload FROM objects INTERSECT DISTINCT SELECT id, payload FROM objects WHERE id <> 1) SELECT id, payload.SCORE AS score FROM chosen ORDER BY id",
      syntax_limits(),
    ).unwrap(),
    context,
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
        "computed-object-property-set-intersect-cte: ordinary checking must close",
      )
  }
  assert_true(semantic(actual).contains("\"name\":\"score\""))
  assert_false(semantic(actual).contains("\"name\":\"SCORE\""))
  let actual = compile_query_script(
    @query.parse_query_script(
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0), chosen AS (FROM objects |> SELECT id, payload |> INTERSECT DISTINCT (FROM objects |> WHERE id <> 1 |> SELECT id, payload)) FROM chosen |> SELECT id, payload.`SCORE` AS score |> ORDER BY id",
      syntax_limits(),
    ).unwrap(),
    context,
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
        "computed-object-property-set-intersect-data-quoted: ordinary checking must close",
      )
  }
  assert_true(semantic(actual).contains("\"name\":\"score\""))
  assert_false(semantic(actual).contains("\"name\":\"SCORE\""))
  let actual = compile_query_script(
    @query.parse_query_script(
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0), chosen AS (SELECT id, payload FROM objects EXCEPT DISTINCT SELECT id, payload FROM objects WHERE id <> 1) SELECT id, payload.SCORE AS score FROM chosen ORDER BY id",
      syntax_limits(),
    ).unwrap(),
    context,
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
        "computed-object-property-set-except-cte: ordinary checking must close",
      )
  }
  assert_true(semantic(actual).contains("\"name\":\"score\""))
  assert_false(semantic(actual).contains("\"name\":\"SCORE\""))
  let actual = compile_query_script(
    @query.parse_query_script(
      "WITH objects AS (SELECT id, CASE WHEN id = 1 THEN @p1 WHEN id = 2 THEN @p2 WHEN id = 3 THEN @p3 ELSE @p4 END AS payload, CASE WHEN id = 1 THEN @o1 WHEN id = 2 THEN @o2 WHEN id = 3 THEN @o3 ELSE @o4 END AS other FROM records WHERE id > 0), chosen AS (FROM objects |> SELECT id, payload |> EXCEPT DISTINCT (FROM objects |> WHERE id <> 1 |> SELECT id, payload)) FROM chosen |> SELECT id, payload.`SCORE` AS score |> ORDER BY id",
      syntax_limits(),
    ).unwrap(),
    context,
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
        "computed-object-property-set-except-data-quoted: ordinary checking must close",
      )
  }
  assert_true(semantic(actual).contains("\"name\":\"score\""))
  assert_false(semantic(actual).contains("\"name\":\"SCORE\""))
}
