///|
fn expression_limits() -> ExpressionLimits {
  { lexical: limits(), max_nodes: 1000, max_depth: 100, max_work: 10000, }
}

///|
fn kind(expression : Expression, index : Int) -> ExpressionKind {
  expression_node(expression, index).unwrap().kind
}

///|
test "query expression precedence follows the adopted GoogleSQL operators" {
  let e = parse_expression(
    "NOT a = b OR c + d * e > f AND g",
    expression_limits(),
  ).unwrap()
  match kind(e, expression_root(e)) {
    Binary("OR", left, right) => {
      match kind(e, left) {
        Unary("NOT", comparison) =>
          assert_true(kind(e, comparison) is Binary("=", _, _))
        _ => fail("NOT must enclose the comparison")
      }
      match kind(e, right) {
        Binary("AND", comparison, _) =>
          match kind(e, comparison) {
            Binary(">", addition, _) =>
              match kind(e, addition) {
                Binary("+", _, product) =>
                  assert_true(kind(e, product) is Binary("*", _, _))
                _ => fail("expected addition")
              }
            _ => fail("expected comparison")
          }
        _ => fail("AND must bind more tightly than OR")
      }
    }
    _ => fail("expected OR root")
  }
  let concat = parse_expression("a + b || c * d", expression_limits()).unwrap()
  match kind(concat, expression_root(concat)) {
    Binary("+", _, product) =>
      match kind(concat, product) {
        Binary("*", joined, _) =>
          assert_true(kind(concat, joined) is Binary("||", _, _))
        _ => fail("concatenation and multiplication associate from the left")
      }
    _ => fail("concatenation binds more tightly than addition")
  }
}

///|
test "query paths preserve quoted components and parameters without legacy text parsing" {
  let e = parse_expression(
    "ACTQL.CONCAT(`left.id`, t.`a.b`, @value)",
    expression_limits(),
  ).unwrap()
  match kind(e, expression_root(e)) {
    Call(path, args) => {
      assert_eq(path, [
        { value: "ACTQL", quoted: false, },
        { value: "CONCAT", quoted: false, },
      ])
      assert_eq(
        kind(e, args[0]),
        Reference([{ value: "left.id", quoted: true, }]),
      )
      assert_eq(
        kind(e, args[1]),
        Reference([
          { value: "t", quoted: false, },
          { value: "a.b", quoted: true, },
        ]),
      )
      assert_eq(kind(e, args[2]), ParameterReference("value"))
      args.clear()
      assert_true(
        kind(e, expression_root(e)) is Call(_, original) &&
        original.length() == 3,
      )
    }
    _ => fail("expected function call")
  }
}

///|
test "query expression syntax rejects ambiguous comparisons and unfinished expressions" {
  for
    text in [
      "a < b < c", "a = b = c", "a +", "f(a,)", "f(a", "(a", "a b", "", "()",
    ] {
    assert_true(parse_expression(text, expression_limits()) is Err(_), msg=text)
  }
  assert_true(parse_expression("(a < b) = TRUE", expression_limits()) is Ok(_))
}

///|
test "expression parentheses retain original source origins" {
  let e = parse_expression(
    "\r\n ('😀')",
    expression_limits(),
    source_path="e.sql",
  ).unwrap()
  let root = expression_node(e, expression_root(e)).unwrap()
  assert_eq(root.start, 3)
  assert_eq(root.end, 11)
  let span = @origin.span(expression_origin(e, expression_root(e)).unwrap())
  assert_eq(span.source_path, "e.sql")
  assert_eq(span.start_line, 2)
  assert_eq(span.start_column, 2)
  assert_true(root.kind is Parenthesized(_))
}

///|
test "expression node depth and work limits are checked during parsing" {
  let e = parse_expression("f(1 + 2)", expression_limits()).unwrap()
  assert_eq(expression_node_count(e), 4)
  assert_true(
    parse_expression("f(1 + 2)", {
      ..expression_limits(),
      max_nodes: 4,
      max_work: expression_work(e),
    })
    is Ok(_),
  )
  assert_true(
    parse_expression("f(1 + 2)", { ..expression_limits(), max_nodes: 3, })
    is Err(_),
  )
  assert_true(
    parse_expression("f(1 + 2)", {
      ..expression_limits(),
      max_work: expression_work(e) - 1,
    })
    is Err(_),
  )
  assert_true(
    parse_expression("(((1)))", { ..expression_limits(), max_depth: 3, })
    is Err(_),
  )
  assert_true(
    parse_expression("(((1)))", { ..expression_limits(), max_depth: 4, })
    is Ok(_),
  )
}

