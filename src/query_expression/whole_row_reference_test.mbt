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
