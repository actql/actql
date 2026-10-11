///|
test "optional derived alias diagnostic emits the actual existing Program" {
  let q = @query.parse_query(
    "SELECT id FROM (SELECT 1 AS id UNION ALL SELECT CAST(NULL AS FLOAT64) UNION ALL SELECT 2 UNION ALL SELECT 1) WHERE id IS NOT NULL ORDER BY id DESC NULLS FIRST LIMIT 3",
    syntax_limits(),
  ).unwrap()
  let p = compile(q, { ..values_context(), inputs: [], }, construction_limits()).unwrap()
  match
    @check.check_parsed(
      p,
      check_environment(numeric=true),
      None,
      check_limits(),
    ) {
    Checked(_) => fail("local 20-step budget must reject 23 steps")
    Rejected(issue) =>
      assert_eq(@check.diagnostic_category(issue), @check.CompileLimit)
    NeedsInputs(_) => fail("closed query")
  }
}

///|
test "named derived alias existing control uses the same predicate and limit" {
  let q = @query.parse_query(
    "SELECT id FROM (SELECT 1 AS id UNION ALL SELECT CAST(NULL AS FLOAT64) UNION ALL SELECT 2 UNION ALL SELECT 1) chosen WHERE id IS NOT NULL ORDER BY id DESC NULLS FIRST LIMIT 3",
    syntax_limits(),
  ).unwrap()
  let p = compile(q, { ..values_context(), inputs: [], }, construction_limits()).unwrap()
  match
    @check.check_parsed(
      p,
      check_environment(numeric=true),
      None,
      check_limits(),
    ) {
    Checked(_) => fail("same 20-step budget must reject the named control too")
    Rejected(issue) =>
      assert_eq(@check.diagnostic_category(issue), @check.CompileLimit)
    NeedsInputs(_) => fail("closed named query")
  }
}
