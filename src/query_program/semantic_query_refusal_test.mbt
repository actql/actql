///|
test "Pure WITH and derived bodies refuse Result at the authored token" {
  for (text, offset) in [
    ("WITH chosen AS (FROM t |> RESULT saved) SELECT x FROM chosen", 25),
    ("SELECT x FROM (FROM t |> RESULT saved) AS chosen", 24),
  ] {
    match @query.parse_query(text, syntax_limits(), source_path="pure.sql") {
      Err({ issue: Syntax(message), span: Some(span), }) => {
        assert_eq(message, "RESULT is not allowed in a producer body")
        assert_eq(span.source_path, "pure.sql")
        assert_eq(span.start_byte, offset)
      }
      _ => fail(text)
    }
  }
}

///|
test "grouped projection violations retain the exact lowering refusal" {
  for
    text in [
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
test "valid unused WITH is checked and pruned while theta JOIN stays unsupported" {
  let actual = compile(
    @query.parse_query(
      "WITH unused AS (SELECT x FROM t WHERE y = 20), chosen AS (SELECT x FROM t WHERE x > 0) SELECT x FROM chosen",
      syntax_limits(),
    ).unwrap(),
    join_order_context(),
    construction_limits(),
  ).unwrap()
  let body = semantic(actual)
  // Independent predicates distinguish demand pruning from leaking the unused
  // binding's filter into the shared Values input. Rows remain [1, 2].
  assert_true(body.contains("\"gt\":[{\"field\":\"x\"},{\"literal\":0}]"))
  assert_false(body.contains("\"eq\":[{\"field\":\"y\"},{\"literal\":20}]"))
  assert_false(body.contains("\"as\":\"unused\""))
  assert_eq(@program.stage_count(actual), 1)
  match @check.check_parsed(actual, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    _ => fail("closed Values and demanded WITH use the ordinary checker")
  }
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
