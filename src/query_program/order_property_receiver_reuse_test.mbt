///|
// Authored independently: project once, deduplicate only the public value,
// then sort its evaluated output without recovering the object input.
fn order_receiver_expected(key : String) -> @program.Program {
  @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.pipe_slots\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"payload\":{\"type\":\"object\",\"nullable\":true,\"fields\":{\"score\":{\"type\":\"number\",\"nullable\":true}}},\"other\":{\"type\":\"object\",\"nullable\":false,\"fields\":{\"score\":{\"type\":\"number\",\"nullable\":false}}}},\"rows\":[{\"id\":2,\"payload\":{\"score\":10},\"other\":{\"score\":100}},{\"id\":1,\"payload\":{\"score\":20},\"other\":{\"score\":200}},{\"id\":3,\"payload\":null,\"other\":{\"score\":300}},{\"id\":4,\"payload\":{\"score\":20},\"other\":{\"score\":400}},{\"id\":5,\"payload\":{\"score\":null},\"other\":{\"score\":500}}]},\"as\":\"objects\"},{\"from\":\"objects\",\"derive\":{\"aql_query_expr_0\":" +
    key +
    "}},{\"select\":[{\"score\":\"aql_query_expr_0\"}]},{\"distinct\":[\"score\"]},{\"sort\":[{\"field\":\"score\",\"dir\":\"asc\",\"nulls\":\"last\"}],\"as\":\"aql_gen_0\"}],\"results\":{\"rows\":{\"from\":\"aql_gen_0\",\"fields\":[\"score\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "DISTINCT ORDER reuses the same property across receiver syntax" {
  let expected = order_receiver_expected(
    "{\"property\":{\"name\":\"score\",\"value\":{\"field\":\"payload\"}}}",
  )
  assert_true(
    @check.check_parsed(expected, check_environment(), None, check_limits())
    is Checked(_),
  )
  for
    text in [
      "SELECT DISTINCT payload.score AS score FROM objects ORDER BY (payload).score NULLS LAST",
      "SELECT DISTINCT (payload).score AS score FROM objects ORDER BY objects.payload.score NULLS LAST",
      "SELECT DISTINCT ((payload)).`SCORE` AS score FROM objects ORDER BY payload.score NULLS LAST",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      group_property_context(),
      construction_limits(),
    ).unwrap()
    let body = semantic(actual)
    assert_eq(body, semantic(expected), msg=text)
    assert_eq(body.split("\"property\":").length(), 2, msg=text)
    assert_false(body.contains("aql_pipe_sort_"), msg=text)
    assert_true(body.contains("\"distinct\":[\"score\"]"), msg=text)
    assert_true(
      @check.check_parsed(actual, check_environment(), None, check_limits())
      is Checked(_),
      msg=text,
    )
  }
}

///|
test "DISTINCT ORDER reuses equivalent property subtrees without repeating arithmetic" {
  for
    (text, key) in [
      (
        "SELECT DISTINCT payload.score + 1 AS score FROM objects ORDER BY (payload).score + 1 NULLS LAST",
        "{\"add\":[{\"property\":{\"name\":\"score\",\"value\":{\"field\":\"payload\"}}},{\"literal\":1}]}",
      ),
      (
        "SELECT DISTINCT -((payload).score) AS score FROM objects ORDER BY -objects.payload.score NULLS LAST",
        "{\"negate\":{\"property\":{\"name\":\"score\",\"value\":{\"field\":\"payload\"}}}}",
      ),
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      group_property_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(
      semantic(actual),
      semantic(order_receiver_expected(key)),
      msg=text,
    )
    assert_eq(semantic(actual).split("\"property\":").length(), 2, msg=text)
    assert_false(semantic(actual).contains("aql_pipe_sort_"), msg=text)
  }
}

///|
test "ORDER reuse cannot confuse a range column with an explicit object receiver" {
  for
    text in [
      "SELECT DISTINCT (payload).score AS score FROM objects AS payload ORDER BY payload.score",
      "SELECT DISTINCT payload.score AS score FROM objects AS payload ORDER BY (payload).score",
      "SELECT DISTINCT (payload).score + 1 AS score FROM objects AS payload ORDER BY payload.score + 1",
    ] {
    assert_true(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        group_receiver_scope_context(),
        construction_limits(),
      )
      is Err(InvalidQuery),
      msg=text,
    )
  }
}

///|
test "Pipe DISTINCT ORDER retains the evaluated equivalent property slot" {
  let actual = compile(
    @query.parse_query(
      "FROM objects AS active |> SELECT DISTINCT active.payload.score AS score |> ORDER BY (payload).score NULLS LAST",
      syntax_limits(),
    ).unwrap(),
    group_property_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual).split("\"property\":").length(), 2)
  assert_false(semantic(actual).contains("aql_pipe_sort_"))
  assert_true(
    @check.check_parsed(actual, check_environment(), None, check_limits())
    is Checked(_),
  )
}
