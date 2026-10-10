///|
// Authored independent wire forms retain both children and their order.
test "trim functions admit explicit STRING set expressions and preserve unary bodies" {
  for op in ["trim", "ltrim", "rtrim"] {
    for name in [op, op.to_upper(), "`" + op + "`"] {
      assert_eq(emit(name + "(x)"), "{\"" + op + "\":{\"field\":\"x\"}}")
      assert_eq(
        emit(name + "(x, @p)"),
        "{\"" + op + "\":[{\"field\":\"x\"},{\"$param\":\"p\"}]}",
      )
      assert_eq(
        emit(name + "(NULL, NULL)"),
        "{\"" + op + "\":[{\"literal\":null},{\"literal\":null}]}",
      )
      assert_eq(
        emit(name + "('😀é', '😀́')"),
        "{\"" + op + "\":[{\"literal\":\"😀é\"},{\"literal\":\"😀́\"}]}",
      )
      assert_eq(
        emit(name + "(' x ', '')"),
        "{\"" + op + "\":[{\"literal\":\" x \"},{\"literal\":\"\"}]}",
      )
    }
  }
}

///|
test "trim sets retain NULL failure and lazy expressions without frontend folding" {
  assert_eq(
    emit("TRIM(NULL, CAST(1 / 0 AS STRING))"),
    "{\"trim\":[{\"literal\":null},{\"cast\":{\"target\":{\"type\":\"string\"},\"value\":{\"divide\":[{\"literal\":1},{\"literal\":0}]}}}]}",
  )
  assert_eq(
    emit("LTRIM(x, IF(TRUE, 'ab', 'ba'))"),
    "{\"ltrim\":[{\"field\":\"x\"},{\"if\":[{\"literal\":true},{\"literal\":\"ab\"},{\"literal\":\"ba\"}]}]}",
  )
  assert_eq(
    emit("RTRIM('x', CAST(NULL AS STRING))"),
    "{\"rtrim\":[{\"literal\":\"x\"},{\"cast\":{\"target\":{\"type\":\"string\"},\"value\":{\"literal\":null}}}]}",
  )
}

///|
test "trim sets reject unsupported arities namespaces and BYTES spelling" {
  for op in ["TRIM", "LTRIM", "RTRIM"] {
    for args in ["", "'x', 'a', 'b'"] {
      assert_true(
        lower(fixture(op + "(" + args + ")"), _ => None, limits())
        is Err({ issue: InvalidArguments, .. }),
      )
    }
    assert_true(
      lower(fixture("ACTQL." + op + "('x', 'a')"), _ => None, limits())
      is Err({ issue: UnsupportedFunction, .. }),
    )
    assert_true(
      @query.parse_expression(op + "(b'x', b'a')", {
        lexical: {
          max_source_bytes: 1000,
          max_tokens: 100,
          max_literal_bytes: 1000,
          max_work: 2000,
        },
        max_nodes: 100,
        max_depth: 20,
        max_work: 2000,
      })
      is Err(_),
    )
  }
}
