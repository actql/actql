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

///|
test "row namespace survives joins and set type joins without hiding authored collisions" {
  for source in [
    "WITH t AS (SELECT 1, 2 AS n), r AS (SELECT t AS row FROM t), u AS (SELECT 3 AS z) SELECT r.row.f0_ AS value FROM r CROSS JOIN u",
    "WITH a AS (SELECT 1), t AS (SELECT STRUCT(2 AS f0_) AS row UNION ALL SELECT a AS row FROM a) SELECT row.f0_ AS value FROM t",
    "WITH t AS (SELECT 1, 2 AS f0_) SELECT (t).f0__ AS value FROM t",
  ] {
    let script = @query.parse_query_script(source, syntax_limits()).unwrap()
    match compile_query_script(script, { ..fixture_context(), inputs: [], }, construction_limits()) {
      Err(Expression({ issue: @expression.UnknownReference, origin: Some(origin), })) =>
        assert_true(@origin.belongs_to(@query.script_document(script), origin), msg=source)
      Err(_) => fail("wrong retained row namespace refusal: " + source)
      Ok(_) => fail("a type join or JOIN manufactured an anonymous member: " + source)
    }
  }
  let named = anonymous_result_program("WITH t AS (SELECT 1, 2 AS f0_) SELECT t.f0_ AS value FROM t")
  assert_true(@check.check_parsed(named, check_environment(), None, check_limits()) is Checked(_))
  // The same original public row excludes the separately retained exact view.
  let numeric = anonymous_result_program("WITH t AS (SELECT 5 AS v) SELECT MOD(v, 2) AS m, t AS row FROM t")
  assert_true(@check.check_parsed(numeric, check_environment(), None, check_limits()) is Checked(_))
  assert_true(semantic(numeric).contains("\"object\":{\"v\":{\"field\":\"v\"}}"))
}

///|
test "row namespace restrictions also apply to predicates ordering and original AS snapshots" {
  for source in [
    "WITH t AS (SELECT 1, 2 AS n), r AS (SELECT t AS row FROM t) SELECT row FROM r WHERE row.f0_ = 1",
    "WITH t AS (SELECT 1, 2 AS n), r AS (SELECT t AS row FROM t) SELECT row FROM r ORDER BY row.f0_",
    "WITH t AS (SELECT 1, 2 AS n) FROM t |> AS saved |> SET n = 3 |> SELECT (saved).f0_ AS value",
  ] {
    let script = @query.parse_query_script(source, syntax_limits()).unwrap()
    match compile_query_script(script, { ..fixture_context(), inputs: [], }, construction_limits()) {
      Err(Expression({ issue: @expression.UnknownReference, origin: Some(origin), })) =>
        assert_true(@origin.belongs_to(@query.script_document(script), origin), msg=source)
      Err(_) => fail("wrong original row namespace refusal: " + source)
      Ok(_) => fail("another clause exposed an anonymous row member: " + source)
    }
  }
  let original = anonymous_result_program("WITH t AS (SELECT 1, 2 AS n) FROM t |> AS saved |> SET n = 3 |> SELECT saved AS old")
  assert_true(@check.check_parsed(original, check_environment(), None, check_limits()) is Checked(_))
  assert_true(semantic(original).contains("\"n\":{\"field\":\"n\"}"))
}

///|
test "pipeline edit targets require original SQL names rather than anonymous storage slots" {
  for operation in ["SET aql_set_anonymous_0 = 2", "RENAME aql_set_anonymous_0 AS visible"] {
    let source = "WITH t AS (SELECT 1) FROM t |> " + operation
    let script = @query.parse_query_script(source, syntax_limits()).unwrap()
    match compile_query_script(script, { ..fixture_context(), inputs: [], }, construction_limits()) {
      Err(UnknownColumn) => ()
      Err(_) => fail("expected the original unknown edit target: " + source)
      Ok(_) => fail("an anonymous storage slot became an edit target: " + source)
    }
  }
  let authored = anonymous_result_program("WITH t AS (SELECT 1, 2 AS aql_set_anonymous_0) FROM t |> SET aql_set_anonymous_0 = 3 |> RENAME aql_set_anonymous_0 AS named |> SELECT *")
  assert_eq(anonymous_result_fields(authored), ["f0_", "named"])
  assert_true(@check.check_parsed(authored, check_environment(), None, check_limits()) is Checked(_))
}
