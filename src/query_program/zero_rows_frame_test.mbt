///|
// The complete expected Program is authored from the physical frame contract,
// including nullable observations; it is not emitted by the compiler.
fn zero_rows_frame_expected(frame : String) -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"flag":{"type":"boolean","nullable":true},"amount":{"type":"number","nullable":true}},"rows":[{"id":3,"flag":true,"amount":20},{"id":1,"flag":null,"amount":null},{"id":2,"flag":false,"amount":10}]},"as":"flags"},{"from":"flags","analytic":{"partition_by":[],"order_by":[{"field":"id","dir":"asc","nulls":"first"}],"functions":{"total":{"fn":"sum","field":"amount"}},"frame":
    ) +
    frame +
    (
      #|}},{"select":["id","total"]},{"sort":[{"field":"id","dir":"asc","nulls":"first"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["id","total"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "zero ROWS SQL Pipe and named windows match complete checked Programs" {
  for
    (boundary, frame) in [
      ("0 PRECEDING", "{\"start\":\"current_row\",\"end\":\"current_row\"}"),
      (
        "BETWEEN 0 PRECEDING AND 0 FOLLOWING", "{\"start\":\"current_row\",\"end\":\"current_row\"}",
      ),
      (
        "BETWEEN 0 FOLLOWING AND 0 FOLLOWING", "{\"start\":\"current_row\",\"end\":\"current_row\"}",
      ),
      (
        "BETWEEN 0 PRECEDING AND 0 PRECEDING", "{\"start\":\"current_row\",\"end\":\"current_row\"}",
      ),
      (
        "BETWEEN 0 FOLLOWING AND 1 FOLLOWING", "{\"start\":\"current_row\",\"end\":{\"following\":1}}",
      ),
      (
        "BETWEEN 1 PRECEDING AND 0 PRECEDING", "{\"start\":{\"preceding\":1},\"end\":\"current_row\"}",
      ),
    ] {
    let expected = zero_rows_frame_expected(frame)
    match
      @check.check_parsed(
        expected,
        check_environment(numeric=true),
        None,
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("the independent physical frame Program must be closed")
    }
    let call = "SUM(amount) OVER (ORDER BY id ROWS " + boundary + ") AS total"
    for
      source in [
        "SELECT id, " + call + " FROM flags ORDER BY id",
        "FROM flags |> SELECT id, " + call + " |> ORDER BY id",
        "SELECT id, SUM(amount) OVER w AS total FROM flags WINDOW w AS (ORDER BY id ROWS " +
        boundary +
        ") ORDER BY id",
      ] {
      let actual = compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        analytic_countif_context(),
        construction_limits(),
      ).unwrap()
      assert_eq(semantic(actual), semantic(expected))
    }
  }
}

///|
test "zero frame projection does not legalize forbidden boundary categories" {
  for
    boundary in [
      "0 FOLLOWING", "BETWEEN CURRENT ROW AND 0 PRECEDING", "BETWEEN 0 FOLLOWING AND CURRENT ROW",
      "BETWEEN 0 FOLLOWING AND 0 PRECEDING",
    ] {
    // A preceding valid call must not hide an invalid second call through reuse.
    let source = "SELECT SUM(amount) OVER (ORDER BY id ROWS CURRENT ROW) AS valid, SUM(amount) OVER (ORDER BY id ROWS " +
      boundary +
      ") AS invalid FROM flags"
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        analytic_countif_context(),
        construction_limits(),
      )
      is Err(InvalidQuery),
      msg=boundary,
    )
  }
}
