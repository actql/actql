///|
fn row_on_query(source : String) -> Result[@program.Program, Issue] {
  compile_query_script(
    @query.parse_query_script(source, syntax_limits()).unwrap(),
    { ..values_context(), inputs: [], },
    construction_limits(),
  )
}

///|
test "JOIN ON does not reinterpret a bare ordinary left range as its numeric column" {
  assert_true(
    row_on_query(
      "SELECT l.id FROM (SELECT 1 AS l,2 AS id) l JOIN (SELECT 1 AS id) r ON l=r.id MAX_OUTPUT_ROWS 10",
    )
    is Err(UnsupportedJoin),
  )
}

///|
test "JOIN ON keeps ordinary right range precedence in the shared row binder" {
  assert_true(
    row_on_query(
      "SELECT l AS row FROM (SELECT 1 AS id) l JOIN (SELECT 1 AS r,2 AS id) r ON l.id=r MAX_OUTPUT_ROWS 10",
    )
    is Err(UnsupportedJoin),
  )
}

///|
test "CTE Pipe JOIN ON retains quoted ordinary range kind" {
  assert_true(
    row_on_query(
      "WITH a AS (SELECT 1 AS l,2 AS id),b AS (SELECT 1 AS id) FROM a AS `L` |> JOIN b AS r ON `L`=r.id MAX_OUTPUT_ROWS 10 |> SELECT `L`.id",
    )
    is Err(UnsupportedJoin),
  )
}

///|
test "qualified ON columns and USING remain column selectors beside colliding ranges" {
  for
    source in [
      "SELECT l.id FROM (SELECT 1 AS l,2 AS id) l JOIN (SELECT 1 AS id) r ON l.l=r.id MAX_OUTPUT_ROWS 10",
      "SELECT l.id FROM (SELECT 1 AS l,2 AS id) l JOIN (SELECT 1 AS l) r USING(l) MAX_OUTPUT_ROWS 10",
    ] {
    let p = row_on_query(source).unwrap()
    match
      @check.check_parsed(
        p,
        check_environment(numeric=true),
        None,
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      _ => fail("closed independent JOIN column control")
    }
  }
}

///|
test "ordinary named source JOIN ON cannot bypass row precedence through specialization" {
  for
    source in [
      "SELECT x.x FROM t AS x JOIN r AS rr ON x=rr.k MAX_OUTPUT_ROWS 10", "SELECT t.x FROM t JOIN r AS k ON t.x=k MAX_OUTPUT_ROWS 10",
      "FROM t AS `X` |> JOIN r AS rr ON `X`=rr.k MAX_OUTPUT_ROWS 10 |> SELECT `X`.x",
    ] {
    let query = @query.parse_query(source, syntax_limits()).unwrap()
    for
      result in [
        compile(query, join_order_context(), construction_limits()),
        compile_query_script(
          @query.single_query_script(query),
          join_order_context(),
          construction_limits(),
        ),
      ] {
      assert_true(result is Err(UnsupportedJoin), msg=source)
    }
  }
}

///|
test "independent object-key Program retains the common incomparable-key rejection" {
  let p = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.join_row_key","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"l":{"type":"number","nullable":false},"id":{"type":"number","nullable":false}},"rows":[{"l":1,"id":2}]},"as":"left"},{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"right"},{"from":"left","derive":{"row":{"object":{"l":{"field":"l"},"id":{"field":"id"}}}},"as":"left_row"},{"from":"left_row","join":{"with":"right","kind":"inner","on":[{"left":"row","right":"id"}],"max_output_rows":10,"select":{"id":"left.id"}},"as":"out"}],"results":{"rows":{"from":"out","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(
      p,
      check_environment(numeric=true),
      None,
      check_limits(),
    ) {
    Rejected(_) => ()
    _ => fail("whole row object is not a numeric JOIN key")
  }
  let number = @contract.primitive(NumberType, nullable=false)
  let row = @contract.object_contract(
    [("l", number), ("id", number)],
    nullable=false,
    max_fields=2,
    max_name_bytes=3,
  ).unwrap()
  let left = @schema.from_fields(
    [(Unqualified("row"), row)],
    max_fields=1,
    max_name_bytes=3,
  ).unwrap()
  let right = @schema.from_fields(
    [(Unqualified("id"), number)],
    max_fields=1,
    max_name_bytes=2,
  ).unwrap()
  assert_true(
    @join_shape.check(
      unnest_value_cursor(
        "{\"with\":\"right\",\"kind\":\"inner\",\"on\":[{\"left\":\"row\",\"right\":\"id\"}],\"max_output_rows\":10}",
      ),
      left,
      right,
      None,
      { max_work: 1000, max_text_bytes: 1000, max_nodes: 1000, max_depth: 10, },
    )
    is Err({ kind: IncomparableKeys("row", "id"), .. }),
  )
}
