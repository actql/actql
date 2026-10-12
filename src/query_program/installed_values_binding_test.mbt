///|
fn installed_values_collision_context(first : Int) -> Context {
  let seed = @wire.admit(
    @source.parse_json(
      "{\"as\":\"aql_source_free\",\"values\":{\"schema\":{\"a\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"a\":" +
      first.to_string() +
      "},{\"a\":" +
      (first + 1).to_string() +
      "}]}}",
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  {
    ..fixture_context(),
    inputs: [
      {
        relation: [{ value: "supplied", quoted: false, }],
        name: "aql_source_free",
        source: GeneratedValues(seed),
        visible_fields: ["a"],
        graph_bindings: [],
      },
    ],
  }
}

///|
fn checked_installed_values_collision(context : Context) -> String raise {
  let program = compile_query_script(
    @query.parse_query_script(
      "WITH supplied_rows AS (SELECT a FROM supplied), unit_rows AS (SELECT 7 AS n) SELECT l.a AS a, r.n AS n FROM supplied_rows AS l CROSS JOIN unit_rows AS r",
      syntax_limits(),
    ).unwrap(),
    context,
    construction_limits(),
  ).unwrap()
  assert_eq(@program.stage_count(program), 1)
  assert_true(
    @check.check_parsed(program, check_environment(), None, check_limits())
    is Checked(_),
  )
  semantic(program)
}

///|
test "installed Values named like the synthetic Unit retain separate producer rows" {
  let body = checked_installed_values_collision(
    installed_values_collision_context(31),
  )
  // Independent source rows have cardinality two; the source-free body has one
  // Unit row. Sharing them would duplicate the CROSS JOIN's output cardinality.
  assert_eq(body.split("\"values\":").length(), 3)
  assert_true(body.contains("\"rows\":[{\"a\":31},{\"a\":32}]"))
  assert_true(body.contains("\"rows\":[{\"aql_source_free_unit\":true}]"))
  assert_true(body.contains("\"literal\":7"))
  assert_true(body.contains("\"fields\":[\"a\",\"n\"]"))
}

///|
test "same named installed Values in independent Contexts preserve their own rows" {
  let first = installed_values_collision_context(31)
  let second = installed_values_collision_context(91)
  let first_body = checked_installed_values_collision(first)
  let second_body = checked_installed_values_collision(second)
  assert_true(first_body.contains("\"rows\":[{\"a\":31},{\"a\":32}]"))
  assert_false(first_body.contains("\"a\":91"))
  assert_true(second_body.contains("\"rows\":[{\"a\":91},{\"a\":92}]"))
  assert_false(second_body.contains("\"a\":31"))
  assert_true(first_body != second_body)
  assert_eq(checked_installed_values_collision(first), first_body)
}
