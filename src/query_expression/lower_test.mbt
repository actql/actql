///|
fn fixture(text : String) -> @query.Expression {
  @query.parse_expression(text, {
    lexical: {
      max_source_bytes: 10000,
      max_tokens: 1000,
      max_literal_bytes: 10000,
      max_work: 20000,
    },
    max_nodes: 1000,
    max_depth: 100,
    max_work: 10000,
  }).unwrap()
}

///|
fn limits() -> Limits {
  {
    construction: {
      source: { max_input_bytes: 10000, max_nodes: 10000, max_depth: 100, },
      tree: {
        max_nodes: 10000,
        max_depth: 100,
        max_string_bytes: 10000,
        max_total_string_bytes: 100000,
      },
      max_origin_entries: 20000,
      max_output_bytes: 100000,
    },
    expression: {
      max_nodes: 10000,
      max_depth: 100,
      max_text_bytes: 10000,
      max_tokens: 1000,
      tree: {
        max_nodes: 10000,
        max_depth: 100,
        max_string_bytes: 10000,
        max_total_string_bytes: 100000,
      },
    },
    max_work: 10000,
  }
}

///|
fn emit(text : String) -> String raise {
  let lowered = lower(
    fixture(text),
    path => if path.length() == 1 { Some(path[0].value) } else { None },
    limits(),
  ).unwrap()
  let writer = @encode.writer(100000, 10000, 100)
  @expression.emit_source(expression(lowered), writer)
  @encode.finish(writer)
}

///|
test "query CONCAT lowers directly to strict expression while explicit legacy spelling stays separate" {
  assert_eq(
    emit("CONCAT('a', NULL)"),
    "{\"concat_strict\":[{\"literal\":\"a\"},{\"literal\":null}]}",
  )
  assert_eq(
    emit("ACTQL.CONCAT('a', NULL)"),
    "{\"concat\":[{\"literal\":\"a\"},{\"literal\":null}]}",
  )
  assert_eq(
    emit("'a' || 'b'"),
    "{\"concat_strict\":[{\"literal\":\"a\"},{\"literal\":\"b\"}]}",
  )
}

///|
test "query expression lowering preserves tree precedence and parameter identity" {
  assert_eq(
    emit("x + @p * 2"),
    "{\"add\":[{\"field\":\"x\"},{\"multiply\":[{\"$param\":\"p\"},{\"literal\":2}]}]}",
  )
  assert_eq(emit("x IS NOT NULL"), "{\"not\":{\"is_null\":{\"field\":\"x\"}}}")
  assert_eq(
    emit("x IN (1,2)"),
    "{\"in\":[{\"field\":\"x\"},{\"literal\":[1,2]}]}",
  )
}

///|
test "lowering never infers a qualified reference or passes through an unknown function" {
  assert_true(lower(fixture("t.x"), _ => None, limits()) is Err(_))
  assert_true(lower(fixture("unknown(x)"), _ => Some("x"), limits()) is Err(_))
  assert_true(
    lower(fixture("ACTQL.OTHER(x)"), _ => Some("x"), limits()) is Err(_),
  )
  assert_true(lower(fixture("CONCAT()"), _ => None, limits()) is Err(_))
}

///|
test "integer literals are checked before rounding and generated trees retain admission bounds" {
  assert_eq(emit("9007199254740991"), "{\"literal\":9007199254740991}")
  for
    text in ["9007199254740992", "99999999999999999999999999", "1e99999", "-0"] {
    assert_true(lower(fixture(text), _ => None, limits()) is Err(_), msg=text)
  }
  assert_eq(emit(".5"), "{\"literal\":0.5}")
  assert_eq(emit("1."), "{\"literal\":1}")
  assert_true(
    lower(fixture("1+2"), _ => None, { ..limits(), max_work: 2, }) is Err(_),
  )
  let tiny = {
    ..limits(),
    construction: { ..limits().construction, max_output_bytes: 1, },
  }
  assert_true(lower(fixture("1+2"), _ => None, tiny) is Err(_))
}

///|
test "signed literal normalization keeps negative IN values and rejects NULL comparison" {
  assert_eq(emit("-1"), "{\"literal\":-1}")
  assert_eq(
    emit("x IN (-1, @p)"),
    "{\"in\":[{\"field\":\"x\"},{\"literal\":[-1,{\"$param\":\"p\"}]}]}",
  )
  assert_true(lower(fixture("NULL = x"), _ => Some("x"), limits()) is Err(_))
  assert_true(lower(fixture("+'string'"), _ => None, limits()) is Err(_))
}

