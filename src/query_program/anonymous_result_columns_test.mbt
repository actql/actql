///|
fn anonymous_result_program(source : String) -> @program.Program {
  compile_query_script(
    @query.parse_query_script(source, syntax_limits()).unwrap(),
    { ..fixture_context(), inputs: [], },
    construction_limits(),
  ).unwrap()
}

///|
fn anonymous_result_fields(program : @program.Program) -> Array[String] {
  let stages = @program.stages(program)
  let body = @wire.open_object(@program.stage_body(stages[stages.length() - 1])).unwrap()
  let results = @wire.open_object(@wire.required(body, "results").unwrap()).unwrap()
  let rows = @wire.open_object(@wire.required(results, "rows").unwrap()).unwrap()
  @wire.elements(@wire.required(rows, "fields").unwrap())
  .unwrap()
  .map(field => @wire.text(field).unwrap())
}

///|
test "anonymous scalar and aggregate results use final output positions" {
  for
    (source, fields) in [
      ("SELECT 1", ["f0_"]),
      ("SELECT 1 + 2, 3 * 4", ["f0_", "f1_"]),
      (
        "WITH t AS (SELECT 1 AS n UNION ALL SELECT 2 AS n) SELECT n + 1 FROM t",
        ["f0_"],
      ),
      (
        "WITH t AS (SELECT 1 AS n UNION ALL SELECT 2 AS n) SELECT COUNT(*) FROM t",
        ["f0_"],
      ),
      (
        "WITH t AS (SELECT 1 AS n UNION ALL SELECT 2 AS n) SELECT COUNT(*), n FROM t GROUP BY n",
        ["f0_", "n"],
      ),
    ] {
    let program = anonymous_result_program(source)
    assert_eq(anonymous_result_fields(program), fields, msg=source)
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      NeedsInputs(_) => fail("these authored Values controls are closed")
    }
  }
}

///|
test "anonymous labels reserve all authored and implicit names before assignment" {
  for
    (source, fields) in [
      ("SELECT 1, 2 AS f0_, 3 AS F0__", ["f0___", "f0_", "F0__"]),
      ("WITH t AS (SELECT 2 AS f0_) SELECT 1, f0_ FROM t", ["f0__", "f0_"]),
      ("SELECT 1 AS first, 2, 3 AS f1_", ["first", "f1__", "f1_"]),
      ("WITH t AS (SELECT 1, 2 AS named) SELECT * FROM t", ["f0_", "named"]),
      ("WITH t AS (SELECT 1, 2 AS named) SELECT t.* FROM t", ["f0_", "named"]),
      (
        "WITH t AS (SELECT 1, 2 AS named) SELECT 0 AS f1_, * FROM t",
        ["f1_", "f1__", "named"],
      ),
    ] {
    let program = anonymous_result_program(source)
    assert_eq(anonymous_result_fields(program), fields, msg=source)
  }
}

///|
test "anonymous display labels never enter SQL expression or BY NAME scope" {
  for
    source in [
      "SELECT 1 ORDER BY f0_", "WITH t AS (SELECT 1) SELECT f0_ FROM t", "WITH t AS (SELECT 1) SELECT t.f0_ FROM t",
      "WITH t AS (SELECT 1) SELECT COUNT(*) FROM t GROUP BY f0_", "SELECT 1 UNION ALL BY NAME SELECT 2",
      "WITH t AS (SELECT 1) SELECT * FROM t UNION ALL BY NAME SELECT 2 AS f0_",
    ] {
    let script = @query.parse_query_script(source, syntax_limits()).unwrap()
    let result = compile_query_script(
      script,
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    )
    match result {
      Err(UnknownColumn) | Err(UnsupportedProjection) => ()
      Err(
        Expression(
          { issue: @expression.UnknownReference, origin: Some(origin), }
        )
      ) =>
        assert_true(@origin.belongs_to(@query.script_document(script), origin))
      Err(Expression(diagnostic)) =>
        fail(source + ": " + @debug.to_string(diagnostic.issue))
      Err(UnsupportedSet) => fail(source + ": UnsupportedSet")
      Err(UnsupportedOrdering) => fail(source + ": UnsupportedOrdering")
      Err(_) => fail(source + ": another typed refusal")
      Ok(_) => fail(source + ": anonymous display label became an SQL name")
    }
  }
  let named = anonymous_result_program(
    "WITH t AS (SELECT 1 AS f0_) SELECT f0_ FROM t ORDER BY f0_",
  )
  assert_eq(anonymous_result_fields(named), ["f0_"])
}
