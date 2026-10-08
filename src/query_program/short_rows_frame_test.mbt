///|
fn short_rows_frame_expected() -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"customer_id":{"type":"string","nullable":false},"status":{"type":"string","nullable":false},"amount":{"type":"number","nullable":false}},"rows":[{"id":"a","customer_id":"one","status":"open","amount":1},{"id":"b","customer_id":"two","status":"open","amount":2}]},"as":"orders"},{"from":"orders","analytic":{"partition_by":[],"order_by":[{"field":"id","dir":"asc","nulls":"first"}],"functions":{"running":{"fn":"sum","field":"amount"}},"frame":{"start":{"preceding":1},"end":"current_row"}}},{"select":["id","running"]},{"sort":[{"field":"id","dir":"asc","nulls":"first"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["id","running"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "independent short ROWS frame Program passes the common checker" {
  match
    @check.check_parsed(
      short_rows_frame_expected(),
      check_environment(numeric=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("independent short frame control must be closed")
  }
}

///|
test "SQL short ROWS frame matches the independently authored complete Program" {
  for
    source in [
      "SELECT id, SUM(amount) OVER (ORDER BY id ROWS 1 PRECEDING) AS running FROM orders ORDER BY id",
      "FROM orders |> SELECT id, SUM(amount) OVER (ORDER BY id ROWS 1 PRECEDING) AS running |> ORDER BY id",
    ] {
    let query = @query.parse_query(source, syntax_limits()).unwrap()
    let actual = compile(query, values_context(), construction_limits()).unwrap()
    assert_eq(semantic(actual), semantic(short_rows_frame_expected()))
  }
}

///|
test "short ROWS frames retain the common invalid interval rejection" {
  for boundary in ["1 FOLLOWING", "UNBOUNDED FOLLOWING"] {
    let query = @query.parse_query(
      "SELECT SUM(amount) OVER (ORDER BY id ROWS " +
      boundary +
      ") AS running FROM orders",
      syntax_limits(),
    ).unwrap()
    let actual = compile(query, values_context(), construction_limits()).unwrap()
    match
      @check.check_parsed(
        actual,
        check_environment(numeric=true),
        None,
        check_limits(),
      ) {
      Rejected(diagnostic) => {
        assert_true(
          @check.diagnostic_cause(diagnostic)
          is Source(
            SourceView(
              Program(
                Program(Pipeline(_, { kind: Operation(InvalidFrame), .. }))
              )
            )
          ),
          msg=boundary,
        )
        assert_eq(@check.diagnostic_category(diagnostic), InvalidInput)
      }
      _ => fail("short frame cannot start after its implicit CURRENT ROW end")
    }
  }
}
