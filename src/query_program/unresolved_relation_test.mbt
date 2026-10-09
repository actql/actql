///|
fn exact_unresolved_relation(
  result : Result[@program.Program, Issue],
  expected : Array[(String, Bool)],
) -> Bool {
  guard result is Err(issue) && issue is UnresolvedRelation(_) else {
    return false
  }
  let path = unresolved_relation_reference(issue).unwrap()
  if path.length() != expected.length() {
    return false
  }
  for index in 0..<expected.length() {
    if path[index].value != expected[index].0 ||
      path[index].quoted != expected[index].1 {
      return false
    }
  }
  true
}

///|
test "unresolved relation witnesses retain the exact selected semantic path" {
  for
    (text, expected) in [
      ("SELECT 1 AS n FROM missing", [("missing", false)]),
      ("FROM missing |> SELECT 1 AS n", [("missing", false)]),
      (
        "SELECT 1 AS n FROM catalog.missing",
        [("catalog", false), ("missing", false)],
      ),
      ("SELECT 1 AS n FROM `é/~🧭`", [("é/~🧭", true)]),
      (
        "SELECT o.id AS n FROM orders AS o JOIN missing AS m ON o.id = m.id",
        [("missing", false)],
      ),
      (
        "WITH chosen AS (SELECT id FROM missing) SELECT id FROM chosen",
        [("missing", false)],
      ),
    ] {
    let query = @query.parse_query(text, syntax_limits()).unwrap()
    let issue = match compile(query, fixture_context(), construction_limits()) {
      Err(issue) => issue
      Ok(_) => fail("a missing input must not compile: " + text)
    }
    assert_true(issue is UnresolvedRelation(_), msg=text)
    let path = unresolved_relation_reference(issue).unwrap()
    assert_eq(path.length(), expected.length(), msg=text)
    for index in 0..<expected.length() {
      assert_eq(path[index].value, expected[index].0, msg=text)
      assert_eq(path[index].quoted, expected[index].1, msg=text)
    }
    path.clear()
    assert_eq(
      unresolved_relation_reference(issue).unwrap().length(),
      expected.length(),
      msg="a returned path must not mutate the retained witness",
    )
  }
}

///|
test "unrelated lowering issues do not invent a named relation witness" {
  let issues : Array[Issue] = [
    UnknownRelation,
    AmbiguousRelation,
    UnknownColumn,
    InvalidContext,
  ]
  for issue in issues {
    assert_true(unresolved_relation_reference(issue) is None)
  }
  let unused = @query.parse_query(
    "WITH chosen AS (SELECT id FROM orders) SELECT id FROM missing",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(unused, fixture_context(), construction_limits())
    is Err(UnsupportedCte),
    msg="unused CTE refusal still precedes resolving the outer relation",
  )
}
