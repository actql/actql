///|
test "row expression projects evaluated slots through the common object form" {
  let ast = fixture("COALESCE(r,NULL)")
  let builder = @builder.create(
    @query.expression_document(ast),
    limits().construction,
  ).unwrap()
  let root = append_with_properties(
    ast,
    _ => None,
    builder,
    1000,
    resolve_row=Some(path => {
      if path.length() == 1 && path[0].value == "r" {
        Some([("x", "old_x"), ("y", "new_y")])
      } else {
        None
      }
    }),
  ).unwrap()
  let source = @builder.finish(builder, root).unwrap()
  let expression = @expression.admit(
    @builder.cursor(source),
    limits().expression,
  ).unwrap()
  let writer = @encode.writer(10000, 1000, 100)
  @expression.emit_source(expression, writer)
  assert_eq(
    @encode.finish(writer),
    "{\"coalesce\":[{\"object\":{\"x\":{\"field\":\"old_x\"},\"y\":{\"field\":\"new_y\"}}},{\"literal\":null}]}",
  )
}

///|
test "field resolution wins without invoking the row callback" {
  let ast = fixture("r")
  let builder = @builder.create(
    @query.expression_document(ast),
    limits().construction,
  ).unwrap()
  let mut calls = 0
  let root = append_with_properties(
    ast,
    _ => Some("actual_value"),
    builder,
    100,
    resolve_row=Some(_ => {
      calls += 1
      Some([("x", "x")])
    }),
  ).unwrap()
  ignore(@builder.finish(builder, root).unwrap())
  assert_eq(calls, 0)
}

///|
test "wide row projection preserves the compile work limit and reference origin" {
  let ast = fixture("r")
  let builder = @builder.create(
    @query.expression_document(ast),
    limits().construction,
  ).unwrap()
  let result = append_with_properties(
    ast,
    _ => None,
    builder,
    5,
    resolve_row=Some(_ => Some([("x", "x"), ("y", "y")])),
  )
  assert_true(result is Err({ issue: WorkLimit, origin: Some(_), }))
  @builder.discard(builder)
}

///|
test "caller-owned row projection spends the same remaining Work before Object construction" {
  let ast = fixture("r")
  for (budget, succeeds) in [(13, true), (12, false)] {
    let builder = @builder.create(@query.expression_document(ast), limits().construction).unwrap()
    let mut calls = 0
    let mut observed = -1
    let result = append_with_properties(ast, _ => None, builder, budget,
      resolve_row_with_work=Some((_, available) => {
        calls += 1
        // One reference visit spends1; the caller's original projection spends7;
        // the existing row Object/field construction spends2+3. Total13.
        observed = available
        Ok(Some(([ ("x", "original_x") ], 7)))
      }),
    )
    assert_eq(calls, 1)
    assert_eq(observed, budget - 1)
    if succeeds {
      let source = @builder.finish(builder, result.unwrap()).unwrap()
      let expression = @expression.admit(@builder.cursor(source), limits().expression).unwrap()
      let writer = @encode.writer(10000, 1000, 100)
      @expression.emit_source(expression, writer)
      assert_eq(@encode.finish(writer), "{\"object\":{\"x\":{\"field\":\"original_x\"}}}")
    } else {
      guard result is Err({ issue: WorkLimit, origin: Some(origin), }) else { fail("one-short projection bypassed the original Work owner") }
      assert_true(@origin.belongs_to(@query.expression_document(ast), origin))
      @builder.discard(builder)
    }
  }
}

///|
test "caller-owned row projection keeps field priority and rejects malformed Work or missing rows" {
  let ast = fixture("r")
  for spent in [-1, 100] {
    let builder = @builder.create(@query.expression_document(ast), limits().construction).unwrap()
    assert_true(append_with_properties(ast, _ => None, builder, 20, resolve_row_with_work=Some((_, _) => Ok(Some(([], spent))))) is Err({ issue: InvalidLimits, .. }))
    @builder.discard(builder)
  }
  let builder = @builder.create(@query.expression_document(ast), limits().construction).unwrap()
  let mut calls = 0
  let field = append_with_properties(ast, _ => Some("original"), builder, 20, resolve_row_with_work=Some((_, _) => {
    calls += 1
    Err(WorkLimit)
  })).unwrap()
  ignore(@builder.finish(builder, field).unwrap())
  assert_eq(calls, 0)
  let missing = @builder.create(@query.expression_document(ast), limits().construction).unwrap()
  assert_true(append_with_properties(ast, _ => None, missing, 20, resolve_row_with_work=Some((_, _) => Ok(None))) is Err({ issue: UnknownReference, origin: Some(_), }))
  @builder.discard(missing)
}
