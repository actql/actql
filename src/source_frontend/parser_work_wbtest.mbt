///|
test "observed frontend parser retains actual declared work on success and rejected prefixes" {
  let (outcome, spent, complete) = observe_parse_query("SELECT 1 AS id", Sql)
  let parsed = outcome.unwrap()
  assert_true(complete)
  assert_eq(
    spent,
    @syntax.usage(@syntax.query_source(parsed), @syntax.Work).to_int64() +
    @syntax.query_work(parsed).to_int64(),
  )
  assert_true(spent > 0L && spent <= query_syntax_work_limit())
  let (rejected, prefix, complete) = observe_parse_query("SELECT (1 +", Sql)
  assert_true(rejected is Err(QuerySyntax(_)))
  assert_true(complete && prefix > 0L && prefix <= query_syntax_work_limit())
  let (foreign, prefix, complete) = observe_parse_query(
    "AQL '0.1'; retired",
    Text,
  )
  assert_true(foreign is Err(WrongQueryForm))
  assert_true(complete && prefix > 0L)
  let (unadmitted, prefix, complete) = observe_parse_query(
    "x".repeat(65537),
    Sql,
  )
  assert_true(unadmitted is Err(QuerySyntax(_)))
  assert_eq(prefix, 0L)
  assert_false(complete)
}
