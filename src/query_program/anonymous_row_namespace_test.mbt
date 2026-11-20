///|
test "whole row output preserves anonymous values with local display keys" {
  for (source, key) in [
    ("WITH t AS (SELECT 1, 2 AS n) SELECT t AS row FROM t", "f0_"),
    ("WITH t AS (SELECT 1, 2 AS f0_) SELECT t AS row FROM t", "f0__"),
    ("WITH t AS (SELECT 1, 2 AS n) SELECT IF(TRUE, t, t) AS row FROM t", "f0_"),
  ] {
    let program = anonymous_result_program(source)
    assert_eq(anonymous_result_fields(program), ["row"])
    assert_true(semantic(program).contains("\"" + key + "\":{\"field\":"), msg=source)
    match @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      NeedsInputs(_) => fail("the original Values row is closed")
    }
  }
}

///|
test "row wrappers and projected row values do not turn display keys into SQL members" {
  for expression in ["t.f0_", "(t).f0_", "IF(TRUE, t, t).f0_", "COALESCE(t, t).f0_", "[t][OFFSET(0)].f0_"] {
    let source = "WITH t AS (SELECT 1, 2 AS n) SELECT " + expression + " AS value FROM t"
    let script = @query.parse_query_script(source, syntax_limits()).unwrap()
    match compile_query_script(script, { ..fixture_context(), inputs: [], }, construction_limits()) {
      Err(UnknownColumn) => ()
      Err(Expression({ issue: @expression.UnknownReference, origin: Some(origin), })) =>
        assert_true(@origin.belongs_to(@query.script_document(script), origin), msg=source)
      Err(_) => fail("wrong anonymous member refusal: " + source)
      Ok(_) => fail("a generated DATA key became a row member: " + source)
    }
  }
  let source = "WITH t AS (SELECT 1, 2 AS n), r AS (SELECT t AS row FROM t) SELECT row.f0_ AS value FROM r"
  assert_true(compile_query_script(@query.parse_query_script(source, syntax_limits()).unwrap(), { ..fixture_context(), inputs: [], }, construction_limits()) is Err(Expression({ issue: @expression.UnknownReference, origin: Some(_), })))
}

///|
test "authored row fields and authored Object display-looking keys remain accessible" {
  for expression in ["t.n", "(t).n", "IF(TRUE, t, t).n", "COALESCE(t, t).n", "[t][OFFSET(0)].n"] {
    let source = "WITH t AS (SELECT 1, 2 AS n) SELECT " + expression + " AS value FROM t"
    let program = anonymous_result_program(source)
    assert_eq(anonymous_result_fields(program), ["value"])
    assert_true(@check.check_parsed(program, check_environment(), None, check_limits()) is Checked(_), msg=source)
  }
  let program = anonymous_result_program("WITH t AS (SELECT STRUCT(1 AS f0_) AS row) SELECT row.f0_ AS value FROM t")
  assert_true(@check.check_parsed(program, check_environment(), None, check_limits()) is Checked(_))
}
