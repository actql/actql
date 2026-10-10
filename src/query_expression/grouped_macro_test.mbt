///|
test "grouped macro bindings share the ordinary bounded property tree" {
  for argument in ["a", "(a)", "(((a)))", "(`a`)"] {
    let ast = fixture(
      "NODE_ID(" + argument + ") IS NOT NULL AND a.payload.score > @min",
    )
    let builder = @builder.create(
      @query.expression_document(ast),
      limits().construction,
    ).unwrap()
    let root = append_with_macros(
      ast,
      path => {
        if path.length() == 2 &&
          path[0].value == "a" &&
          path[1].value == "payload" {
          Some("payload_slot")
        } else {
          None
        }
      },
      (path, binding) => {
        if path.length() == 1 &&
          path[0].value == "NODE_ID" &&
          binding.length() == 1 &&
          binding[0].value == "a" {
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
    let admitted = @expression.admit(
      @builder.cursor(source),
      limits().expression,
    ).unwrap()
    let writer = @encode.writer(100000, 10000, 100)
    @expression.emit_source(admitted, writer)
    assert_eq(
      @encode.finish(writer),
      "{\"and\":[{\"not\":{\"is_null\":{\"field\":\"identity_slot\"}}},{\"gt\":[{\"property\":{\"name\":\"score\",\"value\":{\"field\":\"payload_slot\"}}},{\"$param\":\"min\"}]}]}",
      msg=argument,
    )
  }
}

///|
test "grouped macro arguments preserve node bounds and closed binding roles" {
  let ast = fixture("PATH_LENGTH((((p))))")
  let count = @query.expression_node_count(ast)
  for budget in [count - 1, count] {
    let builder = @builder.create(
      @query.expression_document(ast),
      limits().construction,
    ).unwrap()
    let actual = append_with_macros(
      ast,
      _ => None,
      (path, argument) => {
        if path.length() == 1 &&
          path[0].value == "PATH_LENGTH" &&
          argument.length() == 1 &&
          argument[0].value == "p" {
          Some(Integer(2))
        } else {
          None
        }
      },
      builder,
      budget,
    )
    if budget < count {
      assert_true(actual is Err({ issue: WorkLimit, origin: None, }))
      @builder.discard(builder)
    } else {
      let source = @builder.finish(builder, actual.unwrap()).unwrap()
      let admitted = @expression.admit(
        @builder.cursor(source),
        limits().expression,
      ).unwrap()
      let writer = @encode.writer(100000, 10000, 100)
      @expression.emit_source(admitted, writer)
      assert_eq(@encode.finish(writer), "{\"literal\":2}")
    }
  }
  // A compound expression cannot be passed to the binding resolver even
  // when its leaves would be ordinary visible columns or parameters.
  for text in ["NODE_ID((a + 1))", "NODE_ID((@a))", "NODE_ID((a), (a))"] {
    let callbacks : Array[Bool] = []
    let ast = fixture(text)
    let builder = @builder.create(
      @query.expression_document(ast),
      limits().construction,
    ).unwrap()
    let actual = append_with_macros(
      ast,
      _ => Some("column"),
      (_, _) => {
        callbacks.push(true)
        Some(Field("identity_slot"))
      },
      builder,
      10000,
    )
    assert_true(
      actual is Err({ issue: UnsupportedFunction, origin: Some(_), }),
      msg=text,
    )
    assert_true(callbacks.is_empty(), msg=text)
    @builder.discard(builder)
  }
}
