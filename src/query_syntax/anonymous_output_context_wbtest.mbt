///|
test "anonymous output fact is recorded at original nested projection construction" {
  for
    source in [
      "SELECT 1", "SELECT COUNT(*) FROM t", "SELECT n + 1 FROM t", "WITH t AS (SELECT 1) SELECT * FROM t",
      "SELECT 1 AS n UNION ALL SELECT 2",
    ] {
    let query = parse_query(source, selected_query_limits()).unwrap()
    assert_true(anonymous_output_context_required(query), msg=source)
  }
}

///|
test "authored implicit names and non-code text do not request anonymous context" {
  for
    source in [
      "SELECT 1 AS n", "SELECT t.n FROM t", "SELECT t.n AS value FROM t", "SELECT * FROM t",
      "SELECT 'SELECT 1' AS text", "SELECT 1 AS n /* SELECT 2 */", "WITH t AS (SELECT 1 AS n) SELECT n FROM t",
    ] {
    let query = parse_query(source, selected_query_limits()).unwrap()
    assert_false(anonymous_output_context_required(query), msg=source)
  }
}

///|
test "star growth comes only from actual projections and saturates without overflow" {
  for
    (source, expected) in [
      ("SELECT 1", 0),
      ("SELECT '*' AS text", 0),
      ("WITH t AS (SELECT 1) SELECT t.* FROM t", 1),
      ("WITH t AS (SELECT 1) SELECT *, t.* FROM t", 2),
    ] {
    assert_eq(
      anonymous_output_star_growth(
        parse_query(source, selected_query_limits()).unwrap(),
      ),
      expected,
    )
  }
  // The bound is a representation shortcut, not a31-star language restriction.
  let projections : Array[String] = []
  for _ in 0..<40 {
    projections.push("t.*")
  }
  let source = "SELECT " + projections.join(", ") + " FROM t"
  let limits = selected_query_limits()
  let query = parse_query(source, { ..limits, max_syntax_nodes: 1000, }).unwrap()
  assert_eq(anonymous_output_star_growth(query), 31)
}

///|
test "receiver stars do not acquire an implicit SQL output name" {
  for source in ["SELECT * FROM t", "SELECT t.* FROM t", "SELECT (t).* FROM t"] {
    let query = parse_query(source, selected_query_limits()).unwrap()
    let selected = query.operations.filter_map(operation => match operation {
      Select(columns, _) => Some(columns)
      _ => None
    })
    assert_eq(selected.length(), 1)
    assert_true(projection_public_name(selected[0][0]) is None, msg=source)
  }
}
