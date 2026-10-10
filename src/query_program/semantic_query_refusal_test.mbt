///|
test "authored CTE and grouped projection violations are not lowering gaps" {
  for
    text in [
      "WITH chosen AS (FROM t |> RESULT saved) SELECT x FROM chosen", "SELECT x FROM (FROM t |> RESULT saved) AS chosen",
      "SELECT * FROM t GROUP BY x", "SELECT *, COUNT(*) AS y FROM t GROUP BY x",
      "SELECT *, COUNT(*) AS n FROM t", "SELECT original.* FROM t AS original GROUP BY x",
      "SELECT * EXCEPT (x) FROM t GROUP BY x",
    ] {
    assert_true(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        join_order_context(),
        construction_limits(),
      )
      is Err(InvalidQuery),
      msg=text,
    )
  }
}

///|
test "CTE binding preserves outer resolution witnesses and existing producers" {
  let text = "WITH chosen AS (SELECT x FROM t UNION ALL SELECT x FROM later), later AS (SELECT x FROM t) SELECT x FROM chosen"
  let issue = match
    compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      join_order_context(),
      construction_limits(),
    ) {
    Err(issue) => issue
    Ok(_) => fail("the context has no admitted outer later producer")
  }
  assert_true(issue is UnresolvedRelation(_))
  let path = unresolved_relation_reference(issue).unwrap()
  assert_eq(path.length(), 1)
  assert_eq(path[0].value, "later")
  assert_eq(path[0].quoted, false)
  for
    source in [
      "WITH t AS (SELECT x FROM t) SELECT x FROM t", "WITH chosen AS (SELECT k AS x FROM r UNION ALL SELECT x FROM t), t AS (SELECT x FROM chosen) SELECT x FROM t",
    ] {
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        join_order_context(),
        construction_limits(),
      )
      is Ok(_),
      msg=source,
    )
  }
}

///|
test "unimplemented CTE checking and theta joins remain lowering gaps" {
  assert_true(
    compile(
      @query.parse_query(
        "WITH unused AS (SELECT x FROM t), chosen AS (SELECT x FROM t) SELECT x FROM chosen",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(UnsupportedCte),
  )
  assert_true(
    compile(
      @query.parse_query(
        "SELECT t.x, COUNT(*) AS n FROM t JOIN r ON t.x > r.k MAX_OUTPUT_ROWS 10 GROUP BY t.x",
        syntax_limits(),
      ).unwrap(),
      join_order_context(),
      construction_limits(),
    )
    is Err(UnsupportedJoin),
  )
}
