///|
test "anonymous CTE values survive JOIN star without becoming field aliases" {
  let source = "WITH t AS (SELECT 1), u AS (SELECT 2 AS n) SELECT u.n, t.* FROM t CROSS JOIN u"
  let program = anonymous_result_program(source)
  assert_eq(anonymous_result_fields(program), ["n", "f1_"])
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("the two original Values producers are closed")
  }
}

///|
test "authored storage-like names remain real names beside anonymous values" {
  for
    name in ["aql_set_anonymous_1", "aql_set_anonymous_2", "aql_chain_column_1"] {
    let source = "WITH t AS (SELECT 1), u AS (SELECT 2 AS " +
      name +
      ") SELECT u." +
      name +
      " AS named, t.* FROM t CROSS JOIN u"
    let program = anonymous_result_program(source)
    assert_eq(anonymous_result_fields(program), ["named", "f1_"], msg=name)
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      NeedsInputs(_) => fail("authored names do not create acquisition")
    }
  }
}

///|
test "anonymous positional set output preserves None across another CTE" {
  let source = "WITH t AS (SELECT 1 UNION ALL SELECT 2), u AS (SELECT * FROM t) SELECT * FROM u"
  let script = @query.parse_query_script(source, syntax_limits()).unwrap()
  let document = @query.script_document(script)
  let program = compile_query_script(
    script,
    { ..fixture_context(), inputs: [], },
    construction_limits(),
  ).unwrap()
  assert_eq(anonymous_result_fields(program), ["f0_"])
  assert_true(physical_equal(document, @query.script_document(script)))
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("nested CTE/set controls retain only Values")
  }
}

///|
test "standalone set binding also resolves ORDER before display naming" {
  let source = "SELECT 1 UNION ALL SELECT 2 ORDER BY f0_"
  let query = @query.parse_query(source, syntax_limits()).unwrap()
  match
    compile(query, { ..fixture_context(), inputs: [], }, construction_limits()) {
    Err(UnknownColumn) | Err(UnsupportedOrdering) => ()
    Err(
      Expression({ issue: @expression.UnknownReference, origin: Some(origin), })
    ) => assert_true(@origin.belongs_to(@query.query_document(query), origin))
    Err(_) => fail("expected the original unknown output-name refusal")
    Ok(_) => fail("a display label became a standalone set alias")
  }
}

///|
test "a joined CTE retains anonymous roles for its next consumer" {
  let prefix = "WITH t AS (SELECT 1), u AS (SELECT 2 AS n), j AS (SELECT u.n, t.* FROM t CROSS JOIN u) "
  for source in [prefix + "SELECT f1_ FROM j", prefix + "SELECT j.f1_ FROM j"] {
    let script = @query.parse_query_script(source, syntax_limits()).unwrap()
    match
      compile_query_script(
        script,
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      ) {
      Err(UnknownColumn) => ()
      Err(
        Expression(
          { issue: @expression.UnknownReference, origin: Some(origin), }
        )
      ) =>
        assert_true(@origin.belongs_to(@query.script_document(script), origin))
      Err(_) => fail("expected the original unknown SQL name")
      Ok(_) => fail("JOIN published an anonymous display key as a CTE name")
    }
  }
  let program = anonymous_result_program(prefix + "SELECT j.* FROM j")
  assert_eq(anonymous_result_fields(program), ["n", "f1_"])
  assert_true(
    @check.check_parsed(program, check_environment(), None, check_limits())
    is Checked(_),
  )
}