///|
test "query predicates preserve BETWEEN IN and IS as single source operations" {
  for
    (text, op, count) in [
      ("x BETWEEN 1 AND 2", "BETWEEN", 3),
      ("x NOT BETWEEN 1 AND 2", "NOT BETWEEN", 3),
      ("x IN (1,2,NULL)", "IN", 4),
      ("x NOT IN (1)", "NOT IN", 2),
      ("x IS NULL", "IS NULL", 1),
      ("x IS NOT TRUE", "IS NOT TRUE", 1),
      ("x IS UNKNOWN", "IS UNKNOWN", 1),
      ("x IS DISTINCT FROM y", "IS DISTINCT FROM", 2),
      ("x IS NOT DISTINCT FROM y", "IS NOT DISTINCT FROM", 2),
    ] {
    let e = parse_expression(text, expression_limits()).unwrap()
    match kind(e, expression_root(e)) {
      Predicate(actual, args) => {
        assert_eq(actual, op)
        assert_eq(args.length(), count)
      }
      _ => fail(text)
    }
  }
  let e = parse_expression(
    "x BETWEEN 1 AND 2 AND y IS NOT NULL",
    expression_limits(),
  ).unwrap()
  assert_true(kind(e, expression_root(e)) is Binary("AND", _, _))
  for
    text in [
      "x BETWEEN 1", "x IN ()", "x IN (1,)", "x IS MAYBE", "x NOT y", "x IS NULL IS TRUE",
    ] {
    assert_true(parse_expression(text, expression_limits()) is Err(_), msg=text)
  }
}

///|
test "searched CASE preserves demand branches and does not evaluate them" {
  let e = parse_expression(
    "CASE WHEN x = 0 THEN 0 WHEN x IS NULL THEN NULL ELSE 10 / x END",
    expression_limits(),
  ).unwrap()
  match kind(e, expression_root(e)) {
    SearchedCase(branches, otherwise) => {
      assert_eq(branches.length(), 2)
      assert_true(kind(e, otherwise) is Binary("/", _, _))
      assert_true(kind(e, branches[0].0) is Binary("=", _, _))
      assert_eq(kind(e, branches[0].1), Number("0"))
      branches.clear()
      assert_true(
        kind(e, expression_root(e)) is SearchedCase(original, _) &&
        original.length() == 2,
      )
    }
    _ => fail("expected searched CASE")
  }
  let implicit = parse_expression("CASE WHEN x THEN 1 END", expression_limits()).unwrap()
  match kind(implicit, expression_root(implicit)) {
    SearchedCase(_, otherwise) => assert_eq(kind(implicit, otherwise), Null)
    _ => fail("expected implicit ELSE NULL")
  }
  for
    text in [
      "CASE x WHEN 1 THEN 2 END", "CASE WHEN x 1 END", "CASE WHEN x THEN 1", "CASE ELSE 1 END",
    ] {
    assert_true(parse_expression(text, expression_limits()) is Err(_), msg=text)
  }
}

///|
test "query cast syntax preserves explicitly adopted target types" {
  for
    (text, expected) in [
      ("CAST(x AS BOOL)", CastType::Boolean),
      ("CAST(x AS STRING)", CastType::String),
      ("CAST(x AS FLOAT64)", CastType::Number),
      ("CAST(x AS TIMESTAMP)", CastType::Timestamp),
      ("CAST('1.25' AS DECIMAL(38,2))", CastType::Decimal(38, 2)),
    ] {
    let e = parse_expression(text, expression_limits()).unwrap()
    assert_true(
      kind(e, expression_root(e)) is Cast(_, actual) && actual == expected,
    )
  }
  for
    text in [
      "CAST(x AS INT64)", "CAST(x AS NUMERIC)", "CAST(x AS BIGNUMERIC)", "CAST(x AS DECIMAL(0,0))",
      "CAST(x AS DECIMAL(39,1))", "CAST(x AS DECIMAL(1,2))", "CAST(x AS DECIMAL(2,1.0))",
    ] {
    assert_true(parse_expression(text, expression_limits()) is Err(_), msg=text)
  }
}
