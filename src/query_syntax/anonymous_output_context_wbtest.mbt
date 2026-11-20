///|
test "anonymous output fact is recorded at original nested projection construction" {
  for source in [
    "SELECT 1", "SELECT COUNT(*) FROM t", "SELECT n + 1 FROM t",
    "WITH t AS (SELECT 1) SELECT * FROM t",
    "SELECT 1 AS n UNION ALL SELECT 2",
  ] {
    let query = parse_query(source, selected_query_limits()).unwrap()
    assert_true(anonymous_output_context_required(query), msg=source)
  }
}

///|
test "authored implicit names and non-code text do not request anonymous context" {
  for source in [
    "SELECT 1 AS n", "SELECT t.n FROM t", "SELECT t.n AS value FROM t", "SELECT * FROM t",
    "SELECT 'SELECT 1' AS text", "SELECT 1 AS n /* SELECT 2 */",
    "WITH t AS (SELECT 1 AS n) SELECT n FROM t",
  ] {
    let query = parse_query(source, selected_query_limits()).unwrap()
    assert_false(anonymous_output_context_required(query), msg=source)
  }
}