///|
test "query clauses append to one source owner without expression reparse" {
  let query = @query.parse_query("SELECT x, y + 1 FROM t", {
    lexical: {
      max_source_bytes: 10000,
      max_tokens: 1000,
      max_literal_bytes: 10000,
      max_work: 20000,
    },
    expression: {
      lexical: {
        max_source_bytes: 10000,
        max_tokens: 1000,
        max_literal_bytes: 10000,
        max_work: 20000,
      },
      max_nodes: 1000,
      max_depth: 100,
      max_work: 10000,
    },
    max_syntax_nodes: 100,
    max_cte_count: 20,
    max_work: 10000,
  }).unwrap()
  let projections = match @query.operation_at(query, 0) {
    Some(@query.Select(items, false)) => items
    _ => fail("expected SELECT")
  }
  let first = projections[0].expression.unwrap()
  let second = projections[1].expression.unwrap()
  let builder = @builder.create(
    @query.expression_document(first),
    limits().construction,
  ).unwrap()
  let resolve = (path : Array[@query.NamePart]) => {
    if path.length() == 1 {
      Some(path[0].value)
    } else {
      None
    }
  }
  ignore(append(first, resolve, builder, 10000).unwrap())
  let root = append(second, resolve, builder, 10000).unwrap()
  let source = @builder.finish(builder, root).unwrap()
  let admitted = @expression.admit(@builder.cursor(source), limits().expression).unwrap()
  let writer = @encode.writer(100000, 10000, 100)
  @expression.emit_source(admitted, writer)
  assert_eq(
    @encode.finish(writer),
    "{\"add\":[{\"field\":\"y\"},{\"literal\":1}]}",
  )
  let other = @builder.create(
    @query.expression_document(first),
    limits().construction,
  ).unwrap()
  assert_true(append(fixture("z"), resolve, other, 10000) is Err(_))
  @builder.discard(other)
}

///|
test "property lowering resolves a scope prefix without flattening names" {
  let expression = fixture(
    "assessment.outcome = 'ok' AND assessment.value.risk = 'high'",
  )
  let builder = @builder.create(
    @query.expression_document(expression),
    limits().construction,
  ).unwrap()
  let root = append_with_properties(
    expression,
    path => {
      if path.length() == 1 && path[0].value == "assessment" {
        Some("result_slot")
      } else {
        None
      }
    },
    builder,
    10000,
  ).unwrap()
  let source = @builder.finish(builder, root).unwrap()
  let admitted = @expression.admit(@builder.cursor(source), limits().expression).unwrap()
  let writer = @encode.writer(100000, 10000, 100)
  @expression.emit_source(admitted, writer)
  assert_eq(
    @encode.finish(writer),
    "{\"and\":[{\"eq\":[{\"property\":{\"name\":\"outcome\",\"value\":{\"field\":\"result_slot\"}}},{\"literal\":\"ok\"}]},{\"eq\":[{\"property\":{\"name\":\"risk\",\"value\":{\"property\":{\"name\":\"value\",\"value\":{\"field\":\"result_slot\"}}}}},{\"literal\":\"high\"}]}]}",
  )
  let bounded = @builder.create(
    @query.expression_document(expression),
    limits().construction,
  ).unwrap()
  assert_true(
    append_with_properties(expression, _ => Some("slot"), bounded, 1) is Err(_),
  )
  @builder.discard(bounded)
}

///|
test "macro and property resolution share one bounded expression tree" {
  let expression = fixture("NODE_ID(a) IS NOT NULL AND a.payload.score > @min")
  let builder = @builder.create(
    @query.expression_document(expression),
    limits().construction,
  ).unwrap()
  let root = append_with_macros(
    expression,
    path => {
      if path.length() == 2 &&
        path[0].value == "a" &&
        path[1].value == "payload" {
        Some("payload_slot")
      } else {
        None
      }
    },
    (path, argument) => {
      if path.length() == 1 &&
        path[0].value == "NODE_ID" &&
        argument.length() == 1 &&
        argument[0].value == "a" {
        Some(Field("identity_slot"))
      } else {
        None
      }
    },
    builder,
    10000,
    resolve_properties=true,
  ).unwrap()
  let source = @builder.finish(builder, root).unwrap()
  let admitted = @expression.admit(@builder.cursor(source), limits().expression).unwrap()
  let writer = @encode.writer(100000, 10000, 100)
  @expression.emit_source(admitted, writer)
  assert_eq(
    @encode.finish(writer),
    "{\"and\":[{\"not\":{\"is_null\":{\"field\":\"identity_slot\"}}},{\"gt\":[{\"property\":{\"name\":\"score\",\"value\":{\"field\":\"payload_slot\"}}},{\"$param\":\"min\"}]}]}",
  )
}

///|
test "macro property opt-in preserves default resolution and charges prefix work" {
  let expression = fixture("a.payload.score")
  let resolve = (path : Array[@query.NamePart]) => {
    if path.length() == 2 {
      Some("payload_slot")
    } else {
      None
    }
  }
  let legacy = @builder.create(
    @query.expression_document(expression),
    limits().construction,
  ).unwrap()
  assert_true(
    append_with_macros(expression, resolve, (_, _) => None, legacy, 10000)
    is Err({ issue: UnknownReference, origin: Some(_), }),
  )
  @builder.discard(legacy)
  let bounded = @builder.create(
    @query.expression_document(expression),
    limits().construction,
  ).unwrap()
  assert_true(
    append_with_macros(
      expression,
      resolve,
      (_, _) => None,
      bounded,
      1,
      resolve_properties=true,
    )
    is Err({ issue: WorkLimit, origin: Some(_), }),
  )
  @builder.discard(bounded)
}

///|
test "Named numeric arguments share query literal admission" {
  for
    (token, expected) in [
      (".5", 0.5),
      ("1.", 1.0),
      ("1.e1", 10.0),
      ("0002", 2.0),
      ("-.5", -0.5),
      ("9007199254740991", 9007199254740991.0),
    ] {
    assert_eq(numeric_literal(token).unwrap(), expected)
  }
  for token in ["-0", "9007199254740993", "1e999"] {
    assert_true(numeric_literal(token) is Err(InvalidNumber), msg=token)
  }
}
