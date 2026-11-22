///|
test "simple CASE admits the original SQL form through Common" {
  let text = "WITH t AS (SELECT 1 AS n, 'a' AS s, 10 AS v UNION ALL SELECT 2 AS n, 'b' AS s, 20 AS v UNION ALL SELECT 3 AS n, 'a' AS s, 30 AS v) SELECT CASE n WHEN 1 THEN 'one' ELSE 'other' END AS result FROM t"
  let query = match @query.parse_query(text, syntax_limits()) {
    Ok(query) => query
    Err(_) => fail("the original simple CASE grammar refused")
  }
  let program = match
    compile(query, { ..fixture_context(), inputs: [], }, construction_limits()) {
    Ok(program) => program
    Err(_) => fail("the original simple CASE did not lower to Common")
  }
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("the original CASE uses only literal rows")
  }
}
