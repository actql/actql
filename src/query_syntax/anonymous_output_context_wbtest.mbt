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
    let selected = query.operations.filter_map(operation => {
      match operation {
        Select(columns, _) => Some(columns)
        _ => None
      }
    })
    assert_eq(selected.length(), 1)
    assert_true(projection_public_name(selected[0][0]) is None, msg=source)
  }
}

///|
test "namespace geometry comes from original constructors without another walk" {
  for
    (source, expected) in [
      ("SELECT 1 AS n", (4, 1, 1, 0, 0)),
      ("SELECT t.n FROM t", (4, 1, 1, 0, 1)),
      ("SELECT t.* FROM t", (4, 1, 1, 0, 1)),
      ("SELECT 't.* FROM t' AS text", (4, 1, 1, 0, 0)),
    ] {
    let query = parse_query(source, selected_query_limits()).unwrap()
    let original = query_source(query)
    let work = query_work(query)
    assert_eq(anonymous_namespace_geometry(query), expected, msg=source)
    assert_true(physical_equal(query_source(query), original))
    assert_eq(query_work(query), work)
  }
}

///|
test "namespace width factors count duplicated stars and complete JOIN lists" {
  for
    (source, factor) in [
      ("SELECT t.*, t.* FROM t", 2),
      ("SELECT * FROM t CROSS JOIN u CROSS JOIN v", 3),
      ("SELECT *, * FROM t CROSS JOIN u CROSS JOIN v", 6),
      ("WITH t AS (SELECT 1) SELECT * FROM t", 1),
    ] {
    let query = parse_query(source, selected_query_limits()).unwrap()
    assert_eq(anonymous_namespace_geometry(query).2, factor, msg=source)
  }
  let declarations = ["t0 AS (SELECT 1)"]
  for index in 1..<9 {
    declarations.push(
      "t" +
      index.to_string() +
      " AS (SELECT * FROM t" +
      (index - 1).to_string() +
      ")",
    )
  }
  let source = "WITH " + declarations.join(", ") + " SELECT * FROM t8"
  let query = parse_query(source, selected_query_limits()).unwrap()
  assert_eq(anonymous_namespace_geometry(query).2, 1)
  assert_eq(anonymous_namespace_geometry(query).1, 1)
}

///|
test "namespace growth saturation and same-source edit counts are construction DATA" {
  let query = parse_query(
    "FROM t |> EXTEND 1 AS a, 2 AS b |> SET a = 3 |> RENAME b AS c",
    selected_query_limits(),
  ).unwrap()
  assert_eq(anonymous_namespace_geometry(query).3, 4)
  let tokens = tokenize("SELECT 1", selected_query_limits().lexical).unwrap()
  tokens.namespace_field_factor = 2147483646
  let parser : QueryParser = {
    source: tokens,
    limits: selected_query_limits(),
    index: 0,
    work: 0,
    expression_nodes: 0,
    syntax_nodes: 0,
    source_depth: 0,
    synthetic_sources: 0,
    binding_scopes: [],
  }
  parser.namespace_replace_factor(1, 2)
  assert_eq(tokens.namespace_field_factor, 2147483647)
  parser.namespace_replace_factor(2, 3)
  assert_eq(tokens.namespace_field_factor, 2147483647)
}
