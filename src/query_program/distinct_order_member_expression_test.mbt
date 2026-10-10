///|
// Independent Program: evaluate the nullable member before DISTINCT, then
// add one to the evaluated output solely for ordering and remove that helper.
fn distinct_order_member_expected() -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"payload":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":true}}},"other":{"type":"object","nullable":false,"fields":{"score":{"type":"number","nullable":false}}}},"rows":[{"id":2,"payload":{"score":10},"other":{"score":100}},{"id":1,"payload":{"score":20},"other":{"score":200}},{"id":3,"payload":null,"other":{"score":300}},{"id":4,"payload":{"score":20},"other":{"score":400}},{"id":5,"payload":{"score":null},"other":{"score":500}}]},"as":"objects"},{"from":"objects","derive":{"aql_query_expr_0":{"property":{"name":"score","value":{"field":"payload"}}}}},{"select":[{"score":"aql_query_expr_0"}]},{"distinct":["score"]},{"derive":{"aql_pipe_sort_2":{"add":[{"field":"score"},{"literal":1}]}}},{"sort":[{"field":"aql_pipe_sort_2","dir":"asc","nulls":"last"}]},{"select":["score"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["score"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "selected nullable member ORDER control passes the common checker" {
  assert_true(
    @check.check_parsed(
      distinct_order_member_expected(),
      check_environment(),
      None,
      check_limits(),
    )
    is Checked(_),
  )
}

///|
test "DISTINCT ORDER can use a selected member inside a scalar expression" {
  for
    text in [
      "SELECT DISTINCT payload.score AS score FROM objects ORDER BY payload.score + 1 NULLS LAST",
      "SELECT DISTINCT payload.score AS score FROM objects ORDER BY (payload).score + 1 NULLS LAST",
      "SELECT DISTINCT ((payload)).`SCORE` AS score FROM objects ORDER BY objects.payload.score + 1 NULLS LAST",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      group_property_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(
      semantic(actual),
      semantic(distinct_order_member_expected()),
      msg=text,
    )
    assert_eq(semantic(actual).split("\"property\":").length(), 2, msg=text)
    assert_true(
      @check.check_parsed(actual, check_environment(), None, check_limits())
      is Checked(_),
      msg=text,
    )
  }
}

///|
test "selected member mapping cannot restore an unselected member or receiver" {
  for
    text in [
      "SELECT DISTINCT (payload).score AS score FROM objects AS payload ORDER BY payload.score + 1",
      "SELECT DISTINCT payload.score AS score FROM objects AS payload ORDER BY (payload).score + 1",
      "SELECT DISTINCT payload.score + 1 AS score FROM objects ORDER BY payload.score + 2",
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
test "selected member mapping cannot recover another input object" {
  assert_true(
    compile(
      @query.parse_query(
        "SELECT DISTINCT payload.score AS score FROM objects ORDER BY other.score + 1",
        syntax_limits(),
      ).unwrap(),
      group_property_context(),
      construction_limits(),
    )
    is Err(InvalidQuery),
  )
}

///|
test "receiver alias lowering records the independent common object DISTINCT limit" {
  for
    text in [
      "SELECT DISTINCT payload.score AS original_score, other AS payload FROM objects ORDER BY -payload.score NULLS LAST, original_score NULLS LAST",
      "SELECT DISTINCT payload.score AS original_score, other AS payload FROM objects ORDER BY -objects.payload.score NULLS LAST, original_score NULLS LAST",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      group_property_context(),
      construction_limits(),
    ).unwrap()
    // This separate common limit is preserved, not a successful execution.
    guard @check.check_parsed(actual, check_environment(), None, check_limits())
      is Rejected(error) else {
      fail("retained object DISTINCT support requires a common contract change")
    }
    guard @check.diagnostic_cause(error)
      is Source(SourceView(Program(Program(Pipeline(stage, issue))))) else {
      raise @check.diagnostic_cause(error)
    }
    assert_eq(stage, 0)
    assert_eq(
      issue.kind,
      @pipeline.Operation(@relation.NotKeyComparable("payload")),
    )
    assert_eq(issue.path, [
      Key("stages"),
      Index(0),
      Key("steps"),
      Index(3),
      Key("distinct"),
      Index(1),
    ])
    let body = semantic(actual)
    // The alias path consumes the retained object; the qualified path consumes
    // the evaluated original score. Neither reads the removed input receiver.
    if text.contains("-objects.payload.score") {
      assert_true(body.contains("\"negate\":{\"field\":\"original_score\"}"))
      assert_eq(body.split("\"property\":").length(), 2)
    } else {
      assert_true(
        body.contains(
          "\"negate\":{\"property\":{\"name\":\"score\",\"value\":{\"field\":\"payload\"}}}",
        ),
      )
      assert_eq(body.split("\"property\":").length(), 3)
    }
  }
}

///|
test "Pipe DISTINCT ORDER binds selected members without keeping input ranges" {
  let actual = compile(
    @query.parse_query(
      "FROM objects AS active |> SELECT DISTINCT active.payload.score AS score |> ORDER BY -(payload).score NULLS LAST",
      syntax_limits(),
    ).unwrap(),
    group_property_context(),
    construction_limits(),
  ).unwrap()
  let body = semantic(actual)
  assert_eq(body.split("\"property\":").length(), 2)
  assert_true(body.contains("\"negate\":{\"field\":\"score\"}"))
  assert_true(
    @check.check_parsed(actual, check_environment(), None, check_limits())
    is Checked(_),
  )
}
